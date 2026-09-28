import unittest
from datetime import date, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class MultilingualCatalogBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Ensure Clinic
        cls.clinic = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic:
            cls.clinic = Clinic(id=1, name="Dental Test Clinic")
            cls.db.add(cls.clinic)
            cls.db.commit()

        # Ensure patient user for auth
        cls.patient = cls.db.scalar(select(User).where(User.phone == "+998901112233"))
        if not cls.patient:
            cls.patient = User(
                full_name="Multilingual Test Patient",
                phone="+998901112233",
                hashed_password="fakehashpassword123",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.patient)
            cls.db.commit()
            cls.db.refresh(cls.patient)

        # Generate access token
        cls.token = create_access_token(subject=cls.patient.id)
        cls.headers_base = {"Authorization": f"Bearer {cls.token}"}

        # Create known multilingual specialization for predictable testing
        cls.test_spec = cls.db.scalar(
            select(Specialization).where(Specialization.name_uz == "Test Ortodontiya")
        )
        if not cls.test_spec:
            cls.test_spec = Specialization(
                clinic_id=cls.clinic.id,
                name_uz="Test Ortodontiya",
                name_ru="Тестовая Ортодонтия",
                name_en="Test Orthodontics",
            )
            cls.db.add(cls.test_spec)
            cls.db.commit()
            cls.db.refresh(cls.test_spec)

        # Create specialization with missing ru/en translation to test fallback
        cls.fallback_spec = cls.db.scalar(
            select(Specialization).where(Specialization.name_uz == "Faqat Uzbekcha Nomi")
        )
        if not cls.fallback_spec:
            cls.fallback_spec = Specialization(
                clinic_id=cls.clinic.id,
                name_uz="Faqat Uzbekcha Nomi",
                name_ru=None,
                name_en=None,
            )
            cls.db.add(cls.fallback_spec)
            cls.db.commit()
            cls.db.refresh(cls.fallback_spec)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_specializations_uzbek_response(self):
        """GET /api/catalog/specializations returns Uzbek names when Accept-Language is 'uz'."""
        headers = {**self.headers_base, "Accept-Language": "uz"}
        response = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIsInstance(data, list)
        spec_map = {item["id"]: item["name"] for item in data}

        self.assertIn(self.test_spec.id, spec_map)
        self.assertEqual(spec_map[self.test_spec.id], "Test Ortodontiya")

    def test_specializations_russian_response(self):
        """GET /api/catalog/specializations returns Russian names when Accept-Language is 'ru'."""
        headers = {**self.headers_base, "Accept-Language": "ru"}
        response = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        spec_map = {item["id"]: item["name"] for item in data}

        self.assertIn(self.test_spec.id, spec_map)
        self.assertEqual(spec_map[self.test_spec.id], "Тестовая Ортодонтия")

    def test_specializations_english_response(self):
        """GET /api/catalog/specializations returns English names when Accept-Language is 'en'."""
        headers = {**self.headers_base, "Accept-Language": "en"}
        response = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        spec_map = {item["id"]: item["name"] for item in data}

        self.assertIn(self.test_spec.id, spec_map)
        self.assertEqual(spec_map[self.test_spec.id], "Test Orthodontics")

    def test_ids_remain_stable_across_languages(self):
        """Specialization IDs must remain identical regardless of language requested."""
        res_uz = self.client.get("/api/catalog/specializations?clinic_id=1", headers={**self.headers_base, "Accept-Language": "uz"}).json()
        res_ru = self.client.get("/api/catalog/specializations?clinic_id=1", headers={**self.headers_base, "Accept-Language": "ru"}).json()
        res_en = self.client.get("/api/catalog/specializations?clinic_id=1", headers={**self.headers_base, "Accept-Language": "en"}).json()

        ids_uz = {item["id"] for item in res_uz}
        ids_ru = {item["id"] for item in res_ru}
        ids_en = {item["id"] for item in res_en}

        self.assertEqual(ids_uz, ids_ru)
        self.assertEqual(ids_ru, ids_en)

    def test_missing_translation_fallback(self):
        """When Russian/English translation is missing, it falls back to Uzbek name without error."""
        headers_ru = {**self.headers_base, "Accept-Language": "ru"}
        response_ru = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers_ru)
        self.assertEqual(response_ru.status_code, 200)
        spec_map_ru = {item["id"]: item["name"] for item in response_ru.json()}
        self.assertEqual(spec_map_ru[self.fallback_spec.id], "Faqat Uzbekcha Nomi")

        headers_en = {**self.headers_base, "Accept-Language": "en"}
        response_en = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers_en)
        self.assertEqual(response_en.status_code, 200)
        spec_map_en = {item["id"]: item["name"] for item in response_en.json()}
        self.assertEqual(spec_map_en[self.fallback_spec.id], "Faqat Uzbekcha Nomi")

    def test_unsupported_language_fallback(self):
        """When an unsupported language like 'de' or 'fr' is passed, default to Uzbek."""
        headers = {**self.headers_base, "Accept-Language": "de-DE,de;q=0.9"}
        response = self.client.get("/api/catalog/specializations?clinic_id=1", headers=headers)
        self.assertEqual(response.status_code, 200)

        spec_map = {item["id"]: item["name"] for item in response.json()}
        self.assertEqual(spec_map[self.test_spec.id], "Test Ortodontiya")

    def tearDown(self):
        self.db.rollback()

    def test_my_ticket_specialization_localized(self):
        """GET /api/queues/my-ticket returns the localized specialization name."""
        # Ensure doctor and today queue for test_spec
        doctor = self.db.scalar(select(Doctor).where(Doctor.specialization_id == self.test_spec.id))
        if not doctor:
            doctor = Doctor(
                clinic_id=self.clinic.id,
                specialization_id=self.test_spec.id,
                full_name="Dr. Multilingual Test",
                room_number="202",
                is_active=True,
            )
            self.db.add(doctor)
            self.db.commit()
            self.db.refresh(doctor)

        today = date.today()
        queue = self.db.scalar(select(Queue).where(Queue.doctor_id == doctor.id, Queue.queue_date == today))
        if not queue:
            queue = Queue(doctor_id=doctor.id, queue_date=today, is_paused=False, is_active=True)
            self.db.add(queue)
            self.db.commit()
            self.db.refresh(queue)

        # Clear existing tickets for this queue and patient to avoid conflict
        existing_tickets = self.db.scalars(
            select(QueueTicket).where(
                (QueueTicket.queue_id == queue.id) | (QueueTicket.patient_id == self.patient.id)
            )
        ).all()
        for t in existing_tickets:
            self.db.delete(t)
        self.db.commit()

        # Create active ticket
        ticket = QueueTicket(
            queue_id=queue.id,
            patient_id=self.patient.id,
            ticket_number=999,
            queue_position=1,
            patient_name=self.patient.full_name,
            patient_phone=self.patient.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.WAITING,
        )
        self.db.add(ticket)
        self.db.commit()

        try:
            # Test Russian
            res_ru = self.client.get("/api/queues/my-ticket", headers={**self.headers_base, "Accept-Language": "ru"})
            self.assertEqual(res_ru.status_code, 200)
            self.assertEqual(res_ru.json()["specialization"]["name"], "Тестовая Ортодонтия")

            # Test English
            res_en = self.client.get("/api/queues/my-ticket", headers={**self.headers_base, "Accept-Language": "en"})
            self.assertEqual(res_en.status_code, 200)
            self.assertEqual(res_en.json()["specialization"]["name"], "Test Orthodontics")

            # Test Uzbek
            res_uz = self.client.get("/api/queues/my-ticket", headers={**self.headers_base, "Accept-Language": "uz"})
            self.assertEqual(res_uz.status_code, 200)
            self.assertEqual(res_uz.json()["specialization"]["name"], "Test Ortodontiya")
        finally:
            self.db.delete(ticket)
            self.db.commit()


if __name__ == "__main__":
    unittest.main()
