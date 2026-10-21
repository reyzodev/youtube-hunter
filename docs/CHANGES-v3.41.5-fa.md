# تغییرات v3.41.5

## ۱) دستیار PO Token اجباری شد (مثل موتور جاوااسکریپت)
- `pot.enabled()` همیشه True است؛ سوییچ روشن/خاموش از تنظیمات حذف شد و مقدار قدیمی `"off"` در config نادیده گرفته می‌شود.
- `Deno.ready` جدید = deno نصب **و** bgutil-pot نصب. همه‌ی گیت‌های دانلود به‌جای `Deno.available` این را چک می‌کنند:
  QualityPicker (دکمه‌ی Download)، Resume/Retry در Downloads، برش لینک یوتیوب در Cutter.
- پنجره‌ی «راه‌اندازی یک‌باره» حالا دو فایل ضروری نشان می‌دهد (deno.exe و bgutil-pot.exe). «Download and install» هر دو را پشت‌سرهم نصب می‌کند (`installAll`)، پیشرفت فایل ۱ و ۲ را نشان می‌دهد و فقط وقتی هر دو آماده باشند بسته می‌شود.
- «From file…» فایل را به جزء ناقص می‌دهد (اول deno، بعد bgutil-pot؛ `pot.install_from_file`).
- شروع برنامه: اگر هر کدام نباشد، پنجره باز می‌شود.
- بک‌اند: `runtime_deps.download_engine_missing()`؛ `download_video` و `cut_link` اگر جزء ضروری نباشد همان اول با پیام روشن برمی‌گردند (دیگر دانلود نیمه‌کاره با 403 یا 360p نمی‌شود).
- تنظیمات ← Download Engine: کارت PO Token حالت «Not installed / Required» با رنگ هشدار، دکمه‌ی Install / Reinstall، بدون سوییچ. Health tile و چیپ وضعیت هم `Deno.ready` را نشان می‌دهند.

## ۲) تول‌تیپ پلیر بیرون کارت نمی‌افتد
- `AppTooltip`: ویژگی‌های جدید `preferAbove` و `boundsName` (نزدیک‌ترین والد با آن objectName محدوده‌ی تول‌تیپ می‌شود). تول‌تیپ در هر دو جهت داخل محدوده clamp می‌شود و بعد از گرفتن اندازه‌ی واقعی دوباره جای‌گذاری می‌شود.
- `IconButton`: `tipAbove` و `tipBoundsName`.
- `VideoPlayer`: دکمه‌های داک پایین (Speed & quality، فول‌اسکرین، صدا، پخش…) تول‌تیپ را **بالای** دکمه و داخل کارت پلیر (`playerStage`) نشان می‌دهند. تول‌تیپ «Speed & quality» وقتی منوی خودش باز است پنهان می‌شود.

فایل‌ها: `app/core/pot.py`، `app/core/runtime_deps.py`، `app/core/download.py`، `app/core/cutter.py`، `app/qml_backend/vm/deno_vm.py`، `app/qml/Main.qml`، `app/qml/pages/SettingsPage.qml`، `app/qml/pages/DownloadsPage.qml`، `app/qml/pages/CutterPage.qml`، `app/qml/components/QualityPicker.qml`، `app/qml/components/AppTooltip.qml`، `app/qml/components/IconButton.qml`، `app/qml/components/VideoPlayer.qml`، `app/locales/fa.py`

## ۳) چک اتصال زنده (نه فقط اول برنامه)
قبلاً فقط یک‌بار موقع باز شدن برنامه کشورِ IP چک می‌شد. حالا `GeoVM` در کل مدت اجرا مراقب است:
- هر **۶۰ ثانیه** وقتی همه‌چیز اوکی است، و هر **۱۰ ثانیه** وقتی قطع/بلاک است (تا وصل شدن VPN سریع دیده شود).
- فوراً وقتی ویندوز تغییر شبکه گزارش می‌دهد (`QNetworkInformation`: قطع Wi-Fi، روشن/خاموش شدن VPN، کابل).
- وقتی پنجره بعد از مدتی دوباره فعال می‌شود.
- چک‌های پس‌زمینه بی‌صدا هستند (اسپینر و چشمک ندارند).

**تست مستقیم یوتیوب** (`geo.probe_youtube`): علاوه بر کشور، `generate_204` یوتیوب از همان مسیر شبکه زده می‌شود. فقط پاسخ واقعی 204 یعنی «در دسترس». صفحهٔ فیلتر، DNS دستکاری‌شده، ریدایرکت یا تایم‌اوت یعنی در دسترس نیست. 403/429 واقعی از یوتیوب یعنی «یوتیوب این IP را بلاک کرده». این‌طوری کشورها و سرورهای VPN خارج از لیست هم شناسایی می‌شوند.

سه حالت: `offline` (اینترنت قطع)، `restricted` (IP در کشور فیلتر)، `unreachable` (اینترنت هست ولی یوتیوب جواب نمی‌دهد / IP بلاک).

رفتار UI:
- وسط کار اگر اتصال از «اوکی» به «بلاک» برود، صفحهٔ اتصال دوباره باز می‌شود + نوتیفیکیشن. وقتی برگردد، صفحه خودش بسته می‌شود + نوتیفیکیشن «اتصال برگشت».
- دانلود، Resume و برش لینک قبل از شروع `Geo.allowDownload()` را چک می‌کنند؛ اگر یوتیوب در دسترس نباشد صفحهٔ اتصال (حالت download) باز می‌شود و با وصل شدن خودش بسته می‌شود. این گیت بر اساس تست واقعی یوتیوب است نه لیست کشورها، پس خطای دیتابیس جغرافیایی دانلود را قفل نمی‌کند.
- گیت اسکرپ اگر منتظر بماند، با وصل شدن VPN خودکار شروع می‌شود.
- چیپ «No internet / YouTube is blocked / YouTube isn't answering» در نوار عنوان.
- کلید config: `geo_monitor` (پیش‌فرض true).

فایل‌ها: `app/core/geo.py`، `app/qml_backend/vm/geo_vm.py`، `app/qml/Main.qml`، `app/qml/components/GeoGateDialog.qml`، `app/qml/components/TitleBar.qml`، `app/qml/components/QualityPicker.qml`، `app/qml/pages/DownloadsPage.qml`، `app/qml/pages/CutterPage.qml`، `app/locales/fa.py`
