import threading
import time
import unittest
from datetime import date, datetime, timedelta, timezone

from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import func, select

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from tests.test_db import TestSessionLocal as SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class FullSystemIntegrationAndSecurityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Clinic 1 (Primary)
        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic1:
            cls.clinic1 = Clinic(id=1, name="Dental Main Clinic")
            cls.db.add(cls.clinic1)
            cls.db.commit()

        # Clinic 2 (Isolation Target)
        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.id == 2))
        if not cls.clinic2:
            cls.clinic2 = Clinic(id=2, name="Dental Second Clinic")
            cls.db.add(cls.clinic2)
            cls.db.commit()

        # Specialization for Clinic 1
        cls.spec1 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic1.id,
                Specialization.name_uz == "Ortodontiya",
            )
        )
        if not cls.spec1:
            cls.spec1 = Specialization(
                clinic_id=cls.clinic1.id,
                name_uz="Ortodontiya",
                name_ru="Ортодонтия",
                name_en="Orthodontics",
            )
            cls.db.add(cls.spec1)
            cls.db.commit()
            cls.db.refresh(cls.spec1)

        # Specialization for Clinic 2
        cls.spec2 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic2.id,
                Specialization.name_uz == "Jarrohlik Clinic 2",
            )
        )
        if not cls.spec2:
            cls.spec2 = Specialization(
                clinic_id=cls.clinic2.id,
                name_uz="Jarrohlik Clinic 2",
                name_ru="Хирургия Clinic 2",
                name_en="Surgery Clinic 2",
            )
            cls.db.add(cls.spec2)
            cls.db.commit()
            cls.db.refresh(cls.spec2)

        # Doctor in Clinic 1
        cls.doctor1 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Integration One")
        )
        if not cls.doctor1:
            cls.doctor1 = Doctor(
                clinic_id=cls.clinic1.id,
                specialization_id=cls.spec1.id,
                full_name="Dr. Integration One",
                room_number="201",
                is_active=True,
            )
            cls.db.add(cls.doctor1)
            cls.db.commit()
            cls.db.refresh(cls.doctor1)

        # Doctor in Clinic 2
        cls.doctor2 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Clinic Two Only")
        )
        if not cls.doctor2:
            cls.doctor2 = Doctor(
                clinic_id=cls.clinic2.id,
                specialization_id=cls.spec2.id,
                full_name="Dr. Clinic Two Only",
                room_number="102",
                is_active=True,
            )
            cls.db.add(cls.doctor2)
            cls.db.commit()
            cls.db.refresh(cls.doctor2)

        # Admin for Clinic 1
        cls.admin1 = cls.db.scalar(select(User).where(User.phone == "+998901400001"))
        if not cls.admin1:
            cls.admin1 = User(
                full_name="Admin Clinic One",
                phone="+998901400001",
                hashed_password=get_password_hash("AdminPass123!"),
                role=UserRole.ADMIN,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.admin1)
            cls.db.commit()
            cls.db.refresh(cls.admin1)
        cls.admin1_token = create_access_token(subject=cls.admin1.id)
        cls.admin1_headers = {"Authorization": f"Bearer {cls.admin1_token}"}

        # Receptionist for Clinic 1
        cls.receptionist1 = cls.db.scalar(select(User).where(User.phone == "+998901400002"))
        if not cls.receptionist1:
            cls.receptionist1 = User(
                full_name="Receptionist Clinic One",
                phone="+998901400002",
                hashed_password=get_password_hash("RecepPass123!"),
                role=UserRole.RECEPTIONIST,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.receptionist1)
            cls.db.commit()
            cls.db.refresh(cls.receptionist1)
        cls.receptionist1_token = create_access_token(subject=cls.receptionist1.id)
        cls.receptionist1_headers = {"Authorization": f"Bearer {cls.receptionist1_token}"}

        # Receptionist for Clinic 2 (For Cross-Clinic isolation tests)
        cls.receptionist2 = cls.db.scalar(select(User).where(User.phone == "+998901400003"))
        if not cls.receptionist2:
            cls.receptionist2 = User(
                full_name="Receptionist Clinic Two",
                phone="+998901400003",
                hashed_password=get_password_hash("RecepPass123!"),
                role=UserRole.RECEPTIONIST,
                clinic_id=cls.clinic2.id,
                is_active=True,
            )
            cls.db.add(cls.receptionist2)
            cls.db.commit()
            cls.db.refresh(cls.receptionist2)
        cls.receptionist2_token = create_access_token(subject=cls.receptionist2.id)
        cls.receptionist2_headers = {"Authorization": f"Bearer {cls.receptionist2_token}"}

        # Patient 1
        cls.patient1 = cls.db.scalar(select(User).where(User.phone == "+998901400010"))
        if not cls.patient1:
            cls.patient1 = User(
                full_name="Patient Integration One",
                phone="+998901400010",
                hashed_password=get_password_hash("PatientPass123!"),
                role=UserRole.PATIENT,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.patient1)
            cls.db.commit()
            cls.db.refresh(cls.patient1)
        cls.patient1_token = create_access_token(subject=cls.patient1.id)
        cls.patient1_headers = {"Authorization": f"Bearer {cls.patient1_token}"}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def _get_or_create_queue(self, doctor_id: int) -> int:
        today = date.today()
        q = self.db.scalar(
            select(Queue).where(
                Queue.doctor_id == doctor_id,
                Queue.queue_date == today,
            )
        )
        if not q:
            q = Queue(
                doctor_id=doctor_id,
                queue_date=today,
                is_active=True,
                is_paused=False,
            )
            self.db.add(q)
            self.db.commit()
            self.db.refresh(q)
        elif not q.is_active or q.is_paused:
            q.is_active = True
            q.is_paused = False
            self.db.commit()
        return q.id

    # =========================================================================
    # 1. SECURITY & RBAC TESTS
    # =========================================================================

    def test_missing_jwt_returns_401(self):
        """Unauthenticated requests to protected endpoints return 401 Unauthorized."""
        res = self.client.get("/api/admin/clinic")
        self.assertEqual(res.status_code, 401)

        res2 = self.client.get("/api/queues/my-ticket")
        self.assertEqual(res2.status_code, 401)

    def test_invalid_and_expired_jwt_returns_401(self):
        """Malformed or expired tokens return 401 Unauthorized."""
        bad_headers = {"Authorization": "Bearer not-a-valid-jwt-token"}
        res = self.client.get("/api/admin/clinic", headers=bad_headers)
        self.assertEqual(res.status_code, 401)

        # Expired token
        expired_payload = {
            "sub": str(self.admin1.id),
            "exp": datetime.now(timezone.utc) - timedelta(hours=2),
        }
        expired_token = jwt.encode(
            expired_payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM
        )
        res_exp = self.client.get(
            "/api/admin/clinic",
            headers={"Authorization": f"Bearer {expired_token}"},
        )
        self.assertEqual(res_exp.status_code, 401)

    def test_patient_cannot_access_admin_or_reception_apis(self):
        """Patient role must receive 403 Forbidden when attempting staff operations."""
        # Patient -> Admin endpoint
        res_admin = self.client.get("/api/admin/clinic", headers=self.patient1_headers)
        self.assertEqual(res_admin.status_code, 403)

        res_doctors = self.client.get("/api/admin/doctors", headers=self.patient1_headers)
        self.assertEqual(res_doctors.status_code, 403)

        # Patient -> Receptionist Queue Call-next endpoint
        queue_id = self._get_or_create_queue(self.doctor1.id)
        res_call = self.client.post(
            f"/api/queues/{queue_id}/call-next",
            headers=self.patient1_headers,
        )
        self.assertEqual(res_call.status_code, 403)

    def test_receptionist_cannot_access_admin_management_apis(self):
        """Receptionist role must receive 403 Forbidden on /api/admin/* endpoints."""
        res = self.client.get("/api/admin/clinic", headers=self.receptionist1_headers)
        self.assertEqual(res.status_code, 403)

        res_analytics = self.client.get(
            "/api/admin/analytics/overview",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(res_analytics.status_code, 403)

    def test_cross_clinic_receptionist_isolation(self):
        """Receptionist from Clinic 2 cannot call or manipulate Clinic 1's queues."""
        queue_id = self._get_or_create_queue(self.doctor1.id)
        # Receptionist 2 belongs to clinic 2, queue belongs to doctor1 in clinic 1
        res = self.client.post(
            f"/api/queues/{queue_id}/call-next",
            headers=self.receptionist2_headers,
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("another clinic", res.json()["detail"].lower())

    def test_cross_clinic_admin_isolation(self):
        """Admin from Clinic 1 cannot access or update doctors belonging to Clinic 2 (404 scoped)."""
        res = self.client.patch(
            f"/api/admin/doctors/{self.doctor2.id}",
            json={"room_number": "999"},
            headers=self.admin1_headers,
        )
        # Clinic isolation scopes queries to admin's clinic, returning 404 to avoid leaking ID existence
        self.assertEqual(res.status_code, 404)

    # =========================================================================
    # 2. FULL PATIENT JOURNEY & TICKET INTEGRITY
    # =========================================================================

    def test_full_patient_journey_online_join_to_complete(self):
        """
        Validate end-to-end lifecycle:
        Register -> Login -> Catalog -> Preview -> Take Ticket -> My Queue (with clinic_id)
        -> Reception Check-in -> CALL -> SERVE -> COMPLETE.
        """
        phone = f"+99890{int(time.time() * 1000) % 10000000:07d}"
        reg_res = self.client.post(
            "/api/auth/register",
            json={
                "phone": phone,
                "password": "SecurePassword123!",
                "full_name": "Integration Journey Patient",
            },
        )
        self.assertEqual(reg_res.status_code, 201)

        # Login to obtain JWT
        login_res = self.client.post(
            "/api/auth/login",
            json={
                "phone": phone,
                "password": "SecurePassword123!",
            },
        )
        self.assertEqual(login_res.status_code, 200)
        token = login_res.json()["access_token"]
        p_headers = {"Authorization": f"Bearer {token}"}

        # 1. Catalog Specializations
        specs_res = self.client.get(
            f"/api/catalog/specializations?clinic_id={self.clinic1.id}",
            headers=p_headers,
        )
        self.assertEqual(specs_res.status_code, 200)

        # 2. Doctor Queue Preview
        queue_id = self._get_or_create_queue(self.doctor1.id)
        preview_res = self.client.get(
            f"/api/catalog/doctors/{self.doctor1.id}/queue",
            headers=p_headers,
        )
        self.assertEqual(preview_res.status_code, 200)
        self.assertIn("estimated_position_if_joined", preview_res.json())

        # 3. Take Ticket (Join Queue)
        join_res = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=p_headers,
        )
        self.assertEqual(join_res.status_code, 201)
        ticket_data = join_res.json()
        ticket_id = ticket_data["id"]
        ticket_number = ticket_data["ticket_number"]

        self.assertEqual(ticket_data["status"], "WAITING")
        self.assertIsNone(ticket_data["checked_in_at"])

        # 4. Duplicate Join Protection
        dup_res = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=p_headers,
        )
        self.assertEqual(dup_res.status_code, 409)

        # 5. My Ticket inspection (Verifies Known Issue #1 backend resolution: clinic_id present)
        my_res = self.client.get("/api/queues/my-ticket", headers=p_headers)
        self.assertEqual(my_res.status_code, 200)
        my_data = my_res.json()
        self.assertEqual(my_data["ticket_number"], ticket_number)
        self.assertEqual(my_data["clinic_id"], self.clinic1.id)
        self.assertEqual(my_data["doctor"]["clinic_id"], self.clinic1.id)

        # 6. Receptionist Manual Check-in
        checkin_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/check-in",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(checkin_res.status_code, 200)
        self.assertEqual(checkin_res.json()["check_in_method"], "RECEPTION")
        self.assertIsNotNone(checkin_res.json()["checked_in_at"])

        # 7. Patient My Queue reflects checked-in state
        my_res2 = self.client.get("/api/queues/my-ticket", headers=p_headers)
        self.assertEqual(my_res2.status_code, 200)
        self.assertEqual(my_res2.json()["check_in_method"], "RECEPTION")
        self.assertIsNotNone(my_res2.json()["checked_in_at"])

        # 8. CALL -> SERVE -> COMPLETE
        call_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/call",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(call_res.status_code, 200)
        self.assertEqual(call_res.json()["ticket_number"], ticket_number)
        self.assertEqual(call_res.json()["status"], "CALLED")

        serve_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/serve",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(serve_res.status_code, 200)
        self.assertEqual(serve_res.json()["status"], "SERVING")

        comp_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/complete",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(comp_res.status_code, 200)
        self.assertEqual(comp_res.json()["status"], "COMPLETED")

        # 9. My Ticket returns 404 once completed
        my_done = self.client.get("/api/queues/my-ticket", headers=p_headers)
        self.assertEqual(my_done.status_code, 404)

    # =========================================================================
    # 3. CONCURRENCY & QUEUE INTEGRITY
    # =========================================================================

    def test_missed_turn_reordering_preserves_ticket_number(self):
        """
        When an online waiting ticket misses a turn, it is moved to the end of the queue.
        Invariant: queue_position changes, but ticket_number is permanently unchanged.
        """
        queue_id = self._get_or_create_queue(self.doctor1.id)

        # Create online waiting patient (unchecked-in)
        ts = int(time.time() * 1000)
        phone = f"+99890{ts % 10000000:07d}"
        self.client.post(
            "/api/auth/register",
            json={"phone": phone, "password": "SecurePassword123!", "full_name": "Missed Turn Patient"},
        )
        login = self.client.post("/api/auth/login", json={"phone": phone, "password": "SecurePassword123!"}).json()
        p_headers = {"Authorization": f"Bearer {login['access_token']}"}

        join_res = self.client.post(f"/api/queues/{queue_id}/join", headers=p_headers)
        self.assertEqual(join_res.status_code, 201)
        initial_ticket = join_res.json()
        initial_number = initial_ticket["ticket_number"]
        ticket_id = initial_ticket["id"]

        # Call miss-turn
        miss_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket_id}/miss-turn",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(miss_res.status_code, 200)
        updated_ticket = miss_res.json()

        # Ticket number must be permanently identical
        self.assertEqual(updated_ticket["ticket_number"], initial_number)
        self.assertEqual(updated_ticket["missed_turns"], 1)

    def test_concurrency_race_condition_two_simultaneous_joins(self):
        """
        Two patient threads joining the queue concurrently:
        Both must succeed with distinct queue_positions and unique ticket_numbers.
        """
        queue_id = self._get_or_create_queue(self.doctor1.id)

        results = []
        errors = []

        def _join_worker(patient_idx: int):
            ts = int(time.time() * 1000 + patient_idx * 17)
            phone = f"+99891{ts % 10000000:07d}"
            # Ensure unique registered patient
            with SessionLocal() as db_session:
                u = User(
                    full_name=f"Concurrent Patient {patient_idx}_{ts}",
                    phone=phone,
                    hashed_password=get_password_hash("SecurePassword123!"),
                    role=UserRole.PATIENT,
                    clinic_id=self.clinic1.id,
                    is_active=True,
                )
                db_session.add(u)
                db_session.commit()
                db_session.refresh(u)
                token = create_access_token(subject=u.id)

            try:
                res = self.client.post(
                    f"/api/queues/{queue_id}/join",
                    headers={"Authorization": f"Bearer {token}"},
                )
                if res.status_code == 201:
                    results.append(res.json())
                else:
                    errors.append(res.json())
            except Exception as e:
                errors.append(str(e))

        t1 = threading.Thread(target=_join_worker, args=(1,))
        t2 = threading.Thread(target=_join_worker, args=(2,))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        self.assertEqual(len(results), 2, f"Errors: {errors}")
        t1_data, t2_data = results[0], results[1]
        self.assertNotEqual(t1_data["ticket_number"], t2_data["ticket_number"])
        self.assertNotEqual(t1_data["queue_position"], t2_data["queue_position"])

    def test_paused_queue_prevents_join_and_allows_resume(self):
        """A paused queue prevents new patients from joining and returns 409."""
        queue_id = self._get_or_create_queue(self.doctor1.id)

        # Pause (PATCH /{queue_id}/pause)
        pause_res = self.client.patch(
            f"/api/queues/{queue_id}/pause",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(pause_res.status_code, 200)
        self.assertTrue(pause_res.json()["is_paused"])

        # Attempt join -> 409
        ts = int(time.time() * 1000 + 44)
        phone = f"+99892{ts % 10000000:07d}"
        self.client.post(
            "/api/auth/register",
            json={"phone": phone, "password": "SecurePassword123!", "full_name": "Pause Test"},
        )
        login = self.client.post("/api/auth/login", json={"phone": phone, "password": "SecurePassword123!"}).json()
        p_headers = {"Authorization": f"Bearer {login['access_token']}"}

        join_attempt = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=p_headers,
        )
        self.assertEqual(join_attempt.status_code, 409)
        self.assertIn("paused", join_attempt.json()["detail"].lower())

        # Resume (PATCH /{queue_id}/resume)
        resume_res = self.client.patch(
            f"/api/queues/{queue_id}/resume",
            headers=self.receptionist1_headers,
        )
        self.assertEqual(resume_res.status_code, 200)
        self.assertFalse(resume_res.json()["is_paused"])

        # Attempt join again -> 201
        join_success = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=p_headers,
        )
        self.assertEqual(join_success.status_code, 201)

    # =========================================================================
    # 4. PUBLIC DISPLAY SECURITY & PRIVACY
    # =========================================================================

    def test_public_display_endpoint_privacy_and_checked_in_filter(self):
        """
        Public display endpoint:
        - Only exposes non-sensitive fields
        - Unchecked-in online tickets MUST NOT be visible on public display
        - Checked-in tickets MUST be visible
        """
        queue_id = self._get_or_create_queue(self.doctor1.id)

        # Create unchecked-in online ticket
        ts = int(time.time() * 1000 + 88)
        phone = f"+99893{ts % 10000000:07d}"
        self.client.post(
            "/api/auth/register",
            json={"phone": phone, "password": "SecurePassword123!", "full_name": "Private Patient Name"},
        )
        login = self.client.post("/api/auth/login", json={"phone": phone, "password": "SecurePassword123!"}).json()
        p_headers = {"Authorization": f"Bearer {login['access_token']}"}
        ticket = self.client.post(f"/api/queues/{queue_id}/join", headers=p_headers).json()
        uncheck_num = ticket["ticket_number"]

        # Fetch public display
        res = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display")
        self.assertEqual(res.status_code, 200)
        data = res.json()

        # Verify privacy: no patient name or phone in entire response
        raw_text = res.text
        self.assertNotIn("Private Patient Name", raw_text)
        self.assertNotIn(phone, raw_text)

        # Unchecked-in online ticket must NOT appear in waiting tickets
        found_queue = next((q for q in data["queues"] if q["doctor"]["id"] == self.doctor1.id), None)
        self.assertIsNotNone(found_queue)
        waiting_nums = [t["ticket_number"] for t in found_queue["waiting_tickets"]]
        self.assertNotIn(uncheck_num, waiting_nums)

        # Now check-in ticket via reception
        self.client.patch(
            f"/api/queues/{queue_id}/tickets/{ticket['id']}/check-in",
            headers=self.receptionist1_headers,
        )

        # Re-fetch public display -> now checked-in ticket IS visible
        res_after = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display")
        data_after = res_after.json()
        found_after = next((q for q in data_after["queues"] if q["doctor"]["id"] == self.doctor1.id), None)
        waiting_after = [t["ticket_number"] for t in found_after["waiting_tickets"]]
        self.assertIn(uncheck_num, waiting_after)

    # =========================================================================
    # 5. MULTILINGUAL LOCALIZATION INVARIANTS
    # =========================================================================

    def test_multilingual_catalog_and_display_invariants(self):
        """Catalog and Public Display respond with requested language (uz, ru, en)."""
        headers_uz = {"Authorization": f"Bearer {self.patient1_token}", "Accept-Language": "uz"}
        res_uz = self.client.get(
            f"/api/catalog/specializations?clinic_id={self.clinic1.id}",
            headers=headers_uz,
        )
        self.assertEqual(res_uz.status_code, 200)
        spec_uz = next((s for s in res_uz.json() if s["id"] == self.spec1.id), None)
        self.assertEqual(spec_uz["name"], "Ortodontiya")

        headers_ru = {"Authorization": f"Bearer {self.patient1_token}", "Accept-Language": "ru"}
        res_ru = self.client.get(
            f"/api/catalog/specializations?clinic_id={self.clinic1.id}",
            headers=headers_ru,
        )
        self.assertEqual(res_ru.status_code, 200)
        spec_ru = next((s for s in res_ru.json() if s["id"] == self.spec1.id), None)
        self.assertEqual(spec_ru["name"], "Ортодонтия")

        headers_en = {"Authorization": f"Bearer {self.patient1_token}", "Accept-Language": "en"}
        res_en = self.client.get(
            f"/api/catalog/specializations?clinic_id={self.clinic1.id}",
            headers=headers_en,
        )
        self.assertEqual(res_en.status_code, 200)
        spec_en = next((s for s in res_en.json() if s["id"] == self.spec1.id), None)
        self.assertEqual(spec_en["name"], "Orthodontics")


if __name__ == "__main__":
    unittest.main()
