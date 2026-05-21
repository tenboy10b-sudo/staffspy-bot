# StaffSpy - launcher.ps1 v2.0
# Run as Administrator

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$GITHUB_OWNER  = "tenboy10b-sudo"
$GITHUB_REPO   = "staffspy-private"
$RAILWAY_URL   = "https://YOUR-PROJECT.up.railway.app"
$LICENSE_KEY   = "XXXX-XXXX-XXXX-XXXX"
$LICENSE_PASS  = "XXXXXXXXXX"

Clear-Host
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Yellow
Write-Host "   StaffSpy - Launcher v2.0" -ForegroundColor Yellow
Write-Host "  ============================================" -ForegroundColor Yellow
Write-Host ""

# Step 1 - Check license
Write-Host "  [1/4] Checking license..." -ForegroundColor Cyan

try {
    $licensesUrl = "https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/main/licenses.json?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $response    = Invoke-WebRequest -Uri $licensesUrl -UseBasicParsing -TimeoutSec 20
    $data        = $response.Content | ConvertFrom-Json
    $license     = $data.licenses | Where-Object { $_.key -eq $LICENSE_KEY -and $_.password -eq $LICENSE_PASS }

    if (-not $license) {
        Write-Host "  [x] Invalid license key or password." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
        exit 1
    }
    if (-not $license.active) {
        Write-Host "  [x] License is deactivated." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
        exit 1
    }
    if ($license.runs_used -ge $license.runs_max) {
        Write-Host "  [x] License runs exhausted ($($license.runs_used)/$($license.runs_max))." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
        exit 1
    }

    $runsLeft = $license.runs_max - $license.runs_used
    Write-Host "  [+] License OK: $($license.owner) | Runs left: $runsLeft" -ForegroundColor Green

} catch {
    Write-Host "  [x] License server error: $_" -ForegroundColor Red
    Read-Host "  Press Enter to exit"
    exit 1
}

# Step 2 - Register launch via webhook
Write-Host "  [2/4] Registering launch..." -ForegroundColor Cyan

try {
    $launchTime  = Get-Date -Format "dd.MM.yyyy HH:mm"
    $webhookBody = "{" + [char]34 + "action" + [char]34 + ":" + [char]34 + "use_license" + [char]34 + "," + [char]34 + "key" + [char]34 + ":" + [char]34 + $LICENSE_KEY + [char]34 + "," + [char]34 + "owner" + [char]34 + ":" + [char]34 + $license.owner + [char]34 + "," + [char]34 + "launch_time" + [char]34 + ":" + [char]34 + $launchTime + [char]34 + "," + [char]34 + "computer" + [char]34 + ":" + [char]34 + $env:COMPUTERNAME + [char]34 + "," + [char]34 + "user" + [char]34 + ":" + [char]34 + $env:USERNAME + [char]34 + "}"
    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" -Method POST -Body $webhookBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 15 | Out-Null
    Write-Host "  [+] Launch registered" -ForegroundColor Green
} catch {
    Write-Host "  [!] Webhook not responding (not critical)" -ForegroundColor DarkGray
}

# Step 3 - Check audit
Write-Host "  [3/4] Checking audit settings..." -ForegroundColor Cyan

$auditCheck = auditpol /get /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" 2>&1
if ($auditCheck -notmatch "Success") {
    Write-Host ""
    Write-Host "  [!] WARNING: Audit not configured!" -ForegroundColor Red
    Write-Host "  [!] Run installer.ps1 as Administrator first." -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 2
} else {
    Write-Host "  [+] Audit: active" -ForegroundColor Green
}

# Step 4 - Download and run spy_core
Write-Host "  [4/4] Loading analysis module..." -ForegroundColor Cyan

$reportDir  = "C:\StaffSpy"
$reportName = "StaffSpyReport_" + (Get-Date -Format "yyyy-MM-dd_HH-mm") + ".html"
$reportPath = "$reportDir\$reportName"

if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

try {
    $coreUrl  = "https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/main/spy_core.ps1?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $coreCode = (Invoke-WebRequest -Uri $coreUrl -UseBasicParsing -TimeoutSec 30).Content

    if (-not $coreCode -or $coreCode.Length -lt 100) {
        Write-Host "  [x] Failed to load analysis module." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
        exit 1
    }
    Write-Host "  [+] Module loaded ($([math]::Round($coreCode.Length/1KB,1)) KB)" -ForegroundColor Green
} catch {
    Write-Host "  [x] Download error: $_" -ForegroundColor Red
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "  [*] Running analysis (1-2 min)..." -ForegroundColor Cyan
Write-Host ""

$env:STAFFSPY_REPORT_PATH = $reportPath
$env:STAFFSPY_DAYS_BACK   = "7"

Invoke-Expression $coreCode

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Report saved: $reportPath" -ForegroundColor Cyan
Write-Host "  Runs left: $($runsLeft - 1)" -ForegroundColor $(if(($runsLeft-1) -le 1){"Yellow"}else{"White"})

if (($runsLeft - 1) -le 1) {
    Write-Host ""
    Write-Host "  [!] Runs almost out. Buy more: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
}

Write-Host ""
Read-Host "  Press Enter to exit"
