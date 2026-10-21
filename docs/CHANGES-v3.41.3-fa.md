# تغییرات v3.41.3

## ۱) سوییچ تم جدید: «Eclipse»
- رنگ‌های ثابت زرد/سرمه‌ای حذف شد. ترک سوییچ حالا همان جنس پیل زبان (FA/EN) در تایتل‌بار است: `Theme.surface_low` + خط `Theme.border`.
- خورشید و ماه با رنگ Accent کاربر (`Theme.primary → primary_deep`) کشیده می‌شوند؛ با عوض‌کردن Accent در تنظیمات (Signal، Ocean، Aurora، Tungsten…) سوییچ هم عوض می‌شود.
- روز: هسته‌ی کره‌ای با ۸ پرتو، و سه خط «رنج‌فایندر» (هم‌خوان با انیمیشن Lock-on). هاور: پرتوها یک پله می‌چرخند و خط دور سوییچ Accent می‌شود.
- شب: همان Accent به هلال (Path واقعی با دو PathArc) با هاله‌ی نازک کرونا تبدیل می‌شود؛ خط‌ها تبدیل به ستاره‌های چشمک‌زن می‌شوند (یکی به رنگ Accent).
- همه‌ی حرکت‌ها Animator هستند (Render Thread) و هیچ ColorAnimationی وجود ندارد؛ پس جابه‌جایی پالت پشت پرده بدون لگ می‌ماند. انیمیشن‌های تزئینی به `App.ambientMotion` و فعال بودن پنجره وابسته‌اند.

## ۲) کوتاه‌تر شدن مرحله‌ی «Preparing…» (دانلود و کاتر)
قبل از اولین بایت، هر دانلود ویدیو را ۲ تا ۳ بار کامل extract می‌کرد + یک درخواست صفحه‌ی کانال (تا ۱۵ ثانیه).
- **دانلود از خروجی pre-flight** (`_download_from_preflight`): اطلاعات pre-flight مستقیم با `process_ie_result` دانلود می‌شود (همان مسیر `--load-info-json` در yt-dlp). یک extraction کامل در هر rung حذف شد. اگر قبل از رسیدن اولین بایت خطا بدهد، یک‌بار به روش قبلی (extract تازه) برمی‌گردد.
- **آواتار کانال در پس‌زمینه**: درخواست صفحه‌ی کانال دیگر جلوی شروع دانلود را نمی‌گیرد؛ آواتار با یک on_meta دوم (فقط همان فیلد) ثبت می‌شود.
- **کش probe کیفیت** (۱۵ دقیقه، فقط لیست‌های rich): بعد از پنجره‌ی انتخاب کیفیت، «Best available» دیگر دوباره کل لدر کلاینت‌ها را نمی‌پیماید.
- **کاتر**: خواندن لینک موقع Paste برای مرحله‌ی برش reuse می‌شود («Reading the video…» تقریباً فوری). Paste همیشه تازه می‌خواند و «Refreshing streams…» همیشه کش را دور می‌زند.
- **گرم‌کردن موتور**: ۴ ثانیه بعد از اجرا، yt-dlp، پوشه‌ی ffmpeg و JS runtime در یک thread پس‌زمینه آماده می‌شوند؛ `load_yt_dlp` با RLock thread-safe شد.

فایل‌ها: `app/qml/components/ThemeSwitch.qml`، `app/core/download.py`، `app/core/cutter.py`، `app/core/runtime_deps.py`، `app/qml_backend/app_controller.py`
