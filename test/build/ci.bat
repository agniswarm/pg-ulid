@echo off
setlocal enabledelayedexpansion

REM Comprehensive PostgreSQL Extension Test Script for Windows
REM Runs the full SQL test suite from test/sql/ directory
echo Running comprehensive PostgreSQL extension tests...

REM Check if PostgreSQL is running
pg_isready >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo PostgreSQL is not running. This test requires a running PostgreSQL instance.
    echo In CI, PostgreSQL should be started by the CI environment.
    echo Locally, start PostgreSQL with: net start postgresql
    exit /b 1
)

REM Use the default postgres database
set PGDATABASE=postgres

REM Create test database
echo Creating test database...
psql -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE testdb;" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: testdb already exists or creation failed, continuing...
)

REM Switch to test database
set PGDATABASE=testdb

REM Helper: run a psql command with ON_ERROR_STOP
REM Usage: CALL :psql_run "SQL" varToCapture
:psql_run
set "SQL=%~1"
set "OUTVAR=%~2"
if "%OUTVAR%"=="" (
  REM no capture, just run and check
  psql -v ON_ERROR_STOP=1 -q -c "%SQL%"
  if %ERRORLEVEL% NEQ 0 (
    exit /b 1
  )
  goto :eof
) else (
  for /f "usebackq delims=" %%R in (`psql -v ON_ERROR_STOP=1 -q -t -A -c "%SQL%" 2^>^&1`) do (
    set "%OUTVAR%=%%R"
  )
  if %ERRORLEVEL% NEQ 0 (
    exit /b 1
  )
  goto :eof
)

REM Create extension
echo Creating extension...
call :psql_run "CREATE EXTENSION IF NOT EXISTS ulid;"
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: Failed to create extension. Make sure it's properly installed.
  echo Check that the extension files are in the correct location:
  echo   - %PGSHARE%\extension\ulid.control
  echo   - %PGSHARE%\extension\ulid--0.1.1.sql
  exit /b 1
)

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0
set PROJECT_ROOT=%SCRIPT_DIR%..\..
set SQL_TEST_DIR=%PROJECT_ROOT%\test\sql

REM Check if SQL test directory exists
if not exist "%SQL_TEST_DIR%" (
  echo ERROR: SQL test directory not found: %SQL_TEST_DIR%
  exit /b 1
)

REM Load pgTAP functions first
echo Loading pgTAP functions...
psql -v ON_ERROR_STOP=1 -q -f "%SQL_TEST_DIR%\pgtap_functions.sql"
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: Failed to load pgTAP functions
  exit /b 1
)

REM Run all SQL test files
echo Running comprehensive SQL tests...
set FAILED_TESTS=0

REM Test files array
set TEST_FILES=01_basic_functionality.sql 02_casting_operations.sql 03_monotonic_generation.sql 04_stress_tests.sql 05_binary_storage.sql 06_database_operations.sql 07_error_handling.sql

for %%f in (%TEST_FILES%) do (
  set TEST_FILE=%%f
  set TEST_PATH=%SQL_TEST_DIR%\%%f
  if exist "!TEST_PATH!" (
    echo Running !TEST_FILE!...
    psql -v ON_ERROR_STOP=1 -q -f "!TEST_PATH!"
    if !ERRORLEVEL! NEQ 0 (
      echo ERROR: Test !TEST_FILE! failed
      set /a FAILED_TESTS+=1
    ) else (
      echo ✅ !TEST_FILE! passed
    )
  ) else (
    echo WARNING: Test file !TEST_FILE! not found, skipping
  )
)

REM Clean up
echo Cleaning up...
psql -v ON_ERROR_STOP=1 -q -c "DROP EXTENSION IF EXISTS ulid;" >nul 2>&1
psql -v ON_ERROR_STOP=1 -q -c "DROP DATABASE IF EXISTS testdb;" >nul 2>&1

REM Report results
if %FAILED_TESTS% EQU 0 (
  echo 🎉 All tests passed successfully!
  endlocal
  exit /b 0
) else (
  echo ❌ %FAILED_TESTS% test(s) failed
  endlocal
  exit /b 1
)
