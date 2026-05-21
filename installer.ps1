# StaffSpy - installer.ps1 v2.0
# Run once as Administrator

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Clear-Host
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   StaffSpy - Installer v2.0" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# Check OS
$os    = Get-WmiObject Win32_OperatingSystem
$build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
Write-Host "  [*] OS: $($os.Caption) (build $build)" -ForegroundColor Gray

if ($build -lt 7601) {
    Write-Host "  [x] Windows 7 SP1 or newer required." -ForegroundColor Red
    Read-Host "  Press Enter to exit"
    exit 1
}
Write-Host "  [+] OS check: OK" -ForegroundColor Green

# Step 1 - Enable Process Creation audit
Write-Host ""
Write-Host "  [1/4] Enabling process audit..." -ForegroundColor Cyan

try {
    auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable 2>&1 | Out-Null
    auditpol /set /subcategory:"{0CCE9239-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable 2>&1 | Out-Null
    Write-Host "  [+] Process audit: enabled" -ForegroundColor Green
} catch {
    Write-Host "  [!] Audit setup warning: $_" -ForegroundColor Yellow
}

# Step 2 - Enable command line in audit
Write-Host "  [2/4] Enabling extended audit..." -ForegroundColor Cyan

try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    Write-Host "  [+] Extended audit: enabled" -ForegroundColor Green
} catch {
    Write-Host "  [!] Extended audit skipped (not critical): $_" -ForegroundColor Yellow
}

# Step 3 - Set Security log size to 200MB
Write-Host "  [3/4] Setting log size to 200 MB..." -ForegroundColor Cyan

try {
    $log = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new("Security")
    $log.MaximumSizeInBytes = 200MB
    $log.LogMode = [System.Diagnostics.Eventing.Reader.EventLogMode]::Circular
    $log.SaveChanges()
    Write-Host "  [+] Security log: 200 MB" -ForegroundColor Green
} catch {
    try {
        wevtutil sl Security /ms:209715200 /rt:false 2>&1 | Out-Null
        Write-Host "  [+] Security log: 200 MB (via wevtutil)" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Log size not changed (not critical)" -ForegroundColor Yellow
    }
}

# Step 4 - Apply group policies
Write-Host "  [4/4] Applying policies..." -ForegroundColor Cyan

try {
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [+] Policies applied" -ForegroundColor Green
} catch {
    Write-Host "  [!] gpupdate skipped" -ForegroundColor Yellow
}

# Verify
Write-Host ""
Write-Host "  [*] Verifying..." -ForegroundColor Cyan
$auditResult = auditpol /get /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" 2>&1
if ($auditResult -match "Success") {
    Write-Host "  [+] Process audit: ACTIVE" -ForegroundColor Green
} else {
    Write-Host "  [!] Process audit: check manually" -ForegroundColor Yellow
}

# Save install mark
$installPath = "$env:SystemRoot\staffspy_install.txt"
try {
    $mark = "installed=" + (Get-Date -Format "yyyy-MM-dd HH:mm") + " computer=" + $env:COMPUTERNAME + " user=" + $env:USERNAME
    [System.IO.File]::WriteAllText($installPath, $mark)
} catch {}

# Done
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Monitoring is now active." -ForegroundColor White
Write-Host "  Run launcher.ps1 in a week to get report." -ForegroundColor White
Write-Host ""
Write-Host "  Computer : $($env:COMPUTERNAME)" -ForegroundColor Gray
Write-Host "  User     : $($env:USERNAME)" -ForegroundColor Gray
Write-Host "  Date     : $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to exit"
