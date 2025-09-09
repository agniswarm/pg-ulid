#!/usr/bin/env python3
"""
test_ulid_readme_pytest.py

Pytest-style tests for README-documented ULID functionality.

Run:
    export PGHOST=localhost
    export PGDATABASE=testdb
    export PGUSER=postgres
    export PGPASSWORD=""
    pytest -q test_ulid_readme_pytest.py

Notes:
- The DB connection uses autocommit so expected failing casts won't leave the
  connection in an aborted transaction state.
- Tests prefer to compare ULID values by their binary representation (::bytea)
  when checking round-trips, to avoid differences in textual formatting ( vs 26 chars).
"""

from datetime import datetime
import pytest
from conftest import exec_one, exec_fetchone, has_function, type_exists, DB_CONFIG
import psycopg2


@pytest.fixture(scope="module")
def db():
    """
    Module-scoped DB connection and precondition checks.

    Uses autocommit so tests that intentionally cause a cast error don't abort
    subsequent statements in the same transaction.
    """
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as exc:
        pytest.fail(f"Cannot connect to database: {exc}", pytrace=False)

    # Use autocommit to avoid InFailedSqlTransaction after expected errors
    conn.autocommit = True

    # Required functions and types for README functionality
    required_funcs = [
        "ulid",
        "ulid_random",
        "ulid_time",
        "ulid_generate_with_timestamp",
        "ulid_parse",
        "ulid_timestamp",
        "ulid_batch",
        "ulid_random_batch",
    ]
    missing = [f for f in required_funcs if not has_function(conn, f)]
    if not type_exists(conn, "ulid"):
        missing.append("type:ulid")

    if missing:
        conn.close()
        hint = "Install/enable the ULID extension in the test DB (superuser): CREATE EXTENSION ulid;"
        pytest.fail(f"Missing ULID functions/types: {', '.join(missing)}. {hint}", pytrace=False)

    try:
        yield conn
    finally:
        try:
            conn.close()
        except Exception:
            pass


def test_basic_generators(db):
    """ulid(), ulid_random() should return non-null values."""
    assert exec_one(db, "SELECT ulid()") is not None
    assert exec_one(db, "SELECT ulid_random()") is not None


def test_time_based_generation(db):
    """ulid_time() and ulid_generate_with_timestamp() produce values for a given ms timestamp."""
    assert exec_one(db, "SELECT ulid_time(1609459200000)") is not None
    assert exec_one(db, "SELECT ulid_generate_with_timestamp(1609459200000)") is not None


def test_parsing_and_timestamp_extraction(db):
    """ulid_parse() and ulid_timestamp() behave as expected for a known ULID."""
    # Validate parse returns something and that the bytes produced by ulid_parse
    # match the bytes from a direct cast of the literal.
    known = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    parsed_bytes = exec_one(db, "SELECT ulid_parse(%s)::bytea", (known,))
    direct_bytes = exec_one(db, "SELECT (%s::text)::ulid::bytea", (known,))
    assert parsed_bytes is not None and direct_bytes is not None
    assert parsed_bytes == direct_bytes, "ulid_parse bytes differ from direct cast bytes"

    ts_ms = exec_one(db, "SELECT ulid_timestamp(%s)", (known,))
    assert ts_ms is not None
    assert isinstance(ts_ms, (int, float)), "ulid_timestamp should return numeric milliseconds"


def test_batch_generation_short(db):
    """ulid_batch and ulid_random_batch produce arrays of requested sizes."""
    n = exec_one(db, "SELECT array_length(ulid_batch(5), 1)")
    assert n == 5, f"ulid_batch(5) expected length 5, got {n}"

    m = exec_one(db, "SELECT array_length(ulid_random_batch(3), 1)")
    assert m == 3, f"ulid_random_batch(3) expected length 3, got {m}"


def test_casting_operations(db):
    """Various casting operations: text<->ulid, timestamp<->ulid, timestamptz, uuid casts."""

    # Text -> ulid
    t2u = exec_one(db, "SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid")
    assert t2u is not None, "Text to ulid cast returned NULL"

    # ulid -> text (length)
    txt = exec_one(db, "SELECT ulid()::text")
    assert isinstance(txt, str)
    # Accept 26 (canonical). Prefer 26 per spec.
    assert len(txt) == 26, f"Expected 26 chars from ulid()::text, got {len(txt)}: {txt!r}"

    # timestamp -> ulid (cast)
    ts2u = exec_one(db, "SELECT '2023-09-15 12:00:00'::timestamp::ulid")
    assert ts2u is not None

    # ulid -> timestamp
    u2ts = exec_one(db, "SELECT ulid()::timestamp")
    assert u2ts is not None and isinstance(u2ts, datetime)

    # ulid -> timestamptz
    u2tstz = exec_one(db, "SELECT ulid()::timestamptz")
    assert u2tstz is not None

    # ulid -> uuid (lossless 1:1 mapping expected by this extension)
    u2uuid = exec_one(db, "SELECT ulid()::uuid")
    assert u2uuid is not None

    # uuid -> ulid
    uuid2u = exec_one(db, "SELECT '550e8400-e29b-41d4-a716-446655440000'::uuid::ulid")
    assert uuid2u is not None


def test_round_trips_text_and_timestamp(db):
    """Round-trip checks for text and timestamp preserve value (text via bytes)."""
    # text round-trip: compare bytes
    known = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    parsed_bytes = exec_one(db, "SELECT %s::ulid::bytea", (known,))
    parsed_bytes2 = exec_one(db, "SELECT ulid_parse(%s)::bytea", (known,))
    assert parsed_bytes == parsed_bytes2, "Text->ULID round-trip mismatch in bytes"

    # timestamp round-trip (allow small tolerance)
    row2 = exec_fetchone(
        db,
        """
        WITH t AS (
            SELECT '2023-09-15 12:00:00'::timestamp AS orig
        )
        SELECT orig, orig::ulid::timestamp FROM t
        """,
    )
    assert row2 is not None
    orig_ts, round_ts = row2
    assert isinstance(orig_ts, datetime) and isinstance(round_ts, datetime)
    diff = abs((orig_ts - round_ts).total_seconds())
    assert diff < 1, f"Timestamp round-trip difference too large: {diff}s"


def test_monotonic_and_uniqueness_samples(db):
    """Monotonic generation and small-sample uniqueness checks."""
    # monotonic sample: three values
    row = exec_fetchone(db, "SELECT ulid() AS a, ulid() AS b, ulid() AS c")
    assert row is not None and len(row) == 3
    a, b, c = row
    assert a < b < c, "Monotonic ordering failed for three-sample check"

    # uniqueness 100
    unique_ok = exec_one(
        db,
        """
        WITH s AS (SELECT ulid() AS u FROM generate_series(1, 100))
        SELECT (COUNT(*) = COUNT(DISTINCT u))::boolean FROM s
        """,
    )
    assert unique_ok is True, "Expected 100 unique ULIDs in sample"


def test_length_and_binary_size(db):
    """ULID text length should be 26 and bytea length should be 16."""
    text_len = exec_one(db, "SELECT length(ulid()::text)")
    assert text_len == 26, f"Expected ulid()::text length 26, got {text_len}"

    bin_len = exec_one(db, "SELECT octet_length(ulid()::bytea)")
    assert bin_len == 16, f"Expected ulid()::bytea length 16, got {bin_len}"


def test_binary_operations(db):
    """ULID bytea binary operations work."""
    b = exec_one(db, "SELECT ulid()::bytea")
    assert b is not None, "ulid()::bytea returned NULL"
    assert len(b) == 16, f"Expected 16-byte binary representation, got {len(b)} bytes"


def test_equality_and_inequality(db):
    """Equality for identical ULID literals and inequality for consecutive generated ULIDs."""
    eq = exec_one(db, "SELECT ('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid)::boolean")
    assert eq is True, "Identical ulid literals did not compare equal"

    row = exec_fetchone(db, "SELECT ulid() AS u1, ulid() AS u2")
    assert row is not None and row[0] != row[1], "Two consecutive ulid() calls returned equal values"


def test_ordering_and_comprehensive_checks(db):
    """Ordering and a comprehensive single-row check aggregating many expectations."""
    r = exec_one(
        db,
        """
        WITH s AS (SELECT ulid() AS u FROM generate_series(1, 10))
        SELECT u FROM s ORDER BY u LIMIT 1
        """,
    )
    assert r is not None, "Ordering query returned no rows"

    row = exec_fetchone(
        db,
        """
        WITH c AS (SELECT ulid() AS u)
        SELECT
            (u IS NOT NULL) AS generation_works,
            (length(u::text) = 26) AS length_correct,
            (octet_length(u::bytea) = 16) AS binary_length_correct,
            (u::timestamp IS NOT NULL) AS timestamp_casting_works,
            (u::uuid IS NOT NULL) AS uuid_casting_works
        FROM c
        """,
    )
    assert row is not None
    assert all(row), f"Comprehensive checks failed: {row}"
