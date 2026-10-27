<div align="center">

<img src="assets/logo_256.png" width="112" alt="لوگوی YouTube Hunter">

# YouTube Hunter

**زبان:** [English](README.md) · **فارسی**

**تحقیق و تحلیل یوتیوب، کشف ویدیوهای پرراندمان، دانلود و برش کلیپ — یک اپلیکیشن دسکتاپ ویندوز، به‌همراه یک دکمه داخل خود یوتیوب.**

[نصب](docs/INSTALL.md) · [افزونه مرورگر](docs/EXTENSION.md) · [ساخت از سورس](#ساخت-از-سورس) · [تغییرات](CHANGELOG.md)

![Version](https://img.shields.io/badge/version-1.0.1-22c55e?style=flat-square)
![Platform](https://img.shields.io/badge/Windows-10%201809%2B%20%7C%2011%20(x64)-0ea5e9?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.11%2B-3776ab?style=flat-square&logo=python&logoColor=white)
![Qt](https://img.shields.io/badge/Qt%20Quick-6.12-41cd52?style=flat-square&logo=qt&logoColor=white)
![License](https://img.shields.io/badge/license-proprietary-6b7280?style=flat-square)

</div>

---

YouTube Hunter یک فضای کار دسکتاپ برای افرادی است که کانال یوتیوب اداره می‌کنند. یک کانال یا یک کلیدواژه به آن بدهید: داده‌ها را می‌گیرد، ویدیوهایی را پیدا می‌کند که نسبت به عملکرد معمول همان کانال **بیش‌ازحد خوب** عمل کرده‌اند، برنده‌ها را به یک نقشه راه محتوایی تبدیل می‌کند، هرچه لازم دارید را با کیفیت دلخواه دانلود می‌کند و کلیپ‌ها را برش می‌دهد — بدون ده‌ها تب باز مرورگر و یک فایل اکسل.

این یک اپلیکیشن بومی ویندوز است (Python + Qt Quick/QML). همه‌چیز روی سیستم خودتان اجرا می‌شود: کلید API، دانلودها و آرشیو شما. یک **افزونه Chrome/Edge** همراه آن، همان پنل دانلود و برش را روی صفحه یوتیوب قرار می‌دهد و اپلیکیشن دسکتاپ کار را در پس‌زمینه انجام می‌دهد.

<div align="center">
<img src="screenshots/scraper.png" width="880" alt="صفحه Scraper">
</div>

## دانلود و نصب

1. **[آخرین نسخه](../../releases/latest)** را باز کنید و **`YouTubeHunter-Setup-1.0.1-x64.exe`** را دانلود کنید.
2. آن را اجرا کنید. نصب **برای هر کاربر** در `%LOCALAPPDATA%\Programs\YouTube Hunter` انجام می‌شود — بدون درخواست مدیر، بدون UAC و بدون نوشتن چیزی در `Program Files`.
3. **YouTube Hunter** را از منوی Start یا میانبر دسکتاپ اجرا کنید.

برای نصب یا اجرای برنامه به Python، pip، Visual C++ Redistributable یا اتصال اینترنت نیازی نیست: تمام محیط اجرا داخل نصب‌کننده است (حدود ۲۳۵ مگابایت)، شامل محیط اجرای JavaScript، کمک‌کننده PO Token و مرورگر تعبیه‌شده‌ای که پنجره Support از آن استفاده می‌کند.

> **SmartScreen:** نصب‌کننده امضای دیجیتال ندارد، بنابراین ویندوز ممکن است بار اول پیام *«Windows protected your PC»* را نشان دهد. گزینه **More info → Run anyway** را انتخاب کنید. تنها راه حذف این هشدار، یک گواهی code-signing است.

راهنمای کامل نصب، تنظیمات اولین اجرا و رفع اشکال: **[docs/INSTALL.md](docs/INSTALL.md)**.

### اولین اجرا

برنامه روی صفحه **Scraper** باز می‌شود. برای استفاده از قابلیت‌های مبتنی بر یوتیوب به یک **کلید YouTube Data API v3** نیاز دارید (رایگان از [Google Cloud Console](https://console.cloud.google.com/apis/library/youtube.googleapis.com)) — آن را در **Settings → API** وارد کنید. قابلیت‌های هوش مصنوعی اختیاری هستند: یک ارائه‌دهنده (Google Gemini، OpenAI یا هر endpoint سازگار با OpenAI) را در **Settings → AI Providers** اضافه کنید.

همه‌چیز محلی ذخیره می‌شود: `%APPDATA%\YoutubeScrapperCyber\` شامل تنظیمات، کلیدهای API و آرشیو SQLite است. حذف برنامه عمداً این پوشه را دست‌نخورده باقی می‌گذارد.

## دکمه Hunter (افزونه مرورگر)

<img src="browser-extension/icons/icon48.png" width="20" align="right" alt="">

یک افزونه Chrome/Edge (Manifest V3) دکمه **Hunter** را کنار Like/Share در هر صفحه تماشای یوتیوب و در Shorts اضافه می‌کند:

- **Download** — کیفیت‌های واقعی با حجم واقعی، انتخاب فرمت ویدیو (MP4 / MKV / WEBM)، فرمت صدا (MP3 / M4A / OPUS / WAV / FLAC) و **انتخاب صدا** (اصلی یا هر دوبله). ردیف انتخاب‌شده به یک کپسول زنده تبدیل می‌شود: درصد، سرعت، حجم، زمان باقی‌مانده، توقف/ادامه و Play / Show in folder پس از پایان.
- **Cut** — با یک خط‌کش بزرگ‌نمایی‌شده نقطه In / Out را مشخص کنید (یا timecode را تایپ کنید)، کیفیت یا خروجی صوتی را انتخاب کنید و فقط همان کلیپ دانلود و برش داده می‌شود. پیشرفت زنده است؛ کلیپ با کارت مخصوص خودش در تاریخچه Cutter برنامه ذخیره می‌شود.
- **همراه شما می‌آید** — پنل را ببندید یا تب را عوض کنید؛ **کارت فعالیت زنده** دسکتاپ تا پایان کار نمایش پیشرفت را ادامه می‌دهد.
- **خودش برنامه را اجرا می‌کند** — اگر اپلیکیشن دسکتاپ در حال اجرا نباشد، با کلیک روی Hunter از طریق پروتکل `youtubehunter://` (که نصب‌کننده ثبت می‌کند) و به‌صورت کوچک‌شده اجرا می‌شود.

افزونه از طریق یک سرور JSON محلی روی `127.0.0.1:47391` با برنامه ارتباط می‌گیرد. فقط درخواست‌هایی پذیرفته می‌شوند که هم origin افزونه و هم هدر `X-YTH-Bridge` را داشته باشند؛ بنابراین هیچ وب‌سایتی نمی‌تواند دانلود را شروع کند. برای خاموش کردن کامل این پل، `"browser_bridge": false` را در تنظیمات قرار دهید.

راهنمای قدم‌به‌قدم نصب (۳۰ ثانیه): **[docs/EXTENSION.md](docs/EXTENSION.md)**.

## قابلیت‌ها

### تحقیق و پژوهش

| | |
|---|---|
| **Channel & keyword scraper** | کاتالوگ یک کانال یا یک جست‌وجو را با گام‌بندی آگاه از سهمیه API، مرتب‌سازی و ادامه‌دهی می‌گیرد. عمق جست‌وجو قابل تنظیم است — یک نگاه سریع یا جست‌وجوی کامل. |
| **تشخیص ویدیوهای پرراندمان (Outlier)** | هر ویدیو را با خط پایه همان کانال مقایسه می‌کند تا ویدیوهای ۳ تا ۳۰ برابری دیده شوند، نه فقط ویدیوهایی که بیشترین بازدید مطلق را دارند. |
| **Niche Finder** | یک موضوع را در کانال‌های مختلف جست‌وجو می‌کند، وقتی فیلتری نتیجه‌ای برنمی‌گرداند جست‌وجو را خودکار گسترش می‌دهد و کانال‌های ارزشمند برای بررسی را رتبه‌بندی می‌کند. |
| **Search Archive** | هر جست‌وجو به‌صورت محلی در SQLite ذخیره می‌شود — بدون مصرف دوباره سهمیه، دوباره ببینید، فیلتر کنید، مرتب کنید و تحلیل کنید. کارت‌ها فقط نزدیک محدوده دید رندر می‌شوند، باز شدن سرد با اسکلت به‌جای شبکه سیاه شروع می‌شود و تصاویر بندانگشتی یک‌جا ظاهر می‌شوند. |
| **Snapshot Insights** | یک بریف کانال: ریتم انتشار، فرمت‌ها، طول ویدیوها، الگوهای عنوان و ویژگی‌های مشترک ویدیوهای پرراندمان — به‌همراه نمای ذخیره‌شده **Brief (Dossier)** با بازه‌های اطمینان، نیت، نشانه‌ها و آزمایش‌ها. |

### ساخت محتوا

| | |
|---|---|
| **AI Ideas** | یک ویدیوی پرراندمان را به ایده‌های مشخص ویدیویی با هوک و زاویه تبدیل می‌کند، با ارائه‌دهنده مدل دلخواه شما. |
| **Content Lab** | یک نقشه راه چهاربخشی می‌سازد (هوک → ساختار → نقاط کلیدی → CTA). |
| **AI Chat (اکنون Hunter)** | یک پنل گفت‌وگو متصل به داده‌هایی که قبلاً جمع کرده‌اید: یک بریف ذخیره‌شده را تحلیل کنید، تا ۵۰ لینک را هم‌زمان وارد کنید و درباره یک کانال، نیچ یا یک ویدیوی خاص بپرسید. |
| **بررسی درآمدزایی** | قبل از سرمایه‌گذاری روی یک نیچ یا کانال، تخمین می‌زند که آیا ارزش تلاش را دارد یا نه. |

### تولید

| | |
|---|---|
| **Downloads** | پریست‌های کیفیت، فقط صدا، زیرنویس، تصویر بندانگشتی، انتخاب کانتینر و فرمت صدا، **انتخاب صدا / دوبله**، توقف و ادامه، و زنجیره تلاش مجدد با کلاینت‌های مختلف به‌همراه کوکی اختیاری مرورگر برای مدیریت محدودیت‌های هر کلاینت یوتیوب. |
| **Video Cutter** | برش دقیق تا فریم با پیش‌نمایش زنده، کپی مستقیم استریم برای سرعت یا رمزگذاری مجدد برای دقت، خروجی ویدیو (MP4/MKV/WEBM) یا صدا (MP3/M4A/OPUS/WAV/FLAC)، پشتیبانی از فایل محلی و کشیدن خروجی مستقیم به Explorer، Premiere یا Telegram. |
| **Transcripts** | دو موتور استخراج (کتابخانه + fallback با yt-dlp) با پشتیبانی از proxy/cookie، برای اسکریپت‌نویسی و تحلیل با هوش مصنوعی. |
| **کارت‌های فعالیت زنده** | دانلود یا برش را شروع کنید و به برنامه دیگری بروید — کارتی در گوشه صفحه پیشرفت، سرعت و زمان باقی‌مانده را نشان می‌دهد و پس از پایان سبز می‌شود. |
| **نگهبان اتصال** | بررسی می‌کند که یوتیوب واقعاً در دسترس باشد (نه فقط اینترنت)، هر دقیقه دوباره تست می‌کند و به‌محض قطع شدن VPN دروازه اتصال را دوباره باز می‌کند — دانلودها هرگز بی‌صدا نیمه‌کاره نمی‌مانند. |

### خود برنامه

- **رابط انگلیسی**، تم تیره و روشن، پنج رنگ تأکیدی و ذخیره همه تنظیمات برای هر کاربر.
- **نصب برای هر کاربر، بدون دسترسی مدیر و بدون نیاز به Python** — نصب‌کننده تمام محیط اجرا را همراه دارد.
- **همه‌چیز محلی** — تنظیمات، آرشیو و دانلودها روی سیستم شما می‌مانند؛ کلیدهای API در Settings وارد می‌شوند و هرگز از آن خارج نمی‌شوند.

## تصاویر

| Niche Finder | Video Cutter |
|---|---|
| ![Niche Finder](screenshots/niche-finder.png) | ![Video Cutter](screenshots/video-cutter.png) |

| Content Lab | Settings |
|---|---|
| ![Content Lab](screenshots/content-lab.png) | ![Settings](screenshots/settings.png) |

| Niche Scan | Scraper |
|---|---|
| ![Niche Scan](screenshots/niche-scan.png) | ![Scraper](screenshots/scraper.png) |

## ویندوزهای پشتیبانی‌شده

| | |
|---|---|
| **Windows 11** | ✅ ۶۴ بیتی، همه نسخه‌ها |
| **Windows 10** | ✅ ۶۴ بیتی، **نسخه 1809 (build 17763) یا جدیدتر** |
| **Windows 8.1 / 7** | ❌ پشتیبانی نمی‌شود (محیط Qt 6 همراه برنامه به Windows 10 1809+ نیاز دارد) |
| **ویندوز ۳۲ بیتی** | ❌ پشتیبانی نمی‌شود — بیلد فقط x64 است |
| **Windows on ARM** | ⚠️ با شبیه‌سازی x64 اجرا می‌شود، آزمایش نشده است |
| **macOS / Linux** | ❌ برنامه فقط برای ویندوز است (از Win32 API برای پنجره بدون قاب، taskbar و اعلان‌ها استفاده می‌کند) |

## ساخت از سورس

پیش‌نیازها: **Python 3.11+ (64-bit)** روی ویندوز و [Inno Setup 6](https://jrsoftware.org/isdl.php) در صورت نیاز به ساخت نصب‌کننده.

```bat
git clone https://github.com/reyzodev/youtube-hunter.git
cd youtube-hunter
build.bat
```

`build.bat` یک محیط `.build-venv` جدا می‌سازد، وابستگی‌های قفل‌شده را نصب می‌کند، همه ورودی‌های بیلد را بررسی می‌کند، PyInstaller را با `YoutubeScrapper.spec` اجرا می‌کند، خروجی را بررسی می‌کند و سپس `installer.iss` را کامپایل می‌کند:

```
dist\YouTubeHunter\YouTubeHunter.exe     the app (onedir — ship the whole folder)
Output\YouTubeHunter-Setup.exe           the installer
```

سه فایل باینری به دلیل حجم زیاد در این مخزن قرار ندارند و `build.bat` در صورت نبودشان متوقف شده و به شما می‌گوید:

| فایل | حجم | دلیل نیاز |
|---|---|---|
| `assets/bin/ffprobe.exe` | حدود ۱۴۵ مگابایت | دانلود mp3/فقط صدا، بررسی فایل محلی در Cutter و بررسی کیفیت |
| `assets/bin/deno.exe` | حدود ۹۳ مگابایت | محیط اجرای JavaScript که yt-dlp برای حل چالش دانلود یوتیوب لازم دارد |
| `assets/bin/bgutil-pot.exe` | حدود ۴۵ مگابایت | کمک‌کننده PO Token — بخشی **الزامی** از موتور دانلود؛ بدون آن یوتیوب فقط لیست 360p می‌دهد یا روی IPهای VPN/دیتاسنتر 403 برمی‌گرداند. مجوز GPL-3.0، به‌صورت یک برنامه جداگانه و بدون تغییر همراه شده است (ببینید `assets/bin/bgutil-pot-NOTICE.txt`) |

اجرای برنامه بدون ساخت:

```bat
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python main_qml.py
```

## ساختار پروژه

```
main_qml.py               entry point — builds the bridges, loads QML
app/
  qml/                    the interface: Main.qml + pages/ + components/
  qml_backend/            the ViewModels the QML talks to (incl. web_bridge for the extension)
  core/                   the actual logic: YouTube API, niche search, cutter, AI, downloads
  ui/                     icons, fonts, theme helpers
browser-extension/        the Hunter button (Manifest V3: content.js, panel.css, background.js)
fonts/                    bundled fonts
assets/                   icons, logo, installer icon (bin/ is not committed)
docs/                     install, extension, build notes, release notes
screenshots/              current UI
tools/                    developer lints (hover-flicker checker, icon art)
YoutubeScrapper.spec      PyInstaller recipe (also trims ~75 MB of unused Qt)
installer.iss             Inno Setup script (bundles the app, the extension, the URL protocol)
```

نام فایل‌ها و مسیرها در این بخش به انگلیسی نگه داشته شده‌اند تا با ساختار واقعی پروژه مطابقت داشته باشند.

## پشته فناوری

| لایه | توضیح |
|---|---|
| رابط کاربری | Qt Quick / QML (Qt 6.12)، PySide6، توکن‌های طراحی اختصاصی، بدون web view |
| منطق | Python 3.13، SQLite (آرشیو محلی)، `yt-dlp`، FFmpeg |
| APIها | YouTube Data API v3، `youtube-transcript-api`، Google Gemini / ارائه‌دهنده‌های سازگار با OpenAI |
| افزونه | Chrome/Edge Manifest V3، JavaScript و CSS خالص، پل JSON محلی روی `127.0.0.1:47391` |
| بسته‌بندی | PyInstaller (onedir) + Inno Setup (نصب برای هر کاربر) |

## مستندات

مستندات تفصیلی در پوشه `docs/` فعلاً به انگلیسی است.

- [`docs/INSTALL.md`](docs/INSTALL.md) — نصب، اولین اجرا، راه‌اندازی افزونه و رفع اشکال
- [`docs/EXTENSION.md`](docs/EXTENSION.md) — دکمه Hunter از ابتدا تا انتها
- [`docs/BUILD.md`](docs/BUILD.md) — یادداشت‌های بیلد و بسته‌بندی
- [`docs/UPDATES.md`](docs/UPDATES.md) — نحوه کار آپدیتر داخلی و انتشار نسخه
- [`CHANGELOG.md`](CHANGELOG.md) — یادداشت‌های انتشار

## نسخه

**1.0.1** — Scraper به یک مسیر سریع با تخته نتایج زنده مجهز شده است (مرتب‌سازی بر اساس Outlier، جست‌وجوی عنوان، deep scan، بازه انتشار، کلیدهای Transcript و نوع فایل) و هر بار هشت ویدیو با دکمه **Show more** نشان می‌دهد؛ کارت‌های ذخیره‌شده Niche Scan بازطراحی شده‌اند؛ AI Chat اکنون «Hunter» است؛ نوار عنوان پروژه را در Telegram دنبال می‌کند؛ Settings کارت‌هایش را در پس‌زمینه می‌سازد و Main.qml هنگام راه‌اندازی precompile می‌شود، در حالی که صفحه لودینگ فعلی بدون تغییر می‌ماند. Search Archive فقط کارت‌های نزدیک محدوده دید را رندر می‌کند، بخش‌های سرد را پشت اسکلت باز می‌کند، تصاویر بندانگشتی را یک‌جا آزاد می‌کند و سنگین‌ترین افکت‌های hover را تا توقف اسکرول به تعویق می‌اندازد؛ شبکه Niche Finder هم همین رندر محدود به محدوده دید و نمایش یک‌جای کل شبکه را دارد. کلید Transcripts دیگر قرمز چشمک نمی‌زند.

## مجوز

متن حقوقی به انگلیسی نگه داشته شده است؛ در صورت اختلاف، همین متن معتبر است.

Proprietary — © 2026 YouTube Hunter. All rights reserved.
This repository is published for reference, distribution and support of the app. Redistribution of the compiled application, or of modified versions of it, requires written permission.

Bundled third-party components keep their own licences: `bgutil-pot` is GPL-3.0 (see `assets/bin/bgutil-pot-NOTICE.txt`), and FFmpeg / deno / PySide6 / Qt are distributed under their respective licences inside the installer.
