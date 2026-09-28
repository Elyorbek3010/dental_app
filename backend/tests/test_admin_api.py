import unittest
from datetime import date
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.security import create_access_token, get_password_hash
from app.db.session import SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole


class AdminApiBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Clinic 1 (Admin's clinic)
        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic1:
            cls.clinic1 = Clinic(id=1, name="Dental Admin Main Clinic")
            cls.db.add(cls.clinic1)
            cls.db.commit()

        # Clinic 2 (Other clinic for isolation tests)
        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.id == 2))
        if not cls.clinic2:
            cls.clinic2 = Clinic(id=2, name="Other Dental Clinic")
            cls.db.add(cls.clinic2)
            cls.db.commit()

        # Admin user (clinic 1)
        cls.admin = cls.db.scalar(select(User).where(User.phone == "+998900000099"))
        if not cls.admin:
            cls.admin = User(
                full_name="Super Admin",
                phone="+998900000099",
                hashed_password=get_password_hash("adminpassword123"),
                role=UserRole.ADMIN,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.admin)
        else:
            cls.admin.role = UserRole.ADMIN
            cls.admin.clinic_id = cls.clinic1.id
            cls.admin.is_active = True
        cls.db.commit()
        cls.db.refresh(cls.admin)

        # Receptionist user (clinic 1)
        cls.receptionist = cls.db.scalar(select(User).where(User.phone == "+998900000098"))
        if not cls.receptionist:
            cls.receptionist = User(
                full_name="Front Desk Receptionist",
                phone="+998900000098",
                hashed_password=get_password_hash("receppassword123"),
                role=UserRole.RECEPTIONIST,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.receptionist)
        else:
            cls.receptionist.role = UserRole.RECEPTIONIST
            cls.receptionist.clinic_id = cls.clinic1.id
            cls.receptionist.is_active = True
        cls.db.commit()
        cls.db.refresh(cls.receptionist)

        # Patient user (clinic 1)
        cls.patient = cls.db.scalar(select(User).where(User.phone == "+998900000097"))
        if not cls.patient:
            cls.patient = User(
                full_name="Regular Patient",
                phone="+998900000097",
                hashed_password=get_password_hash("patientpassword123"),
                role=UserRole.PATIENT,
                clinic_id=cls.clinic1.id,
                is_active=True,
            )
            cls.db.add(cls.patient)
        else:
            cls.patient.role = UserRole.PATIENT
            cls.patient.clinic_id = cls.clinic1.id
            cls.patient.is_active = True
        cls.db.commit()
        cls.db.refresh(cls.patient)

        # Specialization in Clinic 2
        cls.spec_c2 = cls.db.scalar(
            select(Specialization).where(
                Specialization.clinic_id == cls.clinic2.id,
                Specialization.name_uz == "Foreign Spec",
            )
        )
        if not cls.spec_c2:
            cls.spec_c2 = Specialization(
                clinic_id=cls.clinic2.id,
                name_uz="Foreign Spec",
                is_active=True,
            )
            cls.db.add(cls.spec_c2)
            cls.db.commit()
            cls.db.refresh(cls.spec_c2)

        cls.admin_token = create_access_token(subject=cls.admin.id)
        cls.admin_headers = {"Authorization": f"Bearer {cls.admin_token}"}

        cls.receptionist_token = create_access_token(subject=cls.receptionist.id)
        cls.receptionist_headers = {"Authorization": f"Bearer {cls.receptionist_token}"}

        cls.patient_token = create_access_token(subject=cls.patient.id)
        cls.patient_headers = {"Authorization": f"Bearer {cls.patient_token}"}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    # --- RBAC Tests ---
    def test_receptionist_cannot_access_admin_api(self):
        resp = self.client.get("/api/admin/specializations", headers=self.receptionist_headers)
        self.assertEqual(resp.status_code, 403)

    def test_patient_cannot_access_admin_api(self):
        resp = self.client.get("/api/admin/specializations", headers=self.patient_headers)
        self.assertEqual(resp.status_code, 403)

    # --- Clinic Info Tests ---
    def test_get_and_update_clinic_info(self):
        resp = self.client.get("/api/admin/clinic", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["id"], self.clinic1.id)

        update_resp = self.client.patch(
            "/api/admin/clinic",
            headers=self.admin_headers,
            json={"name": "Updated Dental Center"},
        )
        self.assertEqual(update_resp.status_code, 200)
        self.assertEqual(update_resp.json()["name"], "Updated Dental Center")

    # --- Specialization CRUD Tests ---
    def test_specialization_crud(self):
        # 1. Create with multilingual fields
        create_resp = self.client.post(
            "/api/admin/specializations",
            headers=self.admin_headers,
            json={
                "name_uz": "Bolalar stomatologiyasi",
                "name_ru": "Детская стоматология",
                "name_en": "Pediatric Dentistry",
            },
        )
        self.assertEqual(create_resp.status_code, 201)
        spec = create_resp.json()
        spec_id = spec["id"]
        self.assertEqual(spec["name_uz"], "Bolalar stomatologiyasi")
        self.assertEqual(spec["name_ru"], "Детская стоматология")
        self.assertEqual(spec["name_en"], "Pediatric Dentistry")
        self.assertTrue(spec["is_active"])

        # 2. List specializations
        list_resp = self.client.get("/api/admin/specializations", headers=self.admin_headers)
        self.assertEqual(list_resp.status_code, 200)
        ids = [s["id"] for s in list_resp.json()]
        self.assertIn(spec_id, ids)

        # 3. Update & deactivate
        update_resp = self.client.patch(
            f"/api/admin/specializations/{spec_id}",
            headers=self.admin_headers,
            json={
                "name_uz": "Pediatrik stomatologiya",
                "is_active": False,
            },
        )
        self.assertEqual(update_resp.status_code, 200)
        updated = update_resp.json()
        self.assertEqual(updated["name_uz"], "Pediatrik stomatologiya")
        self.assertEqual(updated["name_ru"], "Детская стоматология")
        self.assertFalse(updated["is_active"])

        # 4. Verify inactive specialization is hidden from patient catalog
        cat_resp = self.client.get(
            f"/api/catalog/specializations?clinic_id={self.clinic1.id}",
            headers=self.patient_headers,
        )
        self.assertEqual(cat_resp.status_code, 200)
        cat_ids = [s["id"] for s in cat_resp.json()]
        self.assertNotIn(spec_id, cat_ids)

        # 5. Reactivate specialization
        react_resp = self.client.patch(
            f"/api/admin/specializations/{spec_id}",
            headers=self.admin_headers,
            json={"is_active": True},
        )
        self.assertEqual(react_resp.status_code, 200)
        self.assertTrue(react_resp.json()["is_active"])

    def test_specialization_isolation(self):
        # Admin of Clinic 1 cannot update Clinic 2's specialization
        resp = self.client.patch(
            f"/api/admin/specializations/{self.spec_c2.id}",
            headers=self.admin_headers,
            json={"name_uz": "Hacked Name"},
        )
        self.assertEqual(resp.status_code, 404)

    # --- Doctor CRUD Tests ---
    def test_doctor_crud(self):
        # Create a spec in clinic 1
        spec = Specialization(
            clinic_id=self.clinic1.id,
            name_uz="Implantologiya",
            name_ru="Имплантология",
            name_en="Implantology",
            is_active=True,
        )
        self.db.add(spec)
        self.db.commit()
        self.db.refresh(spec)

        # 1. Create doctor
        create_resp = self.client.post(
            "/api/admin/doctors",
            headers=self.admin_headers,
            json={
                "full_name": "Dr. Rustam Karimov",
                "specialization_id": spec.id,
                "room_number": "204",
                "is_active": True,
            },
        )
        self.assertEqual(create_resp.status_code, 201)
        doc = create_resp.json()
        doc_id = doc["id"]
        self.assertEqual(doc["full_name"], "Dr. Rustam Karimov")
        self.assertEqual(doc["room_number"], "204")
        self.assertEqual(doc["specialization_name_uz"], "Implantologiya")

        # 2. Cannot create doctor with specialization from another clinic
        foreign_resp = self.client.post(
            "/api/admin/doctors",
            headers=self.admin_headers,
            json={
                "full_name": "Dr. Wrong Clinic",
                "specialization_id": self.spec_c2.id,
                "room_number": "101",
            },
        )
        self.assertEqual(foreign_resp.status_code, 400)

        # 3. Update doctor and deactivate
        patch_resp = self.client.patch(
            f"/api/admin/doctors/{doc_id}",
            headers=self.admin_headers,
            json={
                "room_number": "205-B",
                "is_active": False,
            },
        )
        self.assertEqual(patch_resp.status_code, 200)
        self.assertEqual(patch_resp.json()["room_number"], "205-B")
        self.assertFalse(patch_resp.json()["is_active"])

        # 4. List doctors includes the inactive doctor for admin
        list_resp = self.client.get("/api/admin/doctors", headers=self.admin_headers)
        self.assertEqual(list_resp.status_code, 200)
        admin_doc_ids = [d["id"] for d in list_resp.json()]
        self.assertIn(doc_id, admin_doc_ids)

        # 5. But inactive doctor is not in patient catalog
        cat_resp = self.client.get(
            f"/api/catalog/doctors?clinic_id={self.clinic1.id}",
            headers=self.patient_headers,
        )
        self.assertEqual(cat_resp.status_code, 200)
        cat_doc_ids = [d["id"] for d in cat_resp.json()]
        self.assertNotIn(doc_id, cat_doc_ids)

    # --- Receptionist Account Tests ---
    def test_receptionist_account_management(self):
        import uuid
        unique_phone = f"+99890{uuid.uuid4().int % 10000000:07d}"
        # 1. Create receptionist
        create_resp = self.client.post(
            "/api/admin/receptionists",
            headers=self.admin_headers,
            json={
                "full_name": "Malika Alimova",
                "phone": unique_phone,
                "password": "receptionpass123",
            },
        )
        self.assertEqual(create_resp.status_code, 201)
        rec = create_resp.json()
        rec_id = rec["id"]
        self.assertEqual(rec["full_name"], "Malika Alimova")
        self.assertEqual(rec["phone"], unique_phone)
        self.assertEqual(rec["role"], "RECEPTIONIST")
        self.assertTrue(rec["is_active"])
        self.assertNotIn("password", rec)
        self.assertNotIn("hashed_password", rec)

        # 2. Duplicate phone rejected
        dup_resp = self.client.post(
            "/api/admin/receptionists",
            headers=self.admin_headers,
            json={
                "full_name": "Duplicate Person",
                "phone": unique_phone,
                "password": "anotherpassword123",
            },
        )
        self.assertEqual(dup_resp.status_code, 409)

        # 3. Update & deactivate receptionist
        update_resp = self.client.patch(
            f"/api/admin/receptionists/{rec_id}",
            headers=self.admin_headers,
            json={
                "full_name": "Malika Karimova",
                "is_active": False,
            },
        )
        self.assertEqual(update_resp.status_code, 200)
        self.assertEqual(update_resp.json()["full_name"], "Malika Karimova")
        self.assertFalse(update_resp.json()["is_active"])

        # 4. Safe password reset
        reset_resp = self.client.patch(
            f"/api/admin/receptionists/{rec_id}",
            headers=self.admin_headers,
            json={"password": "brandnewpassword456"},
        )
        self.assertEqual(reset_resp.status_code, 200)

        # 5. List receptionists
        list_resp = self.client.get("/api/admin/receptionists", headers=self.admin_headers)
        self.assertEqual(list_resp.status_code, 200)
        rec_ids = [r["id"] for r in list_resp.json()]
        self.assertIn(rec_id, rec_ids)

    # --- Analytics Endpoint Tests ---
    def test_analytics_overview(self):
        resp = self.client.get("/api/admin/analytics/overview", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("active_doctors_count", data)
        self.assertIn("active_specializations_count", data)
        self.assertIn("active_receptionists_count", data)
        self.assertIn("today_opened_queues_count", data)
        self.assertIn("today_tickets_total", data)
        self.assertIn("today_tickets_waiting", data)
        self.assertIn("today_tickets_called", data)
        self.assertIn("today_tickets_serving", data)
        self.assertIn("today_tickets_completed", data)
        self.assertIn("doctors_today", data)
        self.assertIsInstance(data["doctors_today"], list)
