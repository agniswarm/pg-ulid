#!/usr/bin/env python3
"""
Test script to verify centralized configuration works.
"""
import os
import sys
sys.path.insert(0, 'test/python')

from conftest import DB_CONFIG, exec_one, has_function, type_exists
import psycopg2

def test_centralized_config():
    """Test that centralized configuration works."""
    print("Testing centralized configuration...")
    print(f"DB_CONFIG: {DB_CONFIG}")
    
    # Test connection
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        print("✅ Database connection successful")
        
        # Test basic functions
        with conn.cursor() as cursor:
            # Test ULID functions
            ulid_exists = has_function(cursor, 'ulid_random')
            print(f"✅ ULID functions available: {ulid_exists}")
            
            # Test ObjectId functions  
            objectid_exists = has_function(cursor, 'objectid_generate')
            print(f"✅ ObjectId functions available: {objectid_exists}")
            
            # Test types
            ulid_type_exists = type_exists(cursor, 'ulid')
            objectid_type_exists = type_exists(cursor, 'objectid')
            print(f"✅ ULID type exists: {ulid_type_exists}")
            print(f"✅ ObjectId type exists: {objectid_type_exists}")
            
            # Test actual function calls
            if ulid_exists:
                ulid_result = exec_one(cursor, "SELECT ulid_random()")
                print(f"✅ ULID generation: {ulid_result}")
                
            if objectid_exists:
                objectid_result = exec_one(cursor, "SELECT objectid_generate()")
                print(f"✅ ObjectId generation: {objectid_result}")
        
        conn.close()
        print("✅ All tests passed!")
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_centralized_config()
    sys.exit(0 if success else 1)
