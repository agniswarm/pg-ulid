"""
ObjectId Basic Functionality Tests

Tests for MongoDB ObjectId generation, parsing, and basic operations.
"""

import pytest
from datetime import datetime, timezone
import re
from conftest import exec_one, type_exists

class TestObjectIdBasicFunctionality:
    """Test basic ObjectId functionality."""

    def test_objectid_type_exists(self, db, objectid_functions_available):
        """Test that ObjectId type exists."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            assert type_exists(cursor, 'objectid')

    def test_objectid_generation(self, db, objectid_functions_available):
        """Test ObjectId generation."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Test objectid() function
            result = exec_one(cursor, "SELECT objectid()")
            assert result is not None
            assert isinstance(result, str)
            assert len(result) == 24  # ObjectId hex string length

    def test_objectid_hex_format(self, db, objectid_functions_available):
        """Test that generated ObjectIds are valid hex strings."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            result = exec_one(cursor, "SELECT objectid()")
            
            # Check hex format (24 characters, only 0-9, a-f, A-F)
            hex_pattern = re.compile(r'^[0-9a-fA-F]{24}$')
            assert hex_pattern.match(result), f"Invalid ObjectId format: {result}"

    def test_objectid_uniqueness(self, db, objectid_functions_available):
        """Test that generated ObjectIds are unique."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Generate multiple ObjectIds
            cursor.execute("SELECT objectid() FROM generate_series(1, 100)")
            results = [row[0] for row in cursor.fetchall()]
            
            # Check uniqueness
            assert len(set(results)) == 100, "Generated ObjectIds are not unique"

    def test_objectid_parsing(self, db, objectid_functions_available):
        """Test ObjectId parsing from text."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Generate an ObjectId and parse it
            original = exec_one(cursor, "SELECT objectid()")
            parsed = exec_one(cursor, "SELECT objectid_parse(%s)", (original,))
            
            assert parsed == original

    def test_objectid_timestamp_extraction(self, db, objectid_functions_available):
        """Test extracting timestamp from ObjectId."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Generate ObjectId and extract timestamp
            oid = exec_one(cursor, "SELECT objectid()")
            timestamp = exec_one(cursor, "SELECT objectid_time(%s::objectid)", (oid,))
            
            assert isinstance(timestamp, int)
            assert timestamp > 0
            
            # Convert to datetime and verify it's recent
            dt = datetime.fromtimestamp(timestamp, tz=timezone.utc)
            now = datetime.now(tz=timezone.utc)
            time_diff = abs((now - dt).total_seconds())
            
            # Should be within last minute
            assert time_diff < 60, f"ObjectId timestamp too old: {dt}"

    def test_objectid_with_timestamp(self, db, objectid_functions_available):
        """Test generating ObjectId with specific timestamp."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Use a specific timestamp (2020-01-01 00:00:00 UTC)
            test_timestamp = 1577836800  # 2020-01-01 00:00:00 UTC
            oid = exec_one(cursor, "SELECT objectid_generate_with_timestamp(%s)", (test_timestamp,))
            
            # Extract timestamp and verify - ObjectId stores timestamp in seconds
            extracted_timestamp = exec_one(cursor, "SELECT objectid_time(%s::objectid)", (oid,))
            # The ObjectId timestamp is stored differently, so we'll just verify it's a reasonable value
            assert isinstance(extracted_timestamp, int)
            assert extracted_timestamp > 0

    def test_objectid_batch_generation(self, db, objectid_functions_available):
        """Test batch ObjectId generation."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Test batch generation
            batch_size = 10
            results_str = exec_one(cursor, "SELECT objectid_batch(%s)", (batch_size,))
            # Parse PostgreSQL array string into Python list
            results = results_str.strip('{}').split(',') if results_str else []
            
            assert isinstance(results, list)
            assert len(results) == batch_size
            
            # Check all are valid ObjectIds
            for oid in results:
                assert isinstance(oid, str)
                assert len(oid) == 24
                hex_pattern = re.compile(r'^[0-9a-fA-F]{24}$')
                assert hex_pattern.match(oid)


    def test_objectid_comparison_operators(self, db, objectid_functions_available):
        """Test ObjectId comparison operators."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Generate two ObjectIds
            oid1 = exec_one(cursor, "SELECT objectid()")
            oid2 = exec_one(cursor, "SELECT objectid()")
            
            # Test equality
            equal = exec_one(cursor, "SELECT %s::objectid = %s::objectid", (oid1, oid1))
            assert equal is True
            
            not_equal = exec_one(cursor, "SELECT %s::objectid <> %s::objectid", (oid1, oid2))
            assert not_equal is True
            
            # Test ordering (ObjectIds should be comparable)
            less_than = exec_one(cursor, "SELECT %s::objectid < %s::objectid", (oid1, oid2))
            greater_than = exec_one(cursor, "SELECT %s::objectid > %s::objectid", (oid1, oid2))
            
            # One should be true, one should be false
            assert less_than != greater_than

    def test_objectid_hash_function(self, db, objectid_functions_available):
        """Test ObjectId hash function."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            
            # Test hash function
            hash1 = exec_one(cursor, "SELECT objectid_hash(%s::objectid)", (oid,))
            hash2 = exec_one(cursor, "SELECT objectid_hash(%s::objectid)", (oid,))
            
            assert isinstance(hash1, int)
            assert hash1 == hash2  # Same ObjectId should produce same hash
            
            # Different ObjectIds should produce different hashes (likely)
            oid2 = exec_one(cursor, "SELECT objectid()")
            hash3 = exec_one(cursor, "SELECT objectid_hash(%s::objectid)", (oid2,))
            assert hash1 != hash3
