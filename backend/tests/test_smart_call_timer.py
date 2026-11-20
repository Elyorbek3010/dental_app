import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

from tests.test_db import TestSessionLocal as SessionLocal
from fastapi.testclient import TestClient
from sqlalchemy import delete, select, text

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.smart_call_timer import process_expired_called_tickets


class SmartCallTimerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()
        for tbl in ("clinics", "specializations", "doctors", "users", "queues", "queue_tickets"):
            cls.db.execute(
                text(
                    f"SELECT setval(pg_get_serial_sequence('{tbl}', 'id'), COALESCE((SELECT MAX(id) FROM {tbl}), 1), true)"
                )
            )
        cls.db.commit()

        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.name == "Smart Call Clinic 1"))
        if not cls.clinic1:
            cls.clinic1 = Clinic(name="Smart Call Clinic 1", smart_call_timeout_seconds=120)
            cls.db.add(cls.clinic1)
            cls.db.commit()
            cls.db.refresh(cls.clinic1)

        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.name == "Smart Call Clinic 2"))
        if not cls.clinic2:
            cls.clinic2 = Clinic(name="Smart Call Clinic 2", smart_call_timeout_seconds=120)
            cls.db.add(cls.clinic2)
            cls.db.commit()
            cls.db.refresh(cls.clinic2)

        cls.spec1 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic1.id,
                Specialization.name_uz == "Smart Call Spec 1",
            )
        )
        if not cls.spec1:
            cls.spec1 = Specialization(
                clinic_id=cls.clinic1.id,
                name_uz="Smart Call Spec 1",
                name_ru="Смарт Спец 1",
                name_en="Smart Spec 1",
            )
            cls.db.add(cls.spec1)
            cls.db.commit()
            cls.db.refresh(cls.spec1)

        cls.spec2 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic2.id,
                Specialization.name_uz == "Smart Call Spec 2",
            )
        )
        if not cls.spec2:
            cls.spec2 = Specialization(
                clinic_id=cls.clinic2.id,
                name_uz="Smart Call Spec 2",
                name_ru="Смарт Спец 2",
                name_en="Smart Spec 2",
            )
            cls.db.add(cls.spec2)
            cls.db.commit()
            cls.db.refresh(cls.spec2)

        cls.doctor1 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec1.id, "Dr. Smart One", "101")
        cls.doctor2 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec1.id, "Dr. Smart Two", "102")
        cls.doctor_other_clinic = cls._get_or_create_doctor(
            cls.clinic2.id, cls.spec2.id, "Dr. Clinic Two", "201"
        )

        cls.admin1 = cls._get_or_create_user(cls.clinic1.id, "Smart Admin 1", "+998905551001", UserRole.ADMIN)
        cls.admin2 = cls._get_or_create_user(cls.clinic2.id, "Smart Admin 2", "+998905551002", UserRole.ADMIN)
        cls.rec1 = cls._get_or_create_user(cls.clinic1.id, "Smart Rec 1", "+998905551003", UserRole.RECEPTIONIST)
        cls.p1 = cls._get_or_create_user(None, "Smart Patient 1", "+998905551004", UserRole.PATIENT)
        cls.p2 = cls._get_or_create_user(None, "Smart Patient 2", "+998905551005", UserRole.PATIENT)
        cls.p3 = cls._get_or_create_user(None, "Smart Patient 3", "+998905551006", UserRole.PATIENT)

        cls.admin1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin1.id)}"}
        cls.admin2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin2.id)}"}
        cls.rec1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"}
        cls.p1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p1.id)}"}
        cls.p2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p2.id)}"}

    @classmethod
    def _get_or_create_doctor(cls, clinic_id: int, spec_id: int, full_name: str, room_number: str) -> Doctor:
        doc = cls.db.scalar(select(Doctor).where(Doctor.clinic_id == clinic_id, Doctor.full_name == full_name))
        if not doc:
            doc = Doctor(
                clinic_id=clinic_id,
                specialization_id=spec_id,
                full_name=full_name,
                room_number=room_number,
                is_active=True,
            )
            cls.db.add(doc)
            cls.db.commit()
            cls.db.refresh(doc)
        return doc

    @classmethod
    def _get_or_create_user(cls, clinic_id: int | None, full_name: str, phone: str, role: UserRole) -> User:
        user = cls.db.scalar(select(User).where(User.phone == phone))
        if not user:
            user = User(
                clinic_id=clinic_id,
                full_name=full_name,
                phone=phone,
                hashed_password="x",
                role=role,
                is_active=True,
            )
            cls.db.add(user)
            cls.db.commit()
            cls.db.refresh(user)
        return user

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        with SessionLocal() as db:
            # Reset clinic timeouts to default 120s
            c1 = db.scalar(select(Clinic).where(Clinic.id == self.clinic1.id))
            c2 = db.scalar(select(Clinic).where(Clinic.id == self.clinic2.id))
            if c1:
                c1.smart_call_timeout_seconds = 120
            if c2:
                c2.smart_call_timeout_seconds = 120

            doctor_ids = [self.doctor1.id, self.doctor2.id, self.doctor_other_clinic.id]
            q_ids = list(db.scalars(select(Queue.id).where(Queue.doctor_id.in_(doctor_ids))).all())
            if q_ids:
                db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
                db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
            db.commit()

    def _create_queue(self, doctor: Doctor, *, is_active: bool = True, is_paused: bool = False) -> Queue:
        with SessionLocal() as db:
            q = Queue(
                doctor_id=doctor.id,
                queue_date=date.today(),
                is_active=is_active,
                is_paused=is_paused,
            )
            db.add(q)
            db.commit()
            db.refresh(q)
            return q

    def _add_ticket(
        self,
        queue_id: int,
        ticket_number: int,
        *,
        patient: User | None = None,
        name: str = "Patient",
        phone: str | None = None,
        status: TicketStatus = TicketStatus.WAITING,
        checked_in: bool = True,
        called_at: datetime | None = None,
        call_deadline_at: datetime | None = None,
        paused_remaining_seconds: int | None = None,
    ) -> QueueTicket:
        with SessionLocal() as db:
            now = datetime.now(timezone.utc)
            ticket = QueueTicket(
                queue_id=queue_id,
                patient_id=patient.id if patient else None,
                ticket_number=ticket_number,
                queue_position=ticket_number,
                patient_name=patient.full_name if patient else name,
                patient_phone=patient.phone if patient else phone,
                source=TicketSource.ONLINE if patient else TicketSource.WALK_IN,
                status=status,
                checked_in_at=now if checked_in else None,
                check_in_method=CheckInMethod.QR if checked_in else None,
                called_at=called_at,
                call_deadline_at=call_deadline_at,
                paused_remaining_seconds=paused_remaining_seconds,
            )
            db.add(ticket)
            db.commit()
            db.refresh(ticket)
            return ticket

    def test_01_admin_clinic_default_and_update_validation_permissions(self):
        # Default is 120s
        res = self.client.get("/api/admin/clinic", headers=self.admin1_headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["smart_call_timeout_seconds"], 120)

        # Non-admin forbidden
        self.assertEqual(
            self.client.get("/api/admin/clinic", headers=self.rec1_headers).status_code,
            403,
        )
        self.assertEqual(
            self.client.patch(
                "/api/admin/clinic",
                json={"smart_call_timeout_seconds": 60},
                headers=self.p1_headers,
            ).status_code,
            403,
        )

        # Invalid boundary values rejected (422)
        for bad_val in [0, 14, -10, 1801, 9999]:
            bad_res = self.client.patch(
                "/api/admin/clinic",
                json={"smart_call_timeout_seconds": bad_val},
                headers=self.admin1_headers,
            )
            self.assertEqual(bad_res.status_code, 422, f"Expected 422 for {bad_val}")

        # Boundary valid values 15 and 1800 succeed, clinic2 stays isolated at 120
        for good_val in [15, 1800, 45]:
            good_res = self.client.patch(
                "/api/admin/clinic",
                json={"smart_call_timeout_seconds": good_val},
                headers=self.admin1_headers,
            )
            self.assertEqual(good_res.status_code, 200)
            self.assertEqual(good_res.json()["smart_call_timeout_seconds"], good_val)

        res_c2 = self.client.get("/api/admin/clinic", headers=self.admin2_headers)
        self.assertEqual(res_c2.status_code, 200)
        self.assertEqual(res_c2.json()["smart_call_timeout_seconds"], 120)

    def test_02_smart_call_and_manual_call_persist_deadline(self):
        self.client.patch(
            "/api/admin/clinic",
            json={"smart_call_timeout_seconds": 45},
            headers=self.admin1_headers,
        )
        queue = self._create_queue(self.doctor1)
        t1 = self._add_ticket(queue.id, 1, patient=self.p1, checked_in=True)
        t2 = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=False)

        with patch("app.api.queues.schedule_called_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            # Smart Call starts ~45s countdown
            call_res = self.client.post(f"/api/queues/{queue.id}/call-next", headers=self.rec1_headers)
            self.assertEqual(call_res.status_code, 200)
            body = call_res.json()
            self.assertEqual(body["id"], t1.id)
            self.assertEqual(body["status"], "CALLED")
            self.assertIsNotNone(body["called_at"])
            self.assertIsNotNone(body["call_deadline_at"])
            self.assertIsNotNone(body["server_time"])
            called_at = datetime.fromisoformat(body["called_at"])
            deadline = datetime.fromisoformat(body["call_deadline_at"])
            self.assertEqual(round((deadline - called_at).total_seconds()), 45)

            # Manual call while CALLED active fails 409
            conflict_res = self.client.patch(
                f"/api/queues/{queue.id}/tickets/{t2.id}/call",
                headers=self.rec1_headers,
            )
            self.assertEqual(conflict_res.status_code, 409)

            # Skip t1 -> then Manual Call on unchecked-in t2 succeeds and starts countdown
            skip_res = self.client.patch(
                f"/api/queues/{queue.id}/tickets/{t1.id}/skip",
                headers=self.rec1_headers,
            )
            self.assertEqual(skip_res.status_code, 200)
            self.assertIsNone(skip_res.json()["call_deadline_at"])

            manual_res = self.client.patch(
                f"/api/queues/{queue.id}/tickets/{t2.id}/call",
                headers=self.rec1_headers,
            )
            self.assertEqual(manual_res.status_code, 200)
            manual_body = manual_res.json()
            self.assertEqual(manual_body["status"], "CALLED")
            called2 = datetime.fromisoformat(manual_body["called_at"])
            deadline2 = datetime.fromisoformat(manual_body["call_deadline_at"])
            self.assertEqual(round((deadline2 - called2).total_seconds()), 45)

    def test_03_expired_ticket_auto_skips_and_calls_next_with_mixed_queue(self):
        self.client.patch(
            "/api/admin/clinic",
            json={"smart_call_timeout_seconds": 30},
            headers=self.admin1_headers,
        )
        queue = self._create_queue(self.doctor1)
        now = datetime.now(timezone.utc)
        t1 = self._add_ticket(
            queue.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now - timedelta(seconds=35),
            call_deadline_at=now - timedelta(seconds=5),
        )
        t2_absent = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=False)
        t3_present = self._add_ticket(queue.id, 3, patient=self.p3, checked_in=True)

        with patch("app.services.smart_call_timer.trigger_skipped_notification") as mock_skip, patch(
            "app.services.smart_call_timer.trigger_missed_turn_notification"
        ) as mock_missed, patch(
            "app.services.smart_call_timer.trigger_called_notification"
        ) as mock_called, patch(
            "app.services.smart_call_timer.check_and_trigger_approaching"
        ), patch(
            "app.services.smart_call_timer.notify_display_update"
        ) as mock_ws:
            events = process_expired_called_tickets(now=now)
            self.assertEqual(len(events), 1)
            mock_skip.assert_called_once_with(t1.id)
            mock_missed.assert_called_once_with(t2_absent.id)
            mock_called.assert_called_once_with(t3_present.id, self.doctor1.room_number)
            mock_ws.assert_called_once()

        with SessionLocal() as db:
            db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1.id))
            db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2_absent.id))
            db_t3 = db.scalar(select(QueueTicket).where(QueueTicket.id == t3_present.id))
            self.assertEqual(db_t1.status, TicketStatus.SKIPPED)
            self.assertIsNone(db_t1.call_deadline_at)
            self.assertEqual(db_t2.status, TicketStatus.WAITING)
            self.assertEqual(db_t2.missed_turns, 1)
            self.assertEqual(db_t2.queue_position, 4)
            self.assertEqual(db_t3.status, TicketStatus.CALLED)
            self.assertIsNotNone(db_t3.call_deadline_at)
            self.assertEqual(round((db_t3.call_deadline_at - now).total_seconds()), 30)

        # Repeated sweep before t3's new deadline is a no-op (no duplicate missed_turns)
        second_events = process_expired_called_tickets(now=now + timedelta(seconds=10))
        self.assertEqual(second_events, [])
        with SessionLocal() as db:
            db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2_absent.id))
            self.assertEqual(db_t2.missed_turns, 1)

    def test_04_expired_with_no_checked_in_waiting_leaves_queue_idle(self):
        queue = self._create_queue(self.doctor1)
        now = datetime.now(timezone.utc)
        t1 = self._add_ticket(
            queue.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now - timedelta(seconds=130),
            call_deadline_at=now - timedelta(seconds=10),
        )
        t2_absent = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=False)

        with patch("app.services.smart_call_timer.trigger_skipped_notification") as mock_skip, patch(
            "app.services.smart_call_timer.trigger_missed_turn_notification"
        ) as mock_missed, patch(
            "app.services.smart_call_timer.trigger_called_notification"
        ) as mock_called, patch(
            "app.services.smart_call_timer.check_and_trigger_approaching"
        ), patch(
            "app.services.smart_call_timer.notify_display_update"
        ):
            events = process_expired_called_tickets(now=now)
            self.assertEqual(len(events), 1)
            mock_skip.assert_called_once_with(t1.id)
            mock_missed.assert_called_once_with(t2_absent.id)
            mock_called.assert_not_called()

        with SessionLocal() as db:
            db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1.id))
            db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2_absent.id))
            self.assertEqual(db_t1.status, TicketStatus.SKIPPED)
            self.assertEqual(db_t2.status, TicketStatus.WAITING)
            self.assertEqual(db_t2.missed_turns, 1)
            active = db.scalar(
                select(QueueTicket).where(
                    QueueTicket.queue_id == queue.id,
                    QueueTicket.status == TicketStatus.CALLED,
                )
            )
            self.assertIsNone(active)

        # Further sweep must NOT re-increment t2_absent
        process_expired_called_tickets(now=now + timedelta(seconds=60))
        with SessionLocal() as db:
            db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2_absent.id))
            self.assertEqual(db_t2.missed_turns, 1)

    def test_05_setting_update_midflight_retains_active_deadline_applies_to_next(self):
        self.client.patch(
            "/api/admin/clinic",
            json={"smart_call_timeout_seconds": 60},
            headers=self.admin1_headers,
        )
        queue = self._create_queue(self.doctor1)
        t1 = self._add_ticket(queue.id, 1, patient=self.p1, checked_in=True)
        t2 = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=True)

        with patch("app.api.queues.schedule_called_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            call_res = self.client.post(f"/api/queues/{queue.id}/call-next", headers=self.rec1_headers)
            original_deadline = datetime.fromisoformat(call_res.json()["call_deadline_at"])

            # Admin updates timeout to 20s while t1 is active
            self.client.patch(
                "/api/admin/clinic",
                json={"smart_call_timeout_seconds": 20},
                headers=self.admin1_headers,
            )

            # t1 retains original 60s deadline
            list_res = self.client.get(f"/api/queues/{queue.id}/tickets", headers=self.rec1_headers)
            active_t1 = [x for x in list_res.json() if x["id"] == t1.id][0]
            self.assertEqual(datetime.fromisoformat(active_t1["call_deadline_at"]), original_deadline)

            # Expire t1 -> t2 gets new 20s timeout
            with patch("app.services.smart_call_timer.trigger_skipped_notification"), patch(
                "app.services.smart_call_timer.trigger_called_notification"
            ), patch("app.services.smart_call_timer.check_and_trigger_approaching"), patch(
                "app.services.smart_call_timer.notify_display_update"
            ):
                process_expired_called_tickets(now=original_deadline + timedelta(seconds=1))

            with SessionLocal() as db:
                db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2.id))
                self.assertEqual(db_t2.status, TicketStatus.CALLED)
                self.assertEqual(round((db_t2.call_deadline_at - db_t2.called_at).total_seconds()), 20)

    def test_06_serve_skip_cancel_clear_countdown_and_prevent_expiration(self):
        queue = self._create_queue(self.doctor1)
        now = datetime.now(timezone.utc)
        t1 = self._add_ticket(
            queue.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now,
            call_deadline_at=now + timedelta(seconds=30),
        )

        # Serve clears deadline
        with patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_approaching_check"
        ):
            serve_res = self.client.patch(
                f"/api/queues/{queue.id}/tickets/{t1.id}/serve",
                headers=self.rec1_headers,
            )
            self.assertEqual(serve_res.status_code, 200)
            self.assertIsNone(serve_res.json()["call_deadline_at"])

        # Future sweep leaves SERVING intact
        events = process_expired_called_tickets(now=now + timedelta(minutes=10))
        self.assertEqual(events, [])
        with SessionLocal() as db:
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t1.id)), TicketStatus.SERVING)

        # Cancel by patient clears deadline
        t2 = self._add_ticket(
            queue.id,
            2,
            patient=self.p2,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now,
            call_deadline_at=now + timedelta(seconds=30),
        )
        with patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_approaching_check"
        ):
            cancel_res = self.client.patch("/api/queues/my-ticket/cancel", headers=self.p2_headers)
            self.assertEqual(cancel_res.status_code, 200)
            self.assertEqual(cancel_res.json()["status"], "CANCELLED")
            self.assertIsNone(cancel_res.json()["call_deadline_at"])

        self.assertEqual(process_expired_called_tickets(now=now + timedelta(minutes=10)), [])

    def test_07_pause_freezes_and_resume_restores_countdown(self):
        queue = self._create_queue(self.doctor1)
        now = datetime.now(timezone.utc)
        t1 = self._add_ticket(
            queue.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now - timedelta(seconds=10),
            call_deadline_at=now + timedelta(seconds=50),
        )
        t2 = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=True)

        with patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_paused_notification"
        ), patch("app.api.queues.schedule_resumed_notification"):
            # Pause queue -> freezes remaining seconds
            pause_res = self.client.patch(f"/api/queues/{queue.id}/pause", headers=self.rec1_headers)
            self.assertEqual(pause_res.status_code, 200)
            self.assertTrue(pause_res.json()["is_paused"])

            with SessionLocal() as db:
                db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1.id))
                self.assertIsNone(db_t1.call_deadline_at)
                self.assertIsNotNone(db_t1.paused_remaining_seconds)
                frozen_secs = db_t1.paused_remaining_seconds
                self.assertGreaterEqual(frozen_secs, 45)
                self.assertLessEqual(frozen_secs, 51)

            # Patient API reports paused countdown & server_time
            my_res = self.client.get("/api/queues/my-ticket", headers=self.p1_headers)
            self.assertEqual(my_res.status_code, 200)
            self.assertTrue(my_res.json()["is_queue_paused"])
            self.assertEqual(my_res.json()["paused_remaining_seconds"], frozen_secs)
            self.assertIsNone(my_res.json()["call_deadline_at"])
            self.assertIsNotNone(my_res.json()["server_time"])

            # Sweeper far in future does NOT expire paused ticket
            self.assertEqual(process_expired_called_tickets(now=now + timedelta(hours=2)), [])

            # Resume queue -> restores deadline from remaining seconds
            resume_res = self.client.patch(f"/api/queues/{queue.id}/resume", headers=self.rec1_headers)
            self.assertEqual(resume_res.status_code, 200)
            self.assertFalse(resume_res.json()["is_paused"])

            with SessionLocal() as db:
                db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1.id))
                self.assertIsNone(db_t1.paused_remaining_seconds)
                self.assertIsNotNone(db_t1.call_deadline_at)
                restored_deadline = db_t1.call_deadline_at

        # Before restored deadline -> still CALLED; after restored deadline -> SKIPPED and calls t2
        self.assertEqual(
            process_expired_called_tickets(now=restored_deadline - timedelta(seconds=2)),
            [],
        )
        with patch("app.services.smart_call_timer.trigger_skipped_notification"), patch(
            "app.services.smart_call_timer.trigger_called_notification"
        ), patch("app.services.smart_call_timer.check_and_trigger_approaching"), patch(
            "app.services.smart_call_timer.notify_display_update"
        ):
            events = process_expired_called_tickets(now=restored_deadline + timedelta(seconds=1))
            self.assertEqual(len(events), 1)
        with SessionLocal() as db:
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t1.id)), TicketStatus.SKIPPED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t2.id)), TicketStatus.CALLED)

    def test_08_multi_doctor_clinic_isolation_and_public_display_privacy(self):
        q1 = self._create_queue(self.doctor1)
        q2 = self._create_queue(self.doctor2)
        q_other = self._create_queue(self.doctor_other_clinic)
        now = datetime.now(timezone.utc)

        t_q1 = self._add_ticket(
            q1.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now - timedelta(seconds=125),
            call_deadline_at=now - timedelta(seconds=5),
        )
        t_q2 = self._add_ticket(
            q2.id,
            10,
            name="Queue2 Patient",
            phone="+998901112233",
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now,
            call_deadline_at=now + timedelta(seconds=110),
        )
        t_other = self._add_ticket(
            q_other.id,
            20,
            name="Other Clinic Secret",
            phone="+998909998877",
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now,
            call_deadline_at=now + timedelta(seconds=110),
        )

        # Public display exposes countdown deadline & ticket_number, NEVER PII
        pub_res = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display")
        self.assertEqual(pub_res.status_code, 200)
        pub_json = pub_res.json()
        self.assertIn("server_time", pub_json)
        raw_text = pub_res.text
        self.assertNotIn("Queue2 Patient", raw_text)
        self.assertNotIn("+998901112233", raw_text)
        self.assertNotIn("Smart Patient 1", raw_text)
        q2_card = [q for q in pub_json["queues"] if q["doctor"]["id"] == self.doctor2.id][0]
        self.assertEqual(q2_card["called_ticket"]["ticket_number"], 10)
        self.assertIsNotNone(q2_card["called_ticket"]["call_deadline_at"])

        # Sweep expires ONLY q1, leaves q2 and other clinic intact
        with patch("app.services.smart_call_timer.trigger_skipped_notification"), patch(
            "app.services.smart_call_timer.check_and_trigger_approaching"
        ), patch("app.services.smart_call_timer.notify_display_update"):
            events = process_expired_called_tickets(now=now)
            self.assertEqual([e.queue_id for e in events], [q1.id])

        with SessionLocal() as db:
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_q1.id)), TicketStatus.SKIPPED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_q2.id)), TicketStatus.CALLED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_other.id)), TicketStatus.CALLED)

    def test_09_concurrency_parallel_sweep_and_serve_race_safe(self):
        queue = self._create_queue(self.doctor1)
        now = datetime.now(timezone.utc)
        t1 = self._add_ticket(
            queue.id,
            1,
            patient=self.p1,
            status=TicketStatus.CALLED,
            checked_in=True,
            called_at=now - timedelta(seconds=60),
            call_deadline_at=now - timedelta(seconds=1),
        )
        t2 = self._add_ticket(queue.id, 2, patient=self.p2, checked_in=True)

        results: list[int] = []
        barrier = threading.Barrier(2)

        def run_sweep():
            barrier.wait()
            with patch("app.services.smart_call_timer.trigger_skipped_notification"), patch(
                "app.services.smart_call_timer.trigger_called_notification"
            ), patch("app.services.smart_call_timer.check_and_trigger_approaching"), patch(
                "app.services.smart_call_timer.notify_display_update"
            ):
                evs = process_expired_called_tickets(now=now)
                results.append(len(evs))

        t_a = threading.Thread(target=run_sweep)
        t_b = threading.Thread(target=run_sweep)
        t_a.start()
        t_b.start()
        t_a.join()
        t_b.join()

        # Exactly one thread swept t1, never both
        self.assertEqual(sum(results), 1)
        with SessionLocal() as db:
            db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1.id))
            db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2.id))
            self.assertEqual(db_t1.status, TicketStatus.SKIPPED)
            self.assertEqual(db_t2.status, TicketStatus.CALLED)

    def test_10_lifespan_starts_and_shuts_down_cleanly(self):
        with TestClient(app) as client:
            health = client.get("/api/health")
            self.assertEqual(health.status_code, 200)


if __name__ == "__main__":
    unittest.main()
