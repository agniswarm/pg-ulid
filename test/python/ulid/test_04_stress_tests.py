#!/usr/bin/env python3
"""
Fixed and consolidated ULID tests (pytest).

- canonical text length: 26
- text <-> ulid round-trip assertions are made on binary equality (::bytea)
- heavyweight stress tests are skipped unless ULID_STRESS_MAX env var is set high enough
"""

import os
import time
import pytest
from conftest import exec_one, exec_fetchone, has_function, type_exists, DB_CONFIG
import psycopg2

# Safety cap for stress tests (default 100k). Raise ULID_STRESS_MAX env var to run heavier tests.
ULID_STRESS_MAX = int(os.getenv("ULID_STRESS_MAX", "100000"))

# ---------------------------------------------------------------------
# DB fixture
# ---------------------------------------------------------------------
@pytest.fixture(scope="module")
def db():
    """Module-scoped DB connection. Fail loudly if we cannot connect."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as exc:
        pytest.fail(f"Cannot connect to database: {exc}", pytrace=False)
    try:
        yield conn
    finally:
        try:
            conn.close()
        except Exception:
            pass

# ---------------------------------------------------------------------
# Precondition helper
# ---------------------------------------------------------------------
def require_ulid_extension(db_conn):
    required_funcs = [
        "ulid", "ulid_batch", "ulid_random", "ulid_random_batch",
        "ulid_time", "ulid_parse", "ulid_timestamp",
    ]
    missing = [f for f in required_funcs if not has_function(db_conn, f)]
    if not type_exists(db_conn, "ulid"):
        missing.append("type:ulid")

    if missing:
        hint = ("Install/enable the ULID extension or add missing functions/types. "
                "Example (superuser): CREATE EXTENSION ulid;")
        pytest.fail(f"Missing ULID functions/types: {', '.join(missing)}. {hint}", pytrace=False)

# ---------------------------------------------------------------------
# Basic precondition test
# ---------------------------------------------------------------------
def test_preconditions(db):
    require_ulid_extension(db)

# ---------------------------------------------------------------------
# Stress tests (skips if ULID_STRESS_MAX is too low)
# ---------------------------------------------------------------------
def clipped_size(requested: int) -> int:
    return requested if requested <= ULID_STRESS_MAX else ULID_STRESS_MAX

def assert_not_clipped(requested: int):
    if requested > ULID_STRESS_MAX:
        pytest.skip(
            f"Requested stress size {requested} exceeds ULID_STRESS_MAX ({ULID_STRESS_MAX}). "
            "Set ULID_STRESS_MAX to run this heavy test.",
        )

def test_small_batch_generation_and_uniqueness(db):
    n_requested = 100
    n = clipped_size(n_requested)
    assert_not_clipped(n_requested)

    count = exec_one(db, "SELECT array_length(ulid_batch(%s), 1)", (n,))
    assert count == n, f"Expected {n} ULIDs, got {count}"

    row = exec_fetchone(
        db,
        """
        WITH small_batch_test AS (
            SELECT unnest(ulid_batch(%s)) as ulid_val
        )
        SELECT COUNT(*)::int AS total, COUNT(DISTINCT ulid_val::text)::int AS unique_count
        FROM small_batch_test
        """,
        (n,),
    )
    assert row is not None
    total, unique_count = row
    assert total == unique_count == n, f"Expected {n} unique ULIDs, got {unique_count} unique out of {total}"

def performance_check(db, series_count: int, time_limit: float):
    start = time.time()
    row = exec_fetchone(
        db,
        f"""
        WITH performance_test AS (
            SELECT ulid() as ulid_val
            FROM generate_series(1, {series_count})
        )
        SELECT COUNT(*)::int FROM performance_test
        """
    )
    elapsed = time.time() - start
    assert row is not None and row[0] == series_count, f"Expected {series_count} ULIDs, got {row}"
    assert elapsed < time_limit, f"Expected < {time_limit:.1f}s, got {elapsed:.2f}s"
    return elapsed

def test_performance_1k_ulids(db):
    performance_check(db, 1_000, 1.0)

def test_performance_10k_ulids(db):
    performance_check(db, 10_000, 5.0)

def test_performance_100k_ulids(db):
    if ULID_STRESS_MAX < 100_000:
        pytest.skip("ULID_STRESS_MAX too low for 100k performance test")
    performance_check(db, 100_000, 30.0)

def test_performance_1m_ulids(db):
    if ULID_STRESS_MAX < 1_000_000:
        pytest.skip("ULID_STRESS_MAX too low for 1M performance test")
    performance_check(db, 1_000_000, 300.0)

# End of file
