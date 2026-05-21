# ================================================================
#  StaffSpy — installer.ps1
#  Запускати ОДИН РАЗ від Адміністратора на кожному ПК
#  Вмикає вбудований аудит Windows. Без ліцензії.
# ================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[x] $msg" -ForegroundColor Red }

Clear-Host
Write-Host @"

  ██████ ████████  █████  ███████ ███████ ███████ ██████  ██    ██
  ██        ██    ██   ██ ██      ██      ██      ██   ██  ██  ██
  ███████   ██    ███████ █████   █████   ███████ ██████    ████
       ██   ██    ██   ██ ██      ██           ██ ██         ██
  ██████    ██    ██   ██ ██      ██      ███████ ██         ██

  Installer v1.0  |  Налаштування моніторингу
"@ -ForegroundColor Cyan

Write-Host ""

# ---- Перевірка ОС ----
$os = Get-WmiObject Win32_OperatingSystem
Write-Step "Система: $($os.Caption) | $($os.OSArchitecture)"

$build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
if ($build -lt 7601) {
    Write-Fail "Потрібен Windows 7 SP1 або новіший. Встановлення скасовано."
    exit 1
}
Write-OK "Версія Windows підтримується (build $build)"

# ---- 1. Увімкнути аудит запуску/завершення процесів ----
Write-Host ""
Write-Step "Крок 1/4: Вмикаю аудит процесів..."

try {
    # Process Creation (4688) + Process Termination (4689)
    auditpol /set /subcategory:"Process Creation"     /success:enable /failure:enable 2>&1 | Out-Null
    auditpol /set /subcategory:"Process Termination"  /success:enable /failure:enable 2>&1 | Out-Null

    # Перевірити що увімкнулось
    $check = auditpol /get /subcategory:"Process Creation" 2>&1
    if ($check -match "Success and Failure|Success") {
        Write-OK "Аудит запуску процесів: УВІМКНЕНО"
    } else {
        # Спробувати через локалізовані назви (українська/російська Windows)
        auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable 2>&1 | Out-Null
        auditpol /set /subcategory:"{0CCE9239-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Аудит запуску процесів: УВІМКНЕНО (через GUID)"
    }
} catch {
    Write-Fail "Помилка при налаштуванні аудиту: $_"
    exit 1
}

# ---- 2. Увімкнути збереження імені виконуваного файлу в логах ----
Write-Step "Крок 2/4: Вмикаю розширений аудит (командний рядок процесу)..."

try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    Write-OK "Розширений аудит командного рядка: УВІМКНЕНО"
} catch {
    Write-Warn "Розширений аудит не вдалося увімкнути (не критично): $_"
}

# ---- 3. Збільшити розмір Security Event Log до 200MB ----
Write-Step "Крок 3/4: Налаштовую розмір журналу подій (200 MB)..."

try {
    $logName = "Security"
    $log = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($logName)

    $currentMB = [math]::Round($log.MaximumSizeInBytes / 1MB, 0)
    Write-Step "  Поточний розмір: $currentMB MB → буде: 200 MB"

    $log.MaximumSizeInBytes = 200MB
    $log.LogMode = [System.Diagnostics.Eventing.Reader.EventLogMode]::Circular  # перезапис старих
    $log.SaveChanges()

    Write-OK "Журнал Security Event Log: 200 MB, режим кругового запису"
} catch {
    # Fallback через wevtutil
    try {
        wevtutil sl Security /ms:209715200 /rt:false 2>&1 | Out-Null
        Write-OK "Журнал Security Event Log: 200 MB (через wevtutil)"
    } catch {
        Write-Warn "Не вдалося змінити розмір журналу: $_ (не критично)"
    }
}

# ---- 4. Застосувати групові політики ----
Write-Step "Крок 4/4: Застосовую політики..."

try {
    gpupdate /force 2>&1 | Out-Null
    Write-OK "Групові політики оновлено"
} catch {
    Write-Warn "gpupdate не вдався, але аудит вже активний"
}

# ---- Перевірка результату ----
Write-Host ""
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ПЕРЕВІРКА НАЛАШТУВАНЬ" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray

$auditResult = auditpol /get /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" 2>&1
if ($auditResult -match "Success") {
    Write-OK "Аудит Process Creation: активний"
} else {
    Write-Warn "Аудит Process Creation: перевір вручну (auditpol /get /category:*)"
}

$logInfo = wevtutil gl Security 2>&1
$maxSize = ($logInfo | Select-String "maxSize") -replace ".*: ",""
if ($maxSize) {
    $mb = [math]::Round([long]$maxSize / 1MB, 0)
    Write-OK "Розмір Security Log: $mb MB"
}

# ---- Запис мітки встановлення ----
$installInfo = @{
    installed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    computer     = $env:COMPUTERNAME
    os           = $os.Caption
    installed_by = $env:USERNAME
    version      = "1.0"
}

$installPath = "C:\Windows\System32\winevt\staffspy_install.json"
try {
    $installInfo | ConvertTo-Json | Out-File -FilePath $installPath -Encoding UTF8 -Force
    Write-OK "Мітка встановлення збережена"
} catch {
    # Тихо ігноруємо — не критично
}

# ---- Фінал ----
Write-Host ""
Write-Host "  ═════════════════════════════════════════" -ForegroundColor Green
Write-Host "   ВСТАНОВЛЕННЯ ЗАВЕРШЕНО УСПІШНО" -ForegroundColor Green
Write-Host "  ═════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Моніторинг активний з цього моменту." -ForegroundColor White
Write-Host "  Через тиждень запустіть launcher.ps1" -ForegroundColor White
Write-Host "  для отримання повного звіту." -ForegroundColor White
Write-Host ""
Write-Host "  Комп'ютер: $($env:COMPUTERNAME)" -ForegroundColor DarkGray
Write-Host "  Встановив: $($env:USERNAME)" -ForegroundColor DarkGray
Write-Host "  Дата:      $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -ForegroundColor DarkGray
Write-Host ""

Read-Host "  Натисніть Enter для виходу"
