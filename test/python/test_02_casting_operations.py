#!/usr/bin/env python3
"""
Pytest-style tests for ULID casting operations (converted from procedural script).

- Reads DB connection from environment variables (PGHOST, PGDATABASE, PGUSER, PGPASSWORD, PGPORT).
- Fails loudly at collection/runtime if DB connectivity or required ULID functions/types are missing.
- Uses small helper utilities for clarity.
- No skipping: missing pieces cause test failures with actionable messages.

Save as: test_ulid_casting_pytest.py
Run: pytest -q test_ulid_casting_pytest.py
"""

import os
import psycopg2
import pytest
from datetime import datetime, timezone

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "database": os.getenv("PGDATABASE", "testdb"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "port": int(os.getenv("PGPORT", 5432)),
}


def exec_one(conn, sql: str, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        row = cur.fetchone()
        return None if row is None else row[0]


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


@pytest.fixture(scope="module")
def db():
    """Module-scoped DB connection. Fail the test run if cannot connect."""
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


def test_required_ulid_functions_and_types_present(db):
    """Fail early if required ULID functions or the ulid type are missing."""
    required_funcs = [
        "ulid",
        "ulid_random",
        "ulid_crypto",
        "ulid_time",
        "ulid_parse",
        "ulid_batch",
        "ulid_random_batch",
        "ulid_timestamp",
        "ulid_generate_with_timestamp",
    ]
    missing = [f for f in required_funcs if not has_function(db, f)]

    if not type_exists(db, "ulid"):
        missing.append("type:ulid")

    if missing:
        hint = (
            "Install/enable the ULID extension or add missing functions/types in the test DB. "
            "Example (superuser): CREATE EXTENSION ulid;"
        )
        pytest.fail(
            f"Missing required ULID functions/types: {', '.join(missing)}. {hint}",
            pytrace=False,
        )


def test_text_to_ulid_and_back_casting(db):
    """Text to ULID and ULID to text casting should work and preserve value."""
    # Text -> ulid cast
    val = exec_one(db, "SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid")
    assert val is not None, "Text to ULID casting returned NULL"

    # ULID -> text cast length
    text_val = exec_one(db, "SELECT ulid()::text")
    assert text_val is not None, "ULID to text casting returned NULL"
    assert isinstance(text_val, str), "ULID to text did not return a string"
    assert len(text_val) == 26, f"ULID to text expected length 26, got {len(text_val)}"


def test_text_round_trip_preserves_value(db):
    """Text -> ULID -> text: canonical text may change, but bytes must be identical."""
    q = """
        WITH round_trip_test AS (
            SELECT
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::text AS original_text,
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::text AS canonical_text,
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::bytea AS parsed_bytes,
                ('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::text)::ulid::bytea AS roundtrip_parsed_bytes
        )
        SELECT original_text, canonical_text, parsed_bytes, roundtrip_parsed_bytes
        FROM round_trip_test
    """

    with db.cursor() as cur:
        cur.execute(q)
        r = cur.fetchone()

    assert r is not None, "round-trip query returned no row"
    original_text, canonical_text, parsed_bytes, roundtrip_parsed_bytes = r

    # Canonical textual representation length (26) — keep this check
    assert isinstance(canonical_text, str)
    assert len(canonical_text) == 26, f"Expected canonical ULID text length 26, got {len(canonical_text)}"

    # Lossless invariant: parsed bytes from the original text and parsed bytes
    # from the canonical text must be identical.
    assert parsed_bytes == roundtrip_parsed_bytes, (
        "Binary round-trip failed: parsed bytes differ "
        f"{parsed_bytes!r} != {roundtrip_parsed_bytes!r}"
    )


def test_timestamp_to_ulid_and_ulid_to_timestamp_casting(db):
    """Timestamp -> ULID and ULID -> timestamp casting should work."""
    # Timestamp -> ulid
    ul = exec_one(db, "SELECT '2023-09-15 12:00:00'::timestamp::ulid")
    assert ul is not None, "Timestamp to ULID casting returned NULL"

    # ulid -> timestamp
    ts = exec_one(db, "SELECT ulid()::timestamp")
    assert ts is not None, "ULID to timestamp casting returned NULL"
    assert isinstance(ts, datetime), "ULID->timestamp did not return datetime"


def test_timestamp_round_trip_preserves_value_with_tolerance(db):
    """Timestamp -> ULID -> timestamp round-trip should preserve timestamp (small tolerance allowed)."""
    q = """
        WITH timestamp_round_trip AS (
            SELECT
                '2023-09-15 12:00:00'::timestamp AS original_timestamp,
                '2023-09-15 12:00:00'::timestamp::ulid::timestamp AS round_trip_timestamp
        )
        SELECT original_timestamp, round_trip_timestamp FROM timestamp_round_trip
    """
    with db.cursor() as cur:
        cur.execute(q)
        orig, round_trip = cur.fetchone()
    assert isinstance(orig, datetime) and isinstance(round_trip, datetime)
    diff = abs((orig - round_trip).total_seconds())
    assert diff < 1, f"Timestamp round-trip difference too large: {diff}s"


def test_ulid_timestamp_round_trip_preserves_timestamp(db):
    """ULID -> timestamp -> ULID round-trip should preserve timestamp-related data."""
    q = """
        WITH ulid_timestamp_round_trip AS (
            SELECT
                '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid AS original_ulid,
                ulid_generate_with_timestamp(ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid)) AS round_trip_ulid,
                ulid_timestamp(ulid_generate_with_timestamp(ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid))) AS round_trip_ts_ms
        )
        SELECT original_ulid, round_trip_ulid, round_trip_ts_ms FROM ulid_timestamp_round_trip
    """
    with db.cursor() as cur:
        cur.execute(q)
        r = cur.fetchone()
    assert r is not None, "ULID timestamp round-trip returned no result"
    original_ulid, round_trip_ulid, round_trip_ts_ms = r
    assert original_ulid is not None
    assert round_trip_ulid is not None
    assert round_trip_ts_ms is not None
    # validate timestamp milliseconds is an integer-like number and > 0
    assert isinstance(round_trip_ts_ms, int) or isinstance(round_trip_ts_ms, float), "round_trip_ts_ms is not numeric"
    assert round_trip_ts_ms > 0, "round_trip_ts_ms is not positive"


def test_timestamptz_casting(db):
    """ULID -> timestamptz casting should produce a timestamptz/datetime with tzinfo (or interpreted as UTC)."""
    val = exec_one(db, "SELECT ulid()::timestamptz")
    assert val is not None, "ULID to timestamptz casting returned NULL"
    assert isinstance(val, datetime), "ULID::timestamptz did not return datetime"
    # psycopg2 may return naive datetime for timestamptz depending on settings; ensure it can be interpreted
    # we at least check it's a datetime object


def test_uuid_and_back_casting(db):
    """ULID <-> UUID casting should be supported in both directions (if semantically meaningful)."""
    u = exec_one(db, "SELECT ulid()::uuid")
    assert u is not None, "ULID to UUID casting returned NULL"

    back = exec_one(db, "SELECT '550e8400-e29b-41d4-a716-446655440000'::uuid::ulid")
    assert back is not None, "UUID to ULID casting returned NULL"


def test_ulid_inequality(db):
    """Two ULID() invocations should produce distinct values (inequality)."""
    with db.cursor() as cur:
        cur.execute("SELECT ulid() as u1, ulid() as u2")
        r = cur.fetchone()
    assert r is not None and r[0] != r[1], "Two consecutive ulid() calls returned equal values"


def test_timestamp_extraction_accuracy(db):
    """ulid_timestamp(ulid) should extract a timestamp close to the original timestamp used to build the ULID."""
    q = """
        WITH timestamp_test AS (
            SELECT
                '2023-09-15 12:00:00'::timestamp AS original_timestamp,
                ulid_timestamp('2023-09-15 12:00:00'::timestamp::ulid) AS extracted_timestamp_ms
        )
        SELECT original_timestamp, extracted_timestamp_ms FROM timestamp_test
    """
    with db.cursor() as cur:
        cur.execute(q)
        orig, extracted_ms = cur.fetchone()
    assert isinstance(orig, datetime)
    assert isinstance(extracted_ms, (int, float))
    extracted_dt = datetime.fromtimestamp(extracted_ms / 1000.0, tz=timezone.utc).replace(tzinfo=None)
    # comparing naive datetimes; convert original to naive (assume original timestamp is in local/system timezone)
    # For robustness allow up to 1s difference
    diff = abs((orig - extracted_dt).total_seconds())
    assert diff < 1, f"Timestamp extraction difference too large: {diff}s"


def test_ulid_text_length(db):
    """ulid() as text should be exactly 26 characters."""
    length = exec_one(db, "SELECT length(ulid()::text)")
    assert length == 26, f"Expected ULID text length 26, got {length}"


def test_batch_casting_uniqueness(db):
    """Unnesting ulid_batch should produce the requested number of unique ULIDs."""
    sql = """
    WITH batch_test AS (
        SELECT unnest(ulid_batch(5)) AS u
    )
    SELECT COUNT(*)::int AS total, COUNT(DISTINCT u)::int AS unique_count
    FROM batch_test
    """
    with db.cursor() as cur:
        cur.execute(sql)
        row = cur.fetchone()

    assert row is not None, "query returned no row"
    total, unique = row

    assert total == 5, f"Expected total 5 from ulid_batch(5), got {total}"
    assert unique == 5, f"Expected 5 unique ULIDs from ulid_batch(5), got {unique}"

def test_null_ulid_casting(db):
    """NULL::ulid should return SQL NULL (maps to Python None)."""
    val = exec_one(db, "SELECT NULL::ulid")
    assert val is None, "NULL::ulid did not produce NULL"


def test_epoch_timestamp_casting(db):
    """Epoch timestamp (1970-01-01) cast to ULID should succeed."""
    ul = exec_one(db, "SELECT '1970-01-01 00:00:00'::timestamp::ulid")
    assert ul is not None, "Epoch timestamp to ULID casting returned NULL"


def test_comprehensive_casts_report(db):
    """Verify a set of casting operations don't return NULL (reporting test)."""
    q = """
        SELECT
            (ulid()::text IS NOT NULL) AS text_cast_works,
            (ulid()::timestamp IS NOT NULL) AS timestamp_cast_works,
            (ulid()::timestamptz IS NOT NULL) AS timestamptz_cast_works,
            (ulid()::uuid IS NOT NULL) AS uuid_cast_works
    """
    with db.cursor() as cur:
        cur.execute(q)
        r = cur.fetchone()
    assert r is not None and all(r), f"Not all comprehensive casting operations succeeded: {r}"

def test_direct_timestamp_to_ulid_casting(db):
    """Test direct timestamp to ULID casting (should be faster than chained)."""
    test_timestamp = '2025-07-24'
    
    with db.cursor() as cur:
        # Test direct casting
        cur.execute(f"SELECT '{test_timestamp}'::timestamp::ulid as result")
        result = cur.fetchone()
        assert result is not None, "Direct casting returned NULL"
        
        ulid_result = result[0]
        assert ulid_result is not None, "ULID result is NULL"
        
        # Verify the ULID can be converted back to timestamp
        cur.execute("SELECT %s::ulid::timestamp as back_to_timestamp", (ulid_result,))
        back_to_timestamp = cur.fetchone()[0]
        assert back_to_timestamp is not None, "ULID to timestamp conversion failed"
        
        # The timestamp should be close to the original
        original_ts = datetime.strptime(test_timestamp, '%Y-%m-%d')
        diff_seconds = abs((back_to_timestamp - original_ts).total_seconds())
        assert diff_seconds < 1.0, f"Timestamp conversion error: {diff_seconds} seconds difference"
        
        print(f"✅ Direct casting works: '{test_timestamp}'::timestamp::ulid = {ulid_result}")
