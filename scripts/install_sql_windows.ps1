<#
scripts/install_sql_windows.ps1

Installs extension SQL and control file into PostgreSQL shared extension dir on Windows.
Writes substituted SQL as UTF-8 WITHOUT BOM so Postgres doesn't choke on an invisible BOM char.
#>

param(
  [string]$DestDir = "",
  [string]$SrcSql = "sql/ulid--1.0.0.sql",
  [string]$Ext = "ulid",
  [string]$Ver = "1.0.0"
)

# Helper: write UTF8 without BOM
function Write-Utf8-NoBOM {
  param (
    [string]$Path,
    [string]$Content
  )
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
  [System.IO.File]::WriteAllBytes($Path, $bytes)
}

# Get pg sharedir and bindir
try {
  $share = (& pg_config --sharedir).Trim()
  $bind = (& pg_config --bindir).Trim()
} catch {
  Write-Error "pg_config not found or failed. Ensure PostgreSQL is installed and pg_config is on PATH."
  exit 2
}

if ([string]::IsNullOrEmpty($DestDir)) {
  $instDir = $share
} else {
  $instDir = Join-Path $DestDir $share
}

$extDir = Join-Path $instDir 'extension'
New-Item -ItemType Directory -Force -Path $extDir | Out-Null

# Install control file (expected at ./ulid.control)
$controlSrc = Join-Path (Get-Location) "$Ext.control"
if (-not (Test-Path $controlSrc)) {
  Write-Warning "Control file '$controlSrc' not found in repo. Tests will fail unless control file exists."
} else {
  $controlDest = Join-Path $extDir "$Ext.control"
  Copy-Item -Force $controlSrc -Destination $controlDest
  Write-Host "Installed control file: $controlDest"
}

# Find SQL source: try explicit param, else pick first sql/ulid--*.sql
$srcSqlPath = Resolve-Path $SrcSql -ErrorAction SilentlyContinue
if (-not $srcSqlPath) {
  $candidates = Get-ChildItem -Path sql -Filter "$Ext--*.sql" -File -ErrorAction SilentlyContinue | Sort-Object Name
  if ($candidates -and $candidates.Count -gt 0) {
    $srcSqlPath = $candidates[0].FullName
    Write-Host "Using discovered SQL source: $srcSqlPath"
  } else {
    Write-Warning "No SQL file found under sql/ matching '$Ext--*.sql'."
  }
}

if ($srcSqlPath) {
  # Read raw SQL (preserve line endings)
  $raw = Get-Content $srcSqlPath -Raw

  # Determine program path to substitute:
  # On Windows use ulid_generator.exe; use forward slashes to be safe in SQL COPY FROM PROGRAM
  $prog = (Join-Path $bind 'ulid_generator.exe') -replace '\\','/'
  # Also support replacing instances that use backslashes in SQL
  $raw = $raw -replace '@BINDIR@/ulid_generator', $prog
  $raw = $raw -replace '@BINDIR@\\ulid_generator', $prog
  $raw = $raw -replace '@BINDIR@', ($bind -replace '\\','/')

  $destSql = Join-Path $extDir ("$Ext--$Ver.sql")

  try {
    Write-Utf8-NoBOM -Path $destSql -Content $raw
    Write-Host "Installed substituted SQL to: $destSql (UTF-8 without BOM)"
  } catch {
    Write-Error "Failed to write substituted SQL to $destSql : $_"
    exit 4
  }
}

# Copy additional sql files (upgrade scripts) if any, as-is (preserve bytes)
Get-ChildItem -Path sql -Filter "$Ext--*.sql" -File -ErrorAction SilentlyContinue | ForEach-Object {
  $name = $_.Name
  $dest = Join-Path $extDir $name
  if ($_.FullName -ne $srcSqlPath) {
    Copy-Item -Force $_.FullName -Destination $dest
    Write-Host "Copied additional SQL: $dest"
  }
}

# Print installed files (diagnostic)
Write-Host ""
Write-Host "Installed extension directory contents:"
Get-ChildItem -Path $extDir -File -ErrorAction SilentlyContinue | ForEach-Object { Write-Host " - " $_.Name }
Write-Host ""
