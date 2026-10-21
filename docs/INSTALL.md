# Install & first run — YouTube Hunter 1.0.0

English first · [فارسی ↓](#فارسی)

---

## 1. Requirements

| | |
|---|---|
| **OS** | Windows 10 **version 1809 (build 17763)** or newer, or Windows 11 — **64-bit only** |
| **Disk** | ~600 MB after install (the installer itself is ~170 MB) |
| **RAM** | 4 GB minimum, 8 GB recommended for downloads + cutting at the same time |
| **Admin rights** | **not required** — the default install is per-user |
| **Python / pip / Visual C++** | **not required** — everything ships inside |
| **Internet** | only for the features that talk to YouTube or an AI provider |

Windows 7/8.1, 32-bit Windows, macOS and Linux are not supported (the bundled Qt 6 runtime needs Windows 10 1809+, and the build is x64-only).

## 2. Install

1. Download **`YouTubeHunter-Setup.exe`** from the [latest release](https://github.com/reyzodev/youtube-hunter/releases/latest).
2. Double-click it. The wizard is a single page: it shows where the app will go and offers a desktop shortcut.
3. Press **Install**, then **Finish**.

What the installer does:

| | |
|---|---|
| Installs to | `%LOCALAPPDATA%\Programs\YouTube Hunter` (per user, no UAC) |
| Adds | Start-menu entry **YouTube Hunter**, optional desktop shortcut, uninstaller in *Apps & features* |
| Copies | the app, its whole Qt/Python runtime, the **browser extension** (`browser-extension\`), and the three helpers (ffprobe, deno, bgutil-pot) |
| Registers | the `youtubehunter://` URL protocol so the browser extension can start the app |
| Leaves alone | `%APPDATA%\YoutubeScrapperCyber\` (your config, API keys, archive) — also on uninstall |

### SmartScreen / antivirus

The installer is **not code-signed**. On a fresh Windows install you will see *"Windows protected your PC"*:

1. Click **More info**.
2. Click **Run anyway**.

Some antivirus products flag unsigned installers that contain `deno.exe`/`ffprobe.exe`. If yours quarantines the installer, restore it and add an exclusion for `%LOCALAPPDATA%\Programs\YouTube Hunter`. A code-signing certificate is the only way to remove the prompt.

### Silent install (for IT / scripted deployment)

```bat
YouTubeHunter-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Add `/ALLUSERS` to install for every user on the machine (this one needs an administrator). The installer writes a log to `%TEMP%` (`SetupLogging=yes`), which is the first thing to read if an install fails.

## 3. First run

The app opens on the **Scraper** with a short guided tour (the `?` button in the title bar replays it).

### YouTube Data API key (needed for scraping)

1. Open [Google Cloud Console → YouTube Data API v3](https://console.cloud.google.com/apis/library/youtube.googleapis.com) and enable the API.
2. Create an **API key** (Credentials → Create credentials → API key).
3. In the app: **Settings → API** → paste the key → **Validate**.

The key is stored locally in your config file and is only ever sent to Google. One key gives 10,000 quota units per day; a channel scrape costs roughly 1 unit per 50 videos, so a normal day of research fits easily.

### AI provider (optional)

**Settings → AI Providers** → add Google Gemini, OpenAI, or any OpenAI-compatible endpoint (base URL + key + model). Used by AI Ideas, Content Lab, AI Chat and the Brief analysis. Nothing in the app requires it.

### Language and theme

**Settings → Appearance**: English / فارسی (full RTL), dark / light, five accent colours. Everything is remembered per user.

## 4. Browser extension (the Hunter button)

The extension is already on disk — the installer put it in the app folder.

1. Open `chrome://extensions` (Chrome, Edge, Brave, Opera) — or `edge://extensions`.
2. Turn on **Developer mode** (top-right).
3. Click **Load unpacked** and select:

   ```
   %LOCALAPPDATA%\Programs\YouTube Hunter\browser-extension
   ```

4. Open any YouTube video. A **Hunter** button appears next to Like/Share.
5. First click: the browser asks *"Open YouTube Hunter?"* — tick **Always allow** and confirm. That is the `youtubehunter://` protocol starting the app (minimised) when it isn't running.

Details, tabs and troubleshooting: **[EXTENSION.md](EXTENSION.md)**.

## 5. Where your data lives

| Path | What |
|---|---|
| `%APPDATA%\YoutubeScrapperCyber\config.json` | settings, API keys, theme, language, download defaults |
| `%APPDATA%\YoutubeScrapperCyber\ideas.db` | the archive: scrapes, channels, videos, ideas, clips, chat history |
| `%APPDATA%\YoutubeScrapperCyber\crash.log` | the app's own error log — attach it to a bug report |
| `%APPDATA%\YoutubeScrapperCyber\deno\`, `pot\` | helpers the app installed itself (only if you installed them from inside the app) |
| your Downloads folder | downloaded videos and cut clips (path is configurable per download) |

To start completely fresh: quit the app, rename `%APPDATA%\YoutubeScrapperCyber` to something else, start the app again. Nothing else needs cleaning.

## 6. Troubleshooting

### The app opens on "No internet / YouTube is blocked"

The gate is not a country list — the app asks YouTube itself. If it says blocked:

- **restricted** → your IP is in a country where YouTube is filtered; turn on your VPN.
- **unreachable** → the internet works but YouTube does not answer from this IP (VPN exit burned, datacenter range). Change the VPN exit or server.
- **offline** → nothing answered at all.

It re-tests every 60 seconds (every 10 while blocked) and closes by itself as soon as YouTube answers.

### Downloads stay at 360p, or fail with 403

YouTube is serving a "thin" format list to this IP. The app ships the **PO Token helper** for exactly this; check **Settings → Download Engine**:

- `bgutil-pot` should say **Ready**.
- If it says *Not installed*, press **Install** (or **Reinstall**).
- If it is Ready and you still get 360p, the IP is heavily flagged: switch the VPN exit, or enable **Settings → Download Engine → Use cookies from browser** (Firefox works best).

### "Waiting for the extension" in the app

The app has not received a request from the extension yet:

1. `chrome://extensions` → **Reload** on YouTube Hunter.
2. Open a YouTube video and click **Hunter** once.
3. In the app, **Settings → Download Engine** shows the bridge status; **Mark as connected** forces it.

### The Hunter button does not appear

- The extension only injects on `youtube.com` — reload the tab after installing it.
- Check that the extension is enabled and has no errors (`chrome://extensions` → *Errors*).
- Some ad-blockers hide injected buttons; whitelist YouTube for this extension.

### Port 47391 is busy

Another copy of the app (or another program) is using the bridge port. Close the other copy — the app only runs one instance — and restart. The bridge is local-only (`127.0.0.1`).

### A download or cut stopped halfway

Open **Downloads** (or **Cutter**) and press **Resume** — partial files are kept as `.part` and the quality/format/audio-track choice is remembered.

### Where to report a problem

Open an [issue](https://github.com/reyzodev/youtube-hunter/issues) with:

- the version (sidebar footer),
- what you did and what happened,
- `%APPDATA%\YoutubeScrapperCyber\crash.log` if the app closed unexpectedly.

---

<div dir="rtl">

## فارسی

### ۱. پیش‌نیازها

| | |
|---|---|
| **سیستم‌عامل** | ویندوز ۱۰ نسخهٔ **۱۸۰۹ (build 17763)** یا جدیدتر، یا ویندوز ۱۱ — **فقط ۶۴ بیتی** |
| **فضای دیسک** | حدود ۶۰۰ مگابایت بعد از نصب (خود نصب‌کننده ~۱۷۰ مگابایت) |
| **رم** | حداقل ۴ گیگ، برای دانلود و برش هم‌زمان ۸ گیگ توصیه می‌شود |
| **دسترسی ادمین** | **لازم نیست** — نصب پیش‌فرض برای همان کاربر است |
| **پایتون / pip / Visual C++** | **لازم نیست** — همه‌چیز داخل نصب‌کننده است |
| **اینترنت** | فقط برای قابلیت‌هایی که با یوتیوب یا سرویس هوش مصنوعی حرف می‌زنند |

ویندوز ۷/۸.۱، ویندوز ۳۲ بیتی، مک و لینوکس پشتیبانی نمی‌شوند.

### ۲. نصب

۱. از بخش **[آخرین نسخه](https://github.com/reyzodev/youtube-hunter/releases/latest)** فایل **`YouTubeHunter-Setup.exe`** را دانلود کن.
۲. اجرا کن؛ ویزارد یک صفحه است: مسیر نصب را نشان می‌دهد و شورتکات دسکتاپ پیشنهاد می‌دهد.
۳. **Install** و بعد **Finish**.

نصب‌کننده چه کار می‌کند:

| | |
|---|---|
| مسیر نصب | `%LOCALAPPDATA%\Programs\YouTube Hunter` (برای همان کاربر، بدون UAC) |
| اضافه می‌کند | ورودی منوی Start، شورتکات دسکتاپ (اختیاری)، آنینستالر در *Apps & features* |
| کپی می‌کند | خود برنامه، کل رانتایم Qt/پایتون، **افزونهٔ مرورگر** (`browser-extension\`) و سه فایل کمکی (ffprobe، deno، bgutil-pot) |
| ثبت می‌کند | پروتکل `youtubehunter://` تا افزونه بتواند برنامه را اجرا کند |
| دست نمی‌زند | به `%APPDATA%\YoutubeScrapperCyber\` (کانفیگ، کلیدها، آرشیو) — حتی موقع حذف برنامه |

**SmartScreen / آنتی‌ویروس:** نصب‌کننده امضای دیجیتال ندارد. اگر ویندوز پیام *«Windows protected your PC»* داد: **More info → Run anyway**. بعضی آنتی‌ویروس‌ها به‌خاطر `deno.exe`/`ffprobe.exe` هشدار می‌دهند؛ فایل را Restore کن و مسیر نصب را در استثناها بگذار.

**نصب سایلنت (برای شبکه/اسکریپت):**

```bat
YouTubeHunter-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

با `/ALLUSERS` برای همهٔ کاربران سیستم نصب می‌شود (نیاز به ادمین). لاگ نصب در `%TEMP%` نوشته می‌شود؛ اگر نصب شکست خورد، اول همان را ببین.

### ۳. اجرای اول

برنامه روی **Scraper** باز می‌شود و یک تور کوتاه نشان می‌دهد (دکمهٔ `?` در نوار عنوان دوباره اجرایش می‌کند).

**کلید YouTube Data API (برای اسکرپ لازم است):**

۱. در [Google Cloud Console](https://console.cloud.google.com/apis/library/youtube.googleapis.com) سرویس YouTube Data API v3 را فعال کن.
۲. یک **API key** بساز (Credentials → Create credentials → API key).
۳. در برنامه: **Settings → API** → کلید را بچسبان → **Validate**.

کلید محلی ذخیره می‌شود و فقط به گوگل فرستاده می‌شود. هر کلید روزی ۱۰٬۰۰۰ واحد سهمیه دارد؛ هر اسکرپ کانال تقریباً ۱ واحد برای هر ۵۰ ویدیو مصرف می‌کند.

**سرویس هوش مصنوعی (اختیاری):** **Settings → AI Providers** → Gemini، OpenAI یا هر سرویس سازگار با OpenAI. هیچ بخشی از برنامه به آن وابسته نیست.

**زبان و تم:** **Settings → Appearance** → انگلیسی/فارسی (RTL کامل)، تیره/روشن، پنج رنگ اکسنت. همه برای همان کاربر ذخیره می‌شود.

### ۴. افزونهٔ مرورگر (دکمهٔ Hunter)

افزونه از قبل روی دیسک است — نصب‌کننده آن را در پوشهٔ برنامه گذاشته:

۱. `chrome://extensions` (کروم، اِج، بریو، اپرا) یا `edge://extensions` را باز کن.
۲. **Developer mode** را روشن کن.
۳. **Load unpacked** را بزن و این پوشه را انتخاب کن:

   ```
   %LOCALAPPDATA%\Programs\YouTube Hunter\browser-extension
   ```

۴. یک ویدیوی یوتیوب باز کن؛ کنار Like/Share دکمهٔ **Hunter** ظاهر می‌شود.
۵. اولین کلیک: مرورگر می‌پرسد *«Open YouTube Hunter?»* — تیک **Always allow** را بزن. این همان پروتکل `youtubehunter://` است که برنامه را (کوچک‌شده) اجرا می‌کند.

جزئیات کامل: **[EXTENSION.md](EXTENSION.md)**.

### ۵. داده‌های تو کجاست

| مسیر | چیست |
|---|---|
| `%APPDATA%\YoutubeScrapperCyber\config.json` | تنظیمات، کلیدها، تم، زبان، پیش‌فرض‌های دانلود |
| `%APPDATA%\YoutubeScrapperCyber\ideas.db` | آرشیو: اسکرپ‌ها، کانال‌ها، ویدیوها، ایده‌ها، کلیپ‌ها، تاریخچهٔ چت |
| `%APPDATA%\YoutubeScrapperCyber\crash.log` | لاگ خطای خود برنامه — برای گزارش باگ همین را بفرست |
| `%APPDATA%\YoutubeScrapperCyber\deno\` و `pot\` | فایل‌های کمکی که خود برنامه نصب کرده (اگر از داخل برنامه نصب کرده باشی) |
| پوشهٔ Downloads | ویدیوهای دانلودشده و کلیپ‌ها (مسیر برای هر دانلود قابل تغییر است) |

برای شروع کاملاً تازه: برنامه را ببند، پوشهٔ `%APPDATA%\YoutubeScrapperCyber` را به اسم دیگری تغییر بده، برنامه را دوباره باز کن.

### ۶. رفع اشکال

**برنامه روی «No internet / YouTube is blocked» باز می‌شود:** این گیت بر اساس لیست کشور نیست؛ خودِ یوتیوب را می‌پرسد. `restricted` یعنی IP در کشور فیلترشده است (VPN را روشن کن)، `unreachable` یعنی اینترنت هست ولی یوتیوب از این IP جواب نمی‌دهد (خروجی VPN را عوض کن)، `offline` یعنی اینترنت قطع است. هر ۶۰ ثانیه (وقتی بلاک است هر ۱۰ ثانیه) دوباره تست می‌کند و خودش بسته می‌شود.

**دانلود روی ۳۶۰p می‌ماند یا ۴۰۳ می‌دهد:** یوتیوب به این IP لیست «لاغر» می‌دهد. **Settings → Download Engine** را ببین: `bgutil-pot` باید **Ready** باشد؛ اگر نبود **Install/Reinstall** را بزن. اگر Ready است و باز هم ۳۶۰p می‌گیری، خروجی VPN را عوض کن یا **Use cookies from browser** را روشن کن (فایرفاکس بهترین نتیجه را می‌دهد).

**«Waiting for the extension» در برنامه:** افزونه را در `chrome://extensions` با **Reload** دوباره بارگذاری کن، یک ویدیو باز کن و یک بار **Hunter** را بزن. دکمهٔ **Mark as connected** هم در Settings → Download Engine هست.

**دکمهٔ Hunter نمی‌آید:** افزونه فقط روی `youtube.com` تزریق می‌شود — بعد از نصب تب را دوباره بارگذاری کن. تبلیغ‌بلاکرها هم ممکن است دکمه را پنهان کنند.

**پورت ۴۷۳۹۱ اشغال است:** یک نسخهٔ دیگر از برنامه باز است؛ ببندش و دوباره اجرا کن (برنامه فقط یک نسخه اجرا می‌کند).

**دانلود یا برش نصفه ماند:** در **Downloads** (یا **Cutter**) دکمهٔ **Resume** را بزن — فایل `.part` و انتخاب کیفیت/فرمت/ترک صدا حفظ شده است.

**گزارش مشکل:** یک [issue](https://github.com/reyzodev/youtube-hunter/issues) باز کن با نسخه (پایین سایدبار)، کاری که کردی و چه شد، و `crash.log` اگر برنامه بسته شد.

</div>
