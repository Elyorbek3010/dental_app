import unittest
from datetime import date
from unittest.mock import AsyncMock, patch

from tests.test_db import TestSessionLocal as SessionLocal
from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class AdminAnalyticsRealtimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic1:
            cls.clinic1 = Clinic(id=1, name="Bug4 Clinic 1")
            cls.db.add(cls.clinic1)
            cls.db.commit()

        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.id == 2))
        if not cls.clinic2:
            cls.clinic2 = Clinic(id=2, name="Bug4 Clinic 2")
            cls.db.add(cls.clinic2)
            cls.db.commit()

        cls.spec1 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic1.id,
                Specialization.name_uz == "Bug4 Terapiya",
            )
        )
        if not cls.spec1:
            cls.spec1 = Specialization(
                clinic_id=cls.clinic1.id,
                name_uz="Bug4 Terapiya",
                name_ru="Bug4 Терапия",
                name_en="Bug4 Therapy",
                is_active=True,
            )
            cls.db.add(cls.spec1)
            cls.db.commit()
            cls.db.refresh(cls.spec1)

        cls.spec2 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic2.id,
                Specialization.name_uz == "Bug4 C2 Terapiya",
            )
        )
        if not cls.spec2:
            cls.spec2 = Specialization(
                clinic_id=cls.clinic2.id,
                name_uz="Bug4 C2 Terapiya",
                name_ru="Bug4 C2 Терапия",
                name_en="Bug4 C2 Therapy",
                is_active=True,
            )
            cls.db.add(cls.spec2)
            cls.db.commit()
            cls.db.refresh(cls.spec2)

        cls.doc1a = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Bug4 Clinic1 A")
        )
        if not cls.doc1a:
            cls.doc1a = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec1.id,
                full_name="Dr. Bug4 Clinic1 A",
                room_number="101",
                is_active=True,
            )
            cls.db.add(cls.doc1a)
            cls.db.commit()
            cls.db.refresh(cls.doc1a)

        cls.doc1b = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Bug4 Clinic1 B")
        )
        if not cls.doc1b:
            cls.doc1b = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec1.id,
                full_name="Dr. Bug4 Clinic1 B",
                room_number="102",
                is_active=True,
            )
            cls.db.add(cls.doc1b)
            cls.db.commit()
            cls.db.refresh(cls.doc1b)

        cls.doc2 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Bug4 Clinic2")
        )
        if not cls.doc2:
            cls.doc2 = Doctor(
                clinic_id=cls.clinic2.id,
                specialization_id=cls.spec2.id,
                full_name="Dr. Bug4 Clinic2",
                room_number="201",
                is_active=True,
            )
            cls.db.add(cls.doc2)
            cls.db.commit()
            cls.db.refresh(cls.doc2)

        def _get_or_create_user(phone: str, full_name: str, role: UserRole, clinic_id: int | None):
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

        cls.admin1 = _get_or_create_user("+998906660001", "Bug4 Admin 1", UserRole.ADMIN, cls.clinic1.id)
        cls.rec1 = _get_or_create_user("+998906660002", "Bug4 Rec 1", UserRole.RECEPTIONIST, cls.clinic1.id)
        cls.rec2 = _get_or_create_user("+998906660003", "Bug4 Rec 2", UserRole.RECEPTIONIST, cls.clinic2.id)
        cls.patient = _get_or_create_user("+998906660004", "Bug4 Private Patient", UserRole.PATIENT, None)

        cls.admin1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin1.id)}"}
        cls.rec1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"}
        cls.rec2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec2.id)}"}
        cls.patient_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.patient.id)}"}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        today = date.today()
        # Clean today's queues across all doctors in clinic1 and clinic2 to avoid cross-test bleed
        doc_ids = self.db.scalars(
            select(Doctor.id).where(Doctor.clinic_id.in_([self.clinic1.id, self.clinic2.id]))
        ).all()
        if doc_ids:
            q_ids = self.db.scalars(
                select(Queue.id).where(Queue.doctor_id.in_(doc_ids), Queue.queue_date == today)
            ).all()
            if q_ids:
                self.db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
                self.db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
                self.db.commit()

    def _open_queue(self, doctor_id: int, headers: dict[str, str]) -> int:
        res = self.client.post("/api/queues/open", json={"doctor_id": doctor_id}, headers=headers)
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    def _complete_ticket(self, queue_id: int, ticket_id: int, headers: dict[str, str]):
        r1 = self.client.patch(f"/api/queues/{queue_id}/tickets/{ticket_id}/call", headers=headers)
        self.assertEqual(r1.status_code, 200)
        r2 = self.client.patch(f"/api/queues/{queue_id}/tickets/{ticket_id}/serve", headers=headers)
        self.assertEqual(r2.status_code, 200)
        r3 = self.client.patch(f"/api/queues/{queue_id}/tickets/{ticket_id}/complete", headers=headers)
        self.assertEqual(r3.status_code, 200)
        self.assertEqual(r3.json()["status"], "COMPLETED")

    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_completing_online_and_walkin_broadcasts_and_updates_admin_analytics(
        self, mock_broadcast
    ):
        q1_id = self._open_queue(self.doc1a.id, self.rec1_headers)
        q2_id = self._open_queue(self.doc1b.id, self.rec1_headers)

        # Initial Admin analytics = 0 completed
        init_res = self.client.get("/api/admin/analytics/overview", headers=self.admin1_headers)
        self.assertEqual(init_res.status_code, 200)
        self.assertEqual(init_res.json()["today_tickets_completed"], 0)

        # 1. ONLINE patient joins doc1a and completes
        join_res = self.client.post(f"/api/queues/{q1_id}/join", headers=self.patient_headers)
        self.assertEqual(join_res.status_code, 201)
        online_tid = join_res.json()["id"]
        self.client.patch(f"/api/queues/{q1_id}/tickets/{online_tid}/check-in", headers=self.rec1_headers)

        mock_broadcast.reset_mock()
        self._complete_ticket(q1_id, online_tid, self.rec1_headers)

        # Verify privacy-safe display_updated broadcast occurred for clinic1
        self.assertTrue(mock_broadcast.called)
        c1_events = [
            call.args[1]
            for call in mock_broadcast.call_args_list
            if call.args[0] == self.clinic1.id
        ]
        self.assertTrue(any(e.get("type") == "display_updated" and e.get("queue_id") == q1_id for e in c1_events))
        self.assertNotIn("Bug4 Private Patient", str(c1_events))
        self.assertNotIn("+998906660004", str(c1_events))

        after_online = self.client.get("/api/admin/analytics/overview", headers=self.admin1_headers).json()
        self.assertEqual(after_online["today_tickets_completed"], 1)
        doc1a_summary = next(d for d in after_online["doctors_today"] if d["doctor_id"] == self.doc1a.id)
        doc1b_summary = next(d for d in after_online["doctors_today"] if d["doctor_id"] == self.doc1b.id)
        self.assertEqual(doc1a_summary["completed_tickets"], 1)
        self.assertEqual(doc1b_summary["completed_tickets"], 0)

        # 2. WALK_IN patient joins doc1b and completes
        walkin_res = self.client.post(
            f"/api/queues/{q2_id}/walk-in",
            json={"patient_name": "WalkIn Bug4"},
            headers=self.rec1_headers,
        )
        self.assertEqual(walkin_res.status_code, 201)
        walkin_tid = walkin_res.json()["id"]

        mock_broadcast.reset_mock()
        self._complete_ticket(q2_id, walkin_tid, self.rec1_headers)

        self.assertTrue(
            any(
                call.args[0] == self.clinic1.id
                and call.args[1].get("type") == "display_updated"
                and call.args[1].get("queue_id") == q2_id
                for call in mock_broadcast.call_args_list
            )
        )

        after_walkin = self.client.get("/api/admin/analytics/overview", headers=self.admin1_headers).json()
        self.assertEqual(after_walkin["today_tickets_completed"], 2)
        self.assertEqual(after_walkin["today_tickets_total"], 2)
        doc1a_summary2 = next(d for d in after_walkin["doctors_today"] if d["doctor_id"] == self.doc1a.id)
        doc1b_summary2 = next(d for d in after_walkin["doctors_today"] if d["doctor_id"] == self.doc1b.id)
        self.assertEqual(doc1a_summary2["completed_tickets"], 1)
        self.assertEqual(doc1b_summary2["completed_tickets"], 1)

    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_clinic_isolation_preserved_on_completion_and_analytics(self, mock_broadcast):
        q2_c2_id = self._open_queue(self.doc2.id, self.rec2_headers)
        walkin_res = self.client.post(
            f"/api/queues/{q2_c2_id}/walk-in",
            json={"patient_name": "Clinic2 WalkIn"},
            headers=self.rec2_headers,
        )
        self.assertEqual(walkin_res.status_code, 201)
        tid = walkin_res.json()["id"]

        mock_broadcast.reset_mock()
        self._complete_ticket(q2_c2_id, tid, self.rec2_headers)

        # Broadcast only went to clinic2, never clinic1
        broadcast_clinics = {call.args[0] for call in mock_broadcast.call_args_list}
        self.assertEqual(broadcast_clinics, {self.clinic2.id})

        # Clinic 1 Admin analytics unaffected and does not list clinic2 doctors
        c1_analytics = self.client.get("/api/admin/analytics/overview", headers=self.admin1_headers).json()
        self.assertEqual(c1_analytics["today_tickets_completed"], 0)
        self.assertFalse(any(d["doctor_id"] == self.doc2.id for d in c1_analytics["doctors_today"]))


if __name__ == "__main__":
    unittest.main()
