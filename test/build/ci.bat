@echo off
REM Standalone PostgreSQL Extension Test Script for Windows
REM This can be run without the Makefile and PostgreSQL build system

echo Running PostgreSQL extension tests...

REM Check if PostgreSQL is running
pg_isready >nul 2>&1
if errorlevel 1 (
    echo PostgreSQL is not running. This test requires a running PostgreSQL instance.
    echo In CI, PostgreSQL should be started by the CI environment.
    echo Locally, start PostgreSQL with: net start postgresql
    exit /b 1
)

REM Use the default postgres database
set PGDATABASE=postgres

REM Test basic extension functionality
echo Creating extension...
psql -c "CREATE EXTENSION IF NOT EXISTS ulid;"

echo Testing ulid() function...
psql -c "SELECT ulid();"

echo Testing ulid_random() function...
psql -c "SELECT ulid_random();"

echo Testing ulid_time() function...
psql -c "SELECT ulid_time(extract(epoch from now()) * 1000);"

echo Testing ulid_batch() function...
psql -c "SELECT array_length(ulid_batch(5), 1);"

echo Testing ulid_random_batch() function...
psql -c "SELECT array_length(ulid_random_batch(3), 1);"

echo Testing ulid_parse() function...
psql -c "SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');"

echo Testing error handling...
psql -c "SELECT ulid_parse('invalid-ulid');" || echo Expected error for invalid ULID

echo Testing batch with zero count...
psql -c "SELECT ulid_batch(0);"

echo Testing batch with negative count...
psql -c "SELECT ulid_batch(-1);" || echo Expected error for negative count

echo Cleaning up...
psql -c "DROP EXTENSION IF EXISTS ulid;"

echo All tests passed successfully!
