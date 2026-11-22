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


class ReceptionCancellationNotificationsTest(unittest.TestCase):
    def setUp(self) -> None:
        clean_test_database()
        self.client = TestClient(app)

        with TestSessionLocal() as db:
            self.clinic1 = Clinic(name="Clinic One", smart_call_timeout_seconds=120)
            self.clinic2 = Clinic(name="Clinic Two", smart_call_timeout_seconds=120)
            db.add_all([self.clinic1, self.clinic2])
            db.flush()

            self.spec1 = Specialization(
                clinic_id=self.clinic1.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="General",
            )
            self.spec2 = Specialization(
                clinic_id=self.clinic2.id,
                name_uz="Ortodontiya",
                name_ru="Ортодонтия",
                name_en="Orthodontics",
            )
            db.add_all([self.spec1, self.spec2])
            db.flush()

            self.doctor1 = Doctor(
                clinic_id=self.clinic1.id,
                specialization_id=self.spec1.id,
                full_name="Dr. Azizbek Rakhimov",
                room_number="101",
                is_active=True,
            )
            self.doctor1b = Doctor(
                clinic_id=self.clinic1.id,
                specialization_id=self.spec1.id,
                full_name="Dr. Malika Tursunova",
                room_number="102",
                is_active=True,
            )
            self.doctor2 = Doctor(
                clinic_id=self.clinic2.id,
                specialization_id=self.spec2.id,
                full_name="Dr. Clinic Two Doc",
                room_number="201",
                is_active=True,
            )
            db.add_all([self.doctor1, self.doctor1b, self.doctor2])
            db.flush()

            self.rec1 = User(
                clinic_id=self.clinic1.id,
                full_name="Rec One",
                phone="+998901110001",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            self.rec2 = User(
                clinic_id=self.clinic2.id,
                full_name="Rec Two",
                phone="+998901110002",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            self.patient1 = User(
                clinic_id=None,
                full_name="Affected Patient",
                phone="+998903330001",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            self.patient2 = User(
                clinic_id=None,
                full_name="Other Patient",
                phone="+998903330002",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            self.patient3 = User(
                clinic_id=None,
                full_name="Clinic Two Patient",
                phone="+998903330003",
                hashed_password="x",
                role=UserRole.PATIENT,
                is_active=True,
            )
            db.add_all([self.rec1, self.rec2, self.patient1, self.patient2, self.patient3])
            db.flush()

            db.add_all([
                PushDevice(user_id=self.patient1.id, fcm_token="tok_patient_1_secret_12345", is_active=True),
                PushDevice(user_id=self.patient2.id, fcm_token="tok_patient_2_secret_67890", is_active=True),
                PushDevice(user_id=self.patient3.id, fcm_token="tok_patient_3_secret_abcde", is_active=True),
            ])
            db.commit()

            self.doc1_id = self.doctor1.id
            self.doc1b_id = self.doctor1b.id
            self.doc2_id = self.doctor2.id
            self.rec1_headers = {"Authorization": f"Bearer {create_access_token(self.rec1.id)}"}
            self.rec2_headers = {"Authorization": f"Bearer {create_access_token(self.rec2.id)}"}
            self.p1_headers = {"Authorization": f"Bearer {create_access_token(self.patient1.id)}"}
            self.p2_headers = {"Authorization": f"Bearer {create_access_token(self.patient2.id)}"}
            self.p3_headers = {"Authorization": f"Bearer {create_access_token(self.patient3.id)}"}

    def tearDown(self) -> None:
        clean_test_database()

    def _open_queue(self, doctor_id: int, headers: dict[str, str]) -> int:
        res = self.client.post("/api/queues/open", json={"doctor_id": doctor_id}, headers=headers)
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    @staticmethod
    def _cancelled_calls(mock_send) -> list[dict]:
        return [
            {
                "token": c.kwargs["token"],
                "title": c.kwargs["title"],
                "body": c.kwargs["body"],
                "data": c.kwargs["data"],
            }
            for c in mock_send.call_args_list
            if c.kwargs.get("data", {}).get("type") == "QUEUE_CANCELLED"
        ]

    @patch("app.services.queue_notifications.send_push_notification")
    @patch("app.realtime.manager.manager.broadcast", new_callable=AsyncMock)
    def test_1_2_3_4_6_reception_cancel_notifies_only_target_patient_once_and_broadcasts(
        self, mock_broadcast, mock_send
    ) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="msg-cancel-1")
        q1 = self._open_queue(self.doc1_id, self.rec1_headers)
        q2 = self._open_queue(self.doc2_id, self.rec2_headers)

        t1 = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        t2 = self.client.post(f"/api/queues/{q1}/join", headers=self.p2_headers).json()
        t3 = self.client.post(f"/api/queues/{q2}/join", headers=self.p3_headers).json()

        mock_send.reset_mock()
        mock_broadcast.reset_mock()

        # 1 & 2 & 3 & 6: Reception cancels patient1's WAITING ticket
        res = self.client.patch(
            f"/api/queues/{q1}/tickets/{t1['id']}/cancel",
            headers=self.rec1_headers,
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "CANCELLED")

        # Realtime broadcast preserved
        self.assertTrue(mock_broadcast.called)
        ws_types = [c.args[1]["type"] for c in mock_broadcast.call_args_list]
        self.assertIn("display_updated", ws_types)
        self.assertIn("queue_updated", ws_types)

        # Exactly one QUEUE_CANCELLED notification sent to patient1 only
        cancel_pushes = self._cancelled_calls(mock_send)
        self.assertEqual(len(cancel_pushes), 1)
        self.assertEqual(cancel_pushes[0]["token"], "tok_patient_1_secret_12345")
        self.assertEqual(cancel_pushes[0]["title"], "Navbatingiz bekor qilindi")
        self.assertIn("Dr. Azizbek Rakhimov", cancel_pushes[0]["body"])
        self.assertIn("Clinic One", cancel_pushes[0]["body"])
        self.assertEqual(cancel_pushes[0]["data"]["ticket_id"], str(t1["id"]))
        self.assertEqual(cancel_pushes[0]["data"]["queue_id"], str(q1))

        # Other patients (same clinic p2 and other clinic p3) received nothing
        all_tokens = {c.kwargs["token"] for c in mock_send.call_args_list}
        self.assertNotIn("tok_patient_2_secret_67890", all_tokens)
        self.assertNotIn("tok_patient_3_secret_abcde", all_tokens)

        # 4: Repeated cancellation attempt returns 409 and produces NO duplicate push
        mock_send.reset_mock()
        dup = self.client.patch(
            f"/api/queues/{q1}/tickets/{t1['id']}/cancel",
            headers=self.rec1_headers,
        )
        self.assertEqual(dup.status_code, 409)
        self.assertEqual(self._cancelled_calls(mock_send), [])

        # t2 & t3 remain untouched WAITING
        with TestSessionLocal() as db:
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t2["id"])), TicketStatus.WAITING)
            self.assertEqual(db.scalar(select(QueueTicket.status).where(QueueTicket.id == t3["id"])), TicketStatus.WAITING)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_4_localization_uz_ru_en(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="msg-i18n")

        # Uzbek default
        q1 = self._open_queue(self.doc1_id, self.rec1_headers)
        t_uz = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        mock_send.reset_mock()
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q1}/tickets/{t_uz['id']}/cancel",
                headers={**self.rec1_headers, "Accept-Language": "uz"},
            ).status_code,
            200,
        )
        uz_push = self._cancelled_calls(mock_send)[0]
        self.assertEqual(uz_push["title"], "Navbatingiz bekor qilindi")
        self.assertIn("Dr. Azizbek Rakhimov", uz_push["body"])

        # Russian
        t_ru = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        mock_send.reset_mock()
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q1}/tickets/{t_ru['id']}/cancel",
                headers={**self.rec1_headers, "Accept-Language": "ru-RU"},
            ).status_code,
            200,
        )
        ru_push = self._cancelled_calls(mock_send)[0]
        self.assertEqual(ru_push["title"], "Ваша запись отменена")
        self.assertIn("Dr. Azizbek Rakhimov", ru_push["body"])

        # English
        t_en = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        mock_send.reset_mock()
        self.assertEqual(
            self.client.patch(
                f"/api/queues/{q1}/tickets/{t_en['id']}/cancel",
                headers={**self.rec1_headers, "Accept-Language": "en-US"},
            ).status_code,
            200,
        )
        en_push = self._cancelled_calls(mock_send)[0]
        self.assertEqual(en_push["title"], "Queue ticket cancelled")
        self.assertIn("Dr. Azizbek Rakhimov", en_push["body"])

    @patch("app.services.queue_notifications.send_push_notification")
    def test_5_patient_self_cancel_does_not_send_reception_cancellation_push(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="msg-self")
        q1 = self._open_queue(self.doc1_id, self.rec1_headers)

        # Case A: Patient cancels via PATCH /my-ticket/cancel
        self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers)
        mock_send.reset_mock()
        res_a = self.client.patch("/api/queues/my-ticket/cancel", headers=self.p1_headers)
        self.assertEqual(res_a.status_code, 200)
        self.assertEqual(res_a.json()["status"], "CANCELLED")
        self.assertEqual(self._cancelled_calls(mock_send), [])

        # Case B: Patient cancels own ticket via PATCH /{queue_id}/tickets/{ticket_id}/cancel
        t_b = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        mock_send.reset_mock()
        res_b = self.client.patch(
            f"/api/queues/{q1}/tickets/{t_b['id']}/cancel",
            headers=self.p1_headers,
        )
        self.assertEqual(res_b.status_code, 200)
        self.assertEqual(res_b.json()["status"], "CANCELLED")
        self.assertEqual(self._cancelled_calls(mock_send), [])

    def test_7_firebase_unavailable_still_cancels_and_logs_safely(self) -> None:
        q1 = self._open_queue(self.doc1_id, self.rec1_headers)
        with patch("app.services.notifications.get_firebase_credentials_path", return_value=None), patch(
            "app.services.notifications.firebase_admin.get_app",
            side_effect=ValueError("uninitialized"),
        ):
            t1 = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
            with self.assertLogs("app.services.queue_notifications", level="WARNING") as cm:
                res = self.client.patch(
                    f"/api/queues/{q1}/tickets/{t1['id']}/cancel",
                    headers=self.rec1_headers,
                )
            self.assertEqual(res.status_code, 200)
            self.assertEqual(res.json()["status"], "CANCELLED")
            joined = "\n".join(cm.output)
            self.assertIn("FIREBASE_NOT_INITIALIZED", joined)
            self.assertNotIn("tok_patient_1_secret_12345", joined)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_8_no_cross_clinic_or_cross_doctor_leakage(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="msg-iso")
        q1 = self._open_queue(self.doc1_id, self.rec1_headers)
        q2 = self._open_queue(self.doc2_id, self.rec2_headers)

        t1 = self.client.post(f"/api/queues/{q1}/join", headers=self.p1_headers).json()
        self.client.post(f"/api/queues/{q2}/join", headers=self.p3_headers)

        # Cross-clinic receptionist cannot cancel clinic1's ticket
        mock_send.reset_mock()
        forbidden = self.client.patch(
            f"/api/queues/{q1}/tickets/{t1['id']}/cancel",
            headers=self.rec2_headers,
        )
        self.assertEqual(forbidden.status_code, 403)
        self.assertEqual(self._cancelled_calls(mock_send), [])

        # Cancelling clinic1's doc1 ticket mentions doc1 only, never leaks to doc1b or clinic2
        res = self.client.patch(
            f"/api/queues/{q1}/tickets/{t1['id']}/cancel",
            headers=self.rec1_headers,
        )
        self.assertEqual(res.status_code, 200)
        pushes = self._cancelled_calls(mock_send)
        self.assertEqual(len(pushes), 1)
        self.assertEqual(pushes[0]["token"], "tok_patient_1_secret_12345")
        self.assertIn("Dr. Azizbek Rakhimov", pushes[0]["body"])
        self.assertNotIn("Dr. Malika Tursunova", pushes[0]["body"])
        self.assertNotIn("Clinic Two", pushes[0]["body"])
