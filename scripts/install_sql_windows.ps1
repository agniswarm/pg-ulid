param(
    [string]$DestDir = "",
    [string]$SrcSql = "sql/ulid--1.0.0.sql",
    [string]$Ext = "ulid",
    [string]$Ver = "1.0.0"
)

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

# Resolve the source SQL path
$srcPath = Resolve-Path $SrcSql -ErrorAction SilentlyContinue
if (-not $srcPath) {
    Write-Error "SQL source '$SrcSql' not found."
    exit 3
}

$destSql = Join-Path $extDir ("$Ext--$Ver.sql")
# Read, substitute @BINDIR@ with the *server* bindir, and write out
try {
    (Get-Content $srcPath) -replace '@BINDIR@', $bind | Set-Content -Encoding UTF8 $destSql
    Write-Host "Installed SQL to: $destSql"
} catch {
    Write-Error "Failed to write substituted SQL to $destSql : $_"
    exit 4
}
