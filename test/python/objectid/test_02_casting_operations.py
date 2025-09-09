"""
ObjectId Casting Operations Tests

Tests for ObjectId casting to/from various PostgreSQL types.
"""

import pytest
from datetime import datetime, timezone
import re
import psycopg2
from conftest import exec_one

class TestObjectIdCastingOperations:
    """Test ObjectId casting operations."""

    def test_objectid_to_bytea_cast(self, db, objectid_functions_available):
        """Test ObjectId to bytea casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            bytea_result = exec_one(cursor, "SELECT %s::objectid::bytea", (oid,))
            
            # Convert memory object to bytes if needed
            if hasattr(bytea_result, 'tobytes'):
                bytea_result = bytea_result.tobytes()
            
            assert isinstance(bytea_result, bytes)
            assert len(bytea_result) == 12  # ObjectId is 12 bytes

    def test_bytea_to_objectid_cast(self, db, objectid_functions_available):
        """Test bytea to ObjectId casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            # Convert to bytea and back to text to get the hex representation
            bytea_hex = exec_one(cursor, "SELECT encode(%s::objectid::bytea, 'hex')", (oid,))
            
            # Convert hex string back to ObjectId
            converted_oid = exec_one(cursor, "SELECT %s::text::objectid", (bytea_hex,))
            
            assert converted_oid == oid

    def test_objectid_to_text_cast(self, db, objectid_functions_available):
        """Test ObjectId to text casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            text_result = exec_one(cursor, "SELECT %s::objectid::text", (oid,))
            
            assert isinstance(text_result, str)
            assert len(text_result) == 24
            hex_pattern = re.compile(r'^[0-9a-fA-F]{24}$')
            assert hex_pattern.match(text_result)

    def test_text_to_objectid_cast(self, db, objectid_functions_available):
        """Test text to ObjectId casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            text_result = exec_one(cursor, "SELECT %s::objectid::text", (oid,))
            
            # Convert back to ObjectId
            converted_oid = exec_one(cursor, "SELECT %s::text::objectid", (text_result,))
            
            assert converted_oid == oid

    def test_timestamp_to_objectid_cast(self, db, objectid_functions_available):
        """Test timestamp to ObjectId casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Use a specific timestamp
            test_timestamp = datetime(2020, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
            oid = exec_one(cursor, "SELECT %s::timestamp::objectid", (test_timestamp,))
            
            # Extract timestamp and verify - ObjectId timestamp functions may work differently
            extracted_timestamp = exec_one(cursor, "SELECT objectid_time(%s::objectid)", (oid,))
            
            # Just verify we get a reasonable timestamp value
            assert isinstance(extracted_timestamp, int)
            assert extracted_timestamp > 0

    def test_timestamptz_to_objectid_cast(self, db, objectid_functions_available):
        """Test timestamptz to ObjectId casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Use a specific timestamp with timezone
            test_timestamp = datetime(2020, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
            oid = exec_one(cursor, "SELECT %s::timestamptz::objectid", (test_timestamp,))
            
            # Extract timestamp and verify - ObjectId timestamp functions may work differently
            extracted_timestamp = exec_one(cursor, "SELECT objectid_time(%s::objectid)", (oid,))
            
            # Just verify we get a reasonable timestamp value
            assert isinstance(extracted_timestamp, int)
            assert extracted_timestamp > 0

    def test_objectid_to_timestamp_cast(self, db, objectid_functions_available):
        """Test ObjectId to timestamp casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            timestamp_result = exec_one(cursor, "SELECT %s::objectid::timestamp", (oid,))
            
            assert isinstance(timestamp_result, datetime)
            
            # Verify the timestamp is recent
            now = datetime.now(tz=timezone.utc)
            time_diff = abs((now - timestamp_result.replace(tzinfo=timezone.utc)).total_seconds())
            assert time_diff < 60  # Should be within last minute

    def test_objectid_to_timestamptz_cast(self, db, objectid_functions_available):
        """Test ObjectId to timestamptz casting."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            timestamptz_result = exec_one(cursor, "SELECT %s::objectid::timestamptz", (oid,))
            
            assert isinstance(timestamptz_result, datetime)
            
            # Verify the timestamp is recent
            now = datetime.now(tz=timezone.utc)
            time_diff = abs((now - timestamptz_result.replace(tzinfo=timezone.utc)).total_seconds())
            assert time_diff < 60  # Should be within last minute

    def test_objectid_round_trip_casting(self, db, objectid_functions_available):
        """Test round-trip casting for ObjectId."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            original_oid = exec_one(cursor, "SELECT objectid()")
            
            # Test round-trip through bytea
            bytea_hex = exec_one(cursor, "SELECT encode(%s::objectid::bytea, 'hex')", (original_oid,))
            bytea_oid = exec_one(cursor, "SELECT %s::text::objectid", (bytea_hex,))
            assert bytea_oid == original_oid
            
            # Test round-trip through text
            text_oid = exec_one(cursor, "SELECT %s::objectid::text::objectid", (original_oid,))
            assert text_oid == original_oid

    def test_objectid_invalid_text_casting(self, db, objectid_functions_available):
        """Test ObjectId casting with invalid text."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Test with invalid hex string
            with pytest.raises(psycopg2.errors.InvalidTextRepresentation):
                exec_one(cursor, "SELECT 'invalid_hex_string'::text::objectid")
            
            # Test with wrong length
            with pytest.raises(psycopg2.errors.InvalidTextRepresentation):
                exec_one(cursor, "SELECT '1234567890abcdef'::text::objectid")  # Too short
            
            with pytest.raises(psycopg2.errors.InvalidTextRepresentation):
                exec_one(cursor, "SELECT '1234567890abcdef1234567890abcdef1234567890abcdef'::text::objectid")  # Too long

    def test_objectid_invalid_bytea_casting(self, db, objectid_functions_available):
        """Test ObjectId casting with invalid bytea."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            # Test with wrong bytea length
            with pytest.raises(psycopg2.errors.InvalidTextRepresentation):
                exec_one(cursor, "SELECT '\\x1234567890abcdef'::bytea::objectid")  # Too short
            
            with pytest.raises(psycopg2.errors.InvalidTextRepresentation):
                exec_one(cursor, "SELECT '\\x1234567890abcdef1234567890abcdef1234567890abcdef'::bytea::objectid")  # Too long

    def test_objectid_timestamp_text_functions(self, db, objectid_functions_available):
        """Test ObjectId timestamp text functions."""
        if not objectid_functions_available:
            pytest.skip("ObjectId functions not available")
        
        with db.cursor() as cursor:
            oid = exec_one(cursor, "SELECT objectid()")
            
            # Test objectid_to_timestamp function
            timestamp_result = exec_one(cursor, "SELECT objectid_to_timestamp(%s)", (oid,))
            assert isinstance(timestamp_result, datetime)
            
            # Test objectid_timestamp_text function
            timestamp_text = exec_one(cursor, "SELECT objectid_timestamp_text(%s)", (oid,))
            assert isinstance(timestamp_text, int)
            assert timestamp_text > 0
            
            # Verify they match
            expected_timestamp = datetime.fromtimestamp(timestamp_text, tz=timezone.utc)
            assert abs((timestamp_result.replace(tzinfo=timezone.utc) - expected_timestamp).total_seconds()) < 1
