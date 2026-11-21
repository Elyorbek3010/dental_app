import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from starlette.requests import Request

from app.core.config import Settings, parse_cors_origins, settings
from app.core.rate_limit import SlidingWindowRateLimiter, get_client_ip, rate_limiter
from app.db.session import build_engine_kwargs
from app.db.staging_bootstrap import (
    STAGING_CLINIC_NAME,
    apply_staging_bootstrap,
    validate_staging_target,
    validate_strong_password,
)
from app.main import app
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.services.notifications import (
    check_firebase_credentials_status,
    get_firebase_credentials_path,
    initialize_firebase,
)
from tests.test_db import TestSessionLocal, clean_test_database


def _make_request(client_host: str = "127.0.0.1", xff: str | None = None) -> Request:
    headers = []
    if xff is not None:
        headers.append((b"x-forwarded-for", xff.encode("latin-1")))
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/api/auth/login",
        "headers": headers,
        "client": (client_host, 12345),
    }
    return Request(scope)


class StagingReadinessTest(unittest.TestCase):
    def setUp(self) -> None:
        clean_test_database()
        self.client = TestClient(app)

    def tearDown(self) -> None:
        clean_test_database()

    # ------------------------------------------------------------------
    # 1. CORS configuration tests
    # ------------------------------------------------------------------
    def test_cors_allows_localhost_defaults_and_exact_https_origins(self) -> None:
        dev_origins = parse_cors_origins(
            "http://localhost:5173, http://127.0.0.1:5173",
            environment="development",
        )
        self.assertEqual(
            dev_origins,
            ["http://localhost:5173", "http://127.0.0.1:5173"],
        )

        staging_origins = parse_cors_origins(
            "https://Aurora-Demo.vercel.app, https://staging.example.org:8443",
            environment="staging",
        )
        self.assertEqual(
            staging_origins,
            ["https://aurora-demo.vercel.app", "https://staging.example.org:8443"],
        )

    def test_cors_rejects_wildcard_malformed_and_unsafe_production_configs(self) -> None:
        invalid_cases = [
            ("", "development"),
            ("*", "development"),
            ("https://*.vercel.app", "staging"),
            ("https://demo.vercel.app/", "staging"),
            ("https://demo.vercel.app/login", "staging"),
            ("https://demo.vercel.app?x=1", "staging"),
            ("https://user:pass@demo.vercel.app", "staging"),
            ("http://demo.vercel.app", "development"),
            ("http://localhost:5173", "staging"),
            ("http://127.0.0.1:5173", "production"),
            ("ftp://demo.vercel.app", "staging"),
        ]
        for raw, env_name in invalid_cases:
            with self.subTest(raw=raw, env=env_name):
                with self.assertRaises(ValueError):
                    parse_cors_origins(raw, environment=env_name)

    def test_settings_rejects_weak_secret_key_in_staging(self) -> None:
        with self.assertRaises(ValueError):
            Settings(
                _env_file=None,
                ENVIRONMENT="staging",
                DATABASE_URL="postgresql+psycopg://u:p@ep-demo.neon.tech/staging?sslmode=require",
                SECRET_KEY="short-secret",
                CORS_ORIGINS="https://demo.vercel.app",
            )

        valid = Settings(
            _env_file=None,
            ENVIRONMENT="staging",
            DATABASE_URL="postgresql+psycopg://u:p@ep-demo.neon.tech/staging?sslmode=require",
            SECRET_KEY="A" * 40,
            CORS_ORIGINS="https://demo.vercel.app,https://preview.vercel.app",
        )
        self.assertEqual(
            valid.cors_origins_list,
            ["https://demo.vercel.app", "https://preview.vercel.app"],
        )

    def test_cors_middleware_allows_configured_origin_and_blocks_unknown(self) -> None:
        allowed_resp = self.client.get(
            "/api/health",
            headers={"Origin": "http://localhost:5173"},
        )
        self.assertEqual(allowed_resp.status_code, 200)
        self.assertEqual(
            allowed_resp.headers.get("access-control-allow-origin"),
            "http://localhost:5173",
        )
        self.assertNotEqual(allowed_resp.headers.get("access-control-allow-origin"), "*")

        blocked_resp = self.client.get(
            "/api/health",
            headers={"Origin": "https://evil-untrusted.example.com"},
        )
        self.assertEqual(blocked_resp.status_code, 200)
        self.assertIsNone(blocked_resp.headers.get("access-control-allow-origin"))

    # ------------------------------------------------------------------
    # 2. Rate limiting & safe proxy IP tests
    # ------------------------------------------------------------------
    def test_sliding_window_rate_limiter_is_deterministic(self) -> None:
        fake_now = [100.0]
        limiter = SlidingWindowRateLimiter(time_func=lambda: fake_now[0])

        self.assertEqual(limiter.check("login:1.2.3.4", max_requests=2, window_seconds=10), (True, 0))
        fake_now[0] = 104.0
        self.assertEqual(limiter.check("login:1.2.3.4", max_requests=2, window_seconds=10), (True, 0))
        allowed, retry_after = limiter.check("login:1.2.3.4", max_requests=2, window_seconds=10)
        self.assertFalse(allowed)
        self.assertEqual(retry_after, 6)

        # Advance past first request expiry (100 + 10 = 110)
        fake_now[0] = 110.5
        self.assertEqual(limiter.check("login:1.2.3.4", max_requests=2, window_seconds=10), (True, 0))

    def test_client_ip_ignores_spoofed_xff_and_extracts_trusted_rightmost_hop(self) -> None:
        spoofed_req = _make_request(
            client_host="10.0.0.5",
            xff="198.51.100.99, 203.0.113.42",
        )
        # Direct mode (0 trusted proxies): ignores XFF completely
        self.assertEqual(get_client_ip(spoofed_req, trusted_proxy_hops=0), "10.0.0.5")

        # 1 trusted proxy (e.g. Render edge appending real client IP on the right)
        self.assertEqual(get_client_ip(spoofed_req, trusted_proxy_hops=1), "203.0.113.42")

        # Invalid IP falls back safely to direct client host
        malformed_req = _make_request(client_host="10.0.0.5", xff="not-an-ip")
        self.assertEqual(get_client_ip(malformed_req, trusted_proxy_hops=1), "10.0.0.5")

    def test_auth_and_display_endpoints_enforce_429_while_health_remains_exempt(self) -> None:
        # Login limit = 15/min
        for _ in range(15):
            res = self.client.post(
                "/api/auth/login",
                json={"phone": "+998900000001", "password": "wrong-password"},
            )
            self.assertEqual(res.status_code, 401)

        throttled_login = self.client.post(
            "/api/auth/login",
            json={"phone": "+998900000001", "password": "wrong-password"},
        )
        self.assertEqual(throttled_login.status_code, 429)
        self.assertIn("retry-after", throttled_login.headers)

        # Register limit = 10/min
        for idx in range(10):
            res = self.client.post(
                "/api/auth/register",
                json={
                    "full_name": f"Rate Test {idx}",
                    "phone": f"+99890999{idx:04d}",
                    "password": "ValidPassword123!",
                },
            )
            self.assertEqual(res.status_code, 201)

        throttled_reg = self.client.post(
            "/api/auth/register",
            json={
                "full_name": "Rate Test Overflow",
                "phone": "+998909990099",
                "password": "ValidPassword123!",
            },
        )
        self.assertEqual(throttled_reg.status_code, 429)

        # Separate trusted proxy IP remains unaffected when login is throttled for previous IP
        with patch.object(settings, "TRUSTED_PROXY_HOPS", 1):
            other_client = self.client.post(
                "/api/auth/login",
                json={"phone": "+998900000001", "password": "wrong-password"},
                headers={"X-Forwarded-For": "198.51.100.77"},
            )
            self.assertEqual(other_client.status_code, 401)

        # Display limit = 120/min (normal clinic display traffic unaffected, flood rejected)
        with TestSessionLocal() as db:
            clinic = Clinic(name="Rate Clinic", smart_call_timeout_seconds=120, timezone="Asia/Tashkent")
            db.add(clinic)
            db.commit()
            db.refresh(clinic)
            clinic_id = clinic.id

        for _ in range(120):
            res = self.client.get(f"/api/public/clinics/{clinic_id}/display")
            self.assertEqual(res.status_code, 200)

        throttled_display = self.client.get(f"/api/public/clinics/{clinic_id}/display")
        self.assertEqual(throttled_display.status_code, 429)

        # Health endpoint stays exempt even under heavy polling
        for _ in range(150):
            health_res = self.client.get("/api/health")
            self.assertEqual(health_res.status_code, 200)

    # ------------------------------------------------------------------
    # 3. Firebase Secret File & Neon Engine Compatibility tests
    # ------------------------------------------------------------------
    def test_firebase_secret_file_resolution_and_missing_or_invalid_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            secret_file = Path(tmpdir) / "firebase-service-account.json"
            secret_file.write_text(
                json.dumps(
                    {
                        "type": "service_account",
                        "project_id": "dental-staging-demo",
                        "private_key": "-----BEGIN PRIVATE KEY-----\nTEST\n-----END PRIVATE KEY-----\n",
                        "client_email": "firebase@dental-staging-demo.iam.gserviceaccount.com",
                    }
                ),
                encoding="utf-8",
            )
            resolved = get_firebase_credentials_path(str(secret_file))
            self.assertEqual(resolved, secret_file)

            status_ok = check_firebase_credentials_status(str(secret_file))
            self.assertEqual(status_ok, {"configured": True, "valid": True, "reason": "ok"})
            self.assertNotIn("PRIVATE KEY", json.dumps(status_ok))

            bad_file = Path(tmpdir) / "corrupt.json"
            bad_file.write_text("{not-json", encoding="utf-8")
            status_bad = check_firebase_credentials_status(str(bad_file))
            self.assertEqual(status_bad, {"configured": True, "valid": False, "reason": "invalid_json"})

            missing = str(Path(tmpdir) / "missing.json")
            self.assertEqual(
                check_firebase_credentials_status(missing),
                {"configured": False, "valid": False, "reason": "missing_file"},
            )
            with patch.object(settings, "FIREBASE_CREDENTIALS_PATH", missing):
                with patch("app.services.notifications.firebase_admin.get_app", side_effect=ValueError("no app")):
                    self.assertFalse(initialize_firebase())

    def test_neon_psycopg_engine_kwargs_disable_auto_prepared_statements(self) -> None:
        kwargs = build_engine_kwargs(
            "postgresql+psycopg://user:pass@ep-cool-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require"
        )
        self.assertTrue(kwargs["pool_pre_ping"])
        self.assertEqual(kwargs["pool_recycle"], 300)
        self.assertEqual(kwargs["connect_args"], {"prepare_threshold": None})

    # ------------------------------------------------------------------
    # 4. Staging Bootstrap Safety Guards & Idempotency tests
    # ------------------------------------------------------------------
    def test_staging_bootstrap_target_and_password_guards_fail_closed(self) -> None:
        bad_targets = [
            ("", "ep-x.neon.tech", "staging_db"),
            ("postgresql+psycopg://u:p@localhost:5433/dental_db?sslmode=require", "localhost", "dental_db"),
            ("postgresql+psycopg://u:p@127.0.0.1:5433/dental_app_test?sslmode=require", "127.0.0.1", "dental_app_test"),
            ("postgresql+psycopg://u:p@ep-x-pooler.neon.tech/dental_db?sslmode=require", "ep-x-pooler.neon.tech", "dental_db"),
            ("postgresql+psycopg://u:p@ep-x-pooler.neon.tech/staging_db?sslmode=require", "other-host.neon.tech", "staging_db"),
            ("postgresql+psycopg://u:p@ep-x-pooler.neon.tech/staging_db?sslmode=require", "ep-x-pooler.neon.tech", "other_db"),
            ("postgresql+psycopg://u:p@ep-x-pooler.neon.tech/staging_db", "ep-x-pooler.neon.tech", "staging_db"),
            ("postgresql+psycopg://u:p@ep-x-pooler.neon.tech/staging_db?sslmode=disable", "ep-x-pooler.neon.tech", "staging_db"),
        ]
        for url, exp_host, exp_db in bad_targets:
            with self.subTest(exp_host=exp_host, exp_db=exp_db):
                with self.assertRaises(ValueError):
                    validate_staging_target(url, exp_host, exp_db)

        ok_target = validate_staging_target(
            "postgresql+psycopg://u:p@ep-demo-pooler.eu-central-1.aws.neon.tech/dental_staging?sslmode=require",
            "ep-demo-pooler.eu-central-1.aws.neon.tech",
            "dental_staging",
        )
        self.assertEqual(ok_target.dbname, "dental_staging")
        self.assertEqual(ok_target.sslmode, "require")

        weak_passwords = ["", "12345678", "Short1!", "Password123!", "DentalClinic#99", "onlylowercase99!"]
        for weak in weak_passwords:
            with self.subTest(weak_len=len(weak)):
                with self.assertRaises(ValueError) as ctx:
                    validate_strong_password(weak, "STAGING_ADMIN_PASSWORD")
                if weak:
                    self.assertNotIn(weak, str(ctx.exception))

        self.assertEqual(
            validate_strong_password("K9m!Vx7q#Rz2Lp", "STAGING_ADMIN_PASSWORD"),
            "K9m!Vx7q#Rz2Lp",
        )

    def test_staging_bootstrap_dry_run_and_idempotent_execution_in_isolated_test_db(self) -> None:
        strong_admin_pw = "K9m!Vx7q#Rz2Lp"
        strong_recep_pw = "T4n@Bw8v$Qm5Xs"

        with TestSessionLocal() as db:
            # 1. Dry-run writes nothing
            dry_summary = apply_staging_bootstrap(
                db,
                admin_password=strong_admin_pw,
                reception_password=strong_recep_pw,
                execute=False,
            )
            self.assertFalse(dry_summary.execute)
            self.assertTrue(dry_summary.clinic_created)
            self.assertEqual(dry_summary.specializations_created, 3)
            self.assertEqual(dry_summary.doctors_created, 3)
            self.assertEqual(db.scalar(select(func.count()).select_from(Clinic)), 0)
            self.assertEqual(db.scalar(select(func.count()).select_from(User)), 0)

            # 2. First execute creates fictional clinic, 2 staff users, 3 specializations, 3 doctors, 0 patients
            exec_summary = apply_staging_bootstrap(
                db,
                admin_password=strong_admin_pw,
                reception_password=strong_recep_pw,
                execute=True,
            )
            self.assertTrue(exec_summary.execute)
            self.assertTrue(exec_summary.clinic_created)
            self.assertTrue(exec_summary.admin_created)
            self.assertTrue(exec_summary.receptionist_created)
            self.assertEqual(exec_summary.specializations_created, 3)
            self.assertEqual(exec_summary.doctors_created, 3)

            clinic = db.scalar(select(Clinic).where(Clinic.name == STAGING_CLINIC_NAME))
            self.assertIsNotNone(clinic)
            self.assertEqual(clinic.timezone, "Asia/Tashkent")
            self.assertEqual(db.scalar(select(func.count()).select_from(Specialization)), 3)
            self.assertEqual(db.scalar(select(func.count()).select_from(Doctor)), 3)
            self.assertEqual(
                db.scalar(select(func.count()).select_from(User).where(User.role == UserRole.PATIENT)),
                0,
            )

            # 3. Second execute is strictly idempotent
            rerun_summary = apply_staging_bootstrap(
                db,
                admin_password=strong_admin_pw,
                reception_password=strong_recep_pw,
                execute=True,
            )
            self.assertFalse(rerun_summary.clinic_created)
            self.assertFalse(rerun_summary.admin_created)
            self.assertFalse(rerun_summary.receptionist_created)
            self.assertEqual(rerun_summary.specializations_created, 0)
            self.assertEqual(rerun_summary.doctors_created, 0)

    # ------------------------------------------------------------------
    # 5. Deployment artifact sanity checks
    # ------------------------------------------------------------------
    def test_deployment_artifacts_exist_and_are_valid(self) -> None:
        repo_root = Path(__file__).resolve().parent.parent.parent
        vercel_cfg = json.loads((repo_root / "web" / "vercel.json").read_text(encoding="utf-8"))
        self.assertEqual(
            vercel_cfg.get("rewrites"),
            [{"source": "/(.*)", "destination": "/index.html"}],
        )

        manifest_text = (
            repo_root / "mobile" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
        ).read_text(encoding="utf-8")
        self.assertIn('android.permission.INTERNET', manifest_text)

        python_ver = (repo_root / "backend" / ".python-version").read_text(encoding="utf-8").strip()
        self.assertEqual(python_ver, "3.12.7")
