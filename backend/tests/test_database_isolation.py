"""
Unit Tests for Database Isolation and Hard Safety Guard.
Verifies that the test suite is strictly prevented from executing against the development database.
"""
import unittest
from tests.safety_guard import normalize_db_target, verify_test_db_isolation
from tests.test_db import TestSessionLocal, test_engine, get_test_db
from app.api.deps import get_db
from app.main import app


class DatabaseIsolationSafetyGuardTest(unittest.TestCase):
    def test_normalize_db_target_safely_extracts_target(self):
        url = "postgresql+psycopg://secret_user:secret_pass@127.0.0.1:5433/dental_test_db"
        scheme, host, port, dbname = normalize_db_target(url)
        self.assertEqual(scheme, "postgresql")
        self.assertEqual(host, "localhost")  # Normalized from 127.0.0.1
        self.assertEqual(port, 5433)
        self.assertEqual(dbname, "dental_test_db")

    def test_verify_isolation_passes_on_valid_separate_databases(self):
        dev = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        test = "postgresql+psycopg://user:pass@localhost:5433/dental_app_test"
        scheme, host, port, dbname = verify_test_db_isolation(
            dev_url=dev,
            test_url=test,
            is_testing_env=True,
        )
        self.assertEqual(dbname, "dental_app_test")
        self.assertEqual(host, "localhost")

    def test_verify_isolation_fails_if_test_db_missing(self):
        dev = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        with self.assertRaises(RuntimeError) as ctx:
            verify_test_db_isolation(
                dev_url=dev,
                test_url="",
                is_testing_env=True,
            )
        self.assertIn("TEST_DATABASE_URL is not set", str(ctx.exception))
        # Ensure credentials are not in exception message
        self.assertNotIn("secret", str(ctx.exception))

    def test_verify_isolation_fails_if_same_database_url(self):
        dev = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        test = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        with self.assertRaises(RuntimeError) as ctx:
            verify_test_db_isolation(
                dev_url=dev,
                test_url=test,
                is_testing_env=True,
            )
        self.assertIn("resolves to the EXACT same database target", str(ctx.exception))
        self.assertNotIn("pass", str(ctx.exception))

    def test_verify_isolation_fails_if_ip_and_localhost_synonyms(self):
        dev = "postgresql+psycopg://user:pass@127.0.0.1:5433/dental_db"
        test = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        with self.assertRaises(RuntimeError) as ctx:
            verify_test_db_isolation(
                dev_url=dev,
                test_url=test,
                is_testing_env=True,
            )
        self.assertIn("EXACT same database target", str(ctx.exception))
        self.assertNotIn("pass", str(ctx.exception))

    def test_verify_isolation_fails_if_dbname_collides_across_hosts(self):
        dev = "postgresql+psycopg://user:pass@prod-cluster:5432/dental_db"
        test = "postgresql+psycopg://user:pass@other-host:5432/dental_db"
        with self.assertRaises(RuntimeError) as ctx:
            verify_test_db_isolation(
                dev_url=dev,
                test_url=test,
                is_testing_env=True,
            )
        self.assertIn("matches development database name", str(ctx.exception))
        self.assertNotIn("pass", str(ctx.exception))

    def test_verify_isolation_fails_if_testing_flag_disabled(self):
        dev = "postgresql+psycopg://user:pass@localhost:5433/dental_db"
        test = "postgresql+psycopg://user:pass@localhost:5433/dental_app_test"
        with self.assertRaises(RuntimeError) as ctx:
            verify_test_db_isolation(
                dev_url=dev,
                test_url=test,
                is_testing_env=False,
            )
        self.assertIn("Testing environment is not explicitly enabled", str(ctx.exception))

    def test_app_dependency_override_points_to_test_db(self):
        self.assertIn(get_db, app.dependency_overrides)
        override_fn = app.dependency_overrides[get_db]
        self.assertEqual(override_fn.__name__, "get_test_db")
        session_gen = override_fn()
        session = next(session_gen)
        try:
            self.assertIn("dental_app_test", str(session.bind.url))
            self.assertNotIn("dental_db", str(session.bind.url).split("/")[-1])
        finally:
            session.close()

    def test_session_local_and_engine_bound_to_test_database(self):
        db = TestSessionLocal()
        try:
            bind_url = str(db.bind.url)
            self.assertIn("dental_app_test", bind_url)
            self.assertNotIn("dental_db", bind_url.split("/")[-1])
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
