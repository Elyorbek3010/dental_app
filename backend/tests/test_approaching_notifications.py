from concurrent.futures import ThreadPoolExecutor
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.security import create_access_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.push_device import PushDevice
from app.models.queue_ticket import QueueTicket
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.notifications import PushNotificationResult
from app.services.queue_notifications import check_and_trigger_approaching
from tests.test_db import TestSessionLocal, clean_test_database


class ApproachingNotificationsTest(unittest.TestCase):
    def setUp(self) -> None:
        clean_test_database()
        self.client = TestClient(app)
        with TestSessionLocal() as db:
            self.clinic = Clinic(name="Approaching Clinic", smart_call_timeout_seconds=120)
            db.add(self.clinic)
            db.flush()

            self.spec = Specialization(
                clinic_id=self.clinic.id,
                name_uz="Terapiya",
                name_ru="Терапия",
                name_en="General",
            )
            self.spec2 = Specialization(
                clinic_id=self.clinic.id,
                name_uz="Ortodontiya",
                name_ru="Ортодонтия",
                name_en="Orthodontics",
            )
            db.add_all([self.spec, self.spec2])
            db.flush()

            self.doctor1 = Doctor(
                clinic_id=self.clinic.id,
                specialization_id=self.spec.id,
                full_name="Dr. One",
                room_number="101",
                is_active=True,
            )
            self.doctor2 = Doctor(
                clinic_id=self.clinic.id,
                specialization_id=self.spec2.id,
                full_name="Dr. Two",
                room_number="102",
                is_active=True,
            )
            db.add_all([self.doctor1, self.doctor2])
            db.flush()

            self.rec = User(
                clinic_id=self.clinic.id,
                full_name="Rec Staff",
                phone="+998901110000",
                hashed_password="x",
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
            db.add(self.rec)
            db.flush()

            self.patients: list[User] = []
            for idx in range(1, 9):
                p = User(
                    clinic_id=None,
                    full_name=f"Patient {idx}",
                    phone=f"+99890222{idx:04d}",
                    hashed_password="x",
                    role=UserRole.PATIENT,
                    is_active=True,
                )
                db.add(p)
                db.flush()
                db.add(
                    PushDevice(
                        user_id=p.id,
                        fcm_token=f"secret_device_token_patient_{idx}_abcdef123456",
                        is_active=True,
                    )
                )
                self.patients.append(p)
            db.commit()

            self.clinic_id = self.clinic.id
            self.doc1_id = self.doctor1.id
            self.doc2_id = self.doctor2.id
            self.rec_headers = {"Authorization": f"Bearer {create_access_token(self.rec.id)}"}
            self.patient_headers = [
                {"Authorization": f"Bearer {create_access_token(p.id)}"}
                for p in self.patients
            ]

    def tearDown(self) -> None:
        clean_test_database()

    def _open_queue(self, doctor_id: int) -> int:
        res = self.client.post(
            "/api/queues/open",
            json={"doctor_id": doctor_id},
            headers=self.rec_headers,
        )
        self.assertEqual(res.status_code, 201)
        return res.json()["id"]

    def _join_and_optionally_check_in(self, queue_id: int, patient_idx: int, check_in: bool = True) -> dict:
        res = self.client.post(
            f"/api/queues/{queue_id}/join",
            headers=self.patient_headers[patient_idx],
        )
        self.assertEqual(res.status_code, 201)
        ticket = res.json()
        if check_in:
            ci = self.client.patch(
                f"/api/queues/{queue_id}/tickets/{ticket['id']}/check-in",
                headers=self.rec_headers,
            )
            self.assertEqual(ci.status_code, 200)
        return ticket

    @staticmethod
    def _approaching_calls(mock_send) -> list[dict]:
        return [
            {
                "token": call.kwargs["token"],
                "body": call.kwargs["body"],
                "data": call.kwargs["data"],
            }
            for call in mock_send.call_args_list
            if call.kwargs.get("data", {}).get("type") == "QUEUE_APPROACHING"
        ]

    @patch("app.services.queue_notifications.send_push_notification")
    def test_1_and_2_normal_3_ahead_notification_and_no_duplicates(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m1")
        qid = self._open_queue(self.doc1_id)

        # Patients 0..4 join -> P3 gets notified as 4th (3 ahead), P4 sits at 4 ahead (unnotified)
        tickets = [self._join_and_optionally_check_in(qid, idx) for idx in range(5)]
        approaching_after_join = self._approaching_calls(mock_send)
        self.assertEqual(len(approaching_after_join), 1)
        self.assertEqual(approaching_after_join[0]["data"]["ticket_id"], str(tickets[3]["id"]))
        self.assertIn("patient_4", approaching_after_join[0]["token"])

        # Complete P0 -> now P4 has 3 ahead and should get notified ONCE
        mock_send.reset_mock()
        self.assertEqual(self.client.post(f"/api/queues/{qid}/call-next", headers=self.rec_headers).status_code, 200)
        self.assertEqual(self.client.patch(f"/api/queues/{qid}/tickets/{tickets[0]['id']}/serve", headers=self.rec_headers).status_code, 200)
        self.assertEqual(self.client.patch(f"/api/queues/{qid}/tickets/{tickets[0]['id']}/complete", headers=self.rec_headers).status_code, 200)

        approaching_after_comp = self._approaching_calls(mock_send)
        self.assertEqual(len(approaching_after_comp), 1)
        self.assertEqual(approaching_after_comp[0]["data"]["ticket_id"], str(tickets[4]["id"]))
        self.assertIn("patient_5", approaching_after_comp[0]["token"])

        # Additional evaluations, refreshes, or joins behind P4 must NOT re-notify P4
        mock_send.reset_mock()
        check_and_trigger_approaching(qid)
        check_and_trigger_approaching(qid)
        self.assertEqual(self.client.get("/api/queues/my-ticket", headers=self.patient_headers[4]).status_code, 200)
        self._join_and_optionally_check_in(qid, 5)
        self.assertEqual(self._approaching_calls(mock_send), [])

    @patch("app.services.queue_notifications.send_push_notification")
    def test_3_miss_turn_resets_for_second_approach_and_avoids_short_queue_noise(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m2")

        # Part A: Short queue guard (4 active total)
        q_short = self._open_queue(self.doc1_id)
        short_tickets = [
            self._join_and_optionally_check_in(q_short, 0, check_in=True),
            self._join_and_optionally_check_in(q_short, 1, check_in=True),
            self._join_and_optionally_check_in(q_short, 2, check_in=True),
            self._join_and_optionally_check_in(q_short, 3, check_in=False),  # 4th -> already notified
        ]
        self.assertEqual(len(self._approaching_calls(mock_send)), 1)

        mock_send.reset_mock()
        miss_res = self.client.patch(
            f"/api/queues/{q_short}/tickets/{short_tickets[3]['id']}/miss-turn",
            headers=self.rec_headers,
        )
        self.assertEqual(miss_res.status_code, 200)
        # Must NOT immediately fire a misleading second approaching notification in a 4-person queue
        self.assertEqual(self._approaching_calls(mock_send), [])

        # Finish short queue cleanly so doc1 can open a fresh queue for Part B
        self.client.patch(f"/api/queues/{q_short}/tickets/{short_tickets[0]['id']}/cancel", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_short}/tickets/{short_tickets[1]['id']}/cancel", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_short}/tickets/{short_tickets[2]['id']}/cancel", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_short}/tickets/{short_tickets[3]['id']}/cancel", headers=self.rec_headers)
        self.assertEqual(self.client.patch(f"/api/queues/{q_short}/finish", headers=self.rec_headers).status_code, 200)

        # Part B: Long queue (> 4 active) -> Miss Turn resets eligibility -> second approach notifies again
        q_long = self._open_queue(self.doc1_id)
        # Join P0..P5 (6 patients). Unchecked-in P3 gets notified as 4th, while P4, P5 stay ahead=4,5
        t_long = [
            self._join_and_optionally_check_in(q_long, 0, check_in=True),
            self._join_and_optionally_check_in(q_long, 1, check_in=True),
            self._join_and_optionally_check_in(q_long, 2, check_in=True),
            self._join_and_optionally_check_in(q_long, 3, check_in=False),  # idx 3
            self._join_and_optionally_check_in(q_long, 4, check_in=True),
            self._join_and_optionally_check_in(q_long, 5, check_in=True),
        ]
        # P3 moves to end (now 5 ahead -> > 3 ahead!), while P4 moves from 4 ahead to 3 ahead
        mock_send.reset_mock()
        miss_long = self.client.patch(
            f"/api/queues/{q_long}/tickets/{t_long[3]['id']}/miss-turn",
            headers=self.rec_headers,
        )
        self.assertEqual(miss_long.status_code, 200)
        calls = self._approaching_calls(mock_send)
        self.assertEqual([c["data"]["ticket_id"] for c in calls], [str(t_long[4]["id"])])

        # Verify P3 approaching_notified_at was reset for the new approach
        with TestSessionLocal() as db:
            p3_db = db.scalar(select(QueueTicket).where(QueueTicket.id == t_long[3]["id"]))
            self.assertIsNone(p3_db.approaching_notified_at)

        # Advance queue: P0 completes (P5 notified), P1 completes -> P3 now sits at 3 ahead!
        mock_send.reset_mock()
        self.client.post(f"/api/queues/{q_long}/call-next", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_long}/tickets/{t_long[0]['id']}/serve", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_long}/tickets/{t_long[0]['id']}/complete", headers=self.rec_headers)
        # Check-in P3 cleanly before P1 completes
        self.client.patch(f"/api/queues/{q_long}/tickets/{t_long[3]['id']}/check-in", headers=self.rec_headers)
        self.client.post(f"/api/queues/{q_long}/call-next", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_long}/tickets/{t_long[1]['id']}/serve", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q_long}/tickets/{t_long[1]['id']}/complete", headers=self.rec_headers)

        second_approach_ids = [c["data"]["ticket_id"] for c in self._approaching_calls(mock_send)]
        self.assertIn(str(t_long[3]["id"]), second_approach_ids)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_4_skip_and_restore_resets_only_when_long_queue(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m3")
        qid = self._open_queue(self.doc1_id)

        # 5 patients initially -> P3 notified at 3 ahead
        tickets = [self._join_and_optionally_check_in(qid, i) for i in range(6)]
        # Skip P3 -> P4 moves to 3 ahead and gets notified
        mock_send.reset_mock()
        self.assertEqual(self.client.patch(f"/api/queues/{qid}/tickets/{tickets[3]['id']}/skip", headers=self.rec_headers).status_code, 200)
        self.assertEqual([c["data"]["ticket_id"] for c in self._approaching_calls(mock_send)], [str(tickets[4]["id"])])

        # Restore P3 while 5 active remain ahead -> resets eligibility, NO immediate alert
        mock_send.reset_mock()
        self.assertEqual(self.client.patch(f"/api/queues/{qid}/tickets/{tickets[3]['id']}/restore", headers=self.rec_headers).status_code, 200)
        self.assertEqual(self._approaching_calls(mock_send), [])

        # Complete P0 and P1 -> P3 moves into 3 ahead (behind P2, P4, P5) -> SECOND approaching alert sent!
        self.client.post(f"/api/queues/{qid}/call-next", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{qid}/tickets/{tickets[0]['id']}/serve", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{qid}/tickets/{tickets[0]['id']}/complete", headers=self.rec_headers)
        self.client.post(f"/api/queues/{qid}/call-next", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{qid}/tickets/{tickets[1]['id']}/serve", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{qid}/tickets/{tickets[1]['id']}/complete", headers=self.rec_headers)

        second_ids = [c["data"]["ticket_id"] for c in self._approaching_calls(mock_send)]
        self.assertIn(str(tickets[3]["id"]), second_ids)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_5_call_next_409_reposition_evaluates_approaching_after_commit(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m4")
        qid = self._open_queue(self.doc1_id)

        # Create 5 unchecked-in patients: P0..P4.
        # P3 initially got notified as 4th; P4 has 4 ahead (unnotified).
        t0 = self._join_and_optionally_check_in(qid, 0, check_in=False)
        t1 = self._join_and_optionally_check_in(qid, 1, check_in=False)
        t2 = self._join_and_optionally_check_in(qid, 2, check_in=False)
        t3 = self._join_and_optionally_check_in(qid, 3, check_in=False)
        t4 = self._join_and_optionally_check_in(qid, 4, check_in=False)

        # Call-next finds zero checked-in patients -> pushes all 5 to the back and returns 409.
        # Even simpler case: P0, P1 unchecked-in, P2 checked-in? Wait if P2 checked-in, call-next returns 200!
        # Let's test exact 409 case: verify when call-next returns 409, it calls check_and_trigger_approaching cleanly
        # AND test P4 crossing if a checked-in patient hadn't arrived yet:
        # Join P5 (unchecked-in) BEFORE call-next so active order is [t0..t5]. Wait: all unchecked in pushes everyone
        # cyclically in same order unless checked in — wait: if t0..t4 are moved, t0 moves past t5 -> t5 moves up to 3 ahead!
        # Let's verify: t0..t4 (5 tickets) + t5? If all 6 unchecked in, t0..t5 ALL move past each other keeping relative order.
        # How does an unchecked-in patient trigger approaching on 409? When t4 had approaching_notified_at=None? No, if t4 was at idx 4, moving all 5 preserves order!
        # Wait: what if t4 had NOT joined before? No, what if t0..t3 already received or missed, AND t4 was skipped/restored earlier?
        # Even clearer: call-next 409 resets eligibility for t3 (since 4 ahead > 3!) AND after commit triggers check_and_trigger_approaching!
        # Verify 409 invokes check_and_trigger_approaching AFTER commit so repositioned state is persisted
        mock_send.reset_mock()
        observed_missed_turns_at_check: list[list[int]] = []

        def _spy_approaching(queue_id, jumped_candidate_ids=None, exclude_ticket_ids=None):
            with TestSessionLocal() as spy_db:
                mt = [
                    tk.missed_turns
                    for tk in spy_db.scalars(
                        select(QueueTicket).where(QueueTicket.queue_id == queue_id)
                    ).all()
                ]
                observed_missed_turns_at_check.append(mt)
            return check_and_trigger_approaching(
                queue_id,
                jumped_candidate_ids=jumped_candidate_ids,
                exclude_ticket_ids=exclude_ticket_ids,
            )

        with patch("app.api.queues.check_and_trigger_approaching", side_effect=_spy_approaching):
            res = self.client.post(f"/api/queues/{qid}/call-next", headers=self.rec_headers)
        self.assertEqual(res.status_code, 409)
        self.assertEqual(res.json()["detail"], "No checked-in patient available")
        self.assertEqual(observed_missed_turns_at_check, [[1, 1, 1, 1, 1]])

        # Verify reposition persisted (missed_turns == 1) and no misleading immediate alert for repositioned tickets
        with TestSessionLocal() as db:
            tickets_db = db.scalars(
                select(QueueTicket).where(QueueTicket.queue_id == qid).order_by(QueueTicket.queue_position.asc())
            ).all()
            self.assertTrue(all(tk.missed_turns == 1 for tk in tickets_db))
            self.assertEqual([c["data"]["ticket_id"] for c in self._approaching_calls(mock_send)], [])
        self.assertIsNotNone(t0)
        self.assertIsNotNone(t1)
        self.assertIsNotNone(t2)
        self.assertIsNotNone(t3)
        self.assertIsNotNone(t4)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_6_jump_across_3_ahead_threshold_and_cancelled_completed_never_notified(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m5")
        qid = self._open_queue(self.doc1_id)

        # Short queue join (< 3 ahead) must NOT send approaching alert
        t0 = self._join_and_optionally_check_in(qid, 0)
        t1 = self._join_and_optionally_check_in(qid, 1)
        t2 = self._join_and_optionally_check_in(qid, 2)
        self.assertEqual(self._approaching_calls(mock_send), [])

        # P3 joins 4th (3 ahead -> notified), P4 joins 5th (4 ahead -> NOT notified)
        t3 = self._join_and_optionally_check_in(qid, 3)
        t4 = self._join_and_optionally_check_in(qid, 4)

        # Cancel P1 and P2 in sequence? Wait: to jump P4 straight from 4 ahead to 2 ahead in ONE step:
        # Put queue in AUTOMATIC mode with t1 & t2 unchecked-in, t0 SERVING, t3 & t4 checked-in.
        # Actually simpler: cancel t1 -> P4 becomes 3 ahead? No, to jump 4 -> 2 in ONE step:
        # Open doc2 with t0(SERVING), t1(unchecked), t2(unchecked), t3(checked-in), t4(checked-in), t5(checked-in)!
        q2 = self._open_queue(self.doc2_id)
        d_t0 = self._join_and_optionally_check_in(q2, 0, check_in=True)
        d_t1 = self._join_and_optionally_check_in(q2, 1, check_in=False)
        d_t2 = self._join_and_optionally_check_in(q2, 2, check_in=False)
        d_t3 = self._join_and_optionally_check_in(q2, 3, check_in=True)   # notified at 3 ahead
        d_t4 = self._join_and_optionally_check_in(q2, 4, check_in=True)   # 4 ahead -> NOT notified yet
        d_t5 = self._join_and_optionally_check_in(q2, 5, check_in=True)   # 5 ahead -> NOT notified yet

        self.client.patch(f"/api/queues/{q2}/smart-call-mode", json={"mode": "AUTOMATIC"}, headers=self.rec_headers)
        self.client.post(f"/api/queues/{q2}/call-next", headers=self.rec_headers)  # calls d_t0
        self.client.patch(f"/api/queues/{q2}/tickets/{d_t0['id']}/serve", headers=self.rec_headers)

        # Complete d_t0 in AUTOMATIC mode -> advance_smart_call moves d_t1 AND d_t2 behind d_t5 and calls d_t3!
        # Suddenly active order is: [d_t3(CALLED), d_t4(WAIT), d_t5(WAIT), d_t1(WAIT), d_t2(WAIT)]!
        # d_t4 jumped from 4 ahead straight to 1 ahead (crossing 3!), AND d_t5 jumped from 5 ahead straight to 2 ahead (crossing 3!)!
        mock_send.reset_mock()
        comp = self.client.patch(f"/api/queues/{q2}/tickets/{d_t0['id']}/complete", headers=self.rec_headers)
        self.assertEqual(comp.status_code, 200)
        self.assertEqual(comp.json()["auto_called_ticket"]["id"], d_t3["id"])

        jumped_calls = self._approaching_calls(mock_send)
        notified_ids = {c["data"]["ticket_id"] for c in jumped_calls}
        self.assertIn(str(d_t4["id"]), notified_ids)
        self.assertIn(str(d_t5["id"]), notified_ids)

        # Cancelled / skipped / completed tickets (t0, t1, t2 or cancelled doc2) must NEVER get notified
        mock_send.reset_mock()
        self.client.patch(f"/api/queues/{qid}/tickets/{t4['id']}/cancel", headers=self.rec_headers)
        check_and_trigger_approaching(qid)
        for c in self._approaching_calls(mock_send):
            self.assertNotEqual(c["data"]["ticket_id"], str(t4["id"]))
        self.assertIsNotNone(t0)
        self.assertIsNotNone(t1)
        self.assertIsNotNone(t2)
        self.assertIsNotNone(t3)

    @patch("app.services.queue_notifications.send_push_notification")
    def test_7_and_8_multi_queue_isolation_and_concurrent_checks(self, mock_send) -> None:
        mock_send.return_value = PushNotificationResult(success=True, message_id="m6")
        q1 = self._open_queue(self.doc1_id)
        q2 = self._open_queue(self.doc2_id)

        # Fill q1 with 5 patients and q2 with 2 patients
        q1_tickets = [self._join_and_optionally_check_in(q1, i) for i in range(5)]
        self._join_and_optionally_check_in(q2, 6)
        self._join_and_optionally_check_in(q2, 7)

        # Manually test concurrent approaching checks when q1[4] reaches 3 ahead
        mock_send.reset_mock()
        self.client.post(f"/api/queues/{q1}/call-next", headers=self.rec_headers)
        self.client.patch(f"/api/queues/{q1}/tickets/{q1_tickets[0]['id']}/serve", headers=self.rec_headers)
        with patch("app.api.queues.schedule_approaching_check"):
            self.client.patch(f"/api/queues/{q1}/tickets/{q1_tickets[0]['id']}/complete", headers=self.rec_headers)

        mock_send.reset_mock()
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(check_and_trigger_approaching, q1) for _ in range(4)]
            for f in futures:
                f.result()

        calls = self._approaching_calls(mock_send)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["data"]["ticket_id"], str(q1_tickets[4]["id"]))
        self.assertEqual(calls[0]["data"]["queue_id"], str(q1))

    def test_9_firebase_failure_logs_safely_without_exposing_tokens_or_secrets(self) -> None:
        with patch(
            "app.services.notifications.get_firebase_credentials_path",
            return_value=None,
        ), patch(
            "app.services.notifications.firebase_admin.get_app",
            side_effect=ValueError("not initialized"),
        ):
            qid = self._open_queue(self.doc1_id)
            with self.assertLogs("app.services.queue_notifications", level="WARNING") as cm:
                for idx in range(4):
                    self._join_and_optionally_check_in(qid, idx)

            joined_logs = "\n".join(cm.output)
            self.assertIn("FIREBASE_NOT_INITIALIZED", joined_logs)
            self.assertNotIn("secret_device_token", joined_logs)
            self.assertNotIn("abcdef123456", joined_logs)
