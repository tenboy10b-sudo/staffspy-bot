# ================================================================
#  StaffSpy — launcher.ps1
#  Файл який отримує клієнт після оплати.
#  Перевіряє ліцензію → завантажує spy_core.ps1 в пам'ять.
# ================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ================================================================
#  КОНФІГУРАЦІЯ (заповнюється автоматично ботом при видачі)
# ================================================================
$GITHUB_OWNER  = "tenboy10b-sudo"
$GITHUB_REPO   = "staffspy-private"
$RAILWAY_URL   = "https://YOUR-PROJECT.up.railway.app"  # замінить бот
$LICENSE_KEY   = "XXXX-XXXX-XXXX-XXXX"                 # замінить бот
$LICENSE_PASS  = "XXXXXXXXXX"                            # замінить бот

# ================================================================
Clear-Host

Write-Host @"

  ██████ ████████  █████  ███████ ███████
  ██        ██    ██   ██ ██      ██
  ███████   ██    ███████ █████   █████
       ██   ██    ██   ██ ██      ██
  ██████    ██    ██   ██ ██      ██      ███████ ██████  ██    ██

"@ -ForegroundColor Yellow

Write-Host "  Запуск аналізу активності персоналу..." -ForegroundColor White
Write-Host ""

function Write-Step { param($msg) Write-Host "  [*] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  [x] $msg" -ForegroundColor Red; Read-Host "`n  Натисніть Enter для виходу"; exit 1 }

# ================================================================
#  КРОК 1 — Перевірка ліцензії
# ================================================================
Write-Step "Перевірка ліцензії..."

try {
    $licensesUrl = "https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/main/licenses.json"
    $headers = @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }

    $response = Invoke-WebRequest -Uri $licensesUrl -Headers $headers -UseBasicParsing -TimeoutSec 15
    $data = $response.Content | ConvertFrom-Json

    $license = $data.licenses | Where-Object {
        $_.key -eq $LICENSE_KEY -and $_.password -eq $LICENSE_PASS
    }

    if (-not $license) {
        Write-Fail "Невірний ключ або пароль ліцензії. Зверніться до підтримки."
    }

    if (-not $license.active) {
        Write-Fail "Ліцензія деактивована. Зверніться до підтримки."
    }

    if ($license.runs_used -ge $license.runs_max) {
        Write-Fail "Ліцензію вичерпано ($($license.runs_used)/$($license.runs_max) запусків). Придбайте новий тариф."
    }

    $runsLeft = $license.runs_max - $license.runs_used
    Write-OK "Ліцензія: $($license.owner) | Залишилось запусків: $runsLeft"

} catch {
    if ($_.Exception.Message -match "401|403|404") {
        Write-Fail "Помилка доступу до ліцензійного сервера. Перевірте інтернет-з'єднання."
    }
    Write-Fail "Не вдалося підключитися до сервера ліцензій: $_"
}

# ================================================================
#  КРОК 2 — Оновити лічильник запусків
# ================================================================
Write-Step "Активую запуск..."

try {
    # Отримати поточний SHA файлу для PUT запиту
    $apiUrl  = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/contents/licenses.json"
    $apiResp = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 15
    $apiData = $apiResp.Content | ConvertFrom-Json
    $fileSha = $apiData.sha

    # Оновити runs_used
    $idx = [array]::IndexOf($data.licenses, $license)
    $data.licenses[$idx].runs_used = $license.runs_used + 1

    # Додати в launch_history
    $launchTime = Get-Date -Format "dd.MM.yyyy HH:mm"

    # Відправити оновлений файл через GitHub API
    $newContent = $data | ConvertTo-Json -Depth 10 -Compress
    $encoded    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newContent))

    $body = @{
        message = "launcher: $LICENSE_KEY used at $launchTime"
        content = $encoded
        sha     = $fileSha
    } | ConvertTo-Json

    # Цей запит потребує токена — він буде передаватись через Railway webhook
    # Тут просто надсилаємо webhook і Railway оновлює файл
    $webhookBody = @{
        action      = "use_license"
        key         = $LICENSE_KEY
        owner       = $license.owner
        launch_time = $launchTime
        computer    = $env:COMPUTERNAME
        user        = $env:USERNAME
    } | ConvertTo-Json

    Invoke-WebRequest -Uri "$RAILWAY_URL/launch" `
        -Method POST `
        -Body $webhookBody `
        -ContentType "application/json" `
        -UseBasicParsing `
        -TimeoutSec 15 | Out-Null

    Write-OK "Запуск зареєстровано"

} catch {
    # Не зупиняємо виконання — webhook може не відповісти, але звіт все одно робимо
    Write-Host "  [!] Webhook не відповів (не критично)" -ForegroundColor DarkGray
}

# ================================================================
#  КРОК 3 — Перевірка чи встановлений інсталятор
# ================================================================
Write-Step "Перевірка налаштувань системи..."

$auditCheck = auditpol /get /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" 2>&1
if ($auditCheck -notmatch "Success") {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  УВАГА: Аудит не налаштовано!               ║" -ForegroundColor Red
    Write-Host "  ║  Спочатку запустіть installer.ps1           ║" -ForegroundColor Red
    Write-Host "  ║  від Адміністратора на цьому комп'ютері.    ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Звіт буде містити тільки поточні процеси." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 3
}

# ================================================================
#  КРОК 4 — Завантажити та виконати spy_core.ps1 в пам'ять
# ================================================================
Write-Step "Завантажую модуль аналізу..."

try {
    $coreUrl = "https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/main/spy_core.ps1"

    # Додати унікальний параметр щоб уникнути кешування
    $coreUrl += "?t=$(Get-Date -UFormat %s)"

    $coreCode = (Invoke-WebRequest -Uri $coreUrl -UseBasicParsing -TimeoutSec 30).Content

    if (-not $coreCode -or $coreCode.Length -lt 100) {
        Write-Fail "Не вдалося завантажити модуль аналізу. Перевірте інтернет-з'єднання."
    }

    Write-OK "Модуль завантажено ($([math]::Round($coreCode.Length/1KB,1)) KB)"

} catch {
    Write-Fail "Помилка завантаження модуля: $_"
}

# ================================================================
#  КРОК 5 — Визначити шлях для звіту
# ================================================================
$reportDir  = "C:\StaffSpy"
$reportName = "StaffSpyReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').html"
$reportPath = "$reportDir\$reportName"

if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

Write-OK "Звіт буде збережено: $reportPath"
Write-Host ""

# ================================================================
#  КРОК 6 — Виконати spy_core.ps1 в пам'яті
# ================================================================
Write-Step "Запускаю аналіз (це може зайняти 1-2 хвилини)..."
Write-Host ""

# Передати параметри через змінні середовища щоб не модифікувати код
$env:STAFFSPY_REPORT_PATH = $reportPath
$env:STAFFSPY_DAYS_BACK   = "7"

# Виконати код в пам'яті — клієнт не бачить вихідний код
Invoke-Expression $coreCode

# ================================================================
#  ФІНАЛ
# ================================================================
Write-Host ""
Write-Host "  ═══════════════════════════════════════════" -ForegroundColor Green
Write-Host "   АНАЛІЗ ЗАВЕРШЕНО" -ForegroundColor Green
Write-Host "  ═══════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Звіт збережено:" -ForegroundColor White
Write-Host "  $reportPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Залишилось запусків: $($runsLeft - 1)" -ForegroundColor $(if(($runsLeft-1) -le 1){"Yellow"}else{"White"})

if (($runsLeft - 1) -le 1) {
    Write-Host ""
    Write-Host "  [!] Запуски закінчуються. Поповніть ліцензію:" -ForegroundColor Yellow
    Write-Host "  t.me/StaffSpy_Bot" -ForegroundColor Cyan
}

Write-Host ""
Read-Host "  Натисніть Enter для виходу"
