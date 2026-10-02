import unittest
from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.security import create_access_token
from tests.test_db import TestSessionLocal as SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class DailyQueueOpenBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Clinic 1
        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic1:
            cls.clinic1 = Clinic(id=1, name="Dental Test Clinic 1")
            cls.db.add(cls.clinic1)
            cls.db.commit()

        # Clinic 2
        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.id == 2))
        if not cls.clinic2:
            cls.clinic2 = Clinic(id=2, name="Dental Test Clinic 2")
            cls.db.add(cls.clinic2)
            cls.db.commit()

        # Specialization
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

        # Doctor 1 (in Clinic 1, active)
        cls.doctor1 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Queue Test One")
        )
        if not cls.doctor1:
            cls.doctor1 = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Queue Test One",
                room_number="101",
                is_active=True,
            )
            cls.db.add(cls.doctor1)
            cls.db.commit()
            cls.db.refresh(cls.doctor1)

        # Doctor 2 (in Clinic 2, active)
        cls.doctor2 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Other Clinic Doctor")
        )
        if not cls.doctor2:
            cls.doctor2 = Doctor(
                clinic_id=cls.clinic2.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Other Clinic Doctor",
                room_number="202",
                is_active=True,
            )
            cls.db.add(cls.doctor2)
            cls.db.commit()
            cls.db.refresh(cls.doctor2)

        # Doctor 3 (in Clinic 1, inactive)
        cls.doctor_inactive = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Inactive Doctor")
        )
        if not cls.doctor_inactive:
            cls.doctor_inactive = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Inactive Doctor",
                room_number="103",
                is_active=False,
            )
            cls.db.add(cls.doctor_inactive)
            cls.db.commit()
            cls.db.refresh(cls.doctor_inactive)

        # Receptionist 1 (Clinic 1)
        cls.receptionist1 = cls.db.scalar(
            select(User).where(User.phone == "+998909990001")
        )
        if not cls.receptionist1:
            cls.receptionist1 = User(
                full_name="Receptionist Clinic 1",
                phone="+998909990001",
                hashed_password="hash",
                role=UserRole.RECEPTIONIST,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.receptionist1)
            cls.db.commit()
            cls.db.refresh(cls.receptionist1)

        cls.rec1_token = create_access_token(subject=cls.receptionist1.id)
        cls.rec1_headers = {"Authorization": f"Bearer {cls.rec1_token}"}

        # Patient User
        cls.patient = cls.db.scalar(select(User).where(User.phone == "+998909990002"))
        if not cls.patient:
            cls.patient = User(
                full_name="Patient Queue Test",
                phone="+998909990002",
                hashed_password="hash",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.patient)
            cls.db.commit()
            cls.db.refresh(cls.patient)

        cls.patient_token = create_access_token(subject=cls.patient.id)
        cls.patient_headers = {"Authorization": f"Bearer {cls.patient_token}"}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        # Clean up any queues for test doctors today so each test starts from known state
        today = date.today()
        doc_ids = [self.doctor1.id, self.doctor2.id, self.doctor_inactive.id]
        queues = self.db.scalars(
            select(Queue).where(
                Queue.doctor_id.in_(doc_ids),
                Queue.queue_date == today,
            )
        ).all()
        q_ids = [q.id for q in queues]
        if q_ids:
            self.db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
            self.db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
            self.db.commit()

    def test_receptionist_open_today_queue_success(self):
        """Receptionist can open today's queue for a doctor in their clinic via POST /api/queues/open."""
        payload = {"doctor_id": self.doctor1.id}
        res = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 201, res.text)
        data = res.json()
        self.assertEqual(data["doctor_id"], self.doctor1.id)
        self.assertEqual(data["queue_date"], str(date.today()))
        self.assertTrue(data["is_active"])
        self.assertFalse(data["is_paused"])
        queue_id = data["id"]

        # Verify it immediately appears in GET /api/queues/reception/today
        rec_res = self.client.get("/api/queues/reception/today", headers=self.rec1_headers)
        self.assertEqual(rec_res.status_code, 200)
        today_queues = rec_res.json()
        matching = [q for q in today_queues if q["queue_id"] == queue_id]
        self.assertEqual(len(matching), 1)
        self.assertEqual(matching[0]["doctor"]["id"], self.doctor1.id)
        self.assertEqual(matching[0]["waiting_count"], 0)

        # Verify patient catalog doctor queue endpoint immediately finds it
        pat_res = self.client.get(
            f"/api/catalog/doctors/{self.doctor1.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(pat_res.status_code, 200, pat_res.text)
        pat_queue = pat_res.json()
        self.assertEqual(pat_queue["id"], queue_id)
        self.assertTrue(pat_queue["is_active"])

    def test_open_queue_alias_endpoint(self):
        """POST /api/queues (root alias) also successfully opens today's queue."""
        payload = {"doctor_id": self.doctor1.id}
        res = self.client.post("/api/queues", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 201, res.text)
        self.assertEqual(res.json()["doctor_id"], self.doctor1.id)

    def test_open_queue_duplicate_conflict(self):
        """Attempting to open a second queue for the same doctor today returns 409 Conflict."""
        payload = {"doctor_id": self.doctor1.id}
        res1 = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res1.status_code, 201)

        # Second attempt without idempotent flag
        res2 = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res2.status_code, 409)
        self.assertIn("already exists", res2.json()["detail"].lower())

    def test_open_queue_idempotent_flag(self):
        """Calling with idempotent=True returns the existing queue with status 200/201 instead of 409."""
        payload = {"doctor_id": self.doctor1.id}
        res1 = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res1.status_code, 201)
        q1_id = res1.json()["id"]

        # Call again with idempotent=True
        payload_idempotent = {"doctor_id": self.doctor1.id, "idempotent": True}
        res2 = self.client.post("/api/queues/open", json=payload_idempotent, headers=self.rec1_headers)
        self.assertIn(res2.status_code, [200, 201])
        self.assertEqual(res2.json()["id"], q1_id)

    def test_receptionist_cannot_open_other_clinic_doctor(self):
        """Receptionist in clinic 1 cannot open queue for a doctor in clinic 2 (403 Forbidden)."""
        payload = {"doctor_id": self.doctor2.id}
        res = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 403)
        self.assertIn("another clinic", res.json()["detail"].lower())

    def test_patient_cannot_open_queue(self):
        """Patients are not authorized to open daily queues (403 Forbidden)."""
        payload = {"doctor_id": self.doctor1.id}
        res = self.client.post("/api/queues/open", json=payload, headers=self.patient_headers)
        self.assertEqual(res.status_code, 403)

    def test_open_queue_inactive_doctor(self):
        """Cannot open queue for an inactive doctor (409 Conflict)."""
        payload = {"doctor_id": self.doctor_inactive.id}
        res = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 409)
        self.assertIn("inactive", res.json()["detail"].lower())

    def test_open_queue_nonexistent_doctor(self):
        """Opening queue for non-existent doctor ID returns 404 Not Found."""
        payload = {"doctor_id": 999999}
        res = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 404)

    def test_open_queue_reactivates_inactive_queue(self):
        """Opening an existing inactive queue sets is_active=True and returns the queue."""
        # Create an inactive queue in DB
        today = date.today()
        inactive_queue = Queue(
            doctor_id=self.doctor1.id,
            queue_date=today,
            is_paused=False,
            is_active=False,
        )
        self.db.add(inactive_queue)
        self.db.commit()
        self.db.refresh(inactive_queue)

        payload = {"doctor_id": self.doctor1.id}
        res = self.client.post("/api/queues/open", json=payload, headers=self.rec1_headers)
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["id"], inactive_queue.id)
        self.assertTrue(data["is_active"])
