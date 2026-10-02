"""
Test Package Initialization.
Guarantees database isolation safety guard is verified before any tests run.
"""
from tests.safety_guard import verify_test_db_isolation
import tests.test_db
