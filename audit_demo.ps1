# StaffSpy - audit_demo.ps1 v2.0

$ErrorActionPreference = "SilentlyContinue"
$RAILWAY_URL = "https://web-production-b6c66.up.railway.app"
$ReportPath  = "$env:USERPROFILE\Desktop\StaffSpy_DEMO.html"

Clear-Host
Write-Host "  StaffSpy DEMO v2.0" -ForegroundColor Yellow
Write-Host "  Демо версiя - 4 модулi з 22" -ForegroundColor Gray
Write-Host ""
Write-Host "  [*] Збираю данi системи..." -ForegroundColor Cyan

$os     = Get-WmiObject Win32_OperatingSystem
$cs     = Get-WmiObject Win32_ComputerSystem
$uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
$uptimeStr = "$([int]$uptime.TotalHours) год $($uptime.Minutes) хв"
$ramGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$osName = $os.Caption

Write-Host "  [+] Система: OK" -ForegroundColor Green

Write-Host "  [*] Збираю встановлене ПЗ..." -ForegroundColor Cyan
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
        $instDate = ""
        if ($_.InstallDate -and $_.InstallDate.Length -eq 8) {
            $instDate = "$($_.InstallDate.Substring(6,2)).$($_.InstallDate.Substring(4,2)).$($_.InstallDate.Substring(0,4))"
        }
        $software += [PSCustomObject]@{
            Name      = [string]$_.DisplayName
            Version   = [string]$_.DisplayVersion
            Publisher = [string]$_.Publisher
            InstDate  = $instDate
        }
    }
}
$software = $software | Where-Object { $_.Name } | Sort-Object Name -Unique
Write-Host "  [+] Програм знайдено: $($software.Count)" -ForegroundColor Green

Write-Host "  [*] Збираю активнi процеси..." -ForegroundColor Cyan
$SYSTEM_PROC = @("svchost","lsass","csrss","wininit","winlogon","services","spoolsv",
    "dwm","conhost","dllhost","rundll32","msiexec","wmiprvse","searchindexer",
    "runtimebroker","shellexperiencehost","startmenuexperiencehost","sihost",
    "ctfmon","msmpeng","smartscreen","taskhostw","fontdrvhost","smss","system","idle",
    "securityhealthservice","nissrv","audiodg","lockapp","logonui")

$processes = Get-WmiObject Win32_Process | ForEach-Object {
    $procName = ($_.Name -replace "\.exe$","" -replace "\.EXE$","")
    if ($SYSTEM_PROC -contains $procName.ToLower()) { return }
    $owner = $_.GetOwner()
    $user  = if ($owner.ReturnValue -eq 0 -and $owner.User) { "$($owner.Domain)\$($owner.User)" } else { "SYSTEM" }
    $startTime = ""
    if ($_.CreationDate) {
        try { $startTime = [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate).ToString("HH:mm dd.MM") } catch {}
    }
    [PSCustomObject]@{
        Name  = [string]$procName
        PID   = $_.ProcessId
        User  = [string]$user
        Start = $startTime
        MemMB = [math]::Round($_.WorkingSetSize / 1MB, 1)
    }
} | Where-Object { $_ -ne $null -and $_.Name } | Sort-Object MemMB -Descending

Write-Host "  [+] Процесiв: $($processes.Count)" -ForegroundColor Green

Write-Host "  [*] Збираю USB iсторiю..." -ForegroundColor Cyan
$usbDevices = @()
try {
    Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*" 2>$null |
    ForEach-Object {
        $friendly = [string]$_.FriendlyName
        if (-not $friendly) { $friendly = ($_.PSChildName -replace "_\d+$","") }
        if ($friendly) {
            $usbDevices += [PSCustomObject]@{ Device = $friendly; ID = [string]$_.PSChildName }
        }
    }
    $usbDevices = $usbDevices | Where-Object { $_.Device } | Sort-Object Device -Unique
} catch {}
Write-Host "  [+] USB: $($usbDevices.Count)" -ForegroundColor Green

try {
    $wh = '{"key":"DEMO","owner":"' + $env:USERNAME + '","computer":"' + $env:COMPUTERNAME + '","demo":true}'
    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" -Method POST -Body $wh -ContentType "application/json" -UseBasicParsing -TimeoutSec 8 | Out-Null
} catch {}

Write-Host "  [*] Генерую звiт..." -ForegroundColor Cyan
$now = Get-Date -Format "dd.MM.yyyy HH:mm"

$swRows = ($software | Select-Object -First 50 | ForEach-Object {
    $n = $_.Name    -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
    $v = $_.Version -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
    $p = $_.Publisher -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
    "<tr><td>$n</td><td>$v</td><td>$p</td><td>$($_.InstDate)</td></tr>"
}) -join ""

$procRows = ($processes | Select-Object -First 40 | ForEach-Object {
    $n = $_.Name -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
    $u = $_.User -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
    "<tr><td>$n</td><td>$($_.PID)</td><td>$u</td><td>$($_.Start)</td><td>$($_.MemMB) MB</td></tr>"
}) -join ""

$usbRows = if ($usbDevices.Count -gt 0) {
    ($usbDevices | ForEach-Object {
        $d = $_.Device -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;"
        "<tr><td>$d</td><td style='color:#94a3b8;font-size:.65rem'>$($_.ID)</td></tr>"
    }) -join ""
} else { "<tr><td colspan='2' style='text-align:center;color:#94a3b8;padding:1.5rem'>USB-пристроїв не знайдено</td></tr>" }

$html = @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="UTF-8">
<title>StaffSpy DEMO</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=Inter:wght@300;400;500;600&display=swap');
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #f0f4f8; color: #1e293b; font-family: 'Inter', sans-serif; font-size: 13px; }
.header { background: #fff; border-bottom: 1px solid #e2e8f0; padding: 1.2rem 2rem; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; box-shadow: 0 1px 4px rgba(0,0,0,.06); }
.logo { font-family: 'Unbounded', sans-serif; font-weight: 900; font-size: 1.3rem; color: #0f172a; }
.logo span { color: #f59e0b; }
.demo-badge { background: #fef3c7; border: 1px solid #fde68a; color: #92400e; font-size: .6rem; padding: .25rem .7rem; border-radius: 100px; font-family: 'Unbounded', sans-serif; font-weight: 700; margin-left: .8rem; }
.meta { font-size: .62rem; color: #94a3b8; text-align: right; line-height: 1.9; }
.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: .75rem; padding: 1.5rem 2rem; }
.card { background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; padding: 1rem 1.2rem; border-top: 3px solid #f59e0b; }
.card:nth-child(2) { border-top-color: #3b82f6; }
.card:nth-child(3) { border-top-color: #10b981; }
.card:nth-child(4) { border-top-color: #8b5cf6; }
.card:nth-child(5) { border-top-color: #ef4444; }
.card:nth-child(6) { border-top-color: #f97316; }
.card-l { font-size: .58rem; color: #94a3b8; text-transform: uppercase; letter-spacing: .1em; margin-bottom: .4rem; font-weight: 600; }
.card-v { font-family: 'Unbounded', sans-serif; font-size: 1.5rem; font-weight: 700; color: #0f172a; }
.section { padding: 0 2rem 2rem; }
h2 { font-family: 'Unbounded', sans-serif; font-size: .65rem; color: #94a3b8; text-transform: uppercase; letter-spacing: .15em; margin-bottom: 1rem; padding-bottom: .5rem; border-bottom: 2px solid #f1f5f9; }
.table-wrap { background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; overflow: auto; margin-bottom: 1rem; box-shadow: 0 1px 4px rgba(0,0,0,.04); }
table { width: 100%; border-collapse: collapse; }
thead th { background: #f8fafc; color: #64748b; font-size: .6rem; text-transform: uppercase; letter-spacing: .08em; padding: .8rem 1rem; text-align: left; border-bottom: 1px solid #e2e8f0; font-weight: 600; }
tbody td { padding: .65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: .72rem; color: #334155; }
tbody tr:last-child td { border-bottom: none; }
tbody tr:hover td { background: #fffbeb; }
.modules { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: .5rem; margin: 0 2rem 2rem; }
.mod { background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; padding: .7rem 1rem; font-size: .65rem; display: flex; align-items: center; gap: .6rem; color: #334155; }
.mod.ok { border-color: #bbf7d0; color: #16a34a; background: #f0fdf4; }
.mod.locked { color: #94a3b8; }
.mod .tag { font-size: .52rem; padding: .1rem .4rem; border-radius: 4px; font-weight: 700; }
.mod.ok .tag { background: #dcfce7; color: #16a34a; }
.mod.locked .tag { background: #f1f5f9; color: #94a3b8; border: 1px solid #e2e8f0; }
.upsell { background: linear-gradient(135deg, #fffbeb 0%, #eff6ff 100%); border: 2px solid #fde68a; border-radius: 16px; padding: 2rem; text-align: center; margin: 0 2rem 2rem; }
.upsell h3 { font-family: 'Unbounded', sans-serif; font-size: 1rem; font-weight: 700; color: #0f172a; margin-bottom: .5rem; }
.upsell p { font-size: .72rem; color: #64748b; margin-bottom: 1.2rem; line-height: 1.8; }
.upsell a { display: inline-block; background: #f59e0b; color: #fff; font-family: 'Unbounded', sans-serif; font-size: .72rem; font-weight: 700; padding: .75rem 2rem; border-radius: 9px; text-decoration: none; box-shadow: 0 4px 12px rgba(245,158,11,.3); }
footer { text-align: center; padding: 1.5rem; color: #94a3b8; font-size: .62rem; border-top: 1px solid #e2e8f0; background: #fff; margin-top: 1rem; }
</style>
</head>
<body>
<div class="header">
  <div>
    <div class="logo">Staff<span>Spy</span><span class="demo-badge">DEMO</span></div>
    <div style="font-size:.6rem;color:#94a3b8;margin-top:.3rem">Демонстрацiйна версiя — 4 з 22 модулiв</div>
  </div>
  <div class="meta">$now | $($env:COMPUTERNAME)<br>$($env:USERNAME) | $osName</div>
</div>

<div class="cards">
  <div class="card"><div class="card-l">ОС</div><div class="card-v" style="font-size:.85rem;margin-top:.2rem">$osName</div></div>
  <div class="card"><div class="card-l">RAM</div><div class="card-v">$ramGB <span style="font-size:.9rem">ГБ</span></div></div>
  <div class="card"><div class="card-l">Аптайм</div><div class="card-v" style="font-size:.95rem">$uptimeStr</div></div>
  <div class="card"><div class="card-l">Процесiв</div><div class="card-v">$($processes.Count)</div></div>
  <div class="card"><div class="card-l">Програм</div><div class="card-v">$($software.Count)</div></div>
  <div class="card"><div class="card-l">USB</div><div class="card-v">$($usbDevices.Count)</div></div>
</div>

<div class="section"><h2>Модулi</h2></div>
<div class="modules">
  <div class="mod ok"><span class="tag">OK</span> Iнформацiя про систему</div>
  <div class="mod ok"><span class="tag">OK</span> Встановлене ПЗ</div>
  <div class="mod ok"><span class="tag">OK</span> Активнi процеси</div>
  <div class="mod ok"><span class="tag">OK</span> USB-пристрої</div>
  <div class="mod locked"><span class="tag">lock</span> Журнал запускiв програм</div>
  <div class="mod locked"><span class="tag">lock</span> Час запуску i закриття</div>
  <div class="mod locked"><span class="tag">lock</span> Тривалiсть роботи</div>
  <div class="mod locked"><span class="tag">lock</span> Активнiсть по днях</div>
  <div class="mod locked"><span class="tag">lock</span> Фiльтри i сортування</div>
  <div class="mod locked"><span class="tag">lock</span> Звiт по користувачах</div>
  <div class="mod locked"><span class="tag">lock</span> Експорт в Excel</div>
  <div class="mod locked"><span class="tag">lock</span> + ще 11 модулiв...</div>
</div>

<div class="section">
  <h2>Встановленi програми (першi 50)</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Назва</th><th>Версiя</th><th>Видавець</th><th>Дата встановлення</th></tr></thead>
      <tbody>$swRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>Активнi процеси</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Процес</th><th>PID</th><th>Користувач</th><th>Запуск</th><th>Пам'ять</th></tr></thead>
      <tbody>$procRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>Iсторiя USB-пристроїв</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Пристрiй</th><th>ID</th></tr></thead>
      <tbody>$usbRows</tbody>
    </table>
  </div>
</div>

<div class="upsell">
  <h3>Хочете бачити повну картину?</h3>
  <p>Повна версiя показує: якi програми запускались i коли, хто i скiльки працював,<br>детальний звiт за будь-який перiод з фiльтрами, сортуванням i експортом в Excel.</p>
  <a href="https://t.me/StaffSpy_01_Bot">Отримати повну версiю</a>
</div>

<footer>StaffSpy DEMO v2.0 | $now | $($env:COMPUTERNAME)</footer>
</body>
</html>
"@

$html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
Start-Process $ReportPath
Write-Host "  [OK] Демо звiт збережено на Робочому столi" -ForegroundColor Green
Write-Host "  StaffSpy_DEMO.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Повна версiя: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Натиснiть Enter для виходу"
