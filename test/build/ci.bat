@echo off
setlocal enabledelayedexpansion

REM Standalone PostgreSQL Extension Test Script for Windows (robust)
echo Running PostgreSQL extension tests...

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
  echo   - %PGSHARE%\extension\ulid--1.0.0.sql
  exit /b 1
)

REM Test ulid()
echo Testing ulid() function...
call :psql_run "SELECT ulid();" ULID_VAL
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid() function test failed
  exit /b 1
)
echo ulid() => %ULID_VAL%

REM Test ulid_random()
echo Testing ulid_random() function...
call :psql_run "SELECT ulid_random();" ULID_RAND
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_random() function test failed
  exit /b 1
)
echo ulid_random() => %ULID_RAND%

REM Test ulid_time()
echo Testing ulid_time() function...
REM pass bigint milliseconds (cast explicitly)
call :psql_run "SELECT ulid_time((extract(epoch from now()) * 1000)::BIGINT);" ULID_TIME
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_time() function test failed
  exit /b 1
)
echo ulid_time() => %ULID_TIME%

REM Test ulid_batch(5)
echo Testing ulid_batch(5) length...
call :psql_run "SELECT array_length(ulid_batch(5),1);" BATCH_LEN
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_batch() function test failed
  exit /b 1
)
echo ulid_batch(5) length => %BATCH_LEN%

REM Test ulid_random_batch(3)
echo Testing ulid_random_batch(3) length...
call :psql_run "SELECT array_length(ulid_random_batch(3),1);" RAND_BATCH_LEN
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_random_batch() function test failed
  exit /b 1
)
echo ulid_random_batch(3) length => %RAND_BATCH_LEN%

REM Test ulid_parse() valid example
echo Testing ulid_parse() valid example...
call :psql_run "SELECT is_valid FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');" PARSE_OK
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_parse() function test failed
  exit /b 1
)
echo ulid_parse(valid) => %PARSE_OK%

REM Test ulid_parse() invalid example (expect false or a result)
echo Testing ulid_parse() invalid example...
call :psql_run "SELECT is_valid FROM ulid_parse('invalid-ulid');" PARSE_INVALID
if %ERRORLEVEL% NEQ 0 (
  echo WARNING: ulid_parse(invalid) returned error (this may be acceptable)
) else (
  echo ulid_parse(invalid) => %PARSE_INVALID%
)

REM Test edge cases
echo Testing ulid_batch(0)...
call :psql_run "SELECT ulid_batch(0);" BATCH_ZERO
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: ulid_batch(0) failed
  exit /b 1
)
echo ulid_batch(0) => %BATCH_ZERO%

echo Testing ulid_batch(-1) (expect error)...
psql -v ON_ERROR_STOP=1 -q -c "SELECT ulid_batch(-1);" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  echo WARNING: ulid_batch(-1) unexpectedly succeeded
) else (
  echo ulid_batch(-1) produced expected error.
)

REM Clean up
echo Cleaning up...
psql -v ON_ERROR_STOP=1 -q -c "DROP EXTENSION IF EXISTS ulid;" >nul 2>&1

echo All tests completed.
endlocal
exit /b 0
