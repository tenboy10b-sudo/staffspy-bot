# ================================================================
#  StaffSpy — audit_demo.ps1
#  Демо версія. Без перевірки ліцензії.
#  Показує 4 модулі: система, ПЗ, процеси, USB
# ================================================================

$ErrorActionPreference = "SilentlyContinue"
$RAILWAY_URL = "https://web-production-b6c66.up.railway.app"
$ReportPath  = "$env:USERPROFILE\Desktop\StaffSpy_DEMO.html"

Clear-Host
Write-Host @"

  ██████ ████████  █████  ███████ ███████
  ██        ██    ██   ██ ██      ██
  ███████   ██    ███████ █████   █████
       ██   ██    ██   ██ ██      ██
  ██████    ██    ██   ██ ██      ██      ███████ ██████  ██    ██

  DEMO версія | 4 модулі з 22
"@ -ForegroundColor Yellow

Write-Host ""
Write-Host "  [*] Збираю дані системи..." -ForegroundColor Cyan

# ── МОДУЛЬ 1: Система ──────────────────────────────────────────
$os      = Get-WmiObject Win32_OperatingSystem
$cs      = Get-WmiObject Win32_ComputerSystem
$cpu     = Get-WmiObject Win32_Processor | Select-Object -First 1
$bios    = Get-WmiObject Win32_BIOS
$uptime  = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
$uptimeStr = "$([int]$uptime.TotalHours)г $($uptime.Minutes)хв"
$ramGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedRAM = [math]::Round($ramGB - $freeRAM / 1024, 1)

Write-Host "  [+] Система: OK" -ForegroundColor Green

# ── МОДУЛЬ 2: Встановлене ПЗ ──────────────────────────────────
Write-Host "  [*] Збираю список програм..." -ForegroundColor Cyan

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

Write-Host "  [+] Програм знайдено: $($software.Count)" -ForegroundColor Green

# ── МОДУЛЬ 3: Поточні процеси ─────────────────────────────────
Write-Host "  [*] Збираю процеси..." -ForegroundColor Cyan

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
    } else { "—" }
    [PSCustomObject]@{
        Name   = $name
        PID    = $_.ProcessId
        User   = $user
        Start  = $start
        MemMB  = [math]::Round($_.WorkingSetSize / 1MB, 1)
    }
} | Where-Object { $_ -ne $null } | Sort-Object MemMB -Descending

Write-Host "  [+] Процесів: $($processes.Count)" -ForegroundColor Green

# ── МОДУЛЬ 4: USB пристрої ────────────────────────────────────
Write-Host "  [*] Збираю USB історію..." -ForegroundColor Cyan

$usbDevices = @()
try {
    $usbReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*" 2>$null
    foreach ($d in $usbReg) {
        $friendly = $d.FriendlyName
        if (-not $friendly) { $friendly = $d.PSChildName -replace "_\d+$","" }
        $usbDevices += [PSCustomObject]@{
            Device     = $friendly
            DeviceId   = $d.PSChildName
        }
    }
    $usbDevices = $usbDevices | Where-Object { $_.Device } | Sort-Object Device -Unique
} catch {}

Write-Host "  [+] USB пристроїв: $($usbDevices.Count)" -ForegroundColor Green

# ── Надіслати webhook ─────────────────────────────────────────
try {
    $body = @{
        key      = "DEMO"
        owner    = $env:USERNAME
        computer = $env:COMPUTERNAME
        demo     = $true
    } | ConvertTo-Json
    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" -Method POST -Body $body `
        -ContentType "application/json" -UseBasicParsing -TimeoutSec 10 | Out-Null
} catch {}

# ── ГЕНЕРАЦІЯ HTML ────────────────────────────────────────────
Write-Host "  [*] Генерую звіт..." -ForegroundColor Cyan

$swRows = ($software | Select-Object -First 50 | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.Version)</td><td>$($_.Publisher)</td><td>$($_.InstDate)</td></tr>"
}) -join ""

$procRows = ($processes | Select-Object -First 40 | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.PID)</td><td>$($_.User)</td><td>$($_.Start)</td><td>$($_.MemMB) MB</td></tr>"
}) -join ""

$usbRows = if ($usbDevices) {
    ($usbDevices | ForEach-Object { "<tr><td>$($_.Device)</td><td style='color:#64748b;font-size:.65rem'>$($_.DeviceId)</td></tr>" }) -join ""
} else { "<tr><td colspan='2' style='color:#64748b;text-align:center'>USB пристроїв не знайдено</td></tr>" }

$now = Get-Date -Format "dd.MM.yyyy HH:mm"

$html = @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="UTF-8">
<title>StaffSpy DEMO</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=JetBrains+Mono:wght@300;400;500&display=swap');
:root{--bg:#07090c;--s1:#0d1117;--border:#1a2332;--accent:#f59e0b;--text:#e2e8f0;--muted:#4b6080;}
*{box-sizing:border-box;margin:0;padding:0;}
body{background:var(--bg);color:var(--text);font-family:'JetBrains Mono',monospace;font-size:13px;padding:0;}
.header{background:var(--s1);border-bottom:1px solid var(--border);padding:1.5rem 2rem;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;}
.logo{font-family:'Unbounded',sans-serif;font-weight:900;font-size:1.4rem;color:#fff;}.logo span{color:var(--accent);}
.demo-badge{background:rgba(245,158,11,.15);border:1px solid rgba(245,158,11,.3);color:var(--accent);font-size:.6rem;padding:.3rem .8rem;border-radius:100px;font-family:'Unbounded',sans-serif;font-weight:700;}
.meta{font-size:.62rem;color:var(--muted);text-align:right;line-height:1.8;}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.75rem;padding:1.5rem 2rem;}
.card{background:var(--s1);border:1px solid var(--border);border-radius:10px;padding:1rem 1.2rem;}
.card-l{font-size:.58rem;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;margin-bottom:.4rem;}
.card-v{font-family:'Unbounded',sans-serif;font-size:1.6rem;font-weight:700;color:var(--accent);}
.section{padding:0 2rem 2rem;}
h2{font-family:'Unbounded',sans-serif;font-size:.65rem;color:var(--muted);text-transform:uppercase;letter-spacing:.15em;margin-bottom:1rem;display:flex;align-items:center;gap:.8rem;}
h2::after{content:'';flex:1;height:1px;background:var(--border);}
.table-wrap{background:var(--s1);border:1px solid var(--border);border-radius:10px;overflow:auto;margin-bottom:1rem;}
table{width:100%;border-collapse:collapse;}
thead th{background:#060a0f;color:var(--muted);font-size:.58rem;text-transform:uppercase;letter-spacing:.08em;padding:.75rem 1rem;text-align:left;border-bottom:1px solid var(--border);}
tbody td{padding:.6rem 1rem;border-bottom:1px solid rgba(26,35,50,.6);font-size:.7rem;}
tbody tr:last-child td{border-bottom:none;}
tbody tr:hover td{background:rgba(245,158,11,.02);}
.upsell{background:linear-gradient(135deg,rgba(245,158,11,.1) 0%,rgba(59,130,246,.06) 100%);border:1px solid rgba(245,158,11,.25);border-radius:14px;padding:2rem;text-align:center;margin:0 2rem 2rem;}
.upsell h3{font-family:'Unbounded',sans-serif;font-size:1rem;font-weight:700;color:#fff;margin-bottom:.5rem;}
.upsell p{font-size:.7rem;color:var(--muted);margin-bottom:1.2rem;}
.upsell a{display:inline-block;background:var(--accent);color:#000;font-family:'Unbounded',sans-serif;font-size:.7rem;font-weight:700;padding:.7rem 1.8rem;border-radius:8px;text-decoration:none;}
.modules-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:.5rem;margin:0 2rem 2rem;}
.mod{background:var(--s1);border:1px solid var(--border);border-radius:8px;padding:.7rem 1rem;font-size:.65rem;display:flex;align-items:center;gap:.6rem;}
.mod.active{border-color:rgba(16,185,129,.3);color:#10b981;}
.mod.locked{color:var(--muted);}
.mod.locked .mi{opacity:.3;}
footer{text-align:center;padding:1.5rem;color:var(--muted);font-size:.6rem;border-top:1px solid var(--border);}
</style>
</head>
<body>
<div class="header">
  <div>
    <div class="logo">Staff<span>Spy</span> <span class="demo-badge">DEMO</span></div>
    <div style="font-size:.6rem;color:var(--muted);margin-top:.3rem">Демонстраційна версія — 4 з 22 модулів</div>
  </div>
  <div class="meta">$now &nbsp;|&nbsp; $($env:COMPUTERNAME)<br>$($env:USERNAME) &nbsp;|&nbsp; $($os.Caption)</div>
</div>

<div class="cards">
  <div class="card"><div class="card-l">ОС</div><div class="card-v" style="font-size:1rem;margin-top:.2rem">$($os.Caption -replace "Microsoft Windows ","Win ")</div></div>
  <div class="card"><div class="card-l">RAM</div><div class="card-v">$ramGB <span style="font-size:.9rem">ГБ</span></div></div>
  <div class="card"><div class="card-l">Аптайм</div><div class="card-v" style="font-size:1rem">$uptimeStr</div></div>
  <div class="card"><div class="card-l">Процесів</div><div class="card-v">$($processes.Count)</div></div>
  <div class="card"><div class="card-l">Програм</div><div class="card-v">$($software.Count)</div></div>
  <div class="card"><div class="card-l">USB</div><div class="card-v">$($usbDevices.Count)</div></div>
</div>

<div class="section">
  <h2>Модулі демо версії</h2>
</div>
<div class="modules-list">
  <div class="mod active"><span class="mi">✅</span> Інформація про систему</div>
  <div class="mod active"><span class="mi">✅</span> Встановлене ПЗ</div>
  <div class="mod active"><span class="mi">✅</span> Поточні процеси</div>
  <div class="mod active"><span class="mi">✅</span> USB пристрої</div>
  <div class="mod locked"><span class="mi">🔒</span> Журнал запусків програм</div>
  <div class="mod locked"><span class="mi">🔒</span> Час запуску і закриття</div>
  <div class="mod locked"><span class="mi">🔒</span> Тривалість роботи</div>
  <div class="mod locked"><span class="mi">🔒</span> Активність по днях</div>
  <div class="mod locked"><span class="mi">🔒</span> Фільтри і сортування</div>
  <div class="mod locked"><span class="mi">🔒</span> Звіт по користувачах</div>
  <div class="mod locked"><span class="mi">🔒</span> + ще 12 модулів...</div>
</div>

<div class="section">
  <h2>Встановлені програми (перші 50)</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Назва</th><th>Версія</th><th>Видавець</th><th>Дата встановлення</th></tr></thead>
      <tbody>$swRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>Активні процеси</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Процес</th><th>PID</th><th>Користувач</th><th>Запуск</th><th>Пам'ять</th></tr></thead>
      <tbody>$procRows</tbody>
    </table>
  </div>
</div>

<div class="section">
  <h2>USB пристрої</h2>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Пристрій</th><th>ID</th></tr></thead>
      <tbody>$usbRows</tbody>
    </table>
  </div>
</div>

<div class="upsell">
  <h3>🔒 Хочете бачити повну картину?</h3>
  <p>Повна версія показує: коли і які програми запускались, хто і скільки працював,<br>детальний звіт за будь-який період з фільтрами і сортуванням.</p>
  <a href="https://t.me/StaffSpy_01_Bot">Отримати повну версію →</a>
</div>

<footer>StaffSpy DEMO v1.0 &bull; $now &bull; $($env:COMPUTERNAME)</footer>
</body>
</html>
"@

$html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
Start-Process $ReportPath

Write-Host ""
Write-Host "  ✅ Демо звіт збережено на Робочому столі" -ForegroundColor Green
Write-Host "  📄 StaffSpy_DEMO.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Для повного звіту: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Натисніть Enter для виходу"
