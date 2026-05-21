# StaffSpy - audit_demo.ps1 v2.0
$ErrorActionPreference = "SilentlyContinue"
$RAILWAY_URL = "https://web-production-b6c66.up.railway.app"
$ReportPath  = "$env:USERPROFILE\Desktop\StaffSpy_DEMO.html"

Clear-Host
Write-Host "  StaffSpy DEMO v2.0" -ForegroundColor Yellow
Write-Host "  Demo - 4 moduli z 22" -ForegroundColor Gray
Write-Host ""
Write-Host "  Zbyrayu dani systemy..." -ForegroundColor Cyan

$os     = Get-WmiObject Win32_OperatingSystem
$cs     = Get-WmiObject Win32_ComputerSystem
$uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
$uptimeH = [int]$uptime.TotalHours
$uptimeM = $uptime.Minutes
$uptimeStr = "$uptimeH god $uptimeM khv"
$ramGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$osName = $os.Caption
Write-Host "  [OK] Systema OK" -ForegroundColor Green

Write-Host "  Zbyrayu PZ..." -ForegroundColor Cyan
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
Write-Host "  [OK] Prohram: $($software.Count)" -ForegroundColor Green

Write-Host "  Zbyrayu protsesy..." -ForegroundColor Cyan
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
Write-Host "  [OK] Protsesiv: $($processes.Count)" -ForegroundColor Green

Write-Host "  Zbyrayu USB..." -ForegroundColor Cyan
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
Write-Host "  [OK] USB: $($usbDevices.Count)" -ForegroundColor Green

try {
    $whUser = $env:USERNAME
    $whComp = $env:COMPUTERNAME
    $whBody = "{" + [char]34 + "key" + [char]34 + ":" + [char]34 + "DEMO" + [char]34 + "," + [char]34 + "owner" + [char]34 + ":" + [char]34 + $whUser + [char]34 + "," + [char]34 + "computer" + [char]34 + ":" + [char]34 + $whComp + [char]34 + "," + [char]34 + "demo" + [char]34 + ":true}"
    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" -Method POST -Body $whBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 8 | Out-Null
} catch {}

Write-Host "  Genuruyu zvit..." -ForegroundColor Cyan
$now = Get-Date -Format "dd.MM.yyyy HH:mm"

function CleanStr { param([string]$s) return ($s -replace "[<>]","") }

$swRows = ($software | Select-Object -First 50 | ForEach-Object {
    $n = CleanStr $_.Name
    $v = CleanStr $_.Version
    $p = CleanStr $_.Publisher
    "<tr><td>" + $n + "</td><td>" + $v + "</td><td>" + $p + "</td><td>" + $_.InstDate + "</td></tr>"
}) -join "`n"

$procRows = ($processes | Select-Object -First 40 | ForEach-Object {
    $n = CleanStr $_.Name
    $u = CleanStr $_.User
    "<tr><td>" + $n + "</td><td>" + $_.PID + "</td><td>" + $u + "</td><td>" + $_.Start + "</td><td>" + $_.MemMB + " MB</td></tr>"
}) -join "`n"

$usbRows = if ($usbDevices.Count -gt 0) {
    ($usbDevices | ForEach-Object {
        $d = CleanStr $_.Device
        "<tr><td>" + $d + "</td><td class=muted>" + $_.ID + "</td></tr>"
    }) -join "`n"
} else { "<tr><td colspan=2 class=center>USB-prystroyiv ne znayshlo</td></tr>" }

$pc  = $env:COMPUTERNAME
$usr = $env:USERNAME

$htmlTemplate = @"
<!DOCTYPE html>
<html lang=`"uk`">
<head>
<meta charset=`"UTF-8`">
<title>StaffSpy DEMO</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Unbounded:wght@400;700;900&family=Inter:wght@300;400;500;600&display=swap');
*{box-sizing:border-box;margin:0;padding:0;}
body{background:#f0f4f8;color:#1e293b;font-family:'Inter',sans-serif;font-size:13px;}
.header{background:#fff;border-bottom:1px solid #e2e8f0;padding:1.2rem 2rem;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;box-shadow:0 1px 4px rgba(0,0,0,.06);}
.logo{font-family:'Unbounded',sans-serif;font-weight:900;font-size:1.3rem;color:#0f172a;}
.logo span{color:#f59e0b;}
.badge{background:#fef3c7;border:1px solid #fde68a;color:#92400e;font-size:.6rem;padding:.25rem .7rem;border-radius:100px;font-family:'Unbounded',sans-serif;font-weight:700;margin-left:.8rem;}
.meta{font-size:.62rem;color:#94a3b8;text-align:right;line-height:1.9;}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.75rem;padding:1.5rem 2rem;}
.card{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:1rem 1.2rem;border-top:3px solid #f59e0b;}
.card:nth-child(2){border-top-color:#3b82f6;}.card:nth-child(3){border-top-color:#10b981;}
.card:nth-child(4){border-top-color:#8b5cf6;}.card:nth-child(5){border-top-color:#ef4444;}
.card:nth-child(6){border-top-color:#f97316;}
.card-l{font-size:.58rem;color:#94a3b8;text-transform:uppercase;letter-spacing:.1em;margin-bottom:.4rem;font-weight:600;}
.card-v{font-family:'Unbounded',sans-serif;font-size:1.5rem;font-weight:700;color:#0f172a;}
.section{padding:0 2rem 2rem;}
h2{font-family:'Unbounded',sans-serif;font-size:.65rem;color:#94a3b8;text-transform:uppercase;letter-spacing:.15em;margin-bottom:1rem;padding-bottom:.5rem;border-bottom:2px solid #f1f5f9;}
.tw{background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:auto;margin-bottom:1rem;box-shadow:0 1px 4px rgba(0,0,0,.04);}
table{width:100%;border-collapse:collapse;}
thead th{background:#f8fafc;color:#64748b;font-size:.6rem;text-transform:uppercase;letter-spacing:.08em;padding:.8rem 1rem;text-align:left;border-bottom:1px solid #e2e8f0;font-weight:600;}
tbody td{padding:.65rem 1rem;border-bottom:1px solid #f1f5f9;font-size:.72rem;color:#334155;}
tbody tr:last-child td{border-bottom:none;}
tbody tr:hover td{background:#fffbeb;}
.modules{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:.5rem;margin:0 2rem 2rem;}
.mod{background:#fff;border:1px solid #e2e8f0;border-radius:8px;padding:.7rem 1rem;font-size:.65rem;display:flex;align-items:center;gap:.6rem;}
.mod.ok{border-color:#bbf7d0;color:#16a34a;background:#f0fdf4;}
.mod.locked{color:#94a3b8;}
.tag{font-size:.52rem;padding:.1rem .4rem;border-radius:4px;font-weight:700;}
.mod.ok .tag{background:#dcfce7;color:#16a34a;}
.mod.locked .tag{background:#f1f5f9;color:#94a3b8;border:1px solid #e2e8f0;}
.upsell{background:linear-gradient(135deg,#fffbeb 0%,#eff6ff 100%);border:2px solid #fde68a;border-radius:16px;padding:2rem;text-align:center;margin:0 2rem 2rem;}
.upsell h3{font-family:'Unbounded',sans-serif;font-size:1rem;font-weight:700;color:#0f172a;margin-bottom:.5rem;}
.upsell p{font-size:.72rem;color:#64748b;margin-bottom:1.2rem;line-height:1.8;}
.upsell a{display:inline-block;background:#f59e0b;color:#fff;font-family:'Unbounded',sans-serif;font-size:.72rem;font-weight:700;padding:.75rem 2rem;border-radius:9px;text-decoration:none;}
.muted{color:#94a3b8;font-size:.65rem;}
.center{text-align:center;color:#94a3b8;padding:1.5rem;}
footer{text-align:center;padding:1.5rem;color:#94a3b8;font-size:.62rem;border-top:1px solid #e2e8f0;background:#fff;margin-top:1rem;}
</style>
</head>
<body>
HEADER_PLACEHOLDER
<div class=`"cards`">
CARDS_PLACEHOLDER
</div>
<div class=`"section`"><h2>Moduli</h2></div>
<div class=`"modules`">
  <div class=`"mod ok`"><span class=`"tag`">OK</span> Informatsiia pro systemu</div>
  <div class=`"mod ok`"><span class=`"tag`">OK</span> Vstanovlene PZ</div>
  <div class=`"mod ok`"><span class=`"tag`">OK</span> Aktyvni protsesy</div>
  <div class=`"mod ok`"><span class=`"tag`">OK</span> USB-prystroi</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Zhurnal zapuskiv</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Chas zapusku i zakryttia</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Tryvalist roboty</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Aktyvnist po dniakh</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Filtry i sortuvannia</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Zvit po korystuvachakh</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> Eksport v Excel</div>
  <div class=`"mod locked`"><span class=`"tag`">lock</span> + 11 moduliv...</div>
</div>
<div class=`"section`">
  <h2>Vstanovleni prohramy (pershi 50)</h2>
  <div class=`"tw`"><table>
    <thead><tr><th>Nazva</th><th>Versiia</th><th>Vydavets</th><th>Data vstanovlennia</th></tr></thead>
    <tbody>SW_ROWS</tbody>
  </table></div>
</div>
<div class=`"section`">
  <h2>Aktyvni protsesy</h2>
  <div class=`"tw`"><table>
    <thead><tr><th>Protses</th><th>PID</th><th>Korystuvach</th><th>Zapusk</th><th>Pamiat</th></tr></thead>
    <tbody>PROC_ROWS</tbody>
  </table></div>
</div>
<div class=`"section`">
  <h2>Istoriia USB-prystroyiv</h2>
  <div class=`"tw`"><table>
    <thead><tr><th>Prystriy</th><th>ID</th></tr></thead>
    <tbody>USB_ROWS</tbody>
  </table></div>
</div>
<div class=`"upsell`">
  <h3>Khochete bachyty povnu kartunu?</h3>
  <p>Povna versiia: iaki prohramy zapuskalys i koly, khto i skilky pratsyuvav,<br>detalnyi zvit za bud-iakyi period z filtramy ta eksportom v Excel.</p>
  <a href=`"https://t.me/StaffSpy_01_Bot`">Otrymaty povnu versiiu</a>
</div>
<footer>StaffSpy DEMO v2.0 | NOW_PLACEHOLDER | PC_PLACEHOLDER</footer>
</body></html>
"@

$headerHtml = "<div class=header><div><div class=logo>Staff<span>Spy</span><span class=badge>DEMO</span></div></div><div class=meta>" + $now + " | " + $pc + "<br>" + $usr + " | " + $osName + "</div></div>"
$cardsHtml  = "<div class=card><div class=card-l>OS</div><div class=card-v style=font-size:.85rem>" + $osName + "</div></div>" +
              "<div class=card><div class=card-l>RAM</div><div class=card-v>" + $ramGB + " GB</div></div>" +
              "<div class=card><div class=card-l>Uptime</div><div class=card-v style=font-size:.95rem>" + $uptimeStr + "</div></div>" +
              "<div class=card><div class=card-l>Protsesiv</div><div class=card-v>" + $processes.Count + "</div></div>" +
              "<div class=card><div class=card-l>Prohram</div><div class=card-v>" + $software.Count + "</div></div>" +
              "<div class=card><div class=card-l>USB</div><div class=card-v>" + $usbDevices.Count + "</div></div>"

$htmlFinal = $htmlTemplate
$htmlFinal = $htmlFinal -replace "HEADER_PLACEHOLDER", $headerHtml
$htmlFinal = $htmlFinal -replace "CARDS_PLACEHOLDER",  $cardsHtml
$htmlFinal = $htmlFinal -replace "SW_ROWS",            $swRows
$htmlFinal = $htmlFinal -replace "PROC_ROWS",          $procRows
$htmlFinal = $htmlFinal -replace "USB_ROWS",           $usbRows
$htmlFinal = $htmlFinal -replace "NOW_PLACEHOLDER",    $now
$htmlFinal = $htmlFinal -replace "PC_PLACEHOLDER",     $pc

[System.IO.File]::WriteAllText($ReportPath, $htmlFinal, [System.Text.Encoding]::UTF8)
Start-Process $ReportPath

Write-Host "  [OK] Demo zvit zberezheno na Robochomu stoli" -ForegroundColor Green
Write-Host "  StaffSpy_DEMO.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Povna versiia: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Natysnit Enter dlia vykhodu"
