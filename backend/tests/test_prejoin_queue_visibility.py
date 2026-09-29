import unittest
from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.realtime import manager, notify_display_update


class PreJoinQueueVisibilityBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        # Clinic
        cls.clinic = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic:
            cls.clinic = Clinic(id=1, name="Dental Visibility Clinic")
            cls.db.add(cls.clinic)
            cls.db.commit()

        # Specialization
        cls.spec = cls.db.scalar(select(Specialization).where(Specialization.id == 1))
        if not cls.spec:
            cls.spec = Specialization(
                id=1,
                clinic_id=cls.clinic.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="Therapy",
            )
            cls.db.add(cls.spec)
            cls.db.commit()

        # Doctor 1
        cls.doctor = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Prejoin Visibility")
        )
        if not cls.doctor:
            cls.doctor = Doctor(
                clinic_id=cls.clinic.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Prejoin Visibility",
                room_number="205",
                is_active=True,
            )
            cls.db.add(cls.doctor)
            cls.db.commit()
            cls.db.refresh(cls.doctor)

        # Doctor 2 (for multi-doctor / scoping tests)
        cls.doctor2 = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Second Prejoin Doctor")
        )
        if not cls.doctor2:
            cls.doctor2 = Doctor(
                clinic_id=cls.clinic.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Second Prejoin Doctor",
                room_number="206",
                is_active=True,
            )
            cls.db.add(cls.doctor2)
            cls.db.commit()
            cls.db.refresh(cls.doctor2)

        # Inactive Doctor
        cls.doctor_inactive = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Inactive Prejoin")
        )
        if not cls.doctor_inactive:
            cls.doctor_inactive = Doctor(
                clinic_id=cls.clinic.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Inactive Prejoin",
                room_number="207",
                is_active=False,
            )
            cls.db.add(cls.doctor_inactive)
            cls.db.commit()
            cls.db.refresh(cls.doctor_inactive)

        # Patient User
        cls.patient = cls.db.scalar(select(User).where(User.phone == "+998901239999"))
        if not cls.patient:
            cls.patient = User(
                full_name="Prejoin Patient",
                phone="+998901239999",
                hashed_password="hash",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.patient)
            cls.db.commit()
            cls.db.refresh(cls.patient)

        # Patient 2 (for join conflict tests)
        cls.patient2 = cls.db.scalar(select(User).where(User.phone == "+998901238888"))
        if not cls.patient2:
            cls.patient2 = User(
                full_name="Second Patient",
                phone="+998901238888",
                hashed_password="hash",
                role=UserRole.PATIENT,
                clinic_id=cls.clinic.id,
                is_active=True,
            )
            cls.db.add(cls.patient2)
            cls.db.commit()
            cls.db.refresh(cls.patient2)

        cls.patient_token = create_access_token(subject=cls.patient.id)
        cls.patient_headers = {"Authorization": f"Bearer {cls.patient_token}"}

        cls.patient2_token = create_access_token(subject=cls.patient2.id)
        cls.patient2_headers = {"Authorization": f"Bearer {cls.patient2_token}"}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        today = date.today()
        doc_ids = [self.doctor.id, self.doctor2.id, self.doctor_inactive.id]
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

    def _create_queue(self, doctor_id: int, is_paused: bool = False, is_active: bool = True) -> Queue:
        queue = Queue(
            doctor_id=doctor_id,
            queue_date=date.today(),
            is_paused=is_paused,
            is_active=is_active,
        )
        self.db.add(queue)
        self.db.commit()
        self.db.refresh(queue)
        return queue

    def _create_ticket(
        self,
        queue_id: int,
        position: int,
        status: TicketStatus = TicketStatus.WAITING,
        patient_id: int | None = None,
        patient_name: str = "Test Patient",
    ) -> QueueTicket:
        ticket = QueueTicket(
            queue_id=queue_id,
            patient_id=patient_id,
            patient_name=patient_name,
            patient_phone="+998901234567",
            ticket_number=position,
            queue_position=position,
            source=TicketSource.ONLINE,
            status=status,
            created_at=datetime.now(timezone.utc),
            checked_in_at=datetime.now(timezone.utc) if status != TicketStatus.WAITING else None,
            check_in_method=CheckInMethod.QR if status != TicketStatus.WAITING else None,
        )
        self.db.add(ticket)
        self.db.commit()
        self.db.refresh(ticket)
        return ticket

    # 1. Empty active queue
    def test_01_empty_active_queue_preview(self):
        queue = self._create_queue(self.doctor.id)
        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["id"], queue.id)
        self.assertEqual(data["queue_id"], queue.id)
        self.assertEqual(data["doctor_id"], self.doctor.id)
        self.assertTrue(data["is_active"])
        self.assertFalse(data["is_paused"])
        self.assertEqual(data["waiting_count"], 0)
        self.assertEqual(data["called_count"], 0)
        self.assertEqual(data["serving_count"], 0)
        self.assertEqual(data["estimated_position_if_joined"], 1)

    # 2. WAITING count
    def test_02_waiting_count(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.WAITING)
        self._create_ticket(queue.id, 2, TicketStatus.WAITING)
        self._create_ticket(queue.id, 3, TicketStatus.WAITING)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["waiting_count"], 3)
        self.assertEqual(data["called_count"], 0)
        self.assertEqual(data["serving_count"], 0)
        self.assertEqual(data["estimated_position_if_joined"], 4)

    # 3. CALLED count
    def test_03_called_count(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.CALLED)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["waiting_count"], 0)
        self.assertEqual(data["called_count"], 1)
        self.assertEqual(data["serving_count"], 0)
        self.assertEqual(data["estimated_position_if_joined"], 2)

    # 4. SERVING count
    def test_04_serving_count(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.SERVING)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["waiting_count"], 0)
        self.assertEqual(data["called_count"], 0)
        self.assertEqual(data["serving_count"], 1)
        self.assertEqual(data["estimated_position_if_joined"], 2)

    # 5. Mixed active statuses
    def test_05_mixed_active_statuses(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.SERVING)
        self._create_ticket(queue.id, 2, TicketStatus.CALLED)
        self._create_ticket(queue.id, 3, TicketStatus.WAITING)
        self._create_ticket(queue.id, 4, TicketStatus.WAITING)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["serving_count"], 1)
        self.assertEqual(data["called_count"], 1)
        self.assertEqual(data["waiting_count"], 2)
        self.assertEqual(data["estimated_position_if_joined"], 5)

    # 6. Terminal statuses excluded
    def test_06_terminal_statuses_excluded_from_counts(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.COMPLETED)
        self._create_ticket(queue.id, 2, TicketStatus.CANCELLED)
        self._create_ticket(queue.id, 3, TicketStatus.SKIPPED)
        self._create_ticket(queue.id, 4, TicketStatus.WAITING)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["serving_count"], 0)
        self.assertEqual(data["called_count"], 0)
        self.assertEqual(data["waiting_count"], 1)
        # Even with terminal statuses, estimated_position_if_joined reflects max(pos) + 1 = 5
        self.assertEqual(data["estimated_position_if_joined"], 5)

    # 7. estimated_position_if_joined matches POST join behavior
    def test_07_estimated_position_if_joined(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.COMPLETED)
        self._create_ticket(queue.id, 2, TicketStatus.WAITING)

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["estimated_position_if_joined"], 3)

        # Real join assigns exactly position 3
        join_res = self.client.post(
            f"/api/queues/{queue.id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(join_res.status_code, 201)
        self.assertEqual(join_res.json()["queue_position"], 3)

    # 8. missed-turn/reordered positions
    def test_08_missed_turn_reordered_positions(self):
        queue = self._create_queue(self.doctor.id)
        t1 = self._create_ticket(queue.id, 1, TicketStatus.CALLED)
        self._create_ticket(queue.id, 2, TicketStatus.WAITING)

        # Reorder t1 via missed turn: position becomes 3
        t1.queue_position = 3
        t1.status = TicketStatus.WAITING
        self.db.commit()

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["waiting_count"], 2)
        # Max pos is 3, so estimated position for new joiner is 4
        self.assertEqual(data["estimated_position_if_joined"], 4)

    # 9. Paused queue
    def test_09_paused_queue_preview(self):
        queue = self._create_queue(self.doctor.id, is_paused=True)
        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertTrue(data["is_paused"])
        self.assertTrue(data["is_active"])

    # 10. No daily queue
    def test_10_no_daily_queue_returns_404(self):
        # Doctor has no queue created today
        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 404)
        self.assertIn("No active queue for this doctor today", res.json()["detail"])

    # 11. Inactive queue
    def test_11_inactive_queue_state(self):
        queue = self._create_queue(self.doctor.id, is_active=False)
        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertFalse(data["is_active"])

    # 12. No private patient data leaked
    def test_12_no_private_patient_data_leaked(self):
        queue = self._create_queue(self.doctor.id)
        self._create_ticket(queue.id, 1, TicketStatus.WAITING, patient_name="Secret VIP Patient")

        res = self.client.get(
            f"/api/catalog/doctors/{self.doctor.id}/queue",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 200)
        body = res.text
        # Verify no names, phone numbers, or ticket lists leaked
        self.assertNotIn("Secret VIP Patient", body)
        self.assertNotIn("+998901234567", body)
        self.assertNotIn("tickets", body)
        self.assertNotIn("patient_id", body)
        self.assertNotIn("patient_name", body)

        # Expected keys only
        data = res.json()
        expected_keys = {
            "id", "queue_id", "doctor_id", "queue_date",
            "is_paused", "is_active", "waiting_count",
            "called_count", "serving_count", "estimated_position_if_joined",
        }
        self.assertEqual(set(data.keys()), expected_keys)

    # 13. Existing join still works
    def test_13_existing_join_still_works(self):
        queue = self._create_queue(self.doctor.id)
        res = self.client.post(
            f"/api/queues/{queue.id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["ticket_number"], 1)
        self.assertEqual(data["queue_position"], 1)
        self.assertEqual(data["status"].upper(), "WAITING")

    # 14. Duplicate active-ticket protection still works
    def test_14_duplicate_active_ticket_protection(self):
        queue = self._create_queue(self.doctor.id)
        # First join succeeds
        res1 = self.client.post(
            f"/api/queues/{queue.id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(res1.status_code, 201)

        # Second join returns 409
        res2 = self.client.post(
            f"/api/queues/{queue.id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(res2.status_code, 409)
        self.assertIn("already has an active ticket", res2.json()["detail"].lower())

    # 15. Relevant queue mutation triggers realtime update
    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_15_queue_mutation_triggers_realtime(self, mock_broadcast):
        queue = self._create_queue(self.doctor.id)

        # Patient joins
        join_res = self.client.post(
            f"/api/queues/{queue.id}/join",
            headers=self.patient_headers,
        )
        self.assertEqual(join_res.status_code, 201)

        # notify_display_update was triggered with queue_id
        # Manager broadcast should have been called
        self.assertTrue(mock_broadcast.called)
        broadcast_messages = [call[0][1] for call in mock_broadcast.call_args_list]

        # Verify queue_updated event is sent
        queue_updated_events = [m for m in broadcast_messages if m.get("type") == "queue_updated"]
        self.assertTrue(len(queue_updated_events) > 0)
        self.assertEqual(queue_updated_events[0]["queue_id"], queue.id)
        self.assertEqual(queue_updated_events[0]["clinic_id"], self.clinic.id)

    # 16. Queue events scoped/distinguished by queue_id
    def test_16_notify_display_update_scopes_by_queue_id(self):
        import asyncio

        async def run_test():
            with patch.object(manager, "broadcast", new_callable=AsyncMock) as mock_b:
                notify_display_update(clinic_id=self.clinic.id, queue_id=999)
                # Allow scheduled task to run
                await asyncio.sleep(0.05)
                self.assertTrue(mock_b.called)
                calls = [call[0][1] for call in mock_b.call_args_list]
                types = {c["type"]: c for c in calls}
                self.assertIn("queue_updated", types)
                self.assertEqual(types["queue_updated"]["queue_id"], 999)
                self.assertEqual(types["queue_updated"]["clinic_id"], self.clinic.id)
                self.assertIn("display_updated", types)
                self.assertEqual(types["display_updated"]["queue_id"], 999)

        asyncio.run(run_test())
