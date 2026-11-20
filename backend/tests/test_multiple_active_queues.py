import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

from tests.test_db import TestSessionLocal as SessionLocal
from fastapi.testclient import TestClient
from sqlalchemy import delete, select, text

from app.core.security import create_access_token, create_check_in_qr_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class MultipleActiveQueuesTest(unittest.TestCase):
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

        cls.clinic1 = cls._get_or_create_clinic("Bug6 Clinic 1", timeout=120)
        cls.clinic2 = cls._get_or_create_clinic("Bug6 Clinic 2", timeout=90)

        cls.spec_ortho = cls._get_or_create_spec(cls.clinic1.id, "Ortodontiya", "Ортодонтия", "Orthodontist")
        cls.spec_surgeon = cls._get_or_create_spec(cls.clinic1.id, "Xirurgiya", "Хирургия", "Surgeon")
        cls.spec_therapist = cls._get_or_create_spec(cls.clinic1.id, "Terapevt", "Терапевт", "Therapist")
        cls.spec_c2_ortho = cls._get_or_create_spec(cls.clinic2.id, "Klinika2 Orto", "Клиника2 Орто", "Clinic2 Ortho")

        cls.doc_ortho_a = cls._get_or_create_doctor(cls.clinic1.id, cls.spec_ortho.id, "Dr. Ortho A", "101")
        cls.doc_ortho_b = cls._get_or_create_doctor(cls.clinic1.id, cls.spec_ortho.id, "Dr. Ortho B", "102")
        cls.doc_surgeon = cls._get_or_create_doctor(cls.clinic1.id, cls.spec_surgeon.id, "Dr. Surgeon A", "201")
        cls.doc_therapist = cls._get_or_create_doctor(cls.clinic1.id, cls.spec_therapist.id, "Dr. Therapist A", "301")
        cls.doc_c2 = cls._get_or_create_doctor(cls.clinic2.id, cls.spec_c2_ortho.id, "Dr. Clinic2", "401")

        cls.rec1 = cls._get_or_create_user(cls.clinic1.id, "Bug6 Rec 1", "+998904440001", UserRole.RECEPTIONIST)
        cls.patient1 = cls._get_or_create_user(None, "Bug6 Patient 1", "+998904440002", UserRole.PATIENT)
        cls.patient2 = cls._get_or_create_user(None, "Bug6 Patient 2", "+998904440003", UserRole.PATIENT)

        cls.rec1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"}
        cls.p1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.patient1.id)}"}
        cls.p2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.patient2.id)}"}

    @classmethod
    def _get_or_create_clinic(cls, name: str, *, timeout: int = 120) -> Clinic:
        c = cls.db.scalar(select(Clinic).where(Clinic.name == name))
        if not c:
            c = Clinic(name=name, smart_call_timeout_seconds=timeout)
            cls.db.add(c)
            cls.db.commit()
            cls.db.refresh(c)
        return c

    @classmethod
    def _get_or_create_spec(cls, clinic_id: int, uz: str, ru: str, en: str) -> Specialization:
        s = cls.db.scalar(
            select(Specialization).where(Specialization.clinic_id == clinic_id, Specialization.name_uz == uz)
        )
        if not s:
            s = Specialization(clinic_id=clinic_id, name_uz=uz, name_ru=ru, name_en=en, is_active=True)
            cls.db.add(s)
            cls.db.commit()
            cls.db.refresh(s)
        return s

    @classmethod
    def _get_or_create_doctor(cls, clinic_id: int, spec_id: int, name: str, room: str) -> Doctor:
        d = cls.db.scalar(select(Doctor).where(Doctor.clinic_id == clinic_id, Doctor.full_name == name))
        if not d:
            d = Doctor(
                clinic_id=clinic_id,
                specialization_id=spec_id,
                full_name=name,
                room_number=room,
                is_active=True,
            )
            cls.db.add(d)
            cls.db.commit()
            cls.db.refresh(d)
        return d

    @classmethod
    def _get_or_create_user(cls, clinic_id: int | None, name: str, phone: str, role: UserRole) -> User:
        u = cls.db.scalar(select(User).where(User.phone == phone))
        if not u:
            u = User(
                clinic_id=clinic_id,
                full_name=name,
                phone=phone,
                hashed_password="x",
                role=role,
                is_active=True,
            )
            cls.db.add(u)
            cls.db.commit()
            cls.db.refresh(u)
        return u

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        with SessionLocal() as db:
            doc_ids = [
                self.doc_ortho_a.id,
                self.doc_ortho_b.id,
                self.doc_surgeon.id,
                self.doc_therapist.id,
                self.doc_c2.id,
            ]
            q_ids = list(db.scalars(select(Queue.id).where(Queue.doctor_id.in_(doc_ids))).all())
            if q_ids:
                db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
                db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
            db.commit()

    def _create_queue(
        self,
        doctor: Doctor,
        *,
        queue_date: date | None = None,
        is_active: bool = True,
        is_paused: bool = False,
    ) -> Queue:
        with SessionLocal() as db:
            q = Queue(
                doctor_id=doctor.id,
                queue_date=queue_date or date.today(),
                is_active=is_active,
                is_paused=is_paused,
            )
            db.add(q)
            db.commit()
            db.refresh(q)
            return q

    def _add_walkin(self, queue_id: int, number: int, status: TicketStatus = TicketStatus.WAITING) -> QueueTicket:
        with SessionLocal() as db:
            t = QueueTicket(
                queue_id=queue_id,
                patient_id=None,
                ticket_number=number,
                queue_position=number,
                patient_name=f"WalkIn {number}",
                source=TicketSource.WALK_IN,
                status=status,
                checked_in_at=datetime.now(timezone.utc),
                check_in_method=CheckInMethod.WALK_IN,
            )
            db.add(t)
            db.commit()
            db.refresh(t)
            return t

    def test_01_join_different_specializations_and_my_tickets_returns_both(self):
        q_ortho = self._create_queue(self.doc_ortho_a)
        q_surgeon = self._create_queue(self.doc_surgeon)
        self._add_walkin(q_surgeon.id, 1, TicketStatus.WAITING)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            r1 = self.client.post(f"/api/queues/{q_ortho.id}/join", headers=self.p1_headers)
            self.assertEqual(r1.status_code, 201)
            r2 = self.client.post(f"/api/queues/{q_surgeon.id}/join", headers=self.p1_headers)
            self.assertEqual(r2.status_code, 201)

        res = self.client.get(
            "/api/queues/my-tickets",
            headers={**self.p1_headers, "Accept-Language": "en"},
        )
        self.assertEqual(res.status_code, 200)
        tickets = res.json()
        self.assertEqual(len(tickets), 2)
        specs = {t["specialization"]["name"]: t for t in tickets}
        self.assertEqual(specs["Orthodontist"]["people_ahead"], 0)
        self.assertEqual(specs["Surgeon"]["people_ahead"], 1)
        self.assertEqual(specs["Orthodontist"]["doctor"]["full_name"], "Dr. Ortho A")
        self.assertEqual(specs["Surgeon"]["doctor"]["full_name"], "Dr. Surgeon A")

        # Legacy single-ticket endpoint remains intact and returns most recent ticket
        legacy = self.client.get("/api/queues/my-ticket", headers=self.p1_headers)
        self.assertEqual(legacy.status_code, 200)
        self.assertEqual(legacy.json()["id"], r2.json()["id"])

    def test_02_duplicate_same_specialization_blocked_until_completed_or_cancelled(self):
        q_ortho_a = self._create_queue(self.doc_ortho_a)
        q_ortho_b = self._create_queue(self.doc_ortho_b)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_skipped_notification"
        ), patch("app.api.queues.schedule_completed_notification"), patch(
            "app.api.queues.schedule_called_notification"
        ):
            r1 = self.client.post(f"/api/queues/{q_ortho_a.id}/join", headers=self.p1_headers)
            self.assertEqual(r1.status_code, 201)
            t1_id = r1.json()["id"]

            # Joining different doctor of SAME specialization while WAITING -> 409
            dup1 = self.client.post(f"/api/queues/{q_ortho_b.id}/join", headers=self.p1_headers)
            self.assertEqual(dup1.status_code, 409)
            self.assertIn("specialization", dup1.json()["detail"].lower())

            # Skip t1 -> STILL unresolved, so joining Dr. Ortho B remains blocked (409)
            self.assertEqual(
                self.client.patch(
                    f"/api/queues/{q_ortho_a.id}/tickets/{t1_id}/skip",
                    headers=self.rec1_headers,
                ).status_code,
                200,
            )
            dup2 = self.client.post(f"/api/queues/{q_ortho_b.id}/join", headers=self.p1_headers)
            self.assertEqual(dup2.status_code, 409)

            # Cancel t1 -> resolved -> patient CAN now book Dr. Ortho B
            self.assertEqual(
                self.client.patch(
                    f"/api/queues/{q_ortho_a.id}/tickets/{t1_id}/cancel",
                    headers=self.p1_headers,
                ).status_code,
                200,
            )
            r2 = self.client.post(f"/api/queues/{q_ortho_b.id}/join", headers=self.p1_headers)
            self.assertEqual(r2.status_code, 201)
            t2_id = r2.json()["id"]

            # Complete t2 -> resolved -> patient CAN re-book Dr. Ortho A
            self.client.patch(f"/api/queues/{q_ortho_b.id}/tickets/{t2_id}/call", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q_ortho_b.id}/tickets/{t2_id}/serve", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q_ortho_b.id}/tickets/{t2_id}/complete", headers=self.rec1_headers)

            r3 = self.client.post(f"/api/queues/{q_ortho_a.id}/join", headers=self.p1_headers)
            self.assertEqual(r3.status_code, 201)

    def test_03_concurrent_same_specialization_joins_allow_only_one(self):
        q_ortho_a = self._create_queue(self.doc_ortho_a)
        q_ortho_b = self._create_queue(self.doc_ortho_b)

        barrier = threading.Barrier(2)
        statuses: list[int] = []

        def join_worker(qid: int):
            barrier.wait()
            r = self.client.post(f"/api/queues/{qid}/join", headers=self.p1_headers)
            statuses.append(r.status_code)

        t_a = threading.Thread(target=join_worker, args=(q_ortho_a.id,))
        t_b = threading.Thread(target=join_worker, args=(q_ortho_b.id,))
        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            t_a.start()
            t_b.start()
            t_a.join()
            t_b.join()

        self.assertEqual(sorted(statuses), [201, 409])
        res = self.client.get("/api/queues/my-tickets", headers=self.p1_headers)
        self.assertEqual(len(res.json()), 1)

    def test_04_mixed_statuses_priority_ordering_and_historical_exclusion(self):
        q_ortho = self._create_queue(self.doc_ortho_a)
        q_surgeon = self._create_queue(self.doc_surgeon)
        q_therapist = self._create_queue(self.doc_therapist)
        q_yesterday = self._create_queue(self.doc_ortho_b, queue_date=date.today() - timedelta(days=1))

        with SessionLocal() as db:
            now = datetime.now(timezone.utc)
            # Historical yesterday WAITING + today COMPLETED should be excluded
            db.add(
                QueueTicket(
                    queue_id=q_yesterday.id,
                    patient_id=self.patient1.id,
                    ticket_number=1,
                    queue_position=1,
                    patient_name=self.patient1.full_name,
                    source=TicketSource.ONLINE,
                    status=TicketStatus.WAITING,
                )
            )
            # Orthodontist: SKIPPED
            db.add(
                QueueTicket(
                    queue_id=q_ortho.id,
                    patient_id=self.patient1.id,
                    ticket_number=5,
                    queue_position=1,
                    patient_name=self.patient1.full_name,
                    source=TicketSource.ONLINE,
                    status=TicketStatus.SKIPPED,
                )
            )
            # Surgeon: CALLED with deadline 1
            db.add(
                QueueTicket(
                    queue_id=q_surgeon.id,
                    patient_id=self.patient1.id,
                    ticket_number=12,
                    queue_position=1,
                    patient_name=self.patient1.full_name,
                    source=TicketSource.ONLINE,
                    status=TicketStatus.CALLED,
                    called_at=now,
                    call_deadline_at=now + timedelta(seconds=90),
                )
            )
            # Therapist: WAITING
            db.add(
                QueueTicket(
                    queue_id=q_therapist.id,
                    patient_id=self.patient1.id,
                    ticket_number=3,
                    queue_position=1,
                    patient_name=self.patient1.full_name,
                    source=TicketSource.ONLINE,
                    status=TicketStatus.WAITING,
                )
            )
            db.commit()

        # Without include_skipped: CALLED, WAITING (ordered CALLED first)
        res_no_skip = self.client.get("/api/queues/my-tickets", headers=self.p1_headers)
        self.assertEqual(res_no_skip.status_code, 200)
        self.assertEqual([t["status"] for t in res_no_skip.json()], ["CALLED", "WAITING"])

        # With include_skipped=true: CALLED, WAITING, SKIPPED (yesterday excluded)
        res_with_skip = self.client.get(
            "/api/queues/my-tickets?include_skipped=true",
            headers=self.p1_headers,
        )
        self.assertEqual(res_with_skip.status_code, 200)
        items = res_with_skip.json()
        self.assertEqual([t["status"] for t in items], ["CALLED", "WAITING", "SKIPPED"])
        self.assertIsNotNone(items[0]["call_deadline_at"])
        self.assertEqual(items[2]["people_ahead"], 0)

    def test_05_two_called_tickets_have_independent_deadlines_and_pause_isolation(self):
        q_ortho = self._create_queue(self.doc_ortho_a)
        q_surgeon = self._create_queue(self.doc_surgeon)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_called_notification"
        ), patch("app.api.queues.schedule_paused_notification"):
            t1 = self.client.post(f"/api/queues/{q_ortho.id}/join", headers=self.p1_headers).json()
            t2 = self.client.post(f"/api/queues/{q_surgeon.id}/join", headers=self.p1_headers).json()

            self.client.patch(f"/api/queues/{q_ortho.id}/tickets/{t1['id']}/call", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q_surgeon.id}/tickets/{t2['id']}/call", headers=self.rec1_headers)

            # Pause ONLY Orthodontist queue
            self.client.patch(f"/api/queues/{q_ortho.id}/pause", headers=self.rec1_headers)

        res = self.client.get("/api/queues/my-tickets", headers=self.p1_headers)
        self.assertEqual(res.status_code, 200)
        by_id = {t["id"]: t for t in res.json()}
        self.assertTrue(by_id[t1["id"]]["is_queue_paused"])
        self.assertIsNotNone(by_id[t1["id"]]["paused_remaining_seconds"])
        self.assertIsNone(by_id[t1["id"]]["call_deadline_at"])

        self.assertFalse(by_id[t2["id"]]["is_queue_paused"])
        self.assertIsNone(by_id[t2["id"]]["paused_remaining_seconds"])
        self.assertIsNotNone(by_id[t2["id"]]["call_deadline_at"])

    def test_06_qr_check_in_ticket_targeting_and_legacy_multi_conflict(self):
        q_ortho = self._create_queue(self.doc_ortho_a)
        q_surgeon = self._create_queue(self.doc_surgeon)
        q_c2 = self._create_queue(self.doc_c2)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            t1 = self.client.post(f"/api/queues/{q_ortho.id}/join", headers=self.p1_headers).json()
            t2 = self.client.post(f"/api/queues/{q_surgeon.id}/join", headers=self.p1_headers).json()
            t_other_patient = self.client.post(f"/api/queues/{q_ortho.id}/join", headers=self.p2_headers).json()

        qr_c1 = create_check_in_qr_token(self.clinic1.id)
        qr_c2 = create_check_in_qr_token(self.clinic2.id)

        # Without ticket_id when 2 eligible waiting tickets exist -> 409 requesting ticket selection
        ambiguous = self.client.post(
            "/api/queues/check-in/qr",
            json={"token": qr_c1},
            headers=self.p1_headers,
        )
        self.assertEqual(ambiguous.status_code, 409)
        self.assertIn("select", ambiguous.json()["detail"].lower())

        # Cannot check in another patient's ticket (403)
        forbidden = self.client.post(
            "/api/queues/check-in/qr",
            json={"token": qr_c1, "ticket_id": t_other_patient["id"]},
            headers=self.p1_headers,
        )
        self.assertEqual(forbidden.status_code, 403)

        # Wrong clinic QR rejected for targeted ticket (404)
        wrong_clinic = self.client.post(
            "/api/queues/check-in/qr",
            json={"token": qr_c2, "ticket_id": t1["id"]},
            headers=self.p1_headers,
        )
        self.assertEqual(wrong_clinic.status_code, 404)

        # Targeted check-in of t1 leaves t2 unchecked in
        with patch("app.api.queues.notify_display_update"):
            ok = self.client.post(
                "/api/queues/check-in/qr",
                json={"token": qr_c1, "ticket_id": t1["id"]},
                headers=self.p1_headers,
            )
            self.assertEqual(ok.status_code, 200)
            self.assertEqual(ok.json()["id"], t1["id"])
            self.assertIsNotNone(ok.json()["checked_in_at"])

            # Now only t2 remains unchecked in clinic 1 -> legacy scan without ticket_id checks in t2 cleanly
            ok_legacy = self.client.post(
                "/api/queues/check-in/qr",
                json={"token": qr_c1},
                headers=self.p1_headers,
            )
            self.assertEqual(ok_legacy.status_code, 200)
            self.assertEqual(ok_legacy.json()["id"], t2["id"])

            # Clean unused q_c2 reference
            self.assertIsNotNone(q_c2.id)

    def test_07_targeted_cancel_and_ownership_preserves_other_specialist(self):
        q_ortho = self._create_queue(self.doc_ortho_a)
        q_surgeon = self._create_queue(self.doc_surgeon)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"), patch(
            "app.api.queues.schedule_called_notification"
        ):
            t1 = self.client.post(f"/api/queues/{q_ortho.id}/join", headers=self.p1_headers).json()
            t2 = self.client.post(f"/api/queues/{q_surgeon.id}/join", headers=self.p1_headers).json()
            self.client.patch(f"/api/queues/{q_ortho.id}/tickets/{t1['id']}/call", headers=self.rec1_headers)

            # Another patient cannot cancel p1's ticket
            self.assertEqual(
                self.client.patch(
                    f"/api/queues/{q_ortho.id}/tickets/{t1['id']}/cancel",
                    headers=self.p2_headers,
                ).status_code,
                403,
            )

            # p1 cancels ONLY t1 -> deadline cleared, t2 remains untouched
            c_res = self.client.patch(
                f"/api/queues/{q_ortho.id}/tickets/{t1['id']}/cancel",
                headers=self.p1_headers,
            )
            self.assertEqual(c_res.status_code, 200)
            self.assertEqual(c_res.json()["status"], "CANCELLED")
            self.assertIsNone(c_res.json()["call_deadline_at"])

        remaining = self.client.get("/api/queues/my-tickets", headers=self.p1_headers).json()
        self.assertEqual([t["id"] for t in remaining], [t2["id"]])
        self.assertEqual(remaining[0]["status"], "WAITING")


if __name__ == "__main__":
    unittest.main()
