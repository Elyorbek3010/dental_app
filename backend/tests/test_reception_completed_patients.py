import unittest
from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from tests.test_db import TestSessionLocal as SessionLocal


class ReceptionCompletedPatientsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic1:
            cls.clinic1 = Clinic(id=1, name="Completed Test Clinic 1")
            cls.db.add(cls.clinic1)
            cls.db.commit()

        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.id == 2))
        if not cls.clinic2:
            cls.clinic2 = Clinic(id=2, name="Completed Test Clinic 2")
            cls.db.add(cls.clinic2)
            cls.db.commit()

        cls.spec = cls.db.scalar(select(Specialization).where(Specialization.id == 1))
        if not cls.spec:
            cls.spec = Specialization(
                id=1,
                clinic_id=cls.clinic1.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="Therapy",
            )
            cls.db.add(cls.spec)
            cls.db.commit()

        cls.doctor1 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Completed Test One")
        )
        if not cls.doctor1:
            cls.doctor1 = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Completed Test One",
                room_number="105",
                is_active=True,
            )
            cls.db.add(cls.doctor1)
            cls.db.commit()
            cls.db.refresh(cls.doctor1)

        cls.doctor2 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Completed Test Two")
        )
        if not cls.doctor2:
            cls.doctor2 = Doctor(
                clinic_id=cls.clinic2.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Completed Test Two",
                room_number="205",
                is_active=True,
            )
            cls.db.add(cls.doctor2)
            cls.db.commit()
            cls.db.refresh(cls.doctor2)

        cls.rec1 = cls.db.scalar(
            select(User).where(User.phone == "+998907770001")
        )
        if not cls.rec1:
            cls.rec1 = User(
                clinic_id=cls.clinic1.id,
                full_name="Rec Completed 1",
                phone="+998907770001",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            cls.db.add(cls.rec1)
            cls.db.commit()
            cls.db.refresh(cls.rec1)

        cls.rec2 = cls.db.scalar(
            select(User).where(User.phone == "+998907770002")
        )
        if not cls.rec2:
            cls.rec2 = User(
                clinic_id=cls.clinic2.id,
                full_name="Rec Completed 2",
                phone="+998907770002",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            cls.db.add(cls.rec2)
            cls.db.commit()
            cls.db.refresh(cls.rec2)

        cls.patient = cls.db.scalar(
            select(User).where(User.phone == "+998907770003")
        )
        if not cls.patient:
            cls.patient = User(
                clinic_id=None,
                full_name="Patient Completed Test",
                phone="+998907770003",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            cls.db.add(cls.patient)
            cls.db.commit()
            cls.db.refresh(cls.patient)

        cls.rec1_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"
        }
        cls.rec2_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.rec2.id)}"
        }
        cls.patient_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.patient.id)}"
        }

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        today = date.today()
        for doc in (self.doctor1, self.doctor2):
            q = self.db.scalar(
                select(Queue).where(Queue.doctor_id == doc.id, Queue.queue_date == today)
            )
            if q:
                self.db.execute(delete(QueueTicket).where(QueueTicket.queue_id == q.id))
                self.db.execute(delete(Queue).where(Queue.id == q.id))
        self.db.commit()

    def _open_queue(self, doctor_id: int, headers: dict[str, str]) -> int:
        res = self.client.post(
            "/api/queues/open",
            json={"doctor_id": doctor_id},
            headers=headers,
        )
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    def _complete_ticket(self, queue_id: int, ticket_id: int, headers: dict[str, str]):
        call_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/call",
            headers=headers,
        )
        self.assertEqual(call_res.status_code, 200)
        serve_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/serve",
            headers=headers,
        )
        self.assertEqual(serve_res.status_code, 200)
        complete_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/complete",
            headers=headers,
        )
        self.assertEqual(complete_res.status_code, 200)
        self.assertEqual(complete_res.json()["status"], TicketStatus.COMPLETED.value)

    def test_completed_online_and_walkin_counted_and_listed_in_reception(self):
        queue_id = self._open_queue(self.doctor1.id, self.rec1_headers)

        # 1. ONLINE patient joins and completes
        join_res = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(join_res.status_code, 201)
        online_ticket_id = join_res.json()["id"]
        self._complete_ticket(queue_id, online_ticket_id, self.rec1_headers)

        # 2. WALK_IN patient added and completes
        walkin_res = self.client.post(
            f"/api/queues/{queue_id}/walk-in",
            json={"patient_name": "WalkIn Completed"},
            headers=self.rec1_headers,
        )
        self.assertEqual(walkin_res.status_code, 201)
        walkin_ticket_id = walkin_res.json()["id"]
        self._complete_ticket(queue_id, walkin_ticket_id, self.rec1_headers)

        # 3. Extra WALK_IN patient remains WAITING
        waiting_res = self.client.post(
            f"/api/queues/{queue_id}/walk-in",
            json={"patient_name": "WalkIn Waiting"},
            headers=self.rec1_headers,
        )
        self.assertEqual(waiting_res.status_code, 201)

        # Verify reception today summary counts
        today_res = self.client.get("/api/queues/reception/today", headers=self.rec1_headers)
        self.assertEqual(today_res.status_code, 200)
        q_summary = next(q for q in today_res.json() if q["queue_id"] == queue_id)
        self.assertEqual(q_summary["completed_count"], 2)
        self.assertEqual(q_summary["waiting_count"], 1)
        self.assertEqual(q_summary["called_count"], 0)
        self.assertEqual(q_summary["serving_count"], 0)

        # Verify completed tickets remain persisted & returned in /tickets
        tickets_res = self.client.get(
            f"/api/queues/{queue_id}/tickets",
            headers=self.rec1_headers,
        )
        self.assertEqual(tickets_res.status_code, 200)
        tickets = tickets_res.json()
        completed = [t for t in tickets if t["status"] == "COMPLETED"]
        waiting = [t for t in tickets if t["status"] == "WAITING"]
        self.assertEqual(len(completed), 2)
        self.assertEqual({t["source"] for t in completed}, {"ONLINE", "WALK_IN"})
        self.assertEqual(len(waiting), 1)

        # Completed ticket cannot be called again
        re_call = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{online_ticket_id}/call",
            headers=self.rec1_headers,
        )
        self.assertEqual(re_call.status_code, 409)

    def test_cross_clinic_reception_isolation_for_completed_queues(self):
        queue1_id = self._open_queue(self.doctor1.id, self.rec1_headers)

        today_res_rec2 = self.client.get("/api/queues/reception/today", headers=self.rec2_headers)
        self.assertEqual(today_res_rec2.status_code, 200)
        self.assertFalse(any(q["queue_id"] == queue1_id for q in today_res_rec2.json()))

        tickets_res_rec2 = self.client.get(
            f"/api/queues/{queue1_id}/tickets",
            headers=self.rec2_headers,
        )
        self.assertEqual(tickets_res_rec2.status_code, 403)


if __name__ == "__main__":
    unittest.main()
