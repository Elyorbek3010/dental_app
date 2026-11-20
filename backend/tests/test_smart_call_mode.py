import os
import subprocess
import sys
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, delete, inspect, select, text
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue, SmartCallMode
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.smart_call_timer import process_expired_called_tickets
from tests.test_db import TestSessionLocal as SessionLocal


class SmartCallModeTest(unittest.TestCase):
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

        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.name == "Smart Mode Clinic 1"))
        if not cls.clinic1:
            cls.clinic1 = Clinic(name="Smart Mode Clinic 1", smart_call_timeout_seconds=60)
            cls.db.add(cls.clinic1)
            cls.db.commit()
            cls.db.refresh(cls.clinic1)

        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.name == "Smart Mode Clinic 2"))
        if not cls.clinic2:
            cls.clinic2 = Clinic(name="Smart Mode Clinic 2", smart_call_timeout_seconds=60)
            cls.db.add(cls.clinic2)
            cls.db.commit()
            cls.db.refresh(cls.clinic2)

        cls.spec1 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic1.id,
                Specialization.name_uz == "Auto Mode Spec 1",
            )
        )
        if not cls.spec1:
            cls.spec1 = Specialization(
                clinic_id=cls.clinic1.id,
                name_uz="Auto Mode Spec 1",
                name_ru="Авто Спец 1",
                name_en="Auto Mode Spec 1",
            )
            cls.db.add(cls.spec1)
            cls.db.commit()
            cls.db.refresh(cls.spec1)

        cls.spec2 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic2.id,
                Specialization.name_uz == "Auto Mode Spec 2",
            )
        )
        if not cls.spec2:
            cls.spec2 = Specialization(
                clinic_id=cls.clinic2.id,
                name_uz="Auto Mode Spec 2",
                name_ru="Авто Спец 2",
                name_en="Auto Mode Spec 2",
            )
            cls.db.add(cls.spec2)
            cls.db.commit()
            cls.db.refresh(cls.spec2)

        cls.doctor1 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec1.id, "Dr. Mode Alpha", "101")
        cls.doctor2 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec1.id, "Dr. Mode Beta", "102")
        cls.doctor_other = cls._get_or_create_doctor(cls.clinic2.id, cls.spec2.id, "Dr. Mode Other", "201")

        cls.rec1 = cls._get_or_create_user(cls.clinic1.id, "Mode Rec 1", "+998906661001", UserRole.RECEPTIONIST)
        cls.rec2 = cls._get_or_create_user(cls.clinic2.id, "Mode Rec 2", "+998906661002", UserRole.RECEPTIONIST)
        cls.admin1 = cls._get_or_create_user(cls.clinic1.id, "Mode Admin 1", "+998906661003", UserRole.ADMIN)
        cls.p1 = cls._get_or_create_user(None, "Mode Patient 1", "+998906661004", UserRole.PATIENT)
        cls.p2 = cls._get_or_create_user(None, "Mode Patient 2", "+998906661005", UserRole.PATIENT)
        cls.p3 = cls._get_or_create_user(None, "Mode Patient 3", "+998906661006", UserRole.PATIENT)

        cls.rec1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"}
        cls.rec2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec2.id)}"}
        cls.admin1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin1.id)}"}
        cls.p1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p1.id)}"}

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
            doctor_ids = [self.doctor1.id, self.doctor2.id, self.doctor_other.id]
            q_ids = list(db.scalars(select(Queue.id).where(Queue.doctor_id.in_(doctor_ids))).all())
            if q_ids:
                db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
                db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
            db.commit()

    def _add_ticket(
        self,
        queue_id: int,
        number: int,
        *,
        patient: User | None = None,
        status: TicketStatus = TicketStatus.WAITING,
        checked_in: bool = True,
        called_at: datetime | None = None,
        call_deadline_at: datetime | None = None,
    ) -> QueueTicket:
        with SessionLocal() as db:
            now = datetime.now(timezone.utc)
            tk = QueueTicket(
                queue_id=queue_id,
                patient_id=patient.id if patient else None,
                ticket_number=number,
                queue_position=number,
                patient_name=patient.full_name if patient else f"WalkIn #{number}",
                patient_phone=patient.phone if patient else None,
                source=TicketSource.ONLINE if patient else TicketSource.WALK_IN,
                status=status,
                checked_in_at=now if checked_in else None,
                check_in_method=CheckInMethod.QR if checked_in else None,
                called_at=called_at,
                call_deadline_at=call_deadline_at,
            )
            db.add(tk)
            db.commit()
            db.refresh(tk)
            return tk

    def test_01_new_day_queue_defaults_to_manual_and_persists_per_date(self):
        today_res = self.client.post(
            "/api/queues/open",
            json={"doctor_id": self.doctor1.id},
            headers=self.rec1_headers,
        )
        self.assertEqual(today_res.status_code, 201)
        q_today = today_res.json()
        self.assertEqual(q_today["smart_call_mode"], "MANUAL")

        # Enable AUTOMATIC today
        mode_res = self.client.patch(
            f"/api/queues/{q_today['id']}/smart-call-mode",
            json={"mode": "AUTOMATIC"},
            headers=self.rec1_headers,
        )
        self.assertEqual(mode_res.status_code, 200)
        self.assertEqual(mode_res.json()["smart_call_mode"], "AUTOMATIC")

        # New day (tomorrow) still resets to MANUAL
        tomorrow = (date.today() + timedelta(days=1)).isoformat()
        next_res = self.client.post(
            "/api/queues/open",
            json={"doctor_id": self.doctor1.id, "queue_date": tomorrow},
            headers=self.rec1_headers,
        )
        self.assertEqual(next_res.status_code, 201)
        self.assertEqual(next_res.json()["smart_call_mode"], "MANUAL")

    def test_02_automatic_handoff_on_completion_chains_checked_in_patients(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        with patch("app.api.queues.notify_display_update") as mock_ws:
            mode_res = self.client.patch(
                f"/api/queues/{q['id']}/smart-call-mode",
                json={"mode": "AUTOMATIC"},
                headers=self.rec1_headers,
            )
            self.assertEqual(mode_res.status_code, 200)
            mock_ws.assert_called()

        t1 = self._add_ticket(q["id"], 1, patient=self.p1, checked_in=True)
        t2_unchecked = self._add_ticket(q["id"], 2, patient=self.p2, checked_in=False)
        t3 = self._add_ticket(q["id"], 3, patient=self.p3, checked_in=True)

        with patch("app.api.queues.schedule_called_notification") as mock_called, patch(
            "app.api.queues.schedule_completed_notification"
        ) as mock_comp, patch("app.api.queues.schedule_missed_turn_notification") as mock_missed, patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            # Reception initiates first call manually
            c1 = self.client.post(f"/api/queues/{q['id']}/call-next", headers=self.rec1_headers)
            self.assertEqual(c1.status_code, 200)
            self.assertEqual(c1.json()["id"], t1.id)
            mock_missed.assert_not_called()

            # Serve -> Complete triggers automatic handoff to t3 (repositioning t2_unchecked)
            s1 = self.client.patch(f"/api/queues/{q['id']}/tickets/{t1.id}/serve", headers=self.rec1_headers)
            self.assertEqual(s1.status_code, 200)

            mock_called.reset_mock()
            done1 = self.client.patch(
                f"/api/queues/{q['id']}/tickets/{t1.id}/complete", headers=self.rec1_headers
            )
            self.assertEqual(done1.status_code, 200)
            body = done1.json()
            self.assertEqual(body["status"], "COMPLETED")
            self.assertIsNotNone(body["auto_called_ticket"])
            self.assertEqual(body["auto_called_ticket"]["id"], t3.id)
            self.assertEqual(body["auto_called_ticket"]["status"], "CALLED")
            self.assertIsNotNone(body["auto_called_ticket"]["call_deadline_at"])
            mock_comp.assert_called_once()
            mock_missed.assert_called_once()
            mock_called.assert_called_once()

            # Serve t3 -> Complete -> no more checked-in patients -> remains idle with AUTOMATIC still on
            self.client.patch(f"/api/queues/{q['id']}/tickets/{t3.id}/serve", headers=self.rec1_headers)
            done3 = self.client.patch(
                f"/api/queues/{q['id']}/tickets/{t3.id}/complete", headers=self.rec1_headers
            )
            self.assertEqual(done3.status_code, 200)
            self.assertIsNone(done3.json()["auto_called_ticket"])

            with SessionLocal() as db:
                db_q = db.scalar(select(Queue).where(Queue.id == q["id"]))
                db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2_unchecked.id))
                self.assertEqual(db_q.smart_call_mode, SmartCallMode.AUTOMATIC)
                self.assertEqual(db_t2.status, TicketStatus.WAITING)

    def test_03_manual_mode_stops_after_completion_and_requires_manual_call(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.assertEqual(q["smart_call_mode"], "MANUAL")
        t1 = self._add_ticket(q["id"], 1, patient=self.p1, checked_in=True)
        t2 = self._add_ticket(q["id"], 2, patient=self.p2, checked_in=True)

        with patch("app.api.queues.schedule_called_notification") as mock_called, patch(
            "app.api.queues.schedule_completed_notification"
        ), patch("app.api.queues.schedule_approaching_check"), patch("app.api.queues.notify_display_update"):
            self.client.post(f"/api/queues/{q['id']}/call-next", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q['id']}/tickets/{t1.id}/serve", headers=self.rec1_headers)
            mock_called.reset_mock()

            done1 = self.client.patch(
                f"/api/queues/{q['id']}/tickets/{t1.id}/complete", headers=self.rec1_headers
            )
            self.assertEqual(done1.status_code, 200)
            self.assertIsNone(done1.json()["auto_called_ticket"])
            mock_called.assert_not_called()

            with SessionLocal() as db:
                db_t2 = db.scalar(select(QueueTicket).where(QueueTicket.id == t2.id))
                self.assertEqual(db_t2.status, TicketStatus.WAITING)

            # Reception can press Call Next to manually call t2
            c2 = self.client.post(f"/api/queues/{q['id']}/call-next", headers=self.rec1_headers)
            self.assertEqual(c2.status_code, 200)
            self.assertEqual(c2.json()["id"], t2.id)

    def test_04_timeout_behavior_automatic_vs_manual(self):
        q_auto = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.client.patch(
            f"/api/queues/{q_auto['id']}/smart-call-mode",
            json={"mode": "AUTOMATIC"},
            headers=self.rec1_headers,
        )
        q_manual = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor2.id}, headers=self.rec1_headers
        ).json()

        now = datetime.now(timezone.utc)
        t_auto_exp = self._add_ticket(
            q_auto["id"], 1, patient=self.p1, status=TicketStatus.CALLED,
            checked_in=True, called_at=now - timedelta(seconds=90), call_deadline_at=now - timedelta(seconds=5),
        )
        t_auto_next = self._add_ticket(q_auto["id"], 2, patient=self.p2, checked_in=True)

        t_man_exp = self._add_ticket(
            q_manual["id"], 1, patient=self.p3, status=TicketStatus.CALLED,
            checked_in=True, called_at=now - timedelta(seconds=90), call_deadline_at=now - timedelta(seconds=5),
        )
        t_man_wait = self._add_ticket(q_manual["id"], 2, checked_in=True)

        with patch("app.services.smart_call_timer.trigger_skipped_notification") as mock_skip, patch(
            "app.services.smart_call_timer.trigger_called_notification"
        ) as mock_called, patch("app.services.smart_call_timer.check_and_trigger_approaching"), patch(
            "app.services.smart_call_timer.notify_display_update"
        ):
            events = process_expired_called_tickets(now=now)
            self.assertEqual(len(events), 2)
            # Only q_auto called next; q_manual skipped without calling t_man_wait
            self.assertEqual(mock_skip.call_count, 2)
            mock_called.assert_called_once_with(t_auto_next.id, self.doctor1.room_number)

        with SessionLocal() as db:
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_auto_exp.id)), TicketStatus.SKIPPED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_auto_next.id)), TicketStatus.CALLED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_man_exp.id)), TicketStatus.SKIPPED)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t_man_wait.id)), TicketStatus.WAITING)

    def test_05_switching_mode_mid_patient_does_not_interrupt_and_controls_future_handoff(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.client.patch(
            f"/api/queues/{q['id']}/smart-call-mode", json={"mode": "AUTOMATIC"}, headers=self.rec1_headers
        )
        t1 = self._add_ticket(q["id"], 1, patient=self.p1, checked_in=True)
        t2 = self._add_ticket(q["id"], 2, patient=self.p2, checked_in=True)

        with patch("app.api.queues.schedule_called_notification"), patch(
            "app.api.queues.schedule_completed_notification"
        ), patch("app.api.queues.schedule_approaching_check"), patch("app.api.queues.notify_display_update"):
            self.client.post(f"/api/queues/{q['id']}/call-next", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q['id']}/tickets/{t1.id}/serve", headers=self.rec1_headers)

            # Switch OFF while t1 is SERVING -> t1 stays SERVING
            off_res = self.client.patch(
                f"/api/queues/{q['id']}/smart-call-mode", json={"mode": "MANUAL"}, headers=self.rec1_headers
            )
            self.assertEqual(off_res.status_code, 200)
            self.assertEqual(off_res.json()["smart_call_mode"], "MANUAL")

            with SessionLocal() as db:
                self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t1.id)), TicketStatus.SERVING)

            # Completing t1 now obeys MANUAL and does NOT call t2
            done = self.client.patch(
                f"/api/queues/{q['id']}/tickets/{t1.id}/complete", headers=self.rec1_headers
            )
            self.assertIsNone(done.json()["auto_called_ticket"])
            with SessionLocal() as db:
                self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t2.id)), TicketStatus.WAITING)

    def test_06_pause_suspends_automatic_handoffs_and_resume_does_not_duplicate_call(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.client.patch(
            f"/api/queues/{q['id']}/smart-call-mode", json={"mode": "AUTOMATIC"}, headers=self.rec1_headers
        )
        t1 = self._add_ticket(q["id"], 1, patient=self.p1, status=TicketStatus.SERVING, checked_in=True)
        t2 = self._add_ticket(q["id"], 2, patient=self.p2, checked_in=True)

        with patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_paused_notification"
        ), patch("app.api.queues.schedule_resumed_notification"), patch(
            "app.api.queues.schedule_completed_notification"
        ), patch("app.api.queues.schedule_approaching_check"):
            # Pause queue -> completing serving ticket must NOT auto-call while paused
            self.client.patch(f"/api/queues/{q['id']}/pause", headers=self.rec1_headers)
            done = self.client.patch(
                f"/api/queues/{q['id']}/tickets/{t1.id}/complete", headers=self.rec1_headers
            )
            self.assertEqual(done.status_code, 200)
            self.assertIsNone(done.json()["auto_called_ticket"])

            # Resume must NOT auto-spawn calls when idle
            res = self.client.patch(f"/api/queues/{q['id']}/resume", headers=self.rec1_headers)
            self.assertEqual(res.status_code, 200)
            with SessionLocal() as db:
                self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t2.id)), TicketStatus.WAITING)

    def test_07_mode_persists_through_backend_reload_and_reception_overview(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.client.patch(
            f"/api/queues/{q['id']}/smart-call-mode", json={"mode": "AUTOMATIC"}, headers=self.rec1_headers
        )

        # Fresh HTTP fetch (simulating browser refresh / new backend session) sees persisted AUTOMATIC
        overview = self.client.get("/api/queues/reception/today", headers=self.rec1_headers)
        self.assertEqual(overview.status_code, 200)
        q_row = [x for x in overview.json() if x["queue_id"] == q["id"]][0]
        self.assertEqual(q_row["smart_call_mode"], "AUTOMATIC")

    def test_08_permissions_clinic_isolation_and_db_constraint_enforcement(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()

        # Patient forbidden
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q['id']}/smart-call-mode",
                json={"mode": "AUTOMATIC"},
                headers=self.p1_headers,
            ).status_code,
            403,
        )
        # Other clinic receptionist forbidden
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q['id']}/smart-call-mode",
                json={"mode": "AUTOMATIC"},
                headers=self.rec2_headers,
            ).status_code,
            403,
        )
        # Invalid enum rejected at API
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q['id']}/smart-call-mode",
                json={"mode": "TURBO"},
                headers=self.rec1_headers,
            ).status_code,
            422,
        )
        # DB-level CHECK constraint rejects invalid value
        with SessionLocal() as db:
            with self.assertRaises(IntegrityError):
                db.execute(
                    text("UPDATE queues SET smart_call_mode = 'TURBO' WHERE id = :qid"),
                    {"qid": q["id"]},
                )
                db.commit()
            db.rollback()

    def test_09_concurrency_complete_and_call_next_never_double_call(self):
        q = self.client.post(
            "/api/queues/open", json={"doctor_id": self.doctor1.id}, headers=self.rec1_headers
        ).json()
        self.client.patch(
            f"/api/queues/{q['id']}/smart-call-mode", json={"mode": "AUTOMATIC"}, headers=self.rec1_headers
        )
        t1 = self._add_ticket(q["id"], 1, patient=self.p1, status=TicketStatus.SERVING, checked_in=True)
        t2 = self._add_ticket(q["id"], 2, patient=self.p2, checked_in=True)
        t3 = self._add_ticket(q["id"], 3, patient=self.p3, checked_in=True)

        statuses: list[int] = []
        barrier = threading.Barrier(2)

        def finish_t1():
            barrier.wait()
            with patch("app.api.queues.schedule_completed_notification"), patch(
                "app.api.queues.schedule_called_notification"
            ), patch("app.api.queues.schedule_approaching_check"), patch("app.api.queues.notify_display_update"):
                res = self.client.patch(
                    f"/api/queues/{q['id']}/tickets/{t1.id}/complete", headers=self.rec1_headers
                )
                statuses.append(res.status_code)

        def call_next_racer():
            barrier.wait()
            with patch("app.api.queues.schedule_called_notification"), patch(
                "app.api.queues.schedule_approaching_check"
            ), patch("app.api.queues.notify_display_update"):
                res = self.client.post(f"/api/queues/{q['id']}/call-next", headers=self.rec1_headers)
                statuses.append(res.status_code)

        ta = threading.Thread(target=finish_t1)
        tb = threading.Thread(target=call_next_racer)
        ta.start()
        tb.start()
        ta.join()
        tb.join()

        self.assertIn(200, statuses)
        with SessionLocal() as db:
            called_rows = list(
                db.scalars(
                    select(QueueTicket).where(
                        QueueTicket.queue_id == q["id"],
                        QueueTicket.status == TicketStatus.CALLED,
                    )
                ).all()
            )
            # At most one patient CALLED (never t2 AND t3 simultaneously)
            self.assertEqual(len(called_rows), 1)
            self.assertIn(called_rows[0].id, {t2.id, t3.id})

    def test_10_isolated_schema_and_migration_constraints_verified(self):
        test_url = os.getenv("TEST_DATABASE_URL") or settings.TEST_DATABASE_URL
        backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        env = os.environ.copy()
        env["ALEMBIC_DATABASE_URL"] = test_url

        # Verify column metadata & check constraint exist on isolated test DB
        eng = create_engine(test_url)
        insp = inspect(eng)
        cols = {c["name"]: c for c in insp.get_columns("queues")}
        self.assertIn("smart_call_mode", cols)
        self.assertFalse(cols["smart_call_mode"]["nullable"])
        checks = {c["name"] for c in insp.get_check_constraints("queues")}
        self.assertIn("ck_queue_smart_call_mode_valid", checks)
        eng.dispose()

        # Verify alembic current points at head on isolated test DB
        cur = subprocess.run(
            [sys.executable, "-m", "alembic", "current"],
            cwd=backend_dir,
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("a2b3c4d5e6f7", cur.stdout)


if __name__ == "__main__":
    unittest.main()
