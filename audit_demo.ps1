# StaffSpy - audit_demo.ps1 v2.0
$ErrorActionPreference = "SilentlyContinue"
$RAILWAY_URL = "https://web-production-b6c66.up.railway.app"
$ReportPath  = "$env:USERPROFILE\Desktop\StaffSpy_DEMO.html"

Clear-Host

# Copy HTML template to TEMP
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateSrc = Join-Path $scriptDir "staffspy_template.html"
if (Test-Path $templateSrc) {
    Copy-Item $templateSrc "$env:TEMP\staffspy_template.html" -Force
} else {
    Write-Host "  [!] Ne znayshov staffspy_template.html v tiy samiy papci" -ForegroundColor Red
    Read-Host "  Natysnit Enter"
    exit 1
}

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
Write-Host "  [OK] Systema: OK" -ForegroundColor Green

Write-Host "  Zbyrayu vstanovlene PZ..." -ForegroundColor Cyan
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


$htmlTemplate = Get-Content -Path "$env:TEMP\staffspy_template.html" -Raw -Encoding UTF8

$headerHtml = "<div class=header><div><div class=logo>Staff<span>Spy</span><span class=badge>DEMO</span></div><div style=font-size:.6rem;color:#94a3b8;margin-top:.3rem>Demo - 4 z 22 moduliv</div></div><div class=meta>" + $now + " | " + $pc + "<br>" + $usr + " | " + $osName + "</div></div>"
$cardsHtml  = "<div class=card><div class=card-l>OS</div><div class=card-v style=font-size:.85rem>" + $osName + "</div></div><div class=card><div class=card-l>RAM</div><div class=card-v>" + $ramGB + " GB</div></div><div class=card><div class=card-l>Uptime</div><div class=card-v style=font-size:.95rem>" + $uptimeStr + "</div></div><div class=card><div class=card-l>Protsesiv</div><div class=card-v>" + $processes.Count + "</div></div><div class=card><div class=card-l>Prohram</div><div class=card-v>" + $software.Count + "</div></div><div class=card><div class=card-l>USB</div><div class=card-v>" + $usbDevices.Count + "</div></div>"

$htmlFinal = $htmlTemplate
$htmlFinal = $htmlFinal -replace "HEADER_PLACEHOLDER", $headerHtml
$htmlFinal = $htmlFinal -replace "CARDS_PLACEHOLDER",  $cardsHtml
$htmlFinal = $htmlFinal -replace "SW_ROWS",            $swRows
$htmlFinal = $htmlFinal -replace "PROC_ROWS",          $procRows
$htmlFinal = $htmlFinal -replace "USB_ROWS",           $usbRows
$htmlFinal = $htmlFinal -replace "NOW_PLACEHOLDER",    $now
$htmlFinal = $htmlFinal -replace "PC_PLACEHOLDER",     $pc

$htmlFinal | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
Start-Process $ReportPath

Write-Host "  [OK] Demo zvit zberezheno na Robochomu stoli" -ForegroundColor Green
Write-Host "  StaffSpy_DEMO.html" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Povna versiia: t.me/StaffSpy_01_Bot" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Natysnit Enter dlia vykhodu"
