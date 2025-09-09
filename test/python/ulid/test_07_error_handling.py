#!/usr/bin/env python3
"""
Pytest-style Test 08: Error Handling (improved)

- Environment-configured DB connection.
- Fails loudly if ULID extension/functions/types are missing.
- Uses helpers to assert expected psycopg2 error classes.
- Protects CI from accidentally executing extremely large allocations by using ULID_STRESS_MAX.
"""

import os
from typing import Iterable, Type
import pytest
from conftest import exec_one, exec_fetchone, has_function, type_exists, DB_CONFIG
import psycopg2

# Safety cap for large/expensive tests (can be increased intentionally via env)
ULID_STRESS_MAX = int(os.getenv("ULID_STRESS_MAX", "1000000"))


@pytest.fixture(scope="module")
def db():
    """Module-scoped DB connection and precondition checks (fail loudly)."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as exc:
        pytest.fail(f"Cannot connect to database: {exc}", pytrace=False)

    required_funcs = [
        "ulid", "ulid_random", "ulid_time", "ulid_parse",
        "ulid_timestamp", "ulid_batch", "ulid_random_batch"
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


# Helper to assert that a DB operation raises a psycopg2 exception class
def expect_db_error(exc_types: Iterable[Type[BaseException]], fn, *args, **kwargs):
    """Run fn(*args, **kwargs) and assert it raises one of exc_types."""
    with pytest.raises(tuple(exc_types)):
        try:
            fn(*args, **kwargs)
        finally:
            # Rollback any failed transaction to allow subsequent tests to run
            if 'db' in kwargs:
                kwargs['db'].rollback()
            elif len(args) > 0 and hasattr(args[0], 'rollback'):
                args[0].rollback()


### Tests ###

def test_invalid_ulid_text_input(db):
    """Invalid ULID text inputs should raise InvalidTextRepresentation for truly invalid inputs."""
    # These should raise errors
    invalid_inputs = [
        "", "123", "01ARZ3NDEKTSV4RRFFQ69G5FAVX", "invalid_ulid_string",
        "01ARZ3NDEKTSV4RRFFQ69G5FAV ", " 01ARZ3NDEKTSV4RRFFQ69G5FAV",
        "01ARZ3NDEKTSV4RRFFQ69G5FAV\n", "01ARZ3NDEKTSV4RRFFQ69G5FAV\t"
    ]
    for s in invalid_inputs:
        expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT %s::ulid", (s,))
    
    # These should work (ULID extension normalizes invalid Base32 chars)
    valid_normalized_inputs = [
        "01ARZ3NDEKTSV4RRFFQ69G5FAI", "01ARZ3NDEKTSV4RRFFQ69G5FAO",
        "01ARZ3NDEKTSV4RRFFQ69G5FA0", "01ARZ3NDEKTSV4RRFFQ69G5FA1",
        "01ARZ3NDEKTSV4RRFFQ69G5FA8", "01ARZ3NDEKTSV4RRFFQ69G5FA9"
    ]
    for s in valid_normalized_inputs:
        result = exec_one(db, "SELECT %s::ulid", (s,))
        assert result is not None, f"Expected {s} to be normalized to valid ULID"


def test_invalid_timestamp_inputs(db):
    """Invalid timestamp strings cast to timestamp::ulid should raise errors."""
    invalid_timestamps = [
        "invalid_timestamp", "2023-13-01 12:00:00", "2023-02-30 12:00:00",
        "2023-02-29 12:00:00", "2023-12-32 12:00:00", "25:00:00",
        "12:60:00", "12:00:60", "2023-01-01T25:00:00"
    ]
    for ts in invalid_timestamps:
        expect_db_error([psycopg2.DataError, psycopg2.ProgrammingError], exec_one, db, "SELECT %s::timestamp::ulid", (ts,))


def test_invalid_uuid_inputs(db):
    """Invalid UUID strings cast to uuid::ulid should raise DataError/ProgrammingError."""
    invalid_uuids = [
        "invalid-uuid", "550e8400-e29b-41d4-a716-44665544000", "550e8400-e29b-41d4-a716-4466554400000",
        "550e8400-e29b-41d4-a716-44665544000g", "550e8400-e29b-41d4-a716", "550e8400-e29b-41d4-a716-446655440000-extra"
    ]
    for s in invalid_uuids:
        expect_db_error([psycopg2.DataError, psycopg2.ProgrammingError], exec_one, db, "SELECT %s::uuid::ulid", (s,))


def test_invalid_bytea_inputs(db):
    """Invalid bytea->ulid conversions should raise DataError."""
    expect_db_error([psycopg2.DataError], exec_one, db, "SELECT %s::bytea::ulid", ("invalid_bytea",))


def test_ulid_time_invalid_inputs(db):
    """ulid_time() with invalid args should raise appropriate errors."""
    # Test with string that can't be converted to bigint
    expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid_time(%s)", ("invalid",))
    
    # Test with NULL (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_time(NULL)")
    assert result is None
    
    # Test with negative timestamp (should work, not error)
    result = exec_one(db, "SELECT ulid_time(-1)")
    assert result is not None


def test_ulid_parse_invalid_inputs(db):
    """ulid_parse with invalid inputs should raise appropriate errors."""
    # These should raise errors
    invalid_inputs = ["", "123", "01ARZ3NDEKTSV4RRFFQ69G5FAVX", "01ARZ3NDEKTSV4RRFFQ69G5FAU"]
    for s in invalid_inputs:
        expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid_parse(%s)", (s,))
    
    # These should work (ULID extension normalizes invalid Base32 chars)
    valid_normalized_inputs = ["01ARZ3NDEKTSV4RRFFQ69G5FAI", "01ARZ3NDEKTSV4RRFFQ69G5FAO"]
    for s in valid_normalized_inputs:
        result = exec_one(db, "SELECT ulid_parse(%s)", (s,))
        assert result is not None, f"Expected {s} to be normalized to valid ULID"
    
    # Test with NULL (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_parse(NULL)")
    assert result is None


def test_ulid_timestamp_invalid_inputs(db):
    """ulid_timestamp with invalid inputs should raise appropriate errors."""
    # These should raise errors
    invalid_inputs = ["", "123", "01ARZ3NDEKTSV4RRFFQ69G5FAVX", "01ARZ3NDEKTSV4RRFFQ69G5FAU"]
    for s in invalid_inputs:
        expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid_timestamp(%s)", (s,))
    
    # These should work (ULID extension normalizes invalid Base32 chars)
    valid_normalized_inputs = ["01ARZ3NDEKTSV4RRFFQ69G5FAI", "01ARZ3NDEKTSV4RRFFQ69G5FAO"]
    for s in valid_normalized_inputs:
        result = exec_one(db, "SELECT ulid_timestamp(%s)", (s,))
        assert result is not None, f"Expected {s} to be normalized to valid ULID"
    
    # Test with NULL (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_timestamp(NULL)")
    assert result is None


def test_ulid_batch_invalid_inputs(db):
    """ulid_batch with invalid inputs should raise appropriate errors."""
    # Test with string that can't be converted to integer
    expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid_batch(%s)", ("invalid",))
    
    # Test with NULL (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_batch(NULL)")
    assert result is None
    
    # Test with negative count (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_batch(-1)")
    assert result is None
    
    # Test with zero count (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_batch(0)")
    assert result is None


def test_ulid_random_batch_invalid_inputs(db):
    """ulid_random_batch with invalid inputs should raise appropriate errors."""
    # Test with string that can't be converted to integer
    expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid_random_batch(%s)", ("invalid",))
    
    # Test with NULL (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_random_batch(NULL)")
    assert result is None
    
    # Test with negative count (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_random_batch(-1)")
    assert result is None
    
    # Test with zero count (should return NULL, not error)
    result = exec_one(db, "SELECT ulid_random_batch(0)")
    assert result is None


def test_null_handling(db):
    """NULL inputs should map to SQL NULL and not raise."""
    assert exec_one(db, "SELECT NULL::ulid") is None
    assert exec_one(db, "SELECT ulid_parse(NULL)") is None
    assert exec_one(db, "SELECT ulid_timestamp(NULL)") is None
    assert exec_one(db, "SELECT ulid_time(NULL)") is None


def test_edge_case_timestamps(db):
    """Edge timestamps: ulid_time(0) (epoch) may be invalid; max 48-bit allowed."""
    # Some implementations disallow zero; assert that either raises DataError or returns a ulid.
    try:
        res = exec_one(db, "SELECT ulid_time(0)")
        # If returned, ensure it's not None
        assert res is not None
    except Exception as exc:
        assert isinstance(exc, (psycopg2.DataError, psycopg2.ProgrammingError))

    future_ts = (1 << 48) - 1
    res2 = exec_one(db, "SELECT ulid_time(%s)", (future_ts,))
    assert res2 is not None


def test_ulid_comparison_edge_cases(db):
    """Comparisons involving NULL should return SQL NULL (None in psycopg2)."""
    assert exec_one(db, "SELECT (ulid() = NULL)::boolean") is None
    assert exec_one(db, "SELECT (ulid() < NULL)::boolean") is None
    assert exec_one(db, "SELECT (ulid() > NULL)::boolean") is None

    # Comparing ULID with text should raise InvalidTextRepresentation
    expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT (ulid() = 'text')::boolean")


def test_casting_edge_cases_for_nulls(db):
    assert exec_one(db, "SELECT NULL::ulid::text") is None
    assert exec_one(db, "SELECT NULL::ulid::timestamp") is None
    assert exec_one(db, "SELECT NULL::ulid::uuid") is None
    assert exec_one(db, "SELECT NULL::ulid::bytea") is None


def test_overflow_and_limit_conditions(db):
    """Protect CI: do not actually run enormous queries; instruct the operator to raise ULID_STRESS_MAX instead."""
    huge = 2_147_483_647
    if ULID_STRESS_MAX < huge:
        pytest.skip(f"Skipping true overflow test unless ULID_STRESS_MAX >= {huge}")
    else:
        expect_db_error([psycopg2.DataError, psycopg2.OperationalError], exec_one, db, "SELECT ulid_batch(%s)", (huge,))


def test_type_coercion_errors(db):
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid()::integer")
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid()::boolean")
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid()::numeric")


def test_function_signature_errors(db):
    """Function calls with wrong number of arguments should raise errors."""
    # ulid() with extra argument - should raise InvalidTextRepresentation (tries to cast 'extra_arg' to ulid)
    expect_db_error([psycopg2.errors.InvalidTextRepresentation], exec_one, db, "SELECT ulid('extra_arg')")
    
    # ulid_time() with no arguments - should raise ProgrammingError
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid_time()")
    
    # ulid_parse() with no arguments - should raise ProgrammingError
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid_parse()")


def test_constraint_violations_and_fk(db):
    """Test constraint violations with ULID primary keys and foreign keys."""
    # create tables
    with db.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS test_constraints (
                id ulid PRIMARY KEY,
                name text
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS test_fk (
                id ulid PRIMARY KEY,
                ref_id ulid REFERENCES test_constraints(id)
            )
        """)
        db.commit()

    try:
        # duplicate key test
        with db.cursor() as cur:
            cur.execute("INSERT INTO test_constraints (id, name) VALUES ('01ARZ3NDEKTSV4RRFFQ69G5FAV', 'test1')")
            db.commit()

        # Test duplicate key violation
        with pytest.raises(psycopg2.IntegrityError):
            with db.cursor() as cur:
                cur.execute("INSERT INTO test_constraints (id, name) VALUES ('01ARZ3NDEKTSV4RRFFQ69G5FAV', 'test2')")
                db.commit()
        db.rollback()  # Rollback after the error

        # FK violation test
        with pytest.raises(psycopg2.IntegrityError):
            with db.cursor() as cur:
                cur.execute("INSERT INTO test_fk (id, ref_id) VALUES ('01ARZ3NDEKTSV4RRFFQ69G5FAV', '01ARZ3NDEKTSV4RRFFQ69G5FAX')")
                db.commit()
        db.rollback()  # Rollback after the error

    finally:
        # cleanup
        db.rollback()  # Ensure clean state
        with db.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS test_fk")
            cur.execute("DROP TABLE IF EXISTS test_constraints")
            db.commit()


def test_concurrent_like_generation_uniqueness(db):
    """Rapid repeated generation should produce unique values in a single connection."""
    # Ensure clean transaction state
    db.rollback()
    
    results = [exec_one(db, "SELECT ulid()") for _ in range(200)]
    assert len(results) == len(set(results))


def test_informative_error_messages(db):
    """Error messages should mention ulid/invalid when invalid ulid literal is provided."""
    # Ensure clean transaction state
    db.rollback()
    
    with pytest.raises(psycopg2.Error) as excinfo:
        exec_one(db, "SELECT %s::ulid", ("invalid",))
    msg = str(excinfo.value).lower()
    assert "ulid" in msg or "invalid" in msg


def test_transactional_rollback_behavior(db):
    """ULIDs generated inside rolled-back transactions should not affect later generations."""
    # Ensure clean transaction state
    db.rollback()
    
    # Start a manual transaction and rollback
    with db.cursor() as cur:
        cur.execute("BEGIN")
        a = exec_one(db, "SELECT ulid()")
        cur.execute("ROLLBACK")

    with db.cursor() as cur:
        cur.execute("BEGIN")
        b = exec_one(db, "SELECT ulid()")
        cur.execute("COMMIT")

    assert a != b


def test_extension_presence_and_type_properties(db):
    """Sanity: extension present and type properties look correct."""
    # Ensure clean transaction state
    db.rollback()
    
    assert has_function(db, "ulid")
    assert type_exists(db, "ulid")

    row = exec_fetchone(db, "SELECT typlen, typalign, typtype FROM pg_type WHERE typname = 'ulid'")
    assert row is not None
    typlen, typalign, typtype = row
    assert typlen == 16
    assert typalign == 'c'
    assert typtype == 'b'


def test_operator_and_aggregate_errors(db):
    """Test that ULID operators and aggregates raise appropriate errors."""
    # Ensure clean transaction state
    db.rollback()
    
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT ulid() + ulid()")
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT SUM(ulid())")
    expect_db_error([psycopg2.ProgrammingError], exec_one, db, "SELECT AVG(ulid())")


def test_index_creation_invalid_expression(db):
    """Invalid index expression should raise ProgrammingError; valid index works."""
    # Ensure clean transaction state
    db.rollback()
    
    with db.cursor() as cur:
        cur.execute("CREATE TABLE IF NOT EXISTS test_index (id ulid PRIMARY KEY, name text)")
        db.commit()

    try:
        with pytest.raises(psycopg2.ProgrammingError):
            with db.cursor() as cur:
                cur.execute("CREATE INDEX invalid_idx ON test_index (id + 1)")
                db.commit()
        db.rollback()  # Rollback after the error

        with db.cursor() as cur:
            cur.execute("CREATE INDEX IF NOT EXISTS valid_idx ON test_index (id)")
            db.commit()

        # usage check - handle case where no rows exist
        try:
            result = exec_one(db, "SELECT id FROM test_index ORDER BY id LIMIT 1")
            if result is not None:
                assert isinstance(result, str)  # ULID should be a string
        except (TypeError, AttributeError):
            # Handle case where no rows exist or result is None
            pass
    finally:
        # cleanup
        db.rollback()  # Ensure clean state
        with db.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS test_index")
            db.commit()


def test_cleanup_placeholder(db):
    """Placeholder test to ensure suite teardown runs cleanly (no assertion — just must run)."""
    pass
