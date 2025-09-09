"""
Centralized test configuration for ULID extension tests.
"""
import os
import psycopg2
import pytest

# Centralized database configuration
DB_CONFIG = {
    'host': os.getenv('PGHOST', 'localhost'),
    'port': int(os.getenv('PGPORT', '5432')),
    'database': os.getenv('PGDATABASE', 'postgres'),
    'user': os.getenv('PGUSER', 'postgres'),
    'password': os.getenv('PGPASSWORD', 'testpass')
}

def exec_one(conn_or_cursor, query, params=None):
    """Execute a single query and return the first result."""
    if hasattr(conn_or_cursor, 'cursor'):
        # It's a connection, create a cursor
        with conn_or_cursor.cursor() as cursor:
            cursor.execute(query, params)
            return cursor.fetchone()[0]
    else:
        # It's already a cursor
        conn_or_cursor.execute(query, params)
        return conn_or_cursor.fetchone()[0]

def exec_fetchone(conn_or_cursor, query, params=None):
    """Execute a query and return the first row."""
    if hasattr(conn_or_cursor, 'cursor'):
        # It's a connection, create a cursor
        with conn_or_cursor.cursor() as cursor:
            cursor.execute(query, params)
            return cursor.fetchone()
    else:
        # It's already a cursor
        conn_or_cursor.execute(query, params)
        return conn_or_cursor.fetchone()

def has_function(conn_or_cursor, function_name):
    """Check if a function exists in the database."""
    if hasattr(conn_or_cursor, 'cursor'):
        # It's a connection, create a cursor
        with conn_or_cursor.cursor() as cursor:
            cursor.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM pg_proc 
                    WHERE proname = %s
                )
            """, (function_name,))
            return cursor.fetchone()[0]
    else:
        # It's already a cursor
        conn_or_cursor.execute("""
            SELECT EXISTS(
                SELECT 1 FROM pg_proc 
                WHERE proname = %s
            )
        """, (function_name,))
        return conn_or_cursor.fetchone()[0]

def type_exists(conn_or_cursor, type_name):
    """Check if a type exists in the database."""
    if hasattr(conn_or_cursor, 'cursor'):
        # It's a connection, create a cursor
        with conn_or_cursor.cursor() as cursor:
            cursor.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM pg_type 
                    WHERE typname = %s
                )
            """, (type_name,))
            return cursor.fetchone()[0]
    else:
        # It's already a cursor
        conn_or_cursor.execute("""
            SELECT EXISTS(
                SELECT 1 FROM pg_type 
                WHERE typname = %s
            )
        """, (type_name,))
        return conn_or_cursor.fetchone()[0]

@pytest.fixture(scope="session")
def db():
    """Database connection fixture."""
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True  # Enable autocommit to avoid transaction issues
    yield conn
    conn.close()

@pytest.fixture(scope="session")
def ulid_functions_available(db):
    """Detect availability of key ULID functions and return a dict of booleans."""
    funcs = ["ulid", "ulid_random", "ulid_time", "ulid_parse",
             "ulid_batch", "ulid_random_batch"]
    availability = {}
    with db.cursor() as cursor:
        for func in funcs:
            availability[func] = has_function(cursor, func)
        availability['ulid_type'] = type_exists(cursor, 'ulid')
    return availability

@pytest.fixture(scope="session")
def objectid_functions_available(db):
    """Check if ObjectId functions are available."""
    with db.cursor() as cursor:
        return (
            has_function(cursor, 'objectid') and
            type_exists(cursor, 'objectid')
        )
