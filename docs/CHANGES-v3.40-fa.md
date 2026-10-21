# YouTube Hunter v3.40.0 — اعلان دسکتاپ («Away notices»)

## چی اضافه شد
وقتی یه کار طولانی تموم می‌شه و شما **توی برنامه نیستید** (رفتید توی یه تب کروم، یه برنامه‌ی دیگه، یا پنجره رو مینیمایز کردید)، یه کارت شیک با لوگوی برنامه از **گوشه‌ی پایین سمت راست مانیتور** سُر می‌خوره بیرون.

کارهایی که اعلان می‌دن:
- استخراج (Scraper) — تموم شدن، خطا، تموم شدن سهمیه
- دانلود — از صفحه‌ی دانلودها، موضوع‌یاب و آرشیو (با تامبنیل و اسم ویدیو)
- برش ویدیو (Video Cutter)
- جست‌وجوی موضوع‌یاب
- ساخت / بازسازی طرح در AI Ideas و Content Lab، گزارش کانال
- بریف Snapshot Insights، بررسی درآمدزایی
- جواب Scope (چت هوش مصنوعی)
- نصب موتور دانلود

توقف دستی (Stop/Cancel) هیچ‌وقت اعلان نمی‌ده.

## رفتار
- فقط وقتی برنامه **جلو نیست** نشون داده می‌شه؛ داخل برنامه همون Toast قبلی کافیه.
- پنجره‌ی اعلان **فوکوس رو نمی‌دزده** (Non-activating) — وسط تایپ توی کروم هیچ کلیدی گم نمی‌شه.
- لوگو موقع ورود «سر هم می‌شه» (assemble + play pop + sheen)، یه نوار نور روی لبه‌ی بالایی رد می‌شه، نشان وضعیت (✓ / ✕ / !) پاپ می‌کنه.
- نوار زمان پایین کارت؛ با هاور متوقف می‌شه. موفق: ۷.۵ ثانیه، خطا: ۱۱ ثانیه.
- حداکثر ۳ کارت روی هم؛ چند دانلود پشت‌سرهم یه کارت با شمارنده‌ی ×N می‌شن.
- کلیک روی کارت: برنامه برمی‌گرده جلو (حتی از حالت مینیمایز) و صفحه‌ی مربوطه باز می‌شه.
- دکمه‌ها: «باز کردن» فایل، «نمایش در پوشه»، «برنامه».
- برگشتن به برنامه همه‌ی کارت‌ها رو آروم می‌بره (توی زنگوله‌ی اعلان‌ها هنوز هستن).
- تم روشن/تاریک، رنگ اکسنت و راست‌به‌چپ فارسی رو دنبال می‌کنه.
- جای کارت از `availableGeometry` صفحه‌ی اصلی میاد، پس تسک‌بار هر طرف باشه روش نمی‌افته.

## تنظیمات (Settings → Appearance)
- **اعلان روی دسکتاپ**: روشن/خاموش + دکمه‌ی «پیش‌نمایش»
- **صدای اعلان**: صدای اعلان خود ویندوز (فقط ویندوز)

کلیدهای config: `desktop_notify`, `desktop_notify_sound` (پیش‌فرض هر دو `true`).

## فایل‌ها
- جدید: `app/qml_backend/desktop_notifier.py`, `app/qml/components/DesktopToast.qml`, `app/qml/components/DesktopToastHost.qml`
- تغییر: `main_qml.py`, `app/qml/Main.qml`, `app/qml/pages/SettingsPage.qml`, `app/core/db/downloads.py` (`downloads_get`)،
  VMها: downloads, niche, archive, cutter, ideas, content_lab, insights, monetize, chat, deno
- `app/locales/fa.py`، نسخه در `constants.py` / `version_info.txt` / `installer.iss`، `YoutubeScrapper.spec` (hiddenimports)

## تست بدون نمایشگر
```bash
QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py
python -m PySide6.qmllint -I app/qml app/qml/components/DesktopToast.qml
```
برای دیدن واقعی: Settings → Appearance → «پیش‌نمایش»، یا یه دانلود شروع کنید و برید توی کروم.


## نسخه 3.40.1 — بزرگ/کوچک‌شدن بومی پنجره (resize fix)
- تویین دستی `x/y/width/height` در `Main.qml` حذف شد؛ به‌جایش `qml_backend/win_frame.py` استایل بومی پنجره را برمی‌گرداند و `WM_NCCALCSIZE` را جواب می‌دهد، پس انیمیشن maximize/restore را DWM پخش می‌کند و برنامه فقط یک بار resize می‌شود.
- `components/PageFreeze.qml`: صفحه‌ی مخفی هنگام resize دوباره لِی‌اوت نمی‌شود و صفحه‌ی تازه‌ساخته از همان اول اندازه‌ی استک را می‌گیرد.
- `qml_backend/perf_probe.py`: پروفایل فریم، فقط با `YH_PERF=1`.
- نسخه در `constants.py` / `version_info.txt` / `installer.iss` روی 3.40.1 تنظیم شد.


## نسخه 3.40.2 — منوی راست‌کلیکِ فیلدهای متنی (EditMenu)
- هر `TextField` / `TextArea` برنامه دیگر منوی سیاه و پیش‌فرض Qt را نشان نمی‌دهد؛ یک منوی سفارشی می‌آید:
  - سه کاشی لمسی **Cut / Copy / Paste** بالای منو (کارهای پرکاربرد = یک تارگت بزرگ).
  - ردیف‌های **Undo / Redo / Delete / Select All** با کپشن واقعی کلید (`Ctrl Z`، `Ctrl Y`، `Del`، `Ctrl A`).
  - یک قرص نورانی که بین ردیف‌ها سُر می‌خورد (به‌جای روشن‌شدن جداگانهٔ هر ردیف) + نوار لبهٔ اکسنت.
  - واش اکسنت، لبهٔ اسپکیولار بالا، سایهٔ نرم عمیق، ورود پله‌ای ردیف‌ها، تم روشن/تاریک، هر اکسنت، RTL، و کنترل کامل با کیبورد (↑ ↓ ← → / Home / End / Enter / Esc).
- هر عمل روی **اسنپ‌شاتِ لحظهٔ باز شدن منو** اجرا می‌شود (چون فوکوس به منو می‌رود و انتخاب می‌تواند عوض شود)، و آیتم‌های بی‌معنی غیرفعالند (مثلاً Copy روی انتخاب خالی).
- اتصال با `T.ContextMenu.menu` (نیاز به **Qt 6.9+**؛ `requirements.txt` به `PySide6>=6.9` رفت — بیلد با 6.12).
- فایل‌ها: جدید `app/qml/components/EditMenu.qml` + آیکون‌های `assets/icons/{undo,redo,select_all}.svg`؛ تغییر `LineField`، `TextAreaField`، `SmartField`، `RangeField`، `Dropdown`، `Teleprompter` و صفحه‌هایی که فیلد مستقیم دارند.
- **رفع ریسک روی سیستم‌های بی‌GPU:** سایهٔ منو با `MultiEffect` روی یک کپیِ لایه‌دارِ جدا کشیده می‌شود و خودِ شیت یک `Rectangle` ساده است. قبلاً `layer.enabled` روی خود شیت بود؛ اگر MultiEffect اجرا نشود (رندر نرم‌افزاری، VM، درایور قدیمی) پنل کامل ناپدید می‌شد و فقط متن‌ها روی صفحه شناور می‌ماندند.
