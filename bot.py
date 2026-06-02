"""
StaffSpy — bot.py
Telegram бот продажів. Розгортається на Railway.
"""

import os
import json
import base64
import hashlib
import random
import string
import logging
from datetime import datetime
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    InputFile
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler
)
import httpx

# ── Логування ──────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s │ %(levelname)s │ %(message)s",
    level=logging.INFO
)
log = logging.getLogger(__name__)

# ── Змінні середовища ──────────────────────────────────────────
TOKEN         = os.environ["TELEGRAM_TOKEN"]
GITHUB_TOKEN  = os.environ["GITHUB_TOKEN"]
GITHUB_OWNER  = os.environ.get("GITHUB_OWNER", "tenboy10b-sudo")
GITHUB_REPO   = os.environ.get("GITHUB_REPO",  "staffspy-private")
ADMIN_ID      = int(os.environ.get("ADMIN_CHAT_ID", "8614909455"))
BOT_USERNAME  = os.environ.get("BOT_USERNAME", "StaffSpy_Bot")

# ── Тарифи ────────────────────────────────────────────────────
TARIFFS = {
    "start":   {"name": "Старт",   "runs": 3,  "price": 9,  "emoji": "🟢"},
    "basic":   {"name": "Базовий", "runs": 5,  "price": 15, "emoji": "🔵"},
    "pro":     {"name": "Про",     "runs": 10, "price": 22, "emoji": "🟣"},
}

PROMOS = {
    "DEMO20":   0.20,
    "AUDIT15":  0.15,
    "VIP30":    0.30,
    "STAFF10":  0.10,
}

# ── Реквізити ──────────────────────────────────────────────────
MONO_CARD = "4441 1114 0021 9824"
USDT_ADDR = "TWmWeRiynWJgAaJRLwgU2fZAG6U8fz6xd8"

# ── Стани ConversationHandler ──────────────────────────────────
(
    STATE_MENU,
    STATE_TARIFF,
    STATE_PROMO,
    STATE_PAYMENT_METHOD,
    STATE_WAITING_SCREENSHOT,
    STATE_ADMIN_NOTE,
    STATE_ADMIN_SEARCH,
) = range(7)

# ══════════════════════════════════════════════════════════════
#  GITHUB HELPERS
# ══════════════════════════════════════════════════════════════
GITHUB_API = "https://api.github.com"
GH_HEADERS = {
    "Authorization": f"token {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json",
}

async def gh_get_file(filename: str) -> tuple[dict, str]:
    """Повертає (parsed_json, sha)"""
    url = f"{GITHUB_API}/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{filename}"
    async with httpx.AsyncClient() as c:
        r = await c.get(url, headers=GH_HEADERS, timeout=15)
        r.raise_for_status()
        data = r.json()
        content = base64.b64decode(data["content"]).decode("utf-8")
        return json.loads(content), data["sha"]

async def gh_put_file(filename: str, content: dict, sha: str, message: str):
    """Оновлює файл на GitHub"""
    url = f"{GITHUB_API}/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{filename}"
    encoded = base64.b64encode(
        json.dumps(content, ensure_ascii=False, indent=2).encode("utf-8")
    ).decode("utf-8")
    body = {"message": message, "content": encoded, "sha": sha}
    async with httpx.AsyncClient() as c:
        r = await c.put(url, headers=GH_HEADERS, json=body, timeout=15)
        r.raise_for_status()

# ══════════════════════════════════════════════════════════════
#  ГЕНЕРАЦІЯ ЛІЦЕНЗІЇ
# ══════════════════════════════════════════════════════════════
def gen_key() -> str:
    parts = [''.join(random.choices(string.ascii_uppercase + string.digits, k=4)) for _ in range(4)]
    return '-'.join(parts)

def gen_password() -> str:
    return ''.join(random.choices(string.ascii_letters + string.digits, k=12))

# ══════════════════════════════════════════════════════════════
#  КЛАВІАТУРИ
# ══════════════════════════════════════════════════════════════
def kb_main(is_admin=False):
    rows = [
        [InlineKeyboardButton("🎯 Безкоштовне демо",   callback_data="demo")],
        [InlineKeyboardButton("🛒 Придбати ліцензію",  callback_data="buy")],
        [InlineKeyboardButton("📋 Мої ліцензії",       callback_data="my_licenses")],
        [InlineKeyboardButton("❓ Підтримка",           callback_data="support")],
    ]
    if is_admin:
        rows.append([InlineKeyboardButton("⚙️ Адмін панель", callback_data="admin")])
    return InlineKeyboardMarkup(rows)

def kb_tariffs(promo_discount=0):
    rows = []
    for key, t in TARIFFS.items():
        price = t["price"]
        if promo_discount:
            price = round(price * (1 - promo_discount))
            label = f"{t['emoji']} {t['name']} — {price}$ (знижка {int(promo_discount*100)}%)"
        else:
            label = f"{t['emoji']} {t['name']} — {price}$ ({t['runs']} запусків)"
        rows.append([InlineKeyboardButton(label, callback_data=f"tariff_{key}")])
    rows.append([InlineKeyboardButton("🏷 У мене є промокод", callback_data="promo")])
    rows.append([InlineKeyboardButton("◀️ Назад", callback_data="back_main")])
    return InlineKeyboardMarkup(rows)

def kb_payment():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💳 Monobank (UAH)", callback_data="pay_mono")],
        [InlineKeyboardButton("💰 USDT TRC-20",    callback_data="pay_usdt")],
        [InlineKeyboardButton("◀️ Назад",           callback_data="back_tariffs")],
    ])

def kb_paid():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Я оплатив — надіслати скрін", callback_data="paid")],
        [InlineKeyboardButton("◀️ Назад", callback_data="back_payment")],
    ])

def kb_admin_license(telegram_id, tariff_key, runs):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(f"✅ Видати ліцензію ({runs} запусків)",
                              callback_data=f"issue_{telegram_id}_{tariff_key}")],
        [InlineKeyboardButton("❌ Відхилити оплату",
                              callback_data=f"reject_{telegram_id}")],
    ])

def kb_admin_main():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👥 Клієнти",    callback_data="adm_clients")],
        [InlineKeyboardButton("📊 Статистика", callback_data="adm_stats")],
        [InlineKeyboardButton("🔍 Пошук",      callback_data="adm_search")],
        [InlineKeyboardButton("◀️ Головна",    callback_data="back_main")],
    ])

# ══════════════════════════════════════════════════════════════
#  /start
# ══════════════════════════════════════════════════════════════
async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    is_admin = user.id == ADMIN_ID

    text = (
        f"👋 Привіт, *{user.first_name}*!\n\n"
        "🕵️ *StaffSpy* — інструмент моніторингу активності персоналу.\n\n"
        "📌 *Що робить:*\n"
        "• Записує які програми запускались\n"
        "• Час запуску та закриття кожної\n"
        "• Тривалість роботи\n"
        "• Який користувач працював\n"
        "• Детальний HTML звіт одним кліком\n\n"
        "⚡️ *Як працює:*\n"
        "1️⃣ Встановлюєш `installer.ps1` один раз\n"
        "2️⃣ Через тиждень запускаєш `launcher.ps1`\n"
        "3️⃣ Отримуєш повний звіт за весь період\n\n"
        "Обери дію:"
    )

    await update.message.reply_text(
        text,
        parse_mode="Markdown",
        reply_markup=kb_main(is_admin)
    )
    return STATE_MENU

# ══════════════════════════════════════════════════════════════
#  КУПІВЛЯ
# ══════════════════════════════════════════════════════════════
async def cb_buy(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    discount = ctx.user_data.get("promo_discount", 0)
    await q.edit_message_text(
        "💼 *Оберіть тариф:*\n\n"
        "Один запуск = один повний звіт з будь-якого ПК.",
        parse_mode="Markdown",
        reply_markup=kb_tariffs(discount)
    )
    return STATE_TARIFF

async def cb_promo(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    await q.edit_message_text(
        "🏷 Введіть промокод:",
        reply_markup=InlineKeyboardMarkup([[
            InlineKeyboardButton("◀️ Назад", callback_data="buy")
        ]])
    )
    return STATE_PROMO

async def handle_promo(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    code = update.message.text.strip().upper()
    if code in PROMOS:
        ctx.user_data["promo_code"]     = code
        ctx.user_data["promo_discount"] = PROMOS[code]
        discount_pct = int(PROMOS[code] * 100)
        await update.message.reply_text(
            f"✅ Промокод *{code}* активовано — знижка *{discount_pct}%*!",
            parse_mode="Markdown",
            reply_markup=kb_tariffs(PROMOS[code])
        )
    else:
        await update.message.reply_text(
            "❌ Промокод не знайдено. Спробуйте ще раз або оберіть тариф без знижки.",
            reply_markup=InlineKeyboardMarkup([[
                InlineKeyboardButton("◀️ До тарифів", callback_data="buy")
            ]])
        )
    return STATE_TARIFF

async def cb_tariff(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()

    tariff_key = q.data.replace("tariff_", "")
    tariff = TARIFFS[tariff_key]
    discount = ctx.user_data.get("promo_discount", 0)
    price = round(tariff["price"] * (1 - discount))

    ctx.user_data["tariff_key"]  = tariff_key
    ctx.user_data["tariff_name"] = tariff["name"]
    ctx.user_data["tariff_runs"] = tariff["runs"]
    ctx.user_data["final_price"] = price

    await q.edit_message_text(
        f"{tariff['emoji']} *Тариф: {tariff['name']}*\n\n"
        f"• Запусків: *{tariff['runs']}*\n"
        f"• Сума до сплати: *{price}$*\n"
        f"{'• Знижка: ' + str(int(discount*100)) + '%' if discount else ''}\n\n"
        "Оберіть спосіб оплати:",
        parse_mode="Markdown",
        reply_markup=kb_payment()
    )
    return STATE_PAYMENT_METHOD

async def cb_payment_method(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()

    method = q.data
    price  = ctx.user_data.get("final_price", "?")
    tariff = ctx.user_data.get("tariff_name", "?")

    if method == "pay_mono":
        ctx.user_data["payment_method"] = "Monobank"
        details = (
            f"💳 *Оплата Monobank (UAH)*\n\n"
            f"Номер картки:\n`{MONO_CARD}`\n\n"
            f"Сума: *{price}$* (за курсом банку)\n"
            f"Призначення: *StaffSpy {tariff}*\n\n"
            "⚠️ Після оплати натисніть кнопку нижче і надішліть скрін."
        )
    else:
        ctx.user_data["payment_method"] = "USDT"
        details = (
            f"💰 *Оплата USDT TRC-20*\n\n"
            f"Адреса:\n`{USDT_ADDR}`\n\n"
            f"Сума: *{price} USDT*\n\n"
            "⚠️ Після оплати натисніть кнопку нижче і надішліть скрін транзакції."
        )

    await q.edit_message_text(details, parse_mode="Markdown", reply_markup=kb_paid())
    return STATE_WAITING_SCREENSHOT

async def cb_paid(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    await q.edit_message_text(
        "📸 Надішліть скріншот оплати прямо в цей чат.\n\n"
        "_Скрін буде перевірено протягом 15 хвилин._",
        parse_mode="Markdown"
    )
    return STATE_WAITING_SCREENSHOT

async def handle_screenshot(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not update.message.photo:
        await update.message.reply_text("⚠️ Будь ласка, надішліть саме фото скріншоту.")
        return STATE_WAITING_SCREENSHOT

    user   = update.effective_user
    photo  = update.message.photo[-1]
    tariff = ctx.user_data.get("tariff_name", "?")
    runs   = ctx.user_data.get("tariff_runs", 0)
    price  = ctx.user_data.get("final_price", "?")
    method = ctx.user_data.get("payment_method", "?")
    promo  = ctx.user_data.get("promo_code", "—")

    # Зберегти дані для адміна
    ctx.bot_data.setdefault("pending_payments", {})[str(user.id)] = {
        "telegram_id": user.id,
        "name":        user.full_name,
        "username":    f"@{user.username}" if user.username else "—",
        "tariff":      tariff,
        "tariff_key":  ctx.user_data.get("tariff_key"),
        "runs":        runs,
        "price":       price,
        "method":      method,
        "promo":       promo,
        "date":        datetime.now().strftime("%d.%m.%Y %H:%M"),
    }

    # Повідомлення клієнту
    await update.message.reply_text(
        "✅ *Скрін отримано!*\n\n"
        "⏳ Чекай підтвердження протягом 15 хвилин.\n"
        "Після перевірки ти отримаєш ключ і всі файли.",
        parse_mode="Markdown"
    )

    # Повідомлення адміну
    admin_text = (
        f"💰 *НОВА ОПЛАТА — StaffSpy*\n\n"
        f"👤 {user.full_name} ({f'@{user.username}' if user.username else user.id})\n"
        f"🆔 ID: `{user.id}`\n"
        f"📦 Тариф: *{tariff}* ({runs} запусків)\n"
        f"💵 Сума: *{price}$*\n"
        f"💳 Метод: {method}\n"
        f"🏷 Промо: {promo}\n"
        f"🕐 Час: {datetime.now().strftime('%d.%m.%Y %H:%M')}"
    )

    await ctx.bot.send_photo(
        chat_id=ADMIN_ID,
        photo=photo.file_id,
        caption=admin_text,
        parse_mode="Markdown",
        reply_markup=kb_admin_license(user.id, ctx.user_data.get("tariff_key"), runs)
    )

    return ConversationHandler.END

# ══════════════════════════════════════════════════════════════
#  АДМІН — ВИДАЧА ЛІЦЕНЗІЇ
# ══════════════════════════════════════════════════════════════
async def cb_issue_license(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()

    if q.from_user.id != ADMIN_ID:
        return

    parts      = q.data.split("_")  # issue_TELEGRAMID_TARIFFKEY
    client_id  = int(parts[1])
    tariff_key = parts[2]
    tariff     = TARIFFS[tariff_key]

    pending = ctx.bot_data.get("pending_payments", {}).get(str(client_id), {})

    key  = gen_key()
    pwd  = gen_password()
    now  = datetime.now().strftime("%Y-%m-%d")
    runs = tariff["runs"]

    try:
        # Оновити licenses.json
        lic_data, lic_sha = await gh_get_file("licenses.json")
        new_license = {
            "key":       key,
            "password":  pwd,
            "owner":     pending.get("name", "Client"),
            "runs_max":  runs,
            "runs_used": 0,
            "active":    True,
            "created":   now,
            "telegram_id": client_id
        }
        lic_data["licenses"].append(new_license)
        await gh_put_file("licenses.json", lic_data, lic_sha,
                          f"issue license {key} to {client_id}")

        # Оновити clients.json
        cli_data, cli_sha = await gh_get_file("clients.json")
        new_client = {
            "telegram_id":    str(client_id),
            "name":           pending.get("name", "—"),
            "username":       pending.get("username", "—"),
            "date":           pending.get("date", now),
            "tariff":         tariff["name"],
            "runs":           runs,
            "price_usd":      str(pending.get("price", "?")),
            "payment_method": pending.get("method", "—"),
            "license_key":    key,
            "runs_used":      0,
            "status":         "Активна",
            "promo_used":     pending.get("promo", "—"),
            "repeat_client":  "Ні",
            "launch_history": [],
            "note":           ""
        }
        cli_data["clients"].append(new_client)
        await gh_put_file("clients.json", cli_data, cli_sha,
                          f"add client {client_id}")

    except Exception as e:
        await q.message.reply_text(f"❌ Помилка запису в GitHub: {e}")
        return

    # Prepare launcher.ps1 with license data
    try:
        with open("launcher.ps1", "r", encoding="utf-8-sig") as f:
            launcher_code = f.read()

        launcher_code = launcher_code.replace('$LICENSE_KEY   = "XXXX-XXXX-XXXX-XXXX"', f'$LICENSE_KEY   = "{key}"')
        launcher_code = launcher_code.replace('$LICENSE_PASS  = "XXXXXXXXXX"',           f'$LICENSE_PASS  = "{pwd}"')
        launcher_code = launcher_code.replace(
            '$RAILWAY_URL   = "https://YOUR-PROJECT.up.railway.app"',
            f'$RAILWAY_URL   = "{os.environ.get("RAILWAY_URL", "https://your-railway-url.up.railway.app")}"'
        )
        launcher_bytes = launcher_code.encode("utf-8-sig")
    except Exception as e:
        await q.message.reply_text(f"❌ Помилка підготовки launcher: {e}")
        return

    # Send license info
    license_text = (
        "🎉 Ваша ліцензія StaffSpy активована!\n\n"
        f"🔑 Ключ: {key}\n"
        f"🔒 Пароль: {pwd}\n\n"
        f"📦 Тариф: {tariff['name']} ({runs} запусків)\n\n"
        "📋 Нижче три файли — інструкція під кожним."
    )
    await ctx.bot.send_message(client_id, license_text)

    # File 1 - installer.ps1
    try:
        cap1 = (
            "1️⃣ installer.ps1 — запустити ПЕРШИМ, один раз на кожному ПК\n\n"
            "Збережіть на робочий стіл, потім PowerShell від адміна:\n\n"
            "powershell.exe -ExecutionPolicy Bypass -File C:\\Users\\Desktop\\installer.ps1"
        )
        await ctx.bot.send_document(client_id, document=open("installer.ps1", "rb"), caption=cap1)
    except Exception as e:
        await ctx.bot.send_message(client_id, "installer.ps1 — запустити першим від адміна")

    # File 2 - launcher.ps1
    try:
        cap2 = (
            "2️⃣ launcher.ps1 — запускати для отримання звіту\n\n"
            "Збережіть на робочий стіл, потім PowerShell від адміна:\n\n"
            "powershell.exe -ExecutionPolicy Bypass -File C:\\Users\\Desktop\\launcher.ps1"
        )
        await ctx.bot.send_document(client_id, document=InputFile(bytes(launcher_bytes), filename="launcher.ps1"), caption=cap2)
    except Exception as e:
        await ctx.bot.send_message(client_id, "launcher.ps1 — запускати для звіту")

    # File 3 - manual.html
    try:
        cap3 = (
            "3️⃣ manual.html — інструкція з використання\n\n"
            "Відкрийте у браузері — там детальний опис кожного кроку та всі команди."
        )
        await ctx.bot.send_document(client_id, document=open("manual.html", "rb"), caption=cap3)
    except Exception as e:
        await ctx.bot.send_message(client_id, "manual.html — інструкція")

    # Повідомити адміна
    await q.edit_message_caption(
        caption=q.message.caption + f"\n\n✅ *ВИДАНО* | Ключ: `{key}`",
        parse_mode="Markdown"
    )

    # Очистити pending
    ctx.bot_data.get("pending_payments", {}).pop(str(client_id), None)

async def cb_reject_payment(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()

    if q.from_user.id != ADMIN_ID:
        return

    client_id = int(q.data.split("_")[1])

    await ctx.bot.send_message(
        client_id,
        "❌ *Оплату не підтверджено.*\n\n"
        "Можлива причина: скрін нечіткий або сума не збігається.\n"
        "Зверніться в підтримку: @StaffSpy_Bot",
        parse_mode="Markdown"
    )
    await q.edit_message_caption(
        caption=q.message.caption + "\n\n❌ *ВІДХИЛЕНО*",
        parse_mode="Markdown"
    )
    ctx.bot_data.get("pending_payments", {}).pop(str(client_id), None)

# ══════════════════════════════════════════════════════════════
#  ДЕМО
# ══════════════════════════════════════════════════════════════
async def cb_demo(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    user = q.from_user

    await q.edit_message_text(
        "🎯 *Демо версія StaffSpy*\n\n"
        "Демо включає:\n"
        "• Список поточних процесів\n"
        "• Базова інформація про систему\n"
        "• Приклад звіту (4 модулі)\n\n"
        "⚡️ Надсилаю демо файл...",
        parse_mode="Markdown"
    )

    try:
        await ctx.bot.send_document(
            q.message.chat_id,
            document=open("audit_demo.ps1", "rb"),
            caption=(
                "📦 *StaffSpy Demo*\n\n"
                "Запустіть від Адміністратора.\n"
                "Звіт збережеться на робочому столі.\n\n"
                "Для повної версії: /start → Придбати"
            ),
            parse_mode="Markdown"
        )
    except Exception:
        await ctx.bot.send_message(
            q.message.chat_id,
            "⚠️ Демо файл тимчасово недоступний. Зверніться в підтримку."
        )

    # Сповістити адміна
    await ctx.bot.send_message(
        ADMIN_ID,
        f"👁 *Демо запит — StaffSpy*\n\n"
        f"👤 {user.full_name} (@{user.username or '—'})\n"
        f"🆔 `{user.id}`\n"
        f"🕐 {datetime.now().strftime('%d.%m.%Y %H:%M')}",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup([[
            InlineKeyboardButton("💬 Надіслати знижку",
                                 callback_data=f"send_promo_{user.id}")
        ]])
    )

    # Зберегти демо юзера
    try:
        cli_data, cli_sha = await gh_get_file("clients.json")
        demo_users = cli_data.get("demo_users", [])
        if not any(d["telegram_id"] == str(user.id) for d in demo_users):
            demo_users.append({
                "telegram_id":    str(user.id),
                "name":           user.full_name,
                "username":       f"@{user.username}" if user.username else "—",
                "date":           datetime.now().strftime("%d.%m.%Y %H:%M"),
                "converted":      "Ні",
                "launch_history": [],
                "note":           ""
            })
            cli_data["demo_users"] = demo_users
            await gh_put_file("clients.json", cli_data, cli_sha,
                              f"add demo user {user.id}")
    except Exception:
        pass

# ══════════════════════════════════════════════════════════════
#  АДМІН ПАНЕЛЬ
# ══════════════════════════════════════════════════════════════
async def cb_admin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.from_user.id != ADMIN_ID:
        return

    await q.edit_message_text("⚙️ *Адмін панель — StaffSpy*", parse_mode="Markdown",
                               reply_markup=kb_admin_main())

async def cb_adm_stats(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.from_user.id != ADMIN_ID:
        return

    try:
        cli_data, _ = await gh_get_file("clients.json")
        clients     = cli_data.get("clients", [])
        demo_users  = cli_data.get("demo_users", [])

        total_revenue = sum(float(c.get("price_usd", 0)) for c in clients)
        tariff_counts = {}
        for c in clients:
            t = c.get("tariff", "—")
            tariff_counts[t] = tariff_counts.get(t, 0) + 1

        converted = sum(1 for d in demo_users if d.get("converted") == "Так")
        conversion = round(converted / len(demo_users) * 100) if demo_users else 0

        tariff_lines = "\n".join(f"  • {t}: {n}" for t, n in tariff_counts.items())

        text = (
            f"📊 *Статистика StaffSpy*\n\n"
            f"💰 Загальний дохід: *${total_revenue:.0f}*\n"
            f"👥 Покупців: *{len(clients)}*\n"
            f"🎯 Демо запитів: *{len(demo_users)}*\n"
            f"🔄 Конверсія демо→покупка: *{conversion}%*\n\n"
            f"📦 По тарифах:\n{tariff_lines or '  —'}"
        )
    except Exception as e:
        text = f"❌ Помилка: {e}"

    await q.edit_message_text(text, parse_mode="Markdown",
                               reply_markup=InlineKeyboardMarkup([[
                                   InlineKeyboardButton("◀️ Назад", callback_data="admin")
                               ]]))

async def cb_adm_clients(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.from_user.id != ADMIN_ID:
        return

    try:
        cli_data, _ = await gh_get_file("clients.json")
        clients = cli_data.get("clients", [])[-10:]  # останні 10

        lines = []
        for c in reversed(clients):
            lines.append(
                f"👤 *{c['name']}* ({c.get('username','—')})\n"
                f"   {c['tariff']} | ${c['price_usd']} | {c['date']}\n"
                f"   Ключ: `{c['license_key'][:9]}...`"
            )

        text = "👥 *Останні клієнти:*\n\n" + "\n\n".join(lines) if lines else "Клієнтів поки немає."
    except Exception as e:
        text = f"❌ Помилка: {e}"

    await q.edit_message_text(text, parse_mode="Markdown",
                               reply_markup=InlineKeyboardMarkup([[
                                   InlineKeyboardButton("◀️ Назад", callback_data="admin")
                               ]]))

async def cb_send_promo_to_demo(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.from_user.id != ADMIN_ID:
        return

    target_id = int(q.data.split("_")[-1])
    await ctx.bot.send_message(
        target_id,
        "🎁 *Спеціальна пропозиція для вас!*\n\n"
        "Промокод на *20% знижку*: `DEMO20`\n\n"
        "Дійсний 48 годин. Введіть при оформленні замовлення.\n\n"
        "👉 /start → Придбати → Є промокод",
        parse_mode="Markdown"
    )
    await q.answer("✅ Промокод надіслано!", show_alert=True)

# ══════════════════════════════════════════════════════════════
#  МОЇ ЛІЦЕНЗІЇ
# ══════════════════════════════════════════════════════════════
async def cb_my_licenses(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    user_id = str(q.from_user.id)

    try:
        lic_data, _ = await gh_get_file("licenses.json")
        my_lics = [l for l in lic_data["licenses"] if str(l.get("telegram_id")) == user_id]

        if not my_lics:
            text = "У вас немає активних ліцензій.\n\nПридбати: /start → Купити"
        else:
            lines = []
            for l in my_lics:
                status = "✅ Активна" if l["active"] else "❌ Деактивована"
                left   = l["runs_max"] - l["runs_used"]
                lines.append(
                    f"{status}\n"
                    f"Ключ: `{l['key']}`\n"
                    f"Запусків залишилось: *{left}/{l['runs_max']}*\n"
                    f"Дата: {l['created']}"
                )
            text = "🔑 *Ваші ліцензії:*\n\n" + "\n\n".join(lines)
    except Exception as e:
        text = f"❌ Помилка: {e}"

    await q.edit_message_text(text, parse_mode="Markdown",
                               reply_markup=InlineKeyboardMarkup([[
                                   InlineKeyboardButton("◀️ Назад", callback_data="back_main")
                               ]]))

# ══════════════════════════════════════════════════════════════
#  ПІДТРИМКА
# ══════════════════════════════════════════════════════════════
async def cb_support(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    await q.edit_message_text(
        "❓ *Підтримка StaffSpy*\n\n"
        "З усіх питань звертайтесь:\n"
        f"👨‍💻 Написати адміну особисто\n\n"
        "Звичайний час відповіді: до 30 хвилин.",
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup([[
            InlineKeyboardButton("◀️ Назад", callback_data="back_main")
        ]])
    )

# ══════════════════════════════════════════════════════════════
#  WEBHOOK /launch (від launcher.ps1)
# ══════════════════════════════════════════════════════════════
from telegram.ext import Application
from fastapi import FastAPI, Request
import uvicorn
import asyncio

web_app = FastAPI()
bot_app: Application = None

@web_app.post("/launch")
async def webhook_launch(request: Request):
    try:
        body = await request.json()
        key         = body.get("key", "—")
        owner       = body.get("owner", "—")
        computer    = body.get("computer", "—")
        launch_time = body.get("launch_time", datetime.now().strftime("%d.%m.%Y %H:%M"))
        is_demo     = body.get("demo", False)

        # Оновити runs_used в licenses.json
        if not is_demo:
            try:
                lic_data, lic_sha = await gh_get_file("licenses.json")
                for l in lic_data["licenses"]:
                    if l["key"] == key:
                        l["runs_used"] = l.get("runs_used", 0) + 1
                        break
                await gh_put_file("licenses.json", lic_data, lic_sha,
                                  f"launch {key} at {launch_time}")

                # Оновити launch_history в clients.json
                cli_data, cli_sha = await gh_get_file("clients.json")
                for c in cli_data["clients"]:
                    if c.get("license_key", "").startswith(key[:9]):
                        c.setdefault("launch_history", []).append(launch_time)
                        c["runs_used"] = c.get("runs_used", 0) + 1
                        break
                await gh_put_file("clients.json", cli_data, cli_sha,
                                  f"update launch history {key}")
            except Exception as e:
                log.error(f"GitHub update error: {e}")

        # Сповістити адміна
        tag  = "ДЕМО" if is_demo else "ПОВНА ВЕРСІЯ"
        text = (
            f"{'🎯' if is_demo else '🚀'} *ЗАПУСК — StaffSpy [{tag}]*\n\n"
            f"👤 Власник: *{owner}*\n"
            f"🔑 Ключ: `{key}`\n"
            f"💻 ПК: {computer}\n"
            f"🕐 Час: {launch_time}"
        )

        if bot_app:
            await bot_app.bot.send_message(ADMIN_ID, text, parse_mode="Markdown")

        return {"status": "ok"}
    except Exception as e:
        log.error(f"Webhook error: {e}")
        return {"status": "error", "detail": str(e)}

@web_app.get("/health")
async def health():
    return {"status": "ok", "service": "StaffSpy Bot"}

@web_app.get("/get-core")
async def get_core(key: str = "", password: str = ""):
    from fastapi.responses import PlainTextResponse
    import base64 as b64
    try:
        if not key or not password:
            return PlainTextResponse("# Missing params", status_code=400)

        # Verify license
        lic_data, _ = await gh_get_file("licenses.json")
        license = None
        for l in lic_data.get("licenses", []):
            if l.get("key") == key and l.get("password") == password:
                license = l
                break

        if not license or not license.get("active") or license.get("runs_used", 0) >= license.get("runs_max", 0):
            return PlainTextResponse("# Invalid license", status_code=403)

        # Get raw spy_core.ps1 from GitHub
        url = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/spy_core.ps1"
        async with httpx.AsyncClient() as c:
            r = await c.get(url, headers=GH_HEADERS, timeout=30)
            r.raise_for_status()
            raw_bytes = b64.b64decode(r.json()["content"])
            raw = raw_bytes.decode("utf-8-sig")

        return PlainTextResponse(raw, status_code=200, media_type="text/plain; charset=utf-8")

    except Exception as e:
        log.error(f"get-core error: {e}")
        return PlainTextResponse(f"# Error: {e}", status_code=500)

@web_app.post("/check-license")
async def check_license(request: Request):
    try:
        body = await request.json()
        key  = body.get("key", "")
        pwd  = body.get("password", "")

        if not key or not pwd:
            return {"valid": False, "error": "Missing key or password"}

        lic_data, _ = await gh_get_file("licenses.json")
        license = None
        for l in lic_data.get("licenses", []):
            if l.get("key") == key and l.get("password") == pwd:
                license = l
                break

        if not license:
            return {"valid": False, "error": "Invalid key or password"}
        if not license.get("active", False):
            return {"valid": False, "error": "License deactivated"}

        runs_used = license.get("runs_used", 0)
        runs_max  = license.get("runs_max", 0)
        if runs_used >= runs_max:
            return {"valid": False, "error": f"Runs exhausted ({runs_used}/{runs_max})"}

        return {
            "valid":     True,
            "owner":     license.get("owner", ""),
            "runs_left": runs_max - runs_used,
            "runs_max":  runs_max
        }

    except Exception as e:
        log.error(f"check-license error: {e}")
        return {"valid": False, "error": str(e)}

# ══════════════════════════════════════════════════════════════
#  НАВІГАЦІЯ (back кнопки)
# ══════════════════════════════════════════════════════════════
async def cb_back_main(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    is_admin = q.from_user.id == ADMIN_ID
    await q.edit_message_text(
        "👋 Головне меню *StaffSpy*\n\nОберіть дію:",
        parse_mode="Markdown",
        reply_markup=kb_main(is_admin)
    )
    return STATE_MENU

# ══════════════════════════════════════════════════════════════
#  ЗАПУСК
# ══════════════════════════════════════════════════════════════
def build_app() -> Application:
    global bot_app

    app = Application.builder().token(TOKEN).build()
    bot_app = app

    conv = ConversationHandler(
        entry_points=[CommandHandler("start", cmd_start)],
        states={
            STATE_MENU: [
                CallbackQueryHandler(cb_buy,         pattern="^buy$"),
                CallbackQueryHandler(cb_demo,        pattern="^demo$"),
                CallbackQueryHandler(cb_my_licenses, pattern="^my_licenses$"),
                CallbackQueryHandler(cb_support,     pattern="^support$"),
                CallbackQueryHandler(cb_admin,       pattern="^admin$"),
                CallbackQueryHandler(cb_adm_stats,   pattern="^adm_stats$"),
                CallbackQueryHandler(cb_adm_clients, pattern="^adm_clients$"),
                CallbackQueryHandler(cb_back_main,   pattern="^back_main$"),
            ],
            STATE_TARIFF: [
                CallbackQueryHandler(cb_tariff,    pattern="^tariff_"),
                CallbackQueryHandler(cb_promo,     pattern="^promo$"),
                CallbackQueryHandler(cb_buy,       pattern="^buy$"),
                CallbackQueryHandler(cb_back_main, pattern="^back_main$"),
                MessageHandler(filters.TEXT & ~filters.COMMAND, handle_promo),
            ],
            STATE_PAYMENT_METHOD: [
                CallbackQueryHandler(cb_payment_method, pattern="^pay_"),
                CallbackQueryHandler(cb_tariff,         pattern="^tariff_"),
                CallbackQueryHandler(cb_buy,            pattern="^back_tariffs$"),
            ],
            STATE_WAITING_SCREENSHOT: [
                CallbackQueryHandler(cb_paid, pattern="^paid$"),
                MessageHandler(filters.PHOTO, handle_screenshot),
                CallbackQueryHandler(cb_payment_method, pattern="^back_payment$"),
            ],
        },
        fallbacks=[CommandHandler("start", cmd_start)],
        allow_reentry=True,
    )

    app.add_handler(conv)
    app.add_handler(CallbackQueryHandler(cb_issue_license,     pattern="^issue_"))
    app.add_handler(CallbackQueryHandler(cb_reject_payment,    pattern="^reject_"))
    app.add_handler(CallbackQueryHandler(cb_send_promo_to_demo,pattern="^send_promo_"))
    app.add_handler(CallbackQueryHandler(cb_adm_stats,         pattern="^adm_stats$"))
    app.add_handler(CallbackQueryHandler(cb_adm_clients,       pattern="^adm_clients$"))

    return app

async def main():
    app = build_app()

    port = int(os.environ.get("PORT", 8000))

    async with app:
        await app.start()
        await app.updater.start_polling(drop_pending_updates=True)
        log.info(f"StaffSpy Bot запущено. Порт: {port}")

        config = uvicorn.Config(web_app, host="0.0.0.0", port=port, log_level="warning")
        server = uvicorn.Server(config)
        await server.serve()

        await app.updater.stop()
        await app.stop()

if __name__ == "__main__":
    asyncio.run(main())
