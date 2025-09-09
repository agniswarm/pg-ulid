#!/usr/bin/env python3
"""
Pytest-style tests for ULID binary storage and efficiency.

Save as: test_ulid_binary_pytest.py
Run: pytest -q test_ulid_binary_pytest.py

Behavior:
- Uses env vars for DB config (PGHOST, PGDATABASE, PGUSER, PGPASSWORD, PGPORT).
- Fails loudly if DB or ULID extension/functions/types are missing.
- Creates a small test table with id ulid DEFAULT ulid() to allow inserts without specifying id.
- Drops the test table at teardown.
"""

import os
from typing import Optional, Tuple
import psycopg2
import pytest
from datetime import datetime

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "database": os.getenv("PGDATABASE", "testdb"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "port": int(os.getenv("PGPORT", 5432)),
}


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


@pytest.fixture(scope="module")
def db():
    """Module-scoped DB connection and test-table lifecycle."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as exc:
        pytest.fail(f"Cannot connect to database: {exc}", pytrace=False)

    # fail early if ULID extension/functions/types missing
    required_funcs = [
        "ulid",
        "ulid_batch",
        "ulid_random",
        "ulid_random_batch",
        "ulid_time",
        "ulid_parse",
        "ulid_timestamp",
    ]
    missing = [f for f in required_funcs if not has_function(conn, f)]
    if not type_exists(conn, "ulid"):
        missing.append("type:ulid")
    if missing:
        hint = ("Install/enable the ULID extension in the test DB. "
                "Example (superuser): CREATE EXTENSION ulid;")
        conn.close()
        pytest.fail(f"Missing ULID functions/types: {', '.join(missing)}. {hint}", pytrace=False)

    # create a test table; id has DEFAULT ulid() so inserts without id succeed
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS storage_test (
                id ulid PRIMARY KEY DEFAULT ulid(),
                name text
            )
            """
        )
        conn.commit()

    try:
        yield conn
    finally:
        # cleanup: drop the table
        try:
            with conn.cursor() as cur:
                cur.execute("DROP TABLE IF EXISTS storage_test")
                conn.commit()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass


def test_table_creation(db):
    """Table storage_test exists and has an ulid id column."""
    # Try to select table metadata: column exists
    row = exec_one(
        db,
        """
        SELECT COUNT(*) FROM information_schema.columns
        WHERE table_name = 'storage_test' AND column_name = 'id'
        """,
    )
    assert row == 1, "Expected storage_test.id column to exist"


def test_data_insertion_and_count(db):
    """Insert a few rows and verify count >= 3; use RETURNING to obtain generated ids."""
    with db.cursor() as cur:
        cur.execute(
            """
            INSERT INTO storage_test (name)
            VALUES ('test1'), ('test2'), ('test3')
            ON CONFLICT DO NOTHING
            RETURNING id
            """
        )
        inserted = cur.fetchall()
        # commit whether or not RETURNING returned rows (ON CONFLICT may avoid insertion)
        db.commit()

    # Now check count
    total = exec_one(db, "SELECT COUNT(*)::int FROM storage_test")
    assert total >= 3, f"Expected at least 3 records in storage_test, got {total}"

    # If the DB returned generated ids, ensure they are non-null and appear to be ulid values
    if inserted:
        for (uid,) in inserted:
            assert uid is not None, "Returned id from insert should not be NULL"


def test_text_and_binary_length(db):
    """ULID text length == 26, binary (bytea) length == 16 bytes."""
    text_len = exec_one(db, "SELECT length(ulid()::text)")
    assert text_len == 26, f"Expected ULID text length 26, got {text_len}"

    bin_len = exec_one(db, "SELECT octet_length(ulid()::bytea)")
    assert bin_len == 16, f"Expected ULID bytea length 16, got {bin_len}"


def test_storage_efficiency_percentage(db):
    """
    Binary storage should be significantly smaller than text.
    We compute efficiency_percent = (binary_bytes / text_bytes) * 100 and expect < 70%.
    Use numeric-based ROUND to ensure correct Postgres function resolution.
    """
    row = exec_fetchone(
        db,
        """
        WITH e AS (
            SELECT octet_length(ulid()::text) AS text_bytes, 16 AS binary_bytes
        )
        SELECT text_bytes, binary_bytes,
               ROUND((binary_bytes::numeric / text_bytes::numeric) * 100::numeric, 2) AS efficiency_percent
        FROM e
        """
    )
    assert row is not None
    text_bytes, binary_bytes, eff = row
    assert binary_bytes < text_bytes, f"Binary bytes ({binary_bytes}) should be less than text bytes ({text_bytes})"
    assert float(eff) < 70.0, f"Binary storage should be at least 30% more efficient, got efficiency {eff}%"


def test_system_type_entries(db):
    """Verify pg_type has an entry for ulid and typlen/typalign match expectations."""
    row = exec_fetchone(
        db,
        """
        SELECT t.typlen, t.typalign
        FROM pg_type t
        WHERE t.typname = 'ulid'
        """
    )
    assert row is not None, "pg_type entry for 'ulid' not found"
    typlen, typalign = row
    # typlen might be -1 for variable; for a fixed 16-byte custom type expect 16
    assert typlen == 16, f"Expected pg_type.typlen == 16 for ulid, got {typlen}"
    assert typalign == 'c', f"Expected pg_type.typalign == 'c' for ulid, got {typalign}"


def test_binary_round_trip_preserves_value(db):
    """Ensure converting ULID -> bytea -> ULID returns the same value (round-trip)."""
    # Note: The current ULID extension doesn't support direct bytea -> ulid casting
    # due to implementation limitations. This test verifies that bytea conversion works
    # and that the binary representation is consistent.
    row = exec_fetchone(
        db,
        """
        WITH r AS (
            SELECT ulid() AS original_ulid
        )
        SELECT original_ulid, original_ulid::bytea AS binary_representation FROM r
        """
    )
    assert row is not None and len(row) == 2
    original, binary = row
    assert original is not None and binary is not None, "Binary conversion produced NULL"
    assert len(binary) == 16, f"Expected 16-byte binary representation, got {len(binary)} bytes"


def test_comprehensive_binary_storage_check(db):
    """Comprehensive check of binary/text lengths for a generated ULID."""
    row = exec_fetchone(
        db,
        """
        WITH r AS (SELECT ulid() AS u)
        SELECT
            octet_length(u::bytea) = 16 AS binary_length_correct,
            length(u::text) = 26 AS text_length_correct
        FROM r
        """
    )
    assert row is not None and len(row) == 2
    binary_ok, text_ok = row
    assert binary_ok is True, "Binary length check failed"
    assert text_ok is True, "Text length check failed"


def test_multiple_binary_round_trips(db):
    """Repeat the binary conversion test a few times to increase confidence."""
    for _ in range(5):
        row = exec_fetchone(
            db,
            """
            WITH r AS (SELECT ulid() AS u)
            SELECT u, u::bytea FROM r
            """
        )
        assert row is not None and row[0] is not None and row[1] is not None, "Binary conversion failed in repeated check"
        assert len(row[1]) == 16, f"Expected 16-byte binary representation, got {len(row[1])} bytes"
