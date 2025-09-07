#!/usr/bin/env python3
"""
Pytest-style tests for ULID monotonic generation and ordering properties.

Save as: test_ulid_monotonic_pytest.py
Run: pytest -q test_ulid_monotonic_pytest.py

This suite fails loudly if the DB or required ULID functions/types are missing.
"""

import os
from datetime import datetime, timezone
import psycopg2
import pytest

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "database": os.getenv("PGDATABASE", "testdb"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "port": int(os.getenv("PGPORT", 5432)),
}


def exec_one(conn, sql: str, params=None):
    """Return first column of the first row, or None if no rows."""
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        row = cur.fetchone()
        return None if row is None else row[0]


def exec_fetchone(conn, sql: str, params=None):
    """Return entire first row as tuple or None."""
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchone()


def has_function(conn, func_name: str) -> bool:
    """Return True if a function with name exists in pg_proc (across all schemas)."""
    q = "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = %s)"
    with conn.cursor() as cur:
        cur.execute(q, (func_name,))
        return cur.fetchone()[0]


def type_exists(conn, type_name: str) -> bool:
    """Return True if a type exists in pg_type."""
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


def test_required_ulid_functions_and_type_present(db):
    """Fail early if any required ULID functions or the ulid type are missing."""
    required_funcs = [
        "ulid",
        "ulid_random",
        "ulid_crypto",
        "ulid_time",
        "ulid_parse",
        "ulid_batch",
        "ulid_random_batch",
        "ulid_timestamp",
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


def test_ulid_generation_non_null(db):
    """ulid() should generate a non-null value."""
    val = exec_one(db, "SELECT ulid()")
    assert val is not None, "ulid() returned NULL"


def test_monotonic_ordering_simple(db):
    """
    Calling ulid() multiple times should produce strictly increasing values
    for the sequence of calls in the same SQL statement.
    """
    # Compare three ULIDs produced in a single statement to ensure ordering
    row = exec_fetchone(db, "SELECT ulid() AS u1, ulid() AS u2, ulid() AS u3")
    assert row is not None and len(row) == 3, "Expected three ULID values"
    u1, u2, u3 = row
    assert u1 < u2, f"Expected u1 < u2, got u1={u1}, u2={u2}"
    assert u2 < u3, f"Expected u2 < u3, got u2={u2}, u3={u3}"
    assert u1 < u3, "Transitive ordering failed: u1 !< u3"


def test_consecutive_ulids_different(db):
    """Two consecutive ulid() calls should be distinct."""
    row = exec_fetchone(db, "SELECT ulid() AS a, ulid() AS b")
    assert row is not None, "No row returned"
    a, b = row
    assert a != b, "Two consecutive ulid() calls returned equal values"


def test_batch_monotonic_count_and_uniqueness(db):
    """ulid_batch(n) should return n values; unnest should yield unique values."""
    total = exec_one(db, "SELECT array_length(ulid_batch(10), 1)")
    assert total == 10, f"ulid_batch(10) expected 10 elements, got {total}"

    # uniqueness
    row = exec_fetchone(
        db,
        """
        WITH batch AS (
            SELECT unnest(ulid_batch(10))::text AS u
        )
        SELECT COUNT(*)::int AS total, COUNT(DISTINCT u)::int AS uniq FROM batch
        """,
    )
    assert row is not None
    total, uniq = row
    assert total == 10 and uniq == 10, f"ulid_batch produced duplicates: total={total}, uniq={uniq}"


def test_timestamp_ordering_between_calls(db):
    """ULID-derived timestamps from consecutive ULID calls should be non-decreasing."""
    row = exec_fetchone(
        db,
        """
        WITH t AS (
            SELECT ulid()::timestamp AS t1, ulid()::timestamp AS t2
        )
        SELECT t1, t2 FROM t
        """,
    )
    assert row is not None and len(row) == 2
    t1, t2 = row
    assert isinstance(t1, datetime) and isinstance(t2, datetime), "Expected timestamp datetimes"
    assert t1 <= t2, f"Expected t1 <= t2, got t1={t1}, t2={t2}"


def test_load_generation_count(db):
    """Generate a larger set of ULIDs to ensure generation under load (count check only)."""
    row = exec_fetchone(
        db,
        """
        WITH generated AS (
            SELECT ulid() AS u FROM generate_series(1, 1000)
        )
        SELECT COUNT(*)::int FROM generated
        """,
    )
    assert row is not None, "Query returned no result"
    (count,) = row  # unpack the tuple
    assert count == 1000, f"Expected 1000 ULIDs in load test, got {count}"


def test_lag_window_produces_prev_and_current_non_null_and_order(db):
    """
    Use LAG(ulid()) OVER (ORDER BY generate_series) to produce previous and current ULIDs.
    Check that prev is not NULL for rows after the first and that ordering holds (prev < curr).
    """
    row = exec_fetchone(
        db,
        """
        WITH lag_test AS (
            SELECT
                generate_series AS idx,
                ulid() AS curr,
                LAG(ulid()) OVER (ORDER BY generate_series) AS prev
            FROM generate_series(1, 100)
        )
        SELECT prev::text, curr::text FROM lag_test WHERE prev IS NOT NULL LIMIT 1
        """,
    )
    assert row is not None and len(row) == 2
    prev_text, curr_text = row
    assert prev_text is not None and curr_text is not None, "prev or curr ULID was NULL"
    assert prev_text < curr_text, f"Expected prev < curr, got prev={prev_text}, curr={curr_text}"


def test_lag_multiple_rows_monotonicity(db):
    """
    Validate that across several rows with prev/curr pairs, prev <= curr holds and prev is not null
    for rows after the first.
    """
    rows_to_check = exec_fetchone(
        db,
        """
        WITH lag_test AS (
            SELECT
                generate_series AS idx,
                ulid() AS curr,
                LAG(ulid()) OVER (ORDER BY generate_series) AS prev
            FROM generate_series(1, 20)
        )
        SELECT COUNT(*) FILTER (WHERE prev IS NULL) AS null_prev_count,
               COUNT(*) FILTER (WHERE prev IS NOT NULL AND prev <= curr) AS nondecreasing_pairs,
               COUNT(*) FILTER (WHERE prev IS NOT NULL) AS pairs_with_prev
        FROM lag_test
        """
    )
    assert rows_to_check is not None and len(rows_to_check) == 3
    null_prev_count, nondecreasing_pairs, pairs_with_prev = rows_to_check
    # Only the first row should have prev IS NULL
    assert null_prev_count == 1, f"Expected exactly 1 null 'prev' row, got {null_prev_count}"
    assert pairs_with_prev == 19, f"Expected 19 rows with prev, got {pairs_with_prev}"
    assert nondecreasing_pairs == pairs_with_prev, "Not all prev<=curr pairs are non-decreasing"


def test_ulid_text_ordering_matches_binary_order(db):
    """
    Verify that text ordering of ulid() matches binary ordering (i.e., ORDER BY ulid()::text is same direction).
    This ensures text ordering is safe for indexed ordering if ulid is stored as text.
    """
    rows = exec_fetchone(
        db,
        """
        WITH s AS (
            SELECT generate_series as idx, ulid()::text AS t FROM generate_series(1, 10)
        )
        SELECT MIN(t), MAX(t) FROM s
        """
    )
    assert rows is not None and len(rows) == 2
    min_t, max_t = rows
    assert min_t < max_t, "Expected min text < max text for generated ULIDs"


def test_final_basic_checks(db):
    """Sanity: canonical text length is 26 and parsing is lossless (binary equality)."""
    # text length check for a generated ULID
    length = exec_one(db, "SELECT length(ulid()::text)")
    assert length == 26, f"ULID text length expected 26, got {length}"

    # Known canonical ULID from the spec (already 26 chars)
    known = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    # Compare binary representations to ensure lossless parsing / casting.
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
              ulid_parse(%s)::text      AS parsed_text,
              ulid_parse(%s)::bytea     AS parsed_bytes,
              (%s::ulid)::bytea         AS direct_cast_bytes
            """,
            (known, known, known),
        )
        row = cur.fetchone()

    assert row is not None, "round-trip query returned no row"
    parsed_text, parsed_bytes, direct_cast_bytes = row

    # canonical textual representation length (should be 26)
    assert isinstance(parsed_text, str)
    assert len(parsed_text) == 26, f"Expected canonical ULID text length 26, got {len(parsed_text)}"

    # Lossless invariant: the 16 bytes must match
    assert parsed_bytes == direct_cast_bytes, (
        "Binary round-trip failed: parsed bytes differ "
        f"{parsed_bytes!r} != {direct_cast_bytes!r}"
    )
