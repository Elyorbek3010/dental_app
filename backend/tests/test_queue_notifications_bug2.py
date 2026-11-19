import unittest
from datetime import date, timedelta
from unittest.mock import AsyncMock, patch

from tests.test_db import TestSessionLocal as SessionLocal
from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.push_device import PushDevice
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.notifications import PushNotificationResult


class QueueNotificationsBug2Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()

        cls.clinic = cls.db.scalar(select(Clinic).where(Clinic.id == 1))
        if not cls.clinic:
            cls.clinic = Clinic(id=1, name="Bug2 Clinic")
            cls.db.add(cls.clinic)
            cls.db.commit()

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

        cls.doctor = cls.db.scalar(
            select(Doctor).where(Doctor.full_name == "Dr. Bug2 Test")
        )
        if not cls.doctor:
            cls.doctor = Doctor(
                clinic_id=cls.clinic.id,
                specialization_id=cls.spec.id,
                full_name="Dr. Bug2 Test",
                room_number="204",
                is_active=True,
            )
            cls.db.add(cls.doctor)
            cls.db.commit()
            cls.db.refresh(cls.doctor)

        cls.rec = cls.db.scalar(select(User).where(User.phone == "+998908880001"))
        if not cls.rec:
            cls.rec = User(
                clinic_id=cls.clinic.id,
                full_name="Bug2 Receptionist",
                phone="+998908880001",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            cls.db.add(cls.rec)
            cls.db.commit()
            cls.db.refresh(cls.rec)

        cls.patient1 = cls.db.scalar(select(User).where(User.phone == "+998908880002"))
        if not cls.patient1:
            cls.patient1 = User(
                clinic_id=None,
                full_name="Bug2 Patient 1",
                phone="+998908880002",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            cls.db.add(cls.patient1)
            cls.db.commit()
            cls.db.refresh(cls.patient1)

        cls.patient2 = cls.db.scalar(select(User).where(User.phone == "+998908880003"))
        if not cls.patient2:
            cls.patient2 = User(
                clinic_id=None,
                full_name="Bug2 Patient 2",
                phone="+998908880003",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            cls.db.add(cls.patient2)
            cls.db.commit()
            cls.db.refresh(cls.patient2)

        # Ensure active PushDevice tokens exist for both patients
        for idx, user in enumerate((cls.patient1, cls.patient2), start=1):
            token = f"bug2_fcm_token_{idx}"
            device = cls.db.scalar(select(PushDevice).where(PushDevice.fcm_token == token))
            if not device:
                cls.db.add(PushDevice(user_id=user.id, fcm_token=token, is_active=True))
            else:
                device.user_id = user.id
                device.is_active = True
        cls.db.commit()

        cls.rec_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.rec.id)}"
        }
        cls.p1_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.patient1.id)}"
        }
        cls.p2_headers = {
            "Authorization": f"Bearer {create_access_token(subject=cls.patient2.id)}"
        }

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def setUp(self):
        queues = self.db.scalars(
            select(Queue).where(Queue.doctor_id == self.doctor.id)
        ).all()
        for q in queues:
            self.db.execute(delete(QueueTicket).where(QueueTicket.queue_id == q.id))
            self.db.execute(delete(Queue).where(Queue.id == q.id))
        self.db.commit()

    def _open_today_queue(self) -> int:
        res = self.client.post(
            "/api/queues/open",
            json={"doctor_id": self.doctor.id},
            headers=self.rec_headers,
        )
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    @patch("app.services.queue_notifications.send_push_notification")
    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_manual_skip_and_restore_send_dedicated_notifications_and_reposition(
        self, mock_broadcast, mock_send_push
    ):
        mock_send_push.return_value = PushNotificationResult(success=True, message_id="msg-1")
        queue_id = self._open_today_queue()

        # Patient 1 joins & checks in
        t1 = self.client.post(f"/api/queues/{queue_id}/join", headers=self.p1_headers).json()
        self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/check-in",
            headers=self.rec_headers,
        )

        # Patient 2 joins
        t2 = self.client.post(f"/api/queues/{queue_id}/join", headers=self.p2_headers).json()

        # Call Patient 1 -> QUEUE_CALLED
        mock_send_push.reset_mock()
        call_res = self.client.post(f"/api/queues/{queue_id}/call-next", headers=self.rec_headers)
        self.assertEqual(call_res.status_code, 200)
        called_types = [c.kwargs["data"]["type"] for c in mock_send_push.call_args_list]
        self.assertIn("QUEUE_CALLED", called_types)
        self.assertNotIn("QUEUE_SKIPPED", called_types)

        # Manual Skip Patient 1 -> QUEUE_SKIPPED (distinct from QUEUE_MISSED_TURN)
        mock_send_push.reset_mock()
        mock_broadcast.reset_mock()
        skip_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/skip",
            headers=self.rec_headers,
        )
        self.assertEqual(skip_res.status_code, 200)
        self.assertEqual(skip_res.json()["status"], "SKIPPED")

        skip_types = [c.kwargs["data"]["type"] for c in mock_send_push.call_args_list]
        self.assertEqual(skip_types, ["QUEUE_SKIPPED"])
        self.assertTrue(mock_broadcast.called)

        # Default /my-ticket still returns 404 for SKIPPED (backward-compatible)
        default_my = self.client.get("/api/queues/my-ticket", headers=self.p1_headers)
        self.assertEqual(default_my.status_code, 404)

        # Optional ?include_skipped=true returns the SKIPPED ticket
        incl_my = self.client.get(
            "/api/queues/my-ticket?include_skipped=true",
            headers=self.p1_headers,
        )
        self.assertEqual(incl_my.status_code, 200)
        self.assertEqual(incl_my.json()["status"], "SKIPPED")
        self.assertEqual(incl_my.json()["ticket_number"], t1["ticket_number"])
        self.assertEqual(incl_my.json()["people_ahead"], 0)

        # Restore Patient 1 -> WAITING at end of queue (after Patient 2), sends QUEUE_RESTORED
        mock_send_push.reset_mock()
        mock_broadcast.reset_mock()
        restore_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/restore",
            headers=self.rec_headers,
        )
        self.assertEqual(restore_res.status_code, 200)
        restored = restore_res.json()
        self.assertEqual(restored["status"], "WAITING")
        self.assertEqual(restored["ticket_number"], t1["ticket_number"])
        self.assertGreater(restored["queue_position"], t2["queue_position"])

        restore_types = [c.kwargs["data"]["type"] for c in mock_send_push.call_args_list]
        self.assertEqual(restore_types, ["QUEUE_RESTORED"])
        self.assertTrue(mock_broadcast.called)

    @patch("app.services.queue_notifications.send_push_notification")
    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_smart_call_reposition_broadcasts_and_notifies_even_on_409(
        self, mock_broadcast, mock_send_push
    ):
        mock_send_push.return_value = PushNotificationResult(success=True, message_id="msg-2")
        queue_id = self._open_today_queue()

        # Patient 1 joins online, does NOT check in
        t1 = self.client.post(f"/api/queues/{queue_id}/join", headers=self.p1_headers).json()

        mock_send_push.reset_mock()
        mock_broadcast.reset_mock()

        # Smart Call finds no checked-in patient -> moves t1 to end, returns 409,
        # MUST still broadcast WebSocket update and send QUEUE_MISSED_TURN (not QUEUE_SKIPPED)
        res = self.client.post(f"/api/queues/{queue_id}/call-next", headers=self.rec_headers)
        self.assertEqual(res.status_code, 409)
        self.assertEqual(res.json()["detail"], "No checked-in patient available")

        # Broadcast occurred despite 409
        self.assertTrue(mock_broadcast.called)
        ws_types = [c.args[1]["type"] for c in mock_broadcast.call_args_list]
        self.assertIn("queue_updated", ws_types)
        self.assertIn("display_updated", ws_types)

        # Notification is QUEUE_MISSED_TURN (not QUEUE_SKIPPED)
        notif_types = [c.kwargs["data"]["type"] for c in mock_send_push.call_args_list]
        self.assertEqual(notif_types, ["QUEUE_MISSED_TURN"])

        # Ticket remains WAITING with same ticket_number and incremented missed_turns
        self.db.expire_all()
        refreshed = self.db.scalar(select(QueueTicket).where(QueueTicket.id == t1["id"]))
        self.assertEqual(refreshed.status, TicketStatus.WAITING)
        self.assertEqual(refreshed.ticket_number, t1["ticket_number"])
        self.assertEqual(refreshed.missed_turns, 1)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_include_skipped_ignores_old_dates_and_prefers_active_ticket(self, mock_send_push):
        mock_send_push.return_value = PushNotificationResult(success=True, message_id="msg-3")

        # Create yesterday's queue with a SKIPPED ticket for patient1
        yesterday_q = Queue(
            doctor_id=self.doctor.id,
            queue_date=date.today() - timedelta(days=1),
            is_paused=False,
            is_active=True,
        )
        self.db.add(yesterday_q)
        self.db.commit()
        self.db.refresh(yesterday_q)

        old_skipped = QueueTicket(
            queue_id=yesterday_q.id,
            patient_id=self.patient1.id,
            ticket_number=1,
            queue_position=1,
            patient_name=self.patient1.full_name,
            patient_phone=self.patient1.phone,
            source=TicketSource.ONLINE,
            status=TicketStatus.SKIPPED,
        )
        self.db.add(old_skipped)
        self.db.commit()

        # Yesterday's SKIPPED ticket must NOT appear with include_skipped=true
        res_old = self.client.get(
            "/api/queues/my-ticket?include_skipped=true",
            headers=self.p1_headers,
        )
        self.assertEqual(res_old.status_code, 404)

        # Open today's queue and create an active WAITING ticket for patient1
        today_qid = self._open_today_queue()
        join_res = self.client.post(f"/api/queues/{today_qid}/join", headers=self.p1_headers)
        self.assertEqual(join_res.status_code, 201)

        # Active WAITING ticket is preferred over skipped
        res_active = self.client.get(
            "/api/queues/my-ticket?include_skipped=true",
            headers=self.p1_headers,
        )
        self.assertEqual(res_active.status_code, 200)
        self.assertEqual(res_active.json()["status"], "WAITING")
        self.assertEqual(res_active.json()["queue_id"], today_qid)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_notification_failure_does_not_break_skip_restore_or_call(self, mock_send_push):
        mock_send_push.side_effect = RuntimeError("Simulated FCM outage")
        queue_id = self._open_today_queue()

        t1 = self.client.post(f"/api/queues/{queue_id}/join", headers=self.p1_headers).json()
        self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/check-in",
            headers=self.rec_headers,
        )

        # Call succeeds despite FCM error
        call_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/call",
            headers=self.rec_headers,
        )
        self.assertEqual(call_res.status_code, 200)
        self.assertEqual(call_res.json()["status"], "CALLED")

        # Skip succeeds despite FCM error
        skip_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/skip",
            headers=self.rec_headers,
        )
        self.assertEqual(skip_res.status_code, 200)
        self.assertEqual(skip_res.json()["status"], "SKIPPED")

        # Restore succeeds despite FCM error
        restore_res = self.client.patch(
            f"/api/queues/{queue_id}/tickets/{t1['id']}/restore",
            headers=self.rec_headers,
        )
        self.assertEqual(restore_res.status_code, 200)
        self.assertEqual(restore_res.json()["status"], "WAITING")


if __name__ == "__main__":
    unittest.main()
