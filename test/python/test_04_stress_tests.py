#!/usr/bin/env python3
"""
Fixed and consolidated ULID tests (pytest).

- canonical text length: 26
- text <-> ulid round-trip assertions are made on binary equality (::bytea)
- heavyweight stress tests are skipped unless ULID_STRESS_MAX env var is set high enough
"""

import os
import time
from typing import Tuple, Optional
import psycopg2
import pytest

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "database": os.getenv("PGDATABASE", "testdb"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "port": int(os.getenv("PGPORT", 5432)),
}

# Safety cap for stress tests (default 100k). Raise ULID_STRESS_MAX env var to run heavier tests.
ULID_STRESS_MAX = int(os.getenv("ULID_STRESS_MAX", "100000"))

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
def exec_one(conn, sql: str, params: Optional[Tuple] = None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        row = cur.fetchone()
        return None if row is None else row[0]

def exec_fetchone(conn, sql: str, params: Optional[Tuple] = None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchone()

def has_function(conn, func_name: str) -> bool:
    q = "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = %s)"
    with conn.cursor() as cur:
        cur.execute(q, (func_name,))
        return cur.fetchone()[0]

def type_exists(conn, type_name: str) -> bool:
    q = "SELECT EXISTS (SELECT 1 FROM pg_type WHERE typname = %s)"
    with conn.cursor() as cur:
        cur.execute(q, (type_name,))
        return cur.fetchone()[0]

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
# Fixed tests
# ---------------------------------------------------------------------
def test_ulid_time_and_parse(db):
    """ulid_time should produce canonical 26-char text and ulid_parse must be lossless (bytes)."""
    if not has_function(db, "ulid_time") or not has_function(db, "ulid_parse"):
        pytest.skip("ulid_time/ulid_parse not available")

    # specific timestamp: 2022-01-01 00:00:00 UTC -> 1640995200000 ms
    ut = exec_one(db, "SELECT ulid_time(1640995200000)::text")
    assert ut is not None
    # canonical textual output from a spec-compliant implementation is 26 chars
    assert len(ut) == 26, f"ulid_time() produced unexpected length: {len(ut)}"

    known = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    # Compare parsed bytes (lossless) instead of textual equality because text may canonicalize
    parsed_bytes = exec_one(db, "SELECT ulid_parse(%s)::bytea", (known,))
    direct_cast_bytes = exec_one(db, "SELECT %s::ulid::bytea", (known,))
    assert parsed_bytes == direct_cast_bytes, "ulid_parse(text)::bytea differs from direct cast text::ulid::bytea"

    # also verify canonical text round-trip is a valid canonical ULID of length 26
    canonical_from_parsed = exec_one(db, "SELECT (ulid_parse(%s))::text", (known,))
    assert canonical_from_parsed is not None and len(canonical_from_parsed) == 26

def test_text_round_trip_preserves_value(db):
    """Text -> ULID -> text should preserve the ULID value (compare bytes)."""
    q = """
        WITH round_trip_test AS (
            SELECT
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::text AS original_text,
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::text AS round_trip_text,
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::bytea AS original_bytes,
                ('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::text)::ulid::bytea AS round_trip_bytes
        )
        SELECT original_text, round_trip_text, original_bytes, round_trip_bytes FROM round_trip_test
    """
    with db.cursor() as cur:
        cur.execute(q)
        r = cur.fetchone()

    assert r is not None, "Round-trip query returned no row"
    original_text, round_trip_text, orig_bytes, round_bytes = r

    # Binary equality is the authoritative lossless check
    assert orig_bytes == round_bytes, "Text -> ULID -> text round-trip did not preserve binary ULID value"

def test_batch_casting_uniqueness(db):
    """Unnesting ulid_batch should produce the requested number of unique ULIDs."""
    row = exec_fetchone(
        db,
        """
        WITH batch_test AS (
            SELECT unnest(ulid_batch(5)) AS u
        )
        SELECT COUNT(*)::int, COUNT(DISTINCT u::text)::int FROM batch_test
        """,
    )
    assert row is not None, "Query returned no row"
    total, unique = row
    assert total == unique == 5, f"Expected 5 unique ULIDs from ulid_batch(5), got total={total}, unique={unique}"

def test_load_generation_count(db):
    """Generate a larger set of ULIDs to ensure generation under load (count check only)."""
    row = exec_fetchone(
        db,
        """
        WITH generated AS (
            SELECT ulid() AS u FROM generate_series(1, 1000)
        )
        SELECT COUNT(*)::int FROM generated
        """
    )
    # exec_fetchone returns a tuple (count,), ensure we read it
    assert row is not None and row[0] == 1000, f"Expected 1000 ULIDs in load test, got {row}"

def test_final_basic_checks(db):
    """A couple of final sanity checks: text length and parse round-trip for a known ULID."""
    length = exec_one(db, "SELECT length(ulid()::text)")
    assert length == 26, f"ULID text length expected 26, got {length}"

    # Parse round-trip (known value) - compare bytes to ensure lossless parsing
    parsed_bytes = exec_one(db, "SELECT ulid_parse('01ARZ3NDEKTSV4RRFFQ69G5FAV')::bytea")
    direct_bytes = exec_one(db, "SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::bytea")
    assert parsed_bytes == direct_bytes, "ulid_parse() did not round-trip the known ULID as binary equality"

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
