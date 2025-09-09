# test_ulid_pytest.py
"""
Pytest-style tests for ULID PostgreSQL extension.

Usage:
    export PGHOST=localhost
    export PGDATABASE=testdb
    export PGUSER=postgres
    export PGPASSWORD=""
    pytest -q test_ulid_pytest.py

The suite will skip tests that rely on missing functions (ulid, ulid_random, etc.).
"""

from datetime import datetime
import pytest
from conftest import exec_one, has_function, type_exists



def test_basic_generation_and_lengths(db, ulid_functions_available):
    # Skip if basic ulid function missing
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() function not available in database")

    val = exec_one(db, "SELECT ulid()::text")
    assert val is not None, "ulid() returned NULL"
    assert isinstance(val, str), "ulid() did not return text"
    assert len(val) == 26, f"Expected length 26 for ulid(), got {len(val)}"


@pytest.mark.parametrize("fn", ["ulid_random"])
def test_other_generators_nonnull_and_length(db, ulid_functions_available, fn):
    if not ulid_functions_available.get(fn):
        pytest.skip(f"{fn}() not available in database")
    val = exec_one(db, f"SELECT {fn}()::text")
    assert val is not None, f"{fn}() returned NULL"
    assert isinstance(val, str)
    assert len(val) == 26, f"{fn}() length expected 26, got {len(val)}"


def test_ulid_time_and_parse(db, ulid_functions_available):
    if not ulid_functions_available.get("ulid_time"):
        pytest.skip("ulid_time() not available in database")
    if not ulid_functions_available.get("ulid_parse"):
        pytest.skip("ulid_parse() not available in database")

    # specific timestamp: 2022-01-01 00:00:00 UTC -> 1640995200000 ms
    ut = exec_one(db, "SELECT ulid_time(1640995200000)::text")
    assert ut is not None
    assert len(ut) == 26  # canonical form is 26 chars

    known = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    # Fetch both the canonical/text form and the binary form produced by parsing
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                ulid_parse(%s)::text AS parsed_text,
                ulid_parse(%s)::bytea AS parsed_bytes,
                (%s::ulid)::bytea AS direct_bytes
            """,
            (known, known, known),
        )
        row = cur.fetchone()

    assert row is not None, "query returned no row"
    parsed_text, parsed_bytes, direct_bytes = row

    # The canonical textual representation may differ (encoders normalize to 26 chars),
    # but the underlying 16 bytes must be identical (lossless binary round-trip).
    assert len(parsed_text) == 26
    assert parsed_bytes == direct_bytes, (
        f"Binary mismatch: parsed_bytes={parsed_bytes!r} direct_bytes={direct_bytes!r}"
    )


def test_readme_basic_generation(db, ulid_functions_available):
    """Basic ULID generation as documented in README."""
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() function not available in database")
    
    # Basic generation
    assert exec_one(db, "SELECT ulid()") is not None
    assert exec_one(db, "SELECT ulid_random()") is not None
    assert exec_one(db, "SELECT ulid_random()") is not None


def test_readme_time_based_generation(db, ulid_functions_available):
    """Time-based ULID generation as documented in README."""
    if not ulid_functions_available.get("ulid_time"):
        pytest.skip("ulid_time() not available in database")
    if not ulid_functions_available.get("ulid_generate_with_timestamp"):
        pytest.skip("ulid_generate_with_timestamp() not available in database")
    
    # Time-based generation
    assert exec_one(db, "SELECT ulid_time(1609459200000)") is not None
    assert exec_one(db, "SELECT ulid_generate_with_timestamp(1609459200000)") is not None


def test_readme_parsing_and_timestamp_extraction(db, ulid_functions_available):
    """Parsing and timestamp extraction as documented in README."""
    if not ulid_functions_available.get("ulid_parse"):
        pytest.skip("ulid_parse() not available in database")
    if not ulid_functions_available.get("ulid_timestamp"):
        pytest.skip("ulid_timestamp() not available in database")
    
    # Parsing and timestamp extraction
    assert exec_one(db, "SELECT ulid_parse('01ARZ3NDEKTSV4RRFFQ69G5FAV')") is not None
    ts_ms = exec_one(db, "SELECT ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV')")
    assert ts_ms is not None and isinstance(ts_ms, (int, float))


def test_readme_batch_generation(db, ulid_functions_available):
    """Batch generation as documented in README."""
    if not ulid_functions_available.get("ulid_batch"):
        pytest.skip("ulid_batch() not available in database")
    if not ulid_functions_available.get("ulid_random_batch"):
        pytest.skip("ulid_random_batch() not available in database")
    
    # Batch generation
    assert exec_one(db, "SELECT array_length(ulid_batch(5), 1)") == 5
    assert exec_one(db, "SELECT array_length(ulid_random_batch(3), 1)") == 3


def test_readme_casting_operations(db, ulid_functions_available):
    """Casting operations as documented in README."""
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() function not available in database")
    
    # Text casting
    assert exec_one(db, "SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid") is not None
    
    # ULID to text
    text_val = exec_one(db, "SELECT ulid()::text")
    assert text_val is not None and isinstance(text_val, str) and len(text_val) == 26
    
    # Timestamp casting
    assert exec_one(db, "SELECT '2023-09-15 12:00:00'::timestamp::ulid") is not None
    
    # ULID to timestamp
    ts_val = exec_one(db, "SELECT ulid()::timestamp")
    assert ts_val is not None and isinstance(ts_val, datetime)
    
    # Other casting operations
    assert exec_one(db, "SELECT ulid()::timestamptz") is not None
    assert exec_one(db, "SELECT ulid()::uuid") is not None
    assert exec_one(db, "SELECT '550e8400-e29b-41d4-a716-446655440000'::uuid::ulid") is not None


def test_uniqueness_small_batch(db, ulid_functions_available):
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() not available in database")
    q = """
    WITH test_ulids AS (
      SELECT ulid()::text AS u
      FROM generate_series(1, 100)
    )
    SELECT (COUNT(*) = COUNT(DISTINCT u))::boolean FROM test_ulids
    """
    all_unique = exec_one(db, q)
    assert all_unique is True


def test_batch_generation_and_uniqueness(db, ulid_functions_available):
    if not ulid_functions_available.get("ulid_batch"):
        pytest.skip("ulid_batch() not available in database")
    count = exec_one(db, "SELECT array_length(ulid_batch(5), 1)")
    assert count == 5

    # uniqueness check
    if not ulid_functions_available.get("ulid_batch"):
        pytest.skip("ulid_batch() not available in database")
    unique_ok = exec_one(
        db,
        """
        WITH batch_test AS (
            SELECT unnest(ulid_batch(10))::text AS u
        )
        SELECT (COUNT(*) = COUNT(DISTINCT u))::boolean FROM batch_test
        """,
    )
    assert unique_ok is True


def test_generators_produce_different_values(db, ulid_functions_available):
    # We require ulid and at least one other generator for a meaningful test
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() not available in database")
    if not ulid_functions_available.get("ulid_random"):
        pytest.skip("ulid_random() not available in database")

    # Compare to ulid_random
    different = exec_one(db, "SELECT (ulid()::text <> ulid_random()::text)::boolean")
    assert different is True


def test_length_bounds(db, ulid_functions_available):
    if not ulid_functions_available.get("ulid"):
        pytest.skip("ulid() not available in database")
    length = exec_one(db, "SELECT length(ulid()::text)")
    assert length > 20
    assert length < 30


def test_text_equality_and_consecutive_difference(db):
    # Parsing/casting equality test uses ulid cast; skip if type/extension not present
    try:
        eq = exec_one(db, "SELECT ('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid)::boolean")
    except Exception:
        pytest.skip("ulid type or casting not available in database for equality test")
    assert eq is True

    # Consecutive ulid() differentiation
    try:
        diff = exec_one(db, "SELECT (ulid()::text <> ulid()::text)::boolean")
    except Exception:
        pytest.skip("ulid() not available for consecutive difference check")
    assert diff is True



def test_required_ulid_functions_and_types_present(db):
    """Fail early if required ULID functions or the ulid type are missing."""
    required_funcs = [
        "ulid",
        "ulid_random",
        "ulid_time",
        "ulid_parse",
        "ulid_batch",
        "ulid_random_batch",
        "ulid_timestamp",
        "ulid_generate_with_timestamp",
    ]
    with db.cursor() as cursor:
        missing = [f for f in required_funcs if not has_function(cursor, f)]

        if not type_exists(cursor, "ulid"):
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
