#!/usr/bin/env python3
"""
Test database connection and basic ULID functionality
"""

import psycopg2
import sys

def test_connection():
    """Test database connection"""
    conn = psycopg2.connect(
        host="localhost",
        database="testdb",
        user="postgres",
        password="testpass"
    )
    print("✅ Database connection successful")
    
    cur = conn.cursor()
    
    # Test ULID extension
    cur.execute("SELECT ulid() as test_ulid")
    result = cur.fetchone()
    assert result[0] is not None, "ULID extension not working"
    print("✅ ULID extension is working")
    print(f"   Generated ULID: {result[0]}")
        
    cur.close()
    conn.close()

if __name__ == "__main__":
    try:
        test_connection()
        print("\n🎉 Ready to run tests!")
        sys.exit(0)
    except Exception as e:
        print(f"\n💥 Setup required before running tests: {e}")
        sys.exit(1)
