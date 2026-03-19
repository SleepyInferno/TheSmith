# TheSmith - Foreign Connection Audit Report
# Launch: .\Start-TheSmith.ps1
# Requires: PowerShell 5.1+ (stock Windows)

param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot

# Dot-source all modules
. "$ScriptRoot\lib\GeoLookup.ps1"
. "$ScriptRoot\lib\FileParser.ps1"
. "$ScriptRoot\lib\DetectionEngine.ps1"
. "$ScriptRoot\lib\IntuneParser.ps1"
. "$ScriptRoot\lib\JobManager.ps1"
. "$ScriptRoot\lib\Server.ps1"

# Create results directory if it doesn't exist
$resultsDir = Join-Path $ScriptRoot 'results'
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# Load IP2Location databases
$ipv4Path = Join-Path $ScriptRoot 'data\IP2LOCATION-LITE-DB1.CSV'
$ipv6Path = Join-Path $ScriptRoot 'data\IP2LOCATION-LITE-DB1.IPV6.CSV'

Write-Host "Loading IP2Location databases..." -ForegroundColor Cyan
$geoStats = Initialize-GeoDatabase -IPv4CsvPath $ipv4Path -IPv6CsvPath $ipv6Path
Write-Host "  IPv4 ranges: $($geoStats.IPv4Rows)" -ForegroundColor Green
Write-Host "  IPv6 ranges: $($geoStats.IPv6Rows)" -ForegroundColor Green

# Open browser
$url = "http://localhost:$Port"
Write-Host "Starting TheSmith server on $url" -ForegroundColor Cyan
Start-Process $url

# Start server (blocks until shutdown)
Start-Server -Port $Port -ScriptRoot $ScriptRoot
