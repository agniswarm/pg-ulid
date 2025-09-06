param(
  [string]$DestDir = "",
  [string]$SrcSql = "sql/ulid--1.0.0.sql",
  [string]$Ext = "ulid",
  [string]$Ver = "1.0.0"
)

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

# Find a SQL file if the given SrcSql is not present; prefer wildcard match
$srcSqlPath = Resolve-Path $SrcSql -ErrorAction SilentlyContinue
if (-not $srcSqlPath) {
  # try to find any sql/ulid--*.sql
  $candidates = Get-ChildItem -Path sql -Filter "$Ext--*.sql" -File -ErrorAction SilentlyContinue | Sort-Object Name
  if ($candidates -and $candidates.Count -gt 0) {
    $srcSqlPath = $candidates[0].FullName
    Write-Host "Using discovered SQL source: $srcSqlPath"
  } else {
    Write-Warning "No SQL file found under sql/ matching '$Ext--*.sql'."
  }
}

if ($srcSqlPath) {
  $destSql = Join-Path $extDir ("$Ext--$Ver.sql")
  try {
    (Get-Content $srcSqlPath) -replace '@BINDIR@', $bind | Set-Content -Encoding UTF8 $destSql
    Write-Host "Installed substituted SQL to: $destSql"
  } catch {
    Write-Error "Failed to write substituted SQL to $destSql : $_"
    exit 4
  }
}

# Copy additional sql files (upgrade scripts) if present
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
