# AI Chat — مرحله ۲ (کامل)

## انجام‌شده در این مرحله
- `app/qml_backend/vm/chat_vm.py`: ViewModel کامل (گفتگوها، استریم، Stop واقعی، منابع، picker، لینک، فایل، درایو، خروجی Markdown، ویرایش/بازنویسی، عنوان هوشمند).
- `app/qml/pages/AIChatPage.qml`: صفحه‌ی پرمیوم (ریل گفتگوها، لنز متحرک Scope، کامپوزر شناور، منوی +، پنل Context با نوار بودجه، drag & drop، picker ویدیو، دیالوگ لینک و درایو، کارت ایده‌ها).
- `components/ScopeLens.qml` (لنز دیافراگمی)، `components/RoundThumb.qml`، آیکون متحرک `nav_chat` در `NavIcon.qml`.
- ثبت صفحه (index 15) در `Main.qml` / `Sidebar.qml` / `app_controller.py` / `main_qml.py`، ترجمه‌های `fa.py`، نسخه **3.14.0**.

## باگ‌های مرحله ۱ که درست شد
- `init_chat_db()` حالا در `main_qml.py` صدا زده می‌شود.
- Stop واقعی: سوکت با `abort_response()` بسته می‌شود؛ دیگر تا ۹۰ ثانیه منتظر نمی‌ماند.
- `fit_history()`: سقف کاراکتر برای تاریخچه + فقط تصاویر ۳ پیام آخر (حداکثر ۶).
- مدل‌های reasoning (o1/o3/o4/gpt-5): `max_completion_tokens` و بدون `temperature`.
- digest کهنه: upsert حالا digest را هم جایگزین می‌کند.
- حذف گفتگو فایل‌های `chat_files/` همان گفتگو را هم پاک می‌کند.
- `pypdf` به requirements و spec اضافه شد؛ `GDRIVE_CLIENT_ID/SECRET` به constants؛ تنظیم OAuth داخل دیالوگ درایو.
- busy timeout برای SQLite (نوشتن هم‌زمان از تردها).

## تست
- منطق پایتون (split_parts / stream_display / fit_history / DB) در محیط بدون Qt تست شد.
- **QML اجرا نشده** (محیط ساخت PySide6 نداشت). اول این را بزن و هر خطای QML را بفرست:
  `QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py`
  و `python -m PySide6.qmllint -I app/qml app/qml/pages/AIChatPage.qml`

# AI Chat — مرحله ۳ (3.14.1)
- کوچ + ایده‌های متکی به دیتا (`concept` و `refs` روی کارت)، Build in AI Ideas با ویدیوهای منبع و حالت `seeded`.
- حذف کامل Context از صفحه‌ی چت.
- فونت IRANYekanX برای متن فارسی در UI انگلیسی.
- تست: منطق پایتون (bind_idea_sources، ideaHandoff، importFromChat، generate با seeded) با Qt جعلی تست شد. **QML اجرا نشده** — اول این را بزن:
  `QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py`
