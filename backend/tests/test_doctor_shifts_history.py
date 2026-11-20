import csv
import io
import os
import subprocess
import sys
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, delete, inspect, select, text

from app.core.config import settings
from app.core.security import create_access_token, create_check_in_qr_token
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue, ShiftStatus, SmartCallMode
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.smart_call_timer import process_expired_called_tickets
from tests.test_db import TestSessionLocal as SessionLocal


class DoctorShiftsAndHistoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls.db = SessionLocal()
        for tbl in ("clinics", "specializations", "doctors", "users", "queues", "queue_tickets"):
            cls.db.execute(
                text(
                    f"SELECT setval(pg_get_serial_sequence('{tbl}', 'id'), COALESCE((SELECT MAX(id) FROM {tbl}), 1), true)"
                )
            )
        cls.db.commit()

        cls.clinic1 = cls.db.scalar(select(Clinic).where(Clinic.name == "Shift Clinic 1"))
        if not cls.clinic1:
            cls.clinic1 = Clinic(
                name="Shift Clinic 1",
                smart_call_timeout_seconds=60,
                timezone="Asia/Tashkent",
            )
            cls.db.add(cls.clinic1)
            cls.db.commit()
            cls.db.refresh(cls.clinic1)

        cls.clinic2 = cls.db.scalar(select(Clinic).where(Clinic.name == "Shift Clinic 2"))
        if not cls.clinic2:
            cls.clinic2 = Clinic(
                name="Shift Clinic 2",
                smart_call_timeout_seconds=60,
                timezone="Asia/Tashkent",
            )
            cls.db.add(cls.clinic2)
            cls.db.commit()
            cls.db.refresh(cls.clinic2)

        cls.spec1 = cls._get_or_create_spec(cls.clinic1.id, "Shift Terapiya", "Терапия", "Therapy")
        cls.spec2 = cls._get_or_create_spec(cls.clinic1.id, "Shift Jarrohlik", "Хирургия", "Surgery")
        cls.spec_c2 = cls._get_or_create_spec(cls.clinic2.id, "Clinic2 Spec", "Спец 2", "Spec 2")

        cls.doc1 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec1.id, "Dr. Farrux Nightshift", "101")
        cls.doc2 = cls._get_or_create_doctor(cls.clinic1.id, cls.spec2.id, "Dr. Madina Dayshift", "102")
        cls.doc_c2 = cls._get_or_create_doctor(cls.clinic2.id, cls.spec_c2.id, "Dr. Clinic Two", "201")

        cls.admin1 = cls._get_or_create_user(cls.clinic1.id, "Shift Admin 1", "+998907771001", UserRole.ADMIN)
        cls.admin2 = cls._get_or_create_user(cls.clinic2.id, "Shift Admin 2", "+998907771002", UserRole.ADMIN)
        cls.rec1 = cls._get_or_create_user(cls.clinic1.id, "Shift Rec 1", "+998907771003", UserRole.RECEPTIONIST)
        cls.rec2 = cls._get_or_create_user(cls.clinic2.id, "Shift Rec 2", "+998907771004", UserRole.RECEPTIONIST)
        cls.p1 = cls._get_or_create_user(None, "Shift Patient 1", "+998907771005", UserRole.PATIENT)
        cls.p2 = cls._get_or_create_user(None, "Shift Patient 2", "+998907771006", UserRole.PATIENT)
        cls.p3 = cls._get_or_create_user(None, "Shift Patient 3", "+998907771007", UserRole.PATIENT)

        cls.admin1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin1.id)}"}
        cls.admin2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.admin2.id)}"}
        cls.rec1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec1.id)}"}
        cls.rec2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.rec2.id)}"}
        cls.p1_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p1.id)}"}
        cls.p2_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p2.id)}"}
        cls.p3_headers = {"Authorization": f"Bearer {create_access_token(subject=cls.p3.id)}"}

    @classmethod
    def _get_or_create_spec(cls, clinic_id: int, uz: str, ru: str, en: str) -> Specialization:
        s = cls.db.scalar(
            select(Specialization).where(Specialization.clinic_id == clinic_id, Specialization.name_uz == uz)
        )
        if not s:
            s = Specialization(clinic_id=clinic_id, name_uz=uz, name_ru=ru, name_en=en, is_active=True)
            cls.db.add(s)
            cls.db.commit()
            cls.db.refresh(s)
        return s

    @classmethod
    def _get_or_create_doctor(cls, clinic_id: int, spec_id: int, full_name: str, room: str) -> Doctor:
        d = cls.db.scalar(select(Doctor).where(Doctor.clinic_id == clinic_id, Doctor.full_name == full_name))
        if not d:
            d = Doctor(clinic_id=clinic_id, specialization_id=spec_id, full_name=full_name, room_number=room, is_active=True)
            cls.db.add(d)
            cls.db.commit()
            cls.db.refresh(d)
        return d

    @classmethod
    def _get_or_create_user(cls, clinic_id: int | None, full_name: str, phone: str, role: UserRole) -> User:
        u = cls.db.scalar(select(User).where(User.phone == phone))
        if not u:
            u = User(clinic_id=clinic_id, full_name=full_name, phone=phone, hashed_password="x", role=role, is_active=True)
            cls.db.add(u)
            cls.db.commit()
            cls.db.refresh(u)
        return u

    @classmethod
    def tearDownClass(cls):
        cls._cleanup_queues()
        cls.db.close()

    @classmethod
    def _cleanup_queues(cls):
        with SessionLocal() as db:
            doc_ids = [cls.doc1.id, cls.doc2.id, cls.doc_c2.id]
            q_ids = list(db.scalars(select(Queue.id).where(Queue.doctor_id.in_(doc_ids))).all())
            if q_ids:
                db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(q_ids)))
                db.execute(delete(Queue).where(Queue.id.in_(q_ids)))
            db.commit()

    def setUp(self):
        self._cleanup_queues()

    def test_01_shift_lifecycle_start_pause_resume_stop_reopen_finish_and_second_shift_same_day(self):
        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_called_notification"
        ), patch("app.api.queues.schedule_completed_notification"), patch(
            "app.api.queues.schedule_skipped_notification"
        ), patch("app.api.queues.schedule_paused_notification"), patch(
            "app.api.queues.schedule_resumed_notification"
        ), patch("app.api.queues.schedule_approaching_check"), patch(
            "app.api.queues.notify_display_update"
        ):
            # 1. Start Shift
            r_start = self.client.post("/api/queues/open", json={"doctor_id": self.doc1.id}, headers=self.rec1_headers)
            self.assertEqual(r_start.status_code, 201)
            q1 = r_start.json()
            self.assertEqual(q1["shift_status"], "OPEN")
            self.assertEqual(q1["smart_call_mode"], "MANUAL")
            self.assertTrue(q1["is_active"])
            self.assertFalse(q1["is_paused"])
            self.assertIsNotNone(q1["started_at"])
            self.assertIsNone(q1["ended_at"])
            q1_id = q1["id"]

            # Patient joins normally while OPEN
            j1 = self.client.post(f"/api/queues/{q1_id}/join", headers=self.p1_headers)
            self.assertEqual(j1.status_code, 201)
            t1_id = j1.json()["id"]

            # 2. Pause -> blocks joins, preserves OPEN shift_status; Resume restores OPEN
            p_res = self.client.patch(f"/api/queues/{q1_id}/pause", headers=self.rec1_headers)
            self.assertEqual(p_res.status_code, 200)
            self.assertTrue(p_res.json()["is_paused"])
            self.assertEqual(p_res.json()["shift_status"], "OPEN")
            self.assertEqual(self.client.post(f"/api/queues/{q1_id}/join", headers=self.p2_headers).status_code, 409)

            res_res = self.client.patch(f"/api/queues/{q1_id}/resume", headers=self.rec1_headers)
            self.assertEqual(res_res.status_code, 200)
            self.assertFalse(res_res.json()["is_paused"])
            self.assertEqual(res_res.json()["shift_status"], "OPEN")

            # p2 joins -> both p1 and p2 are WAITING
            j2 = self.client.post(f"/api/queues/{q1_id}/join", headers=self.p2_headers)
            self.assertEqual(j2.status_code, 201)
            t2_id = j2.json()["id"]

            # 3. Stop New Tickets (CLOSING)
            stop_res = self.client.patch(f"/api/queues/{q1_id}/stop-admissions", headers=self.rec1_headers)
            self.assertEqual(stop_res.status_code, 200)
            self.assertEqual(stop_res.json()["shift_status"], "CLOSING")
            self.assertTrue(stop_res.json()["is_active"])

            # Catalog preview shows CLOSING cleanly for Flutter
            cat = self.client.get(f"/api/catalog/doctors/{self.doc1.id}/queue", headers=self.p3_headers)
            self.assertEqual(cat.status_code, 200)
            self.assertEqual(cat.json()["shift_status"], "CLOSING")

            # New online joins and walk-ins are rejected with clear CLOSING message
            j3 = self.client.post(f"/api/queues/{q1_id}/join", headers=self.p3_headers)
            self.assertEqual(j3.status_code, 409)
            self.assertIn("closed for new patients", j3.json()["detail"].lower())

            w_rej = self.client.post(
                f"/api/queues/{q1_id}/walk-in",
                json={"patient_name": "Late WalkIn"},
                headers=self.rec1_headers,
            )
            self.assertEqual(w_rej.status_code, 409)

            # Reopen admissions -> OPEN without creating a new queue
            reopen_res = self.client.patch(f"/api/queues/{q1_id}/reopen-admissions", headers=self.rec1_headers)
            self.assertEqual(reopen_res.status_code, 200)
            self.assertEqual(reopen_res.json()["id"], q1_id)
            self.assertEqual(reopen_res.json()["shift_status"], "OPEN")

            # Re-stop admissions + test QR check-in and existing patient service during CLOSING
            self.client.patch(f"/api/queues/{q1_id}/stop-admissions", headers=self.rec1_headers)
            qr_tok = create_check_in_qr_token(clinic_id=self.clinic1.id)
            chk1 = self.client.post(
                "/api/queues/check-in/qr",
                json={"token": qr_tok, "ticket_id": t1_id},
                headers=self.p1_headers,
            )
            self.assertEqual(chk1.status_code, 200)

            # Cannot finish shift while WAITING/CALLED/SERVING patients remain
            fin_block = self.client.patch(f"/api/queues/{q1_id}/finish", headers=self.rec1_headers)
            self.assertEqual(fin_block.status_code, 409)

            # Enable AUTOMATIC Smart Call during CLOSING, manual check-in p2, call t1 -> serve -> complete -> auto-calls t2
            self.client.patch(
                f"/api/queues/{q1_id}/smart-call-mode",
                json={"mode": "AUTOMATIC"},
                headers=self.rec1_headers,
            )
            self.client.patch(f"/api/queues/{q1_id}/tickets/{t2_id}/check-in", headers=self.rec1_headers)
            self.client.post(f"/api/queues/{q1_id}/call-next", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q1_id}/tickets/{t1_id}/serve", headers=self.rec1_headers)
            done1 = self.client.patch(f"/api/queues/{q1_id}/tickets/{t1_id}/complete", headers=self.rec1_headers)
            self.assertEqual(done1.json()["auto_called_ticket"]["id"], t2_id)

            # Public Display still shows CALLED ticket during CLOSING
            pub = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display").json()
            self.assertEqual(len(pub["queues"]), 1)
            self.assertEqual(pub["queues"][0]["shift_status"], "CLOSING")
            self.assertEqual(pub["queues"][0]["called_ticket"]["ticket_number"], 2)

            # Complete t2 (cannot finish while SERVING)
            self.client.patch(f"/api/queues/{q1_id}/tickets/{t2_id}/serve", headers=self.rec1_headers)
            self.assertEqual(self.client.patch(f"/api/queues/{q1_id}/finish", headers=self.rec1_headers).status_code, 409)
            self.client.patch(f"/api/queues/{q1_id}/tickets/{t2_id}/complete", headers=self.rec1_headers)

            # Overlapping second shift blocked BEFORE finish
            self.assertEqual(
                self.client.post("/api/queues/open", json={"doctor_id": self.doc1.id}, headers=self.rec1_headers).status_code,
                409,
            )

            # 4. Finish Shift cleanly
            fin_ok = self.client.patch(f"/api/queues/{q1_id}/finish", headers=self.rec1_headers)
            self.assertEqual(fin_ok.status_code, 200)
            self.assertEqual(fin_ok.json()["shift_status"], "FINISHED")
            self.assertFalse(fin_ok.json()["is_active"])
            self.assertIsNotNone(fin_ok.json()["ended_at"])

            # Cannot join, call, pause, or reopen finished shift
            self.assertEqual(self.client.post(f"/api/queues/{q1_id}/join", headers=self.p3_headers).status_code, 409)
            self.assertEqual(self.client.post(f"/api/queues/{q1_id}/call-next", headers=self.rec1_headers).status_code, 409)
            self.assertEqual(self.client.patch(f"/api/queues/{q1_id}/reopen-admissions", headers=self.rec1_headers).status_code, 409)

            # Public Display & Catalog no longer expose FINISHED shift
            pub_after = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display").json()
            self.assertEqual(pub_after["queues"], [])
            self.assertEqual(
                self.client.get(f"/api/catalog/doctors/{self.doc1.id}/queue", headers=self.p3_headers).status_code,
                404,
            )

            # 5. Start a second shift on the SAME calendar date -> fresh ID, fresh ticket #1, historical tickets preserved
            r_start2 = self.client.post("/api/queues/open", json={"doctor_id": self.doc1.id}, headers=self.rec1_headers)
            self.assertEqual(r_start2.status_code, 201)
            q2 = r_start2.json()
            self.assertNotEqual(q2["id"], q1_id)
            self.assertEqual(q2["shift_status"], "OPEN")
            self.assertEqual(q2["smart_call_mode"], "MANUAL")

            j_shift2 = self.client.post(f"/api/queues/{q2['id']}/join", headers=self.p1_headers)
            self.assertEqual(j_shift2.status_code, 201)
            self.assertEqual(j_shift2.json()["ticket_number"], 1)

            with SessionLocal() as db:
                old_tks = db.scalars(select(QueueTicket).where(QueueTicket.queue_id == q1_id)).all()
                self.assertEqual(len(old_tks), 2)

    def test_02_overnight_shift_stays_active_across_midnight_and_skipped_restore_policy(self):
        # Simulate shift opened at 22:00 yesterday (Tashkent +05:00 -> 17:00Z)
        yesterday_date = date.today() - timedelta(days=1)
        yesterday_22_uz = datetime(yesterday_date.year, yesterday_date.month, yesterday_date.day, 17, 0, 0, tzinfo=timezone.utc)
        with SessionLocal() as db:
            q = Queue(
                doctor_id=self.doc1.id,
                queue_date=yesterday_date,
                is_active=True,
                is_paused=False,
                smart_call_mode=SmartCallMode.MANUAL,
                shift_status=ShiftStatus.OPEN,
                started_at=yesterday_22_uz,
            )
            db.add(q)
            db.commit()
            db.refresh(q)
            qid = q.id

        # Across midnight into today: still appears in Reception active list, Public Display, Catalog, Join & QR Check-in
        rec_list = self.client.get("/api/queues/reception/today", headers=self.rec1_headers).json()
        self.assertTrue(any(x["queue_id"] == qid for x in rec_list))
        cat = self.client.get(f"/api/catalog/doctors/{self.doc1.id}/queue", headers=self.p1_headers)
        self.assertEqual(cat.status_code, 200)
        self.assertEqual(cat.json()["id"], qid)
        pub = self.client.get(f"/api/public/clinics/{self.clinic1.id}/display").json()
        self.assertEqual(len(pub["queues"]), 1)

        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_skipped_notification"
        ), patch("app.api.queues.schedule_approaching_check"), patch(
            "app.api.queues.notify_display_update"
        ):
            tk = self.client.post(f"/api/queues/{qid}/join", headers=self.p1_headers).json()
            qr_tok = create_check_in_qr_token(clinic_id=self.clinic1.id)
            self.assertEqual(
                self.client.post("/api/queues/check-in/qr", json={"token": qr_tok, "ticket_id": tk["id"]}, headers=self.p1_headers).status_code,
                200,
            )
            # Skip ticket -> Finish shift preserves SKIPPED in history and removes from active /my-tickets & blocks Restore
            self.client.patch(f"/api/queues/{qid}/tickets/{tk['id']}/skip", headers=self.rec1_headers)
            fin = self.client.patch(f"/api/queues/{qid}/finish", headers=self.rec1_headers)
            self.assertEqual(fin.status_code, 200)

            my_tks = self.client.get("/api/queues/my-tickets?include_skipped=true", headers=self.p1_headers).json()
            self.assertEqual(my_tks, [])
            self.assertEqual(
                self.client.patch(f"/api/queues/{qid}/tickets/{tk['id']}/restore", headers=self.rec1_headers).status_code,
                409,
            )

    def test_03_concurrency_start_shift_and_join_vs_stop_admissions(self):
        # Wrap patches outside worker threads so nested unittest.mock.patch never leaks a MagicMock!
        with patch("app.api.queues.schedule_joined_notification"), patch(
            "app.api.queues.schedule_approaching_check"
        ), patch("app.api.queues.notify_display_update"):
            # Two concurrent Start Shift requests -> strictly 1 created (201), 1 rejected (409)
            codes: list[int] = []
            barrier = threading.Barrier(2)

            def start_racer():
                barrier.wait()
                r = self.client.post("/api/queues/open", json={"doctor_id": self.doc1.id}, headers=self.rec1_headers)
                codes.append(r.status_code)

            t_a = threading.Thread(target=start_racer)
            t_b = threading.Thread(target=start_racer)
            t_a.start()
            t_b.start()
            t_a.join()
            t_b.join()
            self.assertEqual(sorted(codes), [201, 409])

            # Concurrent Join vs Stop Admissions -> never admits ticket after CLOSING without error
            q_id = self.client.get("/api/queues/reception/today", headers=self.rec1_headers).json()[0]["queue_id"]
            race_results: list[tuple[str, int]] = []
            b2 = threading.Barrier(2)

            def join_racer():
                b2.wait()
                r = self.client.post(f"/api/queues/{q_id}/join", headers=self.p1_headers)
                race_results.append(("join", r.status_code))

            def stop_racer():
                b2.wait()
                r = self.client.patch(f"/api/queues/{q_id}/stop-admissions", headers=self.rec1_headers)
                race_results.append(("stop", r.status_code))

            tj = threading.Thread(target=join_racer)
            ts = threading.Thread(target=stop_racer)
            tj.start()
            ts.start()
            tj.join()
            ts.join()
            join_code = dict(race_results)["join"]
            self.assertIn(join_code, (201, 409))

    def test_04_calendar_completion_date_vs_shift_start_date_and_legacy_timestamps(self):
        # Shift started Nov 20 22:00 Asia/Tashkent (17:00 UTC)
        # Ticket 1 completed Nov 21 01:00 Asia/Tashkent (Nov 20 20:00 UTC) -> counts under Nov 21 in Tashkent, but Nov 20 shift!
        # Ticket 2 completed legacy without completed_at -> counts in all_time + shift history, NOT fabricated into today
        d_nov20 = date(2026, 11, 20)
        d_nov21 = date(2026, 11, 21)
        shift_start_utc = datetime(2026, 11, 20, 17, 0, 0, tzinfo=timezone.utc)
        shift_end_utc = datetime(2026, 11, 21, 1, 0, 0, tzinfo=timezone.utc)  # 06:00 Tashkent
        t1_comp_utc = datetime(2026, 11, 20, 20, 0, 0, tzinfo=timezone.utc)  # Nov 21 01:00 Tashkent!

        with SessionLocal() as db:
            q_overnight = Queue(
                doctor_id=self.doc1.id,
                queue_date=d_nov20,
                is_active=False,
                is_paused=False,
                shift_status=ShiftStatus.FINISHED,
                started_at=shift_start_utc,
                ended_at=shift_end_utc,
            )
            db.add(q_overnight)
            db.flush()
            db.add_all([
                QueueTicket(
                    queue_id=q_overnight.id,
                    ticket_number=1,
                    queue_position=1,
                    patient_name="Overnight Completed",
                    source=TicketSource.WALK_IN,
                    status=TicketStatus.COMPLETED,
                    completed_at=t1_comp_utc,
                ),
                QueueTicket(
                    queue_id=q_overnight.id,
                    ticket_number=2,
                    queue_position=2,
                    patient_name="Not Completed Skipped",
                    source=TicketSource.WALK_IN,
                    status=TicketStatus.SKIPPED,
                ),
            ])
            # Separate doctor in same clinic has 1 legacy COMPLETED ticket without completed_at
            q_legacy = Queue(
                doctor_id=self.doc2.id,
                queue_date=date(2026, 10, 15),
                is_active=False,
                is_paused=False,
                shift_status=ShiftStatus.FINISHED,
                started_at=None,
                ended_at=None,
            )
            db.add(q_legacy)
            db.flush()
            db.add(
                QueueTicket(
                    queue_id=q_legacy.id,
                    ticket_number=1,
                    queue_position=1,
                    patient_name="Legacy Completed",
                    source=TicketSource.WALK_IN,
                    status=TicketStatus.COMPLETED,
                    completed_at=None,
                )
            )
            # Clinic 2 doctor ticket must NEVER leak into Clinic 1 reports
            q_c2 = Queue(
                doctor_id=self.doc_c2.id,
                queue_date=d_nov21,
                is_active=False,
                is_paused=False,
                shift_status=ShiftStatus.FINISHED,
                started_at=shift_start_utc,
                ended_at=shift_end_utc,
            )
            db.add(q_c2)
            db.flush()
            db.add(
                QueueTicket(
                    queue_id=q_c2.id,
                    ticket_number=1,
                    queue_position=1,
                    patient_name="Other Clinic Secret",
                    source=TicketSource.WALK_IN,
                    status=TicketStatus.COMPLETED,
                    completed_at=t1_comp_utc,
                )
            )
            db.commit()

        # Check Nov 20 custom calendar filter -> 0 calendar completions (t1 completed at 01:00 Nov 21 local time!)
        r_nov20 = self.client.get(
            f"/api/admin/doctors/performance?doctor_id={self.doc1.id}&period=custom&date_from=2026-11-20&date_to=2026-11-20",
            headers=self.admin1_headers,
        )
        self.assertEqual(r_nov20.status_code, 200)
        self.assertEqual(r_nov20.json()["summary"]["completed_in_selected_range"], 0)
        # Shift started Nov 20 appears in Nov 20 shift history with accurate 8h duration (480 min) & 1 completed
        self.assertEqual(len(r_nov20.json()["shifts"]), 1)
        self.assertEqual(r_nov20.json()["shifts"][0]["duration_seconds"], 8 * 3600)
        self.assertEqual(r_nov20.json()["shifts"][0]["completed_count"], 1)

        # Check Nov 21 custom calendar filter -> 1 calendar completion for doc1!
        r_nov21 = self.client.get(
            f"/api/admin/doctors/performance?doctor_id={self.doc1.id}&period=custom&date_from=2026-11-21&date_to=2026-11-21",
            headers=self.admin1_headers,
        )
        self.assertEqual(r_nov21.status_code, 200)
        self.assertEqual(r_nov21.json()["summary"]["completed_in_selected_range"], 1)

        # Check All-Time clinic report -> doc1 (1) + doc2 (1 legacy unattributed) = 2; other clinic isolated
        r_all = self.client.get("/api/admin/doctors/performance?period=all", headers=self.admin1_headers)
        self.assertEqual(r_all.status_code, 200)
        s = r_all.json()["summary"]
        self.assertEqual(s["completed_all_time"], 2)
        self.assertEqual(s["legacy_unattributed_completed_count"], 1)

    def test_05_csv_export_permissions_formula_injection_and_content(self):
        # Create a doctor with formula-injection attempt in name
        formula_doc = self._get_or_create_doctor(self.clinic1.id, self.spec1.id, "=CMD|'/C calc'!A0", "999")
        try:
            q = self.client.post("/api/queues/open", json={"doctor_id": formula_doc.id}, headers=self.rec1_headers).json()
            w = self.client.post(
                f"/api/queues/{q['id']}/walk-in",
                json={"patient_name": "Secret Patient John", "patient_phone": "+998901234567"},
                headers=self.rec1_headers,
            ).json()
            self.client.patch(f"/api/queues/{q['id']}/tickets/{w['id']}/call", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q['id']}/tickets/{w['id']}/serve", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q['id']}/tickets/{w['id']}/complete", headers=self.rec1_headers)
            self.client.patch(f"/api/queues/{q['id']}/finish", headers=self.rec1_headers)

            # Non-admin (Reception / Patient) forbidden
            self.assertEqual(self.client.get("/api/admin/doctors/performance", headers=self.rec1_headers).status_code, 403)
            self.assertEqual(self.client.get("/api/admin/doctors/performance/export", headers=self.p1_headers).status_code, 403)

            csv_res = self.client.get(
                f"/api/admin/doctors/performance/export?doctor_id={formula_doc.id}&period=all",
                headers=self.admin1_headers,
            )
            self.assertEqual(csv_res.status_code, 200)
            self.assertIn("text/csv", csv_res.headers["content-type"])
            text_body = csv_res.content.decode("utf-8-sig")
            # Formula injection sanitized, zero patient PII leaked
            self.assertIn("'=CMD|'/C calc'!A0", text_body)
            self.assertNotIn("Secret Patient John", text_body)
            self.assertNotIn("+998901234567", text_body)

            parsed_rows = list(csv.reader(io.StringIO(text_body)))
            self.assertTrue(any("DOCTOR PERFORMANCE SUMMARY" in row for row in parsed_rows))
            self.assertTrue(any("SHIFT SESSION HISTORY" in row for row in parsed_rows))
        finally:
            with SessionLocal() as db:
                f_qids = list(db.scalars(select(Queue.id).where(Queue.doctor_id == formula_doc.id)).all())
                if f_qids:
                    db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(f_qids)))
                    db.execute(delete(Queue).where(Queue.id.in_(f_qids)))
                db.execute(delete(Doctor).where(Doctor.id == formula_doc.id))
                db.commit()

    def test_06_period_boundaries_today_week_month_year(self):
        from zoneinfo import ZoneInfo

        uz_tz = ZoneInfo("Asia/Tashkent")
        now_uz = datetime.now(uz_tz)
        today_uz = now_uz.date()
        today_mid_utc = datetime(today_uz.year, today_uz.month, today_uz.day, 10, 0, tzinfo=uz_tz).astimezone(timezone.utc)

        # Create isolated doctor for deterministic calendar-period counts
        period_doc = self._get_or_create_doctor(self.clinic1.id, self.spec1.id, "Dr. Calendar Periods", "198")
        try:
            timestamps_utc: list[tuple[str, datetime]] = [("today", today_mid_utc)]
            if today_uz.weekday() > 0:
                d_week = today_uz - timedelta(days=1)
                timestamps_utc.append(
                    ("week", datetime(d_week.year, d_week.month, d_week.day, 12, 0, tzinfo=uz_tz).astimezone(timezone.utc))
                )
            week_start = today_uz - timedelta(days=today_uz.weekday())
            month_start = today_uz.replace(day=1)
            if month_start < week_start:
                timestamps_utc.append(
                    ("month", datetime(month_start.year, month_start.month, month_start.day, 12, 0, tzinfo=uz_tz).astimezone(timezone.utc))
                )
            year_start = today_uz.replace(month=1, day=1)
            if year_start < month_start:
                timestamps_utc.append(
                    ("year", datetime(year_start.year, year_start.month, year_start.day, 12, 0, tzinfo=uz_tz).astimezone(timezone.utc))
                )
            last_year_utc = datetime(today_uz.year - 1, 6, 15, 12, 0, tzinfo=uz_tz).astimezone(timezone.utc)
            timestamps_utc.append(("last_year", last_year_utc))

            with SessionLocal() as db:
                for idx, (bucket, comp_utc) in enumerate(timestamps_utc, start=1):
                    q = Queue(
                        doctor_id=period_doc.id,
                        queue_date=comp_utc.astimezone(uz_tz).date(),
                        is_active=False,
                        is_paused=False,
                        shift_status=ShiftStatus.FINISHED,
                        started_at=comp_utc - timedelta(hours=1),
                        ended_at=comp_utc + timedelta(minutes=15),
                    )
                    db.add(q)
                    db.flush()
                    db.add(
                        QueueTicket(
                            queue_id=q.id,
                            ticket_number=1,
                            queue_position=1,
                            patient_name=f"Patient {bucket}",
                            source=TicketSource.WALK_IN,
                            status=TicketStatus.COMPLETED,
                            completed_at=comp_utc,
                        )
                    )
                db.commit()

            buckets = {b for b, _ in timestamps_utc}
            expected_counts = {
                "today": 1,
                "week": 1 + (1 if "week" in buckets else 0),
                "month": 1 + (1 if "week" in buckets else 0) + (1 if "month" in buckets else 0),
                "year": len(buckets - {"last_year"}),
                "all": len(buckets),
            }

            for period_name, exp_count in expected_counts.items():
                res = self.client.get(
                    f"/api/admin/doctors/performance?doctor_id={period_doc.id}&period={period_name}",
                    headers=self.admin1_headers,
                )
                self.assertEqual(res.status_code, 200)
                body = res.json()
                self.assertEqual(
                    body["summary"]["completed_in_selected_range"],
                    exp_count,
                    f"Period {period_name} mismatch",
                )
                self.assertEqual(body["summary"]["completed_today"], expected_counts["today"])
                self.assertEqual(body["summary"]["completed_this_week"], expected_counts["week"])
                self.assertEqual(body["summary"]["completed_this_month"], expected_counts["month"])
                self.assertEqual(body["summary"]["completed_this_year"], expected_counts["year"])
                self.assertEqual(body["summary"]["completed_all_time"], expected_counts["all"])
        finally:
            with SessionLocal() as db:
                p_qids = list(db.scalars(select(Queue.id).where(Queue.doctor_id == period_doc.id)).all())
                if p_qids:
                    db.execute(delete(QueueTicket).where(QueueTicket.queue_id.in_(p_qids)))
                    db.execute(delete(Queue).where(Queue.id.in_(p_qids)))
                db.execute(delete(Doctor).where(Doctor.id == period_doc.id))
                db.commit()

    def test_07_legacy_migration_backfill_and_roundtrip(self):
        from sqlalchemy.engine import make_url

        base_test_url = os.getenv("TEST_DATABASE_URL") or settings.TEST_DATABASE_URL
        parsed = make_url(base_test_url)
        mig_db_name = f"{parsed.database}_mig_verify"
        admin_url = parsed.set(database="postgres")
        mig_url = parsed.set(database=mig_db_name)

        admin_engine = create_engine(admin_url, isolation_level="AUTOCOMMIT", pool_pre_ping=True)
        backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        alembic_env = os.environ.copy()
        alembic_env["ALEMBIC_DATABASE_URL"] = mig_url.render_as_string(hide_password=False)

        with admin_engine.connect() as conn:
            conn.execute(text(f"DROP DATABASE IF EXISTS {mig_db_name} WITH (FORCE)"))
            conn.execute(text(f"CREATE DATABASE {mig_db_name}"))

        mig_engine = create_engine(mig_url, pool_pre_ping=True)
        try:
            # 1. Bring isolated DB to previous revision a2b3c4d5e6f7
            res_prev = subprocess.run(
                [sys.executable, "-m", "alembic", "upgrade", "a2b3c4d5e6f7"],
                cwd=backend_dir,
                env=alembic_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res_prev.returncode, 0, res_prev.stderr or res_prev.stdout)

            # 2. Seed legacy queues BEFORE b3c4d5e6f7a8:
            # - inactive queue (should become FINISHED)
            # - stale past queue with 0 active tickets (should become FINISHED, is_active=FALSE)
            # - overnight yesterday queue WITH active WAITING ticket (must stay OPEN, is_active=TRUE)
            with mig_engine.begin() as conn:
                c_id = conn.execute(
                    text("INSERT INTO clinics (name, smart_call_timeout_seconds) VALUES ('Mig Clinic', 60) RETURNING id")
                ).scalar_one()
                s_id = conn.execute(
                    text(
                        "INSERT INTO specializations (clinic_id, name_uz, name_ru, name_en, is_active) "
                        "VALUES (:c, 'U', 'R', 'E', TRUE) RETURNING id"
                    ),
                    {"c": c_id},
                ).scalar_one()
                d_stale = conn.execute(
                    text(
                        "INSERT INTO doctors (clinic_id, specialization_id, full_name, room_number, is_active) "
                        "VALUES (:c, :s, 'Dr. Stale Legacy', '1', TRUE) RETURNING id"
                    ),
                    {"c": c_id, "s": s_id},
                ).scalar_one()
                d_overnight = conn.execute(
                    text(
                        "INSERT INTO doctors (clinic_id, specialization_id, full_name, room_number, is_active) "
                        "VALUES (:c, :s, 'Dr. Overnight Legacy', '2', TRUE) RETURNING id"
                    ),
                    {"c": c_id, "s": s_id},
                ).scalar_one()

                q_inactive_id = conn.execute(
                    text(
                        "INSERT INTO queues (doctor_id, queue_date, is_active, is_paused, smart_call_mode) "
                        "VALUES (:d, CURRENT_DATE - 3, FALSE, TRUE, 'MANUAL') RETURNING id"
                    ),
                    {"d": d_stale},
                ).scalar_one()
                q_stale_past_id = conn.execute(
                    text(
                        "INSERT INTO queues (doctor_id, queue_date, is_active, is_paused, smart_call_mode) "
                        "VALUES (:d, CURRENT_DATE - 2, TRUE, FALSE, 'MANUAL') RETURNING id"
                    ),
                    {"d": d_stale},
                ).scalar_one()
                conn.execute(
                    text(
                        "INSERT INTO queue_tickets "
                        "(queue_id, ticket_number, queue_position, patient_name, source, status) "
                        "VALUES (:q, 1, 1, 'Legacy Done', 'WALK_IN', 'COMPLETED')"
                    ),
                    {"q": q_stale_past_id},
                )

                q_overnight_id = conn.execute(
                    text(
                        "INSERT INTO queues (doctor_id, queue_date, is_active, is_paused, smart_call_mode) "
                        "VALUES (:d, CURRENT_DATE - 1, TRUE, FALSE, 'MANUAL') RETURNING id"
                    ),
                    {"d": d_overnight},
                ).scalar_one()
                conn.execute(
                    text(
                        "INSERT INTO queue_tickets "
                        "(queue_id, ticket_number, queue_position, patient_name, source, status) "
                        "VALUES (:q, 1, 1, 'Overnight Waiting', 'WALK_IN', 'WAITING')"
                    ),
                    {"q": q_overnight_id},
                )

            # 3. Upgrade to head (b3c4d5e6f7a8) and verify deterministic backfill + non-fabrication
            res_up = subprocess.run(
                [sys.executable, "-m", "alembic", "upgrade", "head"],
                cwd=backend_dir,
                env=alembic_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res_up.returncode, 0, res_up.stderr or res_up.stdout)

            with mig_engine.connect() as conn:
                rows = {
                    r.id: r
                    for r in conn.execute(
                        text("SELECT id, is_active, is_paused, shift_status, started_at, ended_at FROM queues")
                    ).fetchall()
                }
                self.assertEqual(rows[q_inactive_id].shift_status, "FINISHED")
                self.assertFalse(rows[q_inactive_id].is_paused)
                self.assertEqual(rows[q_stale_past_id].shift_status, "FINISHED")
                self.assertFalse(rows[q_stale_past_id].is_active)
                self.assertEqual(rows[q_overnight_id].shift_status, "OPEN")
                self.assertTrue(rows[q_overnight_id].is_active)
                for row in rows.values():
                    self.assertIsNone(row.started_at)
                    self.assertIsNone(row.ended_at)

                comp_at = conn.execute(
                    text("SELECT completed_at FROM queue_tickets WHERE patient_name = 'Legacy Done'")
                ).scalar_one()
                self.assertIsNone(comp_at)

                tz_val = conn.execute(text("SELECT timezone FROM clinics WHERE id = :c"), {"c": c_id}).scalar_one()
                self.assertEqual(tz_val, "Asia/Tashkent")

            # 4. Verify downgrade -> re-upgrade round-trip succeeds cleanly
            res_down = subprocess.run(
                [sys.executable, "-m", "alembic", "downgrade", "a2b3c4d5e6f7"],
                cwd=backend_dir,
                env=alembic_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res_down.returncode, 0, res_down.stderr or res_down.stdout)

            res_reup = subprocess.run(
                [sys.executable, "-m", "alembic", "upgrade", "head"],
                cwd=backend_dir,
                env=alembic_env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res_reup.returncode, 0, res_reup.stderr or res_reup.stdout)
        finally:
            mig_engine.dispose()
            with admin_engine.connect() as conn:
                conn.execute(text(f"DROP DATABASE IF EXISTS {mig_db_name} WITH (FORCE)"))
            admin_engine.dispose()


if __name__ == "__main__":
    unittest.main()
