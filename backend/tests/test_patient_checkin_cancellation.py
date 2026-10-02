import unittest
from datetime import date, datetime, timedelta, timezone
from jose import jwt

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.config import settings
from app.core.security import create_access_token
from tests.test_db import TestSessionLocal as SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class PatientCheckInAndCancellationBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Clinic
        cls.clinic = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic:
            cls.clinic = Clinic(id=1, name="Dental Test Clinic")
            cls.db.add(cls.clinic)
            cls.db.commit()

        # Receptionist user
        cls.receptionist = cls.db.scalar(select(User).where(User.phone == "+998901110001"))
        if not cls.receptionist:
            cls.receptionist = User(
                full_name="Test Receptionist",
                phone="+998901110001",
                hashed_password="hash",
                role=UserRole.RECEPTIONIST,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.receptionist)
            cls.db.commit()
            cls.db.refresh(cls.receptionist)

        cls.receptionist_token = create_access_token(subject=cls.receptionist.id)
        cls.receptionist_headers = {"Authorization": f"Bearer {cls.receptionist_token}"}

        # Patient 1
        cls.patient1 = cls.db.scalar(select(User).where(User.phone == "+998901110002"))
        if not cls.patient1:
            cls.patient1 = User(
                full_name="Patient One",
                phone="+998901110002",
                hashed_password="hash",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.patient1)
            cls.db.commit()
            cls.db.refresh(cls.patient1)

        cls.patient1_token = create_access_token(subject=cls.patient1.id)
        cls.patient1_headers = {"Authorization": f"Bearer {cls.patient1_token}"}

        # Patient 2
        cls.patient2 = cls.db.scalar(select(User).where(User.phone == "+998901110003"))
        if not cls.patient2:
            cls.patient2 = User(
                full_name="Patient Two",
                phone="+998901110003",
                hashed_password="hash",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.patient2)
            cls.db.commit()
            cls.db.refresh(cls.patient2)

        cls.patient2_token = create_access_token(subject=cls.patient2.id)
        cls.patient2_headers = {"Authorization": f"Bearer {cls.patient2_token}"}

        # Specialization
        cls.spec = cls.db.scalar(select(Specialization).where(Specialization.clinic_id == cls.clinic.id))
        if not cls.spec:
            cls.spec = Specialization(
                clinic_id=cls.clinic.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="Therapy",
            )
            cls.db.add(cls.spec)
            cls.db.commit()
            cls.db.refresh(cls.spec)

        # Doctor
        cls.doctor = cls.db.scalar(select(Doctor).where(Doctor.clinic_id == cls.clinic.id))
        if not cls.doctor:
            cls.doctor = Doctor(
                clinic_id=cls.clinic.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Checkin Test",
                room_number="105",
                is_active=True,
            )
            cls.db.add(cls.doctor)
            cls.db.commit()
            cls.db.refresh(cls.doctor)

        # Active Queue for today
        today = date.today()
        cls.queue = cls.db.scalar(
            select(Queue).where(Queue.doctor_id == cls.doctor.id, Queue.queue_date == today)
        )
        if not cls.queue:
            cls.queue = Queue(
                doctor_id=cls.doctor.id,
                queue_date=today,
                is_paused=False,
                is_active=True,
            )
            cls.db.add(cls.queue)
            cls.db.commit()
            cls.db.refresh(cls.queue)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        # Clear any existing tickets for this queue
        tickets = self.db.scalars(
            select(QueueTicket).where(
                (QueueTicket.queue_id == self.queue.id) |
                (QueueTicket.patient_id.in_([self.patient1.id, self.patient2.id]))
            )
        ).all()
        for t in tickets:
            self.db.delete(t)
        self.db.commit()

    def test_valid_qr_checkin_and_my_ticket_update(self):
        """Receptionist gets QR token -> Patient scans and checks in -> my-ticket reflects check-in."""
        # 1. Receptionist gets QR token
        qr_res = self.client.get(
            "/api/queues/check-in/qr-token",
            headers=self.receptionist_headers,
        )
        self.assertEqual(qr_res.status_code, 200)
        qr_data = qr_res.json()
        self.assertIn("token", qr_data)
        self.assertIn("expires_in_seconds", qr_data)
        self.assertEqual(qr_data["expires_in_seconds"], 180 * 60)
        qr_token = qr_data["token"]

        # 2. Create online waiting ticket for Patient 1
        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=101,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
        )
        self.db.add(ticket)
        self.db.commit()

        # Before check-in: my-ticket has checked_in_at = None
        my_ticket_res1 = self.client.get("/api/queues/my-ticket", headers=self.patient1_headers)
        self.assertEqual(my_ticket_res1.status_code, 200)
        self.assertIsNone(my_ticket_res1.json()["checked_in_at"])
        self.assertIsNone(my_ticket_res1.json()["check_in_method"])

        # 3. Patient 1 submits QR check-in
        checkin_res = self.client.post(
            "/api/queues/check-in/qr",
            headers=self.patient1_headers,
            json={"token": qr_token},
        )
        self.assertEqual(checkin_res.status_code, 200)
        checkin_data = checkin_res.json()
        self.assertIsNotNone(checkin_data["checked_in_at"])
        self.assertEqual(checkin_data["check_in_method"], "QR")

        # 4. Refreshed GET /api/queues/my-ticket now has checked_in_at and check_in_method
        my_ticket_res2 = self.client.get("/api/queues/my-ticket", headers=self.patient1_headers)
        self.assertEqual(my_ticket_res2.status_code, 200)
        refreshed_data = my_ticket_res2.json()
        self.assertIsNotNone(refreshed_data["checked_in_at"])
        self.assertEqual(refreshed_data["check_in_method"], "QR")

    def test_invalid_qr_checkin(self):
        """Invalid QR token returns 400 Bad Request."""
        res = self.client.post(
            "/api/queues/check-in/qr",
            headers=self.patient1_headers,
            json={"token": "invalid.jwt.token"},
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid or expired", res.json()["detail"])

    def test_expired_qr_checkin(self):
        """Expired QR token returns 400 Bad Request."""
        # Forge an expired token for clinic
        expired_payload = {
            "sub": "check_in_qr",
            "clinic_id": self.clinic.id,
            "exp": datetime.now(timezone.utc) - timedelta(minutes=5),
        }
        expired_token = jwt.encode(expired_payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

        res = self.client.post(
            "/api/queues/check-in/qr",
            headers=self.patient1_headers,
            json={"token": expired_token},
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid or expired", res.json()["detail"])

    def test_repeated_checkin_returns_conflict(self):
        """Attempting to check in a ticket that is already checked in returns 409 Conflict."""
        # Receptionist gets QR token
        qr_res = self.client.get("/api/queues/check-in/qr-token", headers=self.receptionist_headers)
        qr_token = qr_res.json()["token"]

        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=102,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
            checked_in_at=datetime.now(timezone.utc),
            check_in_method=CheckInMethod.QR,
        )
        self.db.add(ticket)
        self.db.commit()

        res = self.client.post(
            "/api/queues/check-in/qr",
            headers=self.patient1_headers,
            json={"token": qr_token},
        )
        self.assertEqual(res.status_code, 409)
        self.assertIn("already checked in", res.json()["detail"])

    def test_patient_cancels_own_ticket_via_my_ticket_cancel(self):
        """Authenticated patient cancels their own active ticket via PATCH /api/queues/my-ticket/cancel."""
        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=103,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
        )
        self.db.add(ticket)
        self.db.commit()

        cancel_res = self.client.patch("/api/queues/my-ticket/cancel", headers=self.patient1_headers)
        self.assertEqual(cancel_res.status_code, 200)
        self.assertEqual(cancel_res.json()["status"], "CANCELLED")

        # After cancellation, /my-ticket returns 404 (no active ticket)
        my_res = self.client.get("/api/queues/my-ticket", headers=self.patient1_headers)
        self.assertEqual(my_res.status_code, 404)

    def test_patient_cancels_own_ticket_via_ticket_endpoint(self):
        """Authenticated patient cancels their own ticket via PATCH /{queue_id}/tickets/{ticket_id}/cancel."""
        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=104,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
        )
        self.db.add(ticket)
        self.db.commit()

        cancel_res = self.client.patch(
            f"/api/queues/{self.queue.id}/tickets/{ticket.id}/cancel",
            headers=self.patient1_headers,
        )
        self.assertEqual(cancel_res.status_code, 200)
        self.assertEqual(cancel_res.json()["status"], "CANCELLED")

    def test_unauthorized_patient_cancellation_denied(self):
        """Patient 2 cannot cancel Patient 1's ticket via PATCH /{queue_id}/tickets/{ticket_id}/cancel."""
        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=105,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
        )
        self.db.add(ticket)
        self.db.commit()

        # Patient 2 attempts to cancel Patient 1's ticket
        cancel_res = self.client.patch(
            f"/api/queues/{self.queue.id}/tickets/{ticket.id}/cancel",
            headers=self.patient2_headers,
        )
        self.assertEqual(cancel_res.status_code, 403)
        self.assertIn("Cannot cancel another patient's ticket", cancel_res.json()["detail"])

        # Patient 1's ticket is still WAITING
        self.db.refresh(ticket)
        self.assertEqual(ticket.status, TicketStatus.WAITING)

    def test_lifecycle_called_and_serving_in_my_ticket(self):
        """Verify CALLED and SERVING statuses in GET /api/queues/my-ticket and cancellation rejection on SERVING."""
        # 1. CALLED
        ticket = QueueTicket(
            queue_id=self.queue.id,
            patient_id=self.patient1.id,
            ticket_number=106,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.CALLED,
        )
        self.db.add(ticket)
        self.db.commit()

        res_called = self.client.get("/api/queues/my-ticket", headers=self.patient1_headers)
        self.assertEqual(res_called.status_code, 200)
        self.assertEqual(res_called.json()["status"], "CALLED")

        # 2. Transition to SERVING
        ticket.status = TicketStatus.SERVING
        self.db.commit()

        res_serving = self.client.get("/api/queues/my-ticket", headers=self.patient1_headers)
        self.assertEqual(res_serving.status_code, 200)
        self.assertEqual(res_serving.json()["status"], "SERVING")

        # 3. Patient cannot cancel when SERVING
        cancel_res = self.client.patch("/api/queues/my-ticket/cancel", headers=self.patient1_headers)
        # SERVING is not in WAITING, CALLED, SKIPPED
        self.assertEqual(cancel_res.status_code, 404)

    def test_qr_token_3_hours_and_access_token_30_minutes_expiration(self):
        """Verify QR token has exactly 3 hours (180 min) lifetime and access token remains 30 min."""
        now_ts = datetime.now(timezone.utc).timestamp()

        # 1. QR token (exactly 3 hours = 180 minutes = 10,800 seconds)
        qr_res = self.client.get(
            "/api/queues/check-in/qr-token",
            headers=self.receptionist_headers,
        )
        self.assertEqual(qr_res.status_code, 200)
        qr_data = qr_res.json()
        self.assertEqual(qr_data["expires_in_seconds"], 3 * 3600)

        decoded_qr = jwt.decode(
            qr_data["token"],
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        self.assertEqual(decoded_qr["type"], "check_in_qr")
        self.assertEqual(decoded_qr["clinic_id"], self.clinic.id)
        # Check exp is ~3 hours from now (+- 15 seconds)
        qr_lifetime = decoded_qr["exp"] - now_ts
        self.assertAlmostEqual(qr_lifetime, 3 * 3600, delta=15)

        # 2. Access token remains normal 30 minutes (1800 seconds)
        access_token = create_access_token(self.patient1.id)
        decoded_access = jwt.decode(
            access_token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        self.assertEqual(decoded_access["type"], "access")
        self.assertEqual(decoded_access["sub"], str(self.patient1.id))
        access_lifetime = decoded_access["exp"] - now_ts
        self.assertAlmostEqual(access_lifetime, 30 * 60, delta=15)

        # 3. Refresh token remains 7 days
        self.assertEqual(settings.REFRESH_TOKEN_EXPIRE_DAYS, 7)


if __name__ == "__main__":
    unittest.main()
