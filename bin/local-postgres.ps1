param(
  [int]$Port = 55432
)

$ErrorActionPreference = "Stop"

$pgBin = if ($env:PG_BIN) { $env:PG_BIN } else { "C:\Program Files\PostgreSQL\17\bin" }
$initdb = Join-Path $pgBin "initdb.exe"
$pgCtl = Join-Path $pgBin "pg_ctl.exe"
$createdb = Join-Path $pgBin "createdb.exe"
$psql = Join-Path $pgBin "psql.exe"
$dataDir = Join-Path $PSScriptRoot "..\..\artifacts\backend\tmp\local-postgres"
$logFile = Join-Path $PSScriptRoot "..\..\artifacts\backend\tmp\local-postgres.log"

if (!(Test-Path $initdb) -or !(Test-Path $pgCtl) -or !(Test-Path $createdb) -or !(Test-Path $psql)) {
  throw "PostgreSQL tools were not found in $pgBin. Set PG_BIN to your PostgreSQL bin directory."
}

New-Item -ItemType Directory -Force -Path (Split-Path $dataDir) | Out-Null

$serverReady = $false
& $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -c "SELECT 1" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  $serverReady = $true
} else {
  if (!(Test-Path (Join-Path $dataDir "PG_VERSION"))) {
    & $initdb -D $dataDir -U postgres -A trust --encoding=UTF8
  }

  & $pgCtl -D $dataDir -l $logFile -o "-h 127.0.0.1 -p $Port" start
  $serverReady = $true
}

foreach ($database in @("pushpet_development", "pushpet_test")) {
  $exists = & $psql -h 127.0.0.1 -p $Port -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$database'"
  if ($exists.Trim() -ne "1") {
    & $createdb -h 127.0.0.1 -p $Port -U postgres $database
  }
}

Write-Host "Local PushPet Postgres is ready on 127.0.0.1:$Port"
