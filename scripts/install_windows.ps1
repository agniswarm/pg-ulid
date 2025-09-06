param(
  [string]$DestDir = ""
)

try {
  $bind = (& pg_config --bindir).Trim()
} catch {
  Write-Error "pg_config not found or failed. Ensure PostgreSQL is installed and pg_config is on PATH."
  exit 2
}

if ([string]::IsNullOrEmpty($DestDir)) {
  $target = $bind
} else {
  $target = Join-Path $DestDir $bind
}

# Create directory and copy exe
New-Item -ItemType Directory -Force -Path $target | Out-Null
$destPath = Join-Path $target 'ulid_generator.exe'
Try {
  Copy-Item -Force ulid_generator.exe -Destination $destPath
  Write-Host "Installed: $destPath"
} Catch {
  Write-Error "Failed to copy ulid_generator.exe to $destPath : $_"
  exit 3
}
