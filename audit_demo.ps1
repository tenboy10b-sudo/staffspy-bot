# StaffSpy - audit_demo.ps1
# Demo version - 4 modules, no license check

$ErrorActionPreference = "SilentlyContinue"
$RAILWAY_URL = "https://web-production-b6c66.up.railway.app"
$ReportPath  = "$env:USERPROFILE\Desktop\StaffSpy_DEMO.html"

Clear-Host
Write-Host ""
Write-Host "  StaffSpy DEMO" -ForegroundColor Yellow
Write-Host "  Demo version - 4 modules" -ForegroundColor Gray
Write-Host ""
Write-Host "  [*] Collecting system data..." -ForegroundColor Cyan

# MODULE 1: System info
$os     = Get-WmiObject Win32_OperatingSystem
$cs     = Get-WmiObject Win32_ComputerSystem
$cpu    = Get-WmiObject Win32_Processor | Select-Object -First 1
$uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
$uptimeStr = "$([int]$uptime.TotalHours)h $($uptime.Minutes)min"
$ramGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
Write-Host "  [+] System: OK" -ForegroundColor Green

# MODULE 2: Installed software
Write-Host "  [*] Collecting installed software..." -ForegroundColor Cyan
$software = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($path in $regPaths) {
    Get-ItemProperty $path 2>$null |
    Where-Object { $_.DisplayName -and $_.DisplayName -notmatch "^KB\d+" } |
    ForEach-Object {
        $software += [PSCustomObject]@{
            Name      = $_.DisplayName
            Version   = $_.DisplayVersion
            Publisher = $_.Publisher
            InstDate  = $_.InstallDate
        }
    }
}
$software = $software | Sort-Object Name -Unique
Write-Host "  [+] Software found: $($software.Count)" -ForegroundColor Green

# MODULE 3: Running processes
Write-Host "  [*] Collecting processes..." -ForegroundColor Cyan
$SYSTEM_PROC = @("svchost","lsass","csrss","wininit","winlogon","services","spoolsv",
    "dwm","conhost","dllhost","rundll32","msiexec","WmiPrvSE","SearchIndexer",
    "RuntimeBroker","ShellExperienceHost","StartMenuExperienceHost","sihost",
    "ctfmon","MsMpEng","smartscreen","taskhostw","fontdrvhost","smss","System","Idle")

$processes = Get-WmiObject Win32_Process | ForEach-Object {
    $name = ($_.Name -replace "\.exe$","")
    if ($SYSTEM_PROC -contains $name) { return }
    $owner = $_.GetOwner()
    $user  = if ($owner.ReturnValue -eq 0) { "$($owner.Domain)\$($owner.User)" } else { "SYSTEM" }
    $start = if ($_.CreationDate) {
        [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate).ToString("HH:mm dd.MM")
    } else { "---" }
    [PSCustomObject]@{
        Name  = $name
        PID   = $_.ProcessId
        User  = $user
        Start = $start
        MemMB = [math]::Round($_.WorkingSetSize / 1MB, 1)
    }
} | Where-Object { $_ -ne $null } | Sort-Object MemMB -Descending
Write-Host "  [+] Processes: $($processes.Count)" -ForegroundColor Green

# MODULE 4: USB devices
Write-Host "  [*] Collecting USB history..." -ForegroundColor Cyan
$usbDevices = @()
try {
    Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*" 2>$null |
    ForEach-Object {
        $friendly = $_.FriendlyName
        if (-not $friendly) { $friendly = $_.PSChildName -replace "_\d+$","" }
        if ($friendly) {
            $usbDevices += [PSCustomObject]@{
                Device   = $friendly
                DeviceId = $_.PSChildName
            }
        }
    }
    $usbDevices = $usbDevices | Sort-Object Device -Unique
} catch {}
Write-Host "  [+] USB devices: $($usbDevices.Count)" -ForegroundColor Green

# Send webhook
try {
    $body = '{"key":"DEMO","owner":"' + $env:USERNAME + '","computer":"' + $env:COMPUTERNAME + '","demo":true}'
    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" -Method POST -Body $body `
        -ContentType "application/json" -UseBasicParsing -TimeoutSec 10 | Out-Null
} catch {}

# Build HTML
Write-Host "  [*] Generating report..." -ForegroundColor Cyan
$now = Get-Date -Format "dd.MM.yyyy HH:mm"
$osName = $os.Caption -replace "Microsoft Windows ","Win "

$swRows = ($software | Select-Object -First 50 | ForEach-Object {
    $n = [System.Web.HttpUtility]::HtmlEncode($_.Name)
    $v = [System.Web.HttpUtility]::HtmlEncode($_.Version)
    $p = [System.Web.HttpUtility]::HtmlEncode($_.Publisher)
    "<tr><td>$n</td><td>$v</td><td>$p</td><td>$($_.InstDate)</td></tr>"
}) -join "`n"

$procRows = ($processes | Select-Object -First 40 | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.PID)</td><td>$($_.User)</td><td>$($_.Start)</td><td>$($_.MemMB) MB</td></tr>"
}) -join "`n"

$usbRows = if ($usbDevices.Count -gt 0) {
    ($usbDevices | ForEach-Object { "<tr><td>$($_.Device)</td><td class='muted'>$($_.DeviceId)</td></tr>" }) -join "`n"
} else { "<tr><td colspan='2' class='muted center'>No USB devices found</td></tr>" }

$modLocked = @("Launch log","Start and close times","Work duration","Activity by day","Filters and sorting","User reports","+ 12 more modules...")
$modLockedHtml = ($modLocked | ForEach-Object { "<div class='mod locked'><span>locked</span> $_</div>" }) -join "`n"

$html = @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="UTF-8">
<title>StaffSpy DEMO</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=JetBrains+Mono:wght@300;400;500&display=swap');
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #07090c; color: #e2e8f0; font-family: 'JetBrains Mono', monospace; font-size: 13px; }
.header { background: #0d1117; border-bottom: 1px solid #1a2332; padding: 1.5rem 2rem; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; }
.logo { font-family: 'Unbounded', sans-serif; font-weight: 900; font-size: 1.4rem; color: #fff; }
.logo span { color: #f59e0b; }
.demo-badge { background: rgba(245,158,11,.15); border: 1px solid rgba(245,158,11,.3); color: #f59e0b; font-size: .6rem; padding: .3rem .8rem; border-radius: 100px; font-family: 'Unbounded', sans-serif; font-weight: 700; margin-left: .8rem; }
.meta { font-size: .62rem; color: #4b6080; text-align: right; line-height: 1.8; }
.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: .75rem; padding: 1.5rem 2rem; }
.card { background: #0d1117; border: 1px solid #1a2332; border-radius: 10px; padding: 1rem 1.2rem; }
.card-l { font-size: .58rem; color: #4b6080; text-transform: uppercase; letter-spacing: .1em; margin-bottom: .4rem; }
.card-v { font-family: 'Unbounded', sans-serif; font-size: 1.6rem; font-weight: 700; color: #f59e0b; }
.section { padding: 0 2rem 2rem; }
h2 { font-family: 'Unbounded', sans-serif; font-size: .65rem; color: #4b6080; text-transform: uppercase; letter-spacing: .15em; margin-bottom: 1rem; padding-bottom: .5rem; border-bottom: 1px solid #1a2332; }
.table-wrap { background: #0d1117; border: 1px solid #1a2332; border-radius: 10px; overflow: auto; margin-bottom: 1rem; }
table { width: 100%; border-collapse: collapse; }
thead th { background: #060a0f; color: #4b6080; font-size: .58rem; text-transform: uppercase; letter-spacing: .08em; padding: .75rem 1rem; text-align: left; border-bottom: 1px solid #1a2332; }
tbody td { padding: .6rem 1rem; border-bottom: 1px solid rgba(26,35,50,.6); font-size: .7rem; }
tbody tr:last-child td { border-bottom: none; }
tbody tr:hover td { background: rgba(245,158,11,.02); }
.modules-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: .5rem; margin-bottom: 2rem; padding: 0 2rem; }
.mod { background: #0d1117; border: 1px solid #1a2332; border-radius: 8px; padding: .7rem 1rem; font-size: .65rem; display: flex; align-items: center; gap: .6rem; }
.mod.active { border-color: rgba(16,185,129,.3); color: #10b981; }
.mod.locked { color: #4b6080; }
.mod.locked span { background: rgba(75,96,128,.2); border: 1px solid #2d3f55; border-radius: 4px; padding: .1rem .4rem; font-size: .5rem; }
.upsell { background: linear-gradient(135deg, rgba(245,158,11,.1) 0%, rgba(59,130,246,.06) 100%); border: 1px solid rgba(245,158,11,.25); border-radius: 14px; padding: 2rem; text-align: center; margin: 0 2rem 2rem; }
.upsell h3 { font-family: 'Unbounded', sans-serif; font-size: 1rem; font-weight: 700; color: #fff; margin-bottom: .5rem; }
.upsell p { font-size: .7rem; color: #4b6080; margin-bottom: 1.2rem; line-height: 1.7; }
.upsell a { display: inline-block; background: #f59e0b; color: #000; font-family: 'Unbounded', sans-serif; font-size: .7rem; font-weight: 700; padding: .7rem 1.8rem; border-radius: 8px; text-decoration: none; }
.muted { color: #4b6080; font-size: .65rem; }
.center { text-align: center; }
footer { text-align: center; padding: 1.5rem; color: #4b6080; font-size: .6rem; border-top: 1px solid #1a2332; }
</style>
</head>
<body>
<div class="header">
  <div>
    <div class="logo">Staff<span>Spy</span><span class="demo-badge">DEMO</span></div>
    <div style="font-size:.6rem;color:#4b6080;margin-top:.3rem">Demo version - 4 of 22 modules</div>
  </div>
  <div class="meta">$now | $($env:COMPUTERNAME)<br>$($env:USERNAME) | $osName</div>
</div>

<div class="cards">
  <div class="card"><div class="card-l">OS</div><div class="card-v" style="font-size:.9rem;margin-top:.2rem">$osName</div></div>
  <div class="card"><div class="card-l">RAM</div><div class="card-v">$ramGB <span style="font-size:.9rem">GB</span></div></div>
  <div class="card"><div class="card-l">Uptime</div><div class="card-v" style="font-size:1rem">$uptimeStr</div></div>
  <div class="card"><div class="card-l">Processes</div><div class="card-v">$($processes.Count)</div></div>
  <div class="card"><div class="card-l">Software</div><div class="card-v">$($software.Count)</div></div>
  <div class="card"><div class="card-l">USB</div><div class="card-v">$($usbDevices.Count)</div></div>
</div>

<div class="section"><h2>Modules</h2></div>
<div class="modules-grid">
  <div class="mod active">OK  System info</div>
  <div class="mod active">OK  Installed software</div>
  <div class="mod active">OK  Running processes</div>
  <div class="mod active">OK  USB devices</div>
$modLockedHtml
</div>

<div class="section">
  <h2>Installed Software (first 50)</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Name</th><th>Version</th><th>Publisher</th><th>Install Date</th></tr></thead>
      <tbody>$swRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>Running Processes</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Process</th><th>PID</th><th>User</th><th>Started</th><th>Memory</th></tr></thead>
      <tbody>$procRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>USB Devices History</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Device</th><th>ID</th></tr></thead>
      <tbody>$usbRows</tbody>
    </table>
  </div>
</div>

<div class="upsell">
  <h3>Want to see the full picture?</h3>
  <p>Full version shows: which programs were launched and when,<br>who worked and for how long, detailed report for any period with filters.</p>
  <a href="https://t.me/StaffSpy_01_Bot">Get full version</a>
</div>

<footer>StaffSpy DEMO v1.0 | $now | $($env:COMPUTERNAME)</footer>
</body>
</html>
"@

$html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
Start-Process $ReportPath

Write-Host "  [OK] Demo report saved to Desktop" -ForegroundColor Green
Write-Host "  StaffSpy_DEMO.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Full version: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Press Enter to exit"
