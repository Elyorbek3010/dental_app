from concurrent.futures import ThreadPoolExecutor
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.push_device import PushDevice
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.notifications import PushNotificationResult
from tests.test_db import TestSessionLocal, clean_test_database


class ManualCallCheckInValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        clean_test_database()
        self.client = TestClient(app)

        with TestSessionLocal() as db:
            self.clinic = Clinic(name="Validation Clinic", smart_call_timeout_seconds=120)
            db.add(self.clinic)
            db.flush()

            self.spec = Specialization(
                clinic_id=self.clinic.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="General",
            )
            db.add(self.spec)
            db.flush()

            self.doctor = Doctor(
                clinic_id=self.clinic.id,
                specialization_id=self.spec.id,
                full_name="Dr. Manual Call Test",
                room_number="105",
                is_active=True,
            )
            db.add(self.doctor)
            db.flush()

            self.rec = User(
                clinic_id=self.clinic.id,
                full_name="Rec Validation",
                phone="+998901110010",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            self.patient1 = User(
                clinic_id=None,
                full_name="Online Patient 1",
                phone="+998903330011",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            self.patient2 = User(
                clinic_id=None,
                full_name="Online Patient 2",
                phone="+998903330012",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            db.add_all([self.rec, self.patient1, self.patient2])
            db.flush()

            db.add_all([
                PushDevice(user_id=self.patient1.id, fcm_token="tok_manual_call_p1_secret", is_active=True),
                PushDevice(user_id=self.patient2.id, fcm_token="tok_manual_call_p2_secret", is_active=True),
            ])
            db.commit()

            self.doctor_id = self.doctor.id
            self.clinic_id = self.clinic.id
            self.rec_headers = {"Authorization": f"Bearer {create_access_token(self.rec.id)}"}
            self.p1_headers = {"Authorization": f"Bearer {create_access_token(self.patient1.id)}"}
            self.p2_headers = {"Authorization": f"Bearer {create_access_token(self.patient2.id)}"}

    def tearDown(self) -> None:
        clean_test_database()

    def _open_queue(self) -> int:
        res = self.client.post("/api/queues/open", json={"doctor_id": self.doctor_id}, headers=self.rec_headers)
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    @patch("app.services.queue_notifications.send_push_notification")
    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_unchecked_in_patient_rejected_409_and_checked_in_allowed(
        self, mock_broadcast, mock_send
    ) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m-ok")
        qid = self._open_queue()

        # Online patient joins (unchecked-in)
        t1 = self.client.post(f"/api/queues/{qid}/join", headers=self.p1_headers).json()
        self.assertIsNone(t1["checked_in_at"])

        mock_send.reset_mock()
        mock_broadcast.reset_mock()

        # Direct API manual call MUST fail with 409 Conflict
        blocked = self.client.patch(
            f"/api/queues/{qid}/tickets/{t1['id']}/call",
            headers=self.rec_headers,
        )
        self.assertEqual(blocked.status_code, 409)
        self.assertIn("checked in", blocked.json()["detail"].lower())
        self.assertFalse(mock_broadcast.called)
        self.assertEqual(mock_send.call_count, 0)

        with TestSessionLocal() as db:
            db_t1 = db.scalar(select(QueueTicket).where(QueueTicket.id == t1["id"]))
            self.assertEqual(db_t1.status, TicketStatus.WAITING)
            self.assertIsNone(db_t1.called_at)
            self.assertIsNone(db_t1.call_deadline_at)

        # After QR or Reception check-in, manual call succeeds (200)
        qr = self.client.get("/api/queues/check-in/qr-token", headers=self.rec_headers)
        self.assertEqual(qr.status_code, 200)
        ci = self.client.post(
            "/api/queues/check-in/qr",
            json={"token": qr.json()["token"]},
            headers=self.p1_headers,
        )
        self.assertEqual(ci.status_code, 200)
        self.assertIsNotNone(ci.json()["checked_in_at"])

        allowed = self.client.patch(
            f"/api/queues/{qid}/tickets/{t1['id']}/call",
            headers=self.rec_headers,
        )
        self.assertEqual(allowed.status_code, 200)
        self.assertEqual(allowed.json()["status"], "CALLED")
        self.assertIsNotNone(allowed.json()["call_deadline_at"])
        self.assertTrue(mock_broadcast.called)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_walk_in_auto_checked_in_allowed_and_smart_call_preserved(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m-wi")
        qid = self._open_queue()

        # Unchecked online patient + checked-in walk-in patient
        t_online = self.client.post(f"/api/queues/{qid}/join", headers=self.p1_headers).json()
        t_walkin = self.client.post(
            f"/api/queues/{qid}/walk-in",
            json={"patient_name": "WalkIn Checked"},
            headers=self.rec_headers,
        ).json()
        self.assertIsNotNone(t_walkin["checked_in_at"])

        # Manual call on walk-in succeeds directly
        res = self.client.patch(
            f"/api/queues/{qid}/tickets/{t_walkin['id']}/call",
            headers=self.rec_headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "CALLED")

        # Complete walk-in, then Smart Call still repositions unchecked online patient -> 409
        self.client.patch(f"/api/queues/{qid}/tickets/{t_walkin['id']}/serve", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{qid}/tickets/{t_walkin['id']}/complete", headers=self.rec_headers)

        sc = self.client.post(f"/api/queues/{qid}/call-next", headers=self.rec_headers)
        self.assertEqual(sc.status_code, 409)
        with TestSessionLocal() as db:
            db_t = db.scalar(select(QueueTicket).where(QueueTicket.id == t_online["id"]))
            self.assertEqual(db_t.missed_turns, 1)
            self.assertEqual(db_t.status, TicketStatus.WAITING)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_concurrent_manual_call_requests_safe_for_unchecked_and_checked_in(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m-conc")
        qid = self._open_queue()

        t_unchecked = self.client.post(f"/api/queues/{qid}/join", headers=self.p1_headers).json()

        def _call_ticket(tid: int) -> int:
            with TestClient(app) as c:
                return c.patch(
                    f"/api/queues/{qid}/tickets/{tid}/call",
                    headers=self.rec_headers,
                ).status_code

        # Concurrent manual calls on unchecked-in ticket -> all return 409
        with ThreadPoolExecutor(max_workers=3) as pool:
            statuses_unchecked = list(pool.map(_call_ticket, [t_unchecked["id"]] * 3))
        self.assertEqual(statuses_unchecked, [409, 409, 409])

        # Check-in patient2, then race concurrent manual calls -> exactly one 200 and rest 409
        t_checked = self.client.post(f"/api/queues/{qid}/join", headers=self.p2_headers).json()
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{qid}/tickets/{t_checked['id']}/check-in",
                headers=self.rec_headers,
            ).status_code,
            200,
        )

        with ThreadPoolExecutor(max_workers=3) as pool:
            statuses_checked = list(pool.map(_call_ticket, [t_checked["id"]] * 3))
        self.assertEqual(statuses_checked.count(200), 1)
        self.assertEqual(statuses_checked.count(409), 2)
