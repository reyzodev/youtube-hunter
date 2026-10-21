# تغییرات 3.39.7

## ۱) توقف ساخت ایده (AI Ideas)
- دکمه‌ی «Create with AI» هنگام ساخت به «توقف ساخت» (قرمز) تبدیل می‌شود.
- توقف واقعی است: سوکت درخواست فوراً بسته می‌شود (پرووایدر هم تولید را قطع می‌کند)، صفحه بلافاصله آزاد می‌شود، و هیچ چیزی از اجرای متوقف‌شده ذخیره نمی‌شود. پاسخ دیرِ اجرای قبلی با run-id نادیده گرفته می‌شود.
- `core/net.py`: `CancelToken` / `cancel_scope` / `RequestCancelled` (برای بقیه‌ی بخش‌ها هم قابل استفاده). retry و backoff هم قابل قطع‌اند.

## ۲) رنگ انتخاب متن
- همه‌ی فیلدهای ورودی (۲۵ مورد TextField/TextArea) رنگ selection را از رنگ تم می‌گیرند (`Theme.primary` با ۳۵٪) به جای آبی سیستم؛ با عوض شدن تم/اکسنت زنده عوض می‌شود.

## ۳) اسکرول‌بار منوی کناری
- خط اسکرول فقط وقتی دیده می‌شود که آیتم‌های منو جا نشوند (پنجره‌ی کوچک). قبلاً contentItem سفارشی حالت‌های show/hide را حذف کرده بود و خط همیشه دیده می‌شد.
- بزرگ کردن پنجره دیگر لیست را اسکرول‌شده و با فاصله‌ی خالی رها نمی‌کند.

## ۴) بهینه‌سازی
- دیتابیس: حالت WAL + `synchronous=NORMAL` برای همه‌ی اتصال‌ها (`core/db/_sqlite.py`) — خواندن UI دیگر پشت نوشتن workerها قفل نمی‌شود؛ timeout پیش‌فرض ۱۰ ثانیه.
- ایندکس: `content_lab_ideas(entry_id, sort_order, id)` و `downloads(added_at)`.
- Niche Finder: ذخیره‌ی خودکار نتایج در آرشیو از GUI thread به worker منتقل شد (بعد از هر جستجو دیگر فریز کوتاه ندارد).
- AI Ideas: خواندن CSV/XLSX روی worker، و نتیجه کش می‌شود تا موقع Generate دوباره خوانده نشود.

## پیشنهادهای بعدی (اعمال نشده، نیاز به تست روی ویندوز)
- AI Chat: `_DIGEST_POOL` (۴ worker) در chat_vm تعریف شده؛ دو جای `threading.Thread(target=self._digest_worker…)` را به `_DIGEST_POOL.submit(...)` تبدیل کنید.
- Dashboard: batch کردن لاگ/پیشرفت اسکرپ (هر ۵۰–۱۰۰ms یک emit).
- Content Lab: کوئری تجمیعی به جای N+1 در `_entry_stats` و کش `list_deep_reports`.
- Downloads: نوشتن checkpoint پیشرفت روی worker؛ Archive: باز کردن گروه‌های بزرگ روی worker.
- `IdeaRefCard`: `sourceSize` برای thumbnailها؛ چند انیمیشن بی‌نهایت AIChatPage به `page.visible` بسته شوند.
