# The Hunter button — browser extension guide

English first · [فارسی ↓](#فارسی)

---

The extension puts **YouTube Hunter** on the YouTube page: a *Hunter* button next to Like/Share that opens a panel for downloading the video you are watching or cutting a clip out of it. The desktop app does the actual work — the browser only asks it.

Supported browsers: **Chrome, Edge, Brave, Opera, Vivaldi** (anything Chromium-based with Manifest V3).

## 1. Install (30 seconds)

The installer already put the extension on your disk:

```
%LOCALAPPDATA%\Programs\YouTube Hunter\browser-extension
```

1. Open `chrome://extensions` (or `edge://extensions`).
2. Turn on **Developer mode** — the toggle in the top-right corner.
3. Click **Load unpacked**.
4. Select the `browser-extension` folder above.
5. Open any YouTube video and **reload the tab** once. The **Hunter** button appears next to Like / Share, and inside Shorts.

> The extension is unpacked rather than installed from the Chrome Web Store, so Chrome keeps it in place and updates nothing by itself. After you update the desktop app, the copy in the app folder is replaced — open `chrome://extensions` and press **Reload** on *YouTube Hunter*.

## 2. The first click

If the desktop app is **not running**, clicking Hunter launches it through the `youtubehunter://` protocol (registered by the installer) — minimised, so it does not steal focus. The browser asks *"Open YouTube Hunter?"* the first time: tick **Always allow** and confirm.

If launching fails, the panel shows a *"The app is closed"* card with **Start** / **Retry**.

If the app is already running, nothing is launched — the panel talks to it directly on `127.0.0.1:47391`.

## 3. Download tab

| | |
|---|---|
| **Video** | Every real quality the video has (up to 4K/8K where available) with its real file size, computed from the actual streams — not a guess. |
| **Video format** | MP4 / MKV / WEBM. Sizes are recomputed for the chosen container. |
| **Audio only** | Download the soundtrack instead of the video. |
| **Audio format** | MP3 / M4A / OPUS / WAV / FLAC. |
| **Audio track** | Original, or any dub the video has (creator dubs and YouTube's auto-dubs). The dropdown shows the language code, the native name and a colour tag: **Original** / **Dub** / **Auto**. |
| **Download** | Turns the row into a live capsule: percent, status, quality, speed with a sparkline, size, time remaining, and **⏸ / ▶** pause & resume (the `.part` file is kept). |
| **When it finishes** | The capsule offers **▶ Play** and **Show in folder**. A saved quality keeps its ▶ button, so you can switch to another quality and back without losing it. |

The panel stays open after you press Download — you can start another quality or another video.

## 4. Cut tab

| | |
|---|---|
| **In / Out** | Drag the handles on the ruler (the YouTube player seeks as you drag), type a timecode, or press `[` / `]` at the current position. |
| **Ruler** | Zoomed around your clip (clip + 60% each side, minimum 12 s), with an overview strip for the whole video. *Whole video / Zoom to clip* switches the scale. |
| **Output** | **Video** (MP4 / MKV / WEBM) or **Audio only** (MP3 / M4A / OPUS / WAV / FLAC). Only the options for the chosen output are shown. |
| **Audio track** | Pick a dub for the clip, same as the download tab. |
| **Cut** | Only the selected range is downloaded and cut — not the whole video. The progress capsule shows percent, speed, size and ETA, with a ■ stop button. |

Finished clips appear in the app's **Cutter** history with their own card, ready to play, reveal or re-cut.

## 5. What happens when you leave the page

While the panel is open it keeps the desktop **live activity card** away (the panel is already showing the job). Close the panel, switch tabs, or navigate away and the desktop card takes over within a few seconds and follows the job to the end — same as an in-app download or cut.

## 6. Security

The bridge is a local HTTP server:

- Binds **`127.0.0.1:47391`** only — not reachable from your network or the internet.
- Accepts a request only when it carries the extension's `Origin` **and** the `X-YTH-Bridge` header. A random website cannot start a download.
- Accepts only the documented endpoints (`/v1/ping`, `/v1/qualities`, `/v1/download`, `/v1/status`, `/v1/pause`, `/v1/resume`, `/v1/cut`, `/v1/cut/status`, `/v1/cut/cancel`, `/v1/reveal`, `/v1/play`, `/v1/watch`).
- Can be switched off completely: set `"browser_bridge": false` in `%APPDATA%\YoutubeScrapperCyber\config.json` and restart the app. The extension then reports that the app is unreachable.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| No Hunter button | Reload the tab after installing; check the extension is enabled and has no errors; whitelist YouTube in ad-blockers. |
| *"Waiting for the extension"* in the app | `chrome://extensions` → **Reload**; click Hunter once; or press **Mark as connected** in Settings → Download Engine. |
| *"The app is closed"* even though it is open | A second copy of the app may be running, or the port is taken. Close all copies and start one. |
| Panel opens but lists no qualities | The video may be region-locked, members-only, or the app is not connected to YouTube (the connection gate explains which). |
| Cut fails immediately | Make sure In < Out and the clip is at least 1 second. If the app shows an error, the panel now waits and retries instead of reporting a false failure. |
| Everything worked, then stopped after an app update | Reload the extension (`chrome://extensions` → **Reload**) so it picks up the new panel. |

---

<div dir="rtl">

## فارسی

افزونه **یوتیوب هانتر** را روی خودِ صفحهٔ یوتیوب می‌آورد: کنار Like/Share یک دکمهٔ **Hunter** که پنل دانلود همان ویدیو یا برش یک تکه از آن را باز می‌کند. کار اصلی را برنامهٔ دسکتاپ انجام می‌دهد؛ مرورگر فقط درخواست می‌دهد.

مرورگرهای پشتیبانی‌شده: **کروم، اِج، بریو، اپرا، ویوالدی** (هر مرورگر مبتنی بر Chromium با Manifest V3).

### ۱. نصب (۳۰ ثانیه)

نصب‌کننده از قبل افزونه را روی دیسک گذاشته:

```
%LOCALAPPDATA%\Programs\YouTube Hunter\browser-extension
```

۱. `chrome://extensions` (یا `edge://extensions`) را باز کن.
۲. **Developer mode** را روشن کن (گوشهٔ بالا-راست).
۳. **Load unpacked** را بزن.
۴. پوشهٔ `browser-extension` بالا را انتخاب کن.
۵. یک ویدیوی یوتیوب باز کن و تب را **یک بار reload** کن. دکمهٔ **Hunter** کنار Like/Share (و داخل Shorts) ظاهر می‌شود.

> افزونه به‌صورت unpacked نصب می‌شود، پس کروم خودش آن را آپدیت نمی‌کند. بعد از هر آپدیت برنامه، نسخهٔ داخل پوشهٔ نصب عوض می‌شود — در `chrome://extensions` روی **Reload** بزن.

### ۲. اولین کلیک

اگر برنامه بسته باشد، با کلیک روی Hunter از طریق پروتکل `youtubehunter://` (که نصب‌کننده ثبت می‌کند) **کوچک‌شده** اجرا می‌شود و فوکوس را نمی‌دزدد. مرورگر بار اول می‌پرسد *«Open YouTube Hunter?»* — تیک **Always allow** را بزن و تأیید کن.

اگر اجرا نشد، پنل کارت *«برنامه بسته است»* با دکمه‌های **Start / Retry** نشان می‌دهد. اگر برنامه از قبل باز باشد، چیز جدیدی اجرا نمی‌شود؛ پنل مستقیم روی `127.0.0.1:47391` با آن حرف می‌زند.

### ۳. تب دانلود

| | |
|---|---|
| **ویدیو** | همهٔ کیفیت‌های واقعی ویدیو (تا 4K/8K اگر باشد) با حجم واقعی که از خود استریم‌ها حساب می‌شود — نه حدس. |
| **فرمت ویدیو** | MP4 / MKV / WEBM؛ حجم‌ها با کانتینر انتخاب‌شده دوباره حساب می‌شوند. |
| **فقط صدا** | به‌جای ویدیو، صدا دانلود می‌شود. |
| **فرمت صدا** | MP3 / M4A / OPUS / WAV / FLAC. |
| **ترک صدا** | صدای اصلی یا هر دوبله‌ای که ویدیو دارد (دوبلهٔ سازنده و دوبلهٔ خودکار یوتیوب). دراپ‌داون کد زبان، نام بومی و برچسب رنگی **Original / Dub / Auto** را نشان می‌دهد. |
| **Download** | ردیف به کپسول زنده تبدیل می‌شود: درصد، وضعیت، کیفیت، سرعت با اسپارک‌لاین، حجم، زمان باقی‌مانده و **⏸ / ▶** مکث و ادامه (فایل `.part` حفظ می‌شود). |
| **پایان کار** | کپسول **▶ Play** و **Show in folder** می‌دهد. کیفیت ذخیره‌شده دکمهٔ ▶ خودش را نگه می‌دارد، پس می‌توانی کیفیت را عوض کنی و برگردی. |

بعد از Download پنل بسته نمی‌شود؛ می‌توانی کیفیت یا ویدیوی دیگری را شروع کنی.

### ۴. تب برش

| | |
|---|---|
| **In / Out** | دستگیره‌ها را روی خط‌کش بکش (پلیر همان لحظه seek می‌شود)، تایم‌کد تایپ کن، یا در نقطهٔ جاری `[` و `]` را بزن. |
| **خط‌کش** | دور کلیپ زوم می‌شود (کلیپ + ۶۰٪ هر طرف، حداقل ۱۲ ثانیه) و یک نوار نمای کل ویدیو دارد. کلید *Whole video / Zoom to clip* مقیاس را عوض می‌کند. |
| **خروجی** | **ویدیو** (MP4 / MKV / WEBM) یا **فقط صدا** (MP3 / M4A / OPUS / WAV / FLAC). فقط گزینه‌های خروجی انتخاب‌شده نشان داده می‌شوند. |
| **ترک صدا** | برای کلیپ هم می‌توانی دوبله انتخاب کنی. |
| **Cut** | فقط همان بازه دانلود و بریده می‌شود، نه کل ویدیو. کپسول پیشرفت درصد، سرعت، حجم و زمان باقی‌مانده را با دکمهٔ ■ توقف نشان می‌دهد. |

کلیپ‌های آماده در تاریخچهٔ **Cutter** برنامه با کارت خودشان می‌آیند: پخش، نمایش در پوشه یا برش دوباره.

### ۵. وقتی صفحه را ترک می‌کنی

تا وقتی پنل باز است، **کارت فعالیت زندهٔ** دسکتاپ نمی‌آید (پنل خودش کار را نشان می‌دهد). پنل را ببند، تب را عوض کن یا از صفحه برو: چند ثانیه بعد کارت دسکتاپ ادامه را می‌گیرد و تا پایان کار را دنبال می‌کند — مثل دانلود یا برش داخل خود برنامه.

### ۶. امنیت

پل یک سرور HTTP محلی است:

- فقط روی **`127.0.0.1:47391`** گوش می‌دهد — از شبکه یا اینترنت قابل دسترسی نیست.
- فقط درخواستی را قبول می‌کند که هم `Origin` افزونه را داشته باشد و هم هدر `X-YTH-Bridge` را. هیچ سایتی نمی‌تواند دانلود شروع کند.
- فقط اندپوینت‌های مستند (`/v1/ping`، `/v1/qualities`، `/v1/download`، `/v1/status`، `/v1/pause`، `/v1/resume`، `/v1/cut`، `/v1/cut/status`، `/v1/cut/cancel`، `/v1/reveal`، `/v1/play`، `/v1/watch`).
- کامل خاموش‌کردنی است: در `%APPDATA%\YoutubeScrapperCyber\config.json` مقدار `"browser_bridge": false` را بگذار و برنامه را دوباره اجرا کن.

### ۷. رفع اشکال

| نشانه | راه‌حل |
|---|---|
| دکمهٔ Hunter نمی‌آید | بعد از نصب تب را reload کن؛ افزونه فعال و بدون خطا باشد؛ یوتیوب را در تبلیغ‌بلاکر استثنا کن. |
| «Waiting for the extension» در برنامه | `chrome://extensions` → **Reload**؛ یک بار Hunter را بزن؛ یا **Mark as connected** در Settings → Download Engine. |
| «برنامه بسته است» در حالی که باز است | شاید نسخهٔ دومی از برنامه باز است یا پورت اشغال شده؛ همه را ببند و یکی را اجرا کن. |
| پنل باز می‌شود ولی کیفیتی ندارد | ویدیو ممکن است منطقه‌ای/اعضایی باشد یا برنامه به یوتیوب دسترسی نداشته باشد (صفحهٔ گیت اتصال دلیل را می‌گوید). |
| برش فوراً خطا می‌دهد | مطمئن شو In < Out و کلیپ حداقل ۱ ثانیه است. خطای گذرا دیگر «Cut failed» کاذب نمی‌سازد؛ پنل دوباره می‌پرسد. |
| بعد از آپدیت برنامه کار نکرد | در `chrome://extensions` روی **Reload** بزن تا پنل جدید بارگذاری شود. |

</div>
