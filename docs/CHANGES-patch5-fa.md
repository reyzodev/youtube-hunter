# v3.16 — patch 5 (Keyword Lab — مرحلهٔ اول)

## انجام‌شده و تست‌شده (بک‌اند)
- صفحهٔ Keyword Research دوباره در سایدبار نمایش داده می‌شود.
- پشتیبانی فارسی: seed فارسی با کلمات فارسی (چیست، چطور، آموزش، بهترین…)، پیشوندها (آموزش X، بهترین X) و الفبای فارسی گسترش داده می‌شود (`suggest.detect_lang`).
- تکمیل خودکار زنده هنگام تایپ (یوتیوب + گوگل، علامت «فقط یوتیوب») — `KeywordsVM.preview` + کامپوننت جدید `KeywordCascade.qml`.
- `app/core/keywords/insights.py` (جدید): سؤال‌ها، زیرموضوع‌ها (clusters)، intent، long-tail، پک تگ ۵۰۰ کاراکتری یوتیوب، momentum ترند (صعودی/نزولی + تاریخ اوج).
- `app/core/keywords/store.py` (جدید): کلمات ذخیره‌شده (ستاره) + اجراهای اخیر کامل (بازکردن فوری بدون درخواست دوباره به Trends).
- VM: explorer با فیلتر/مرتب‌سازی/جست‌وجو، خروجی CSV/Excel، کپی، tagPack، savedList، recentRuns، فیلدهای جدید focus (ترند، سهم یوتیوب/گوگل، KD، intent).
- باگ: آیکون `person_search` در ICON_MAP نبود (پنل Who is searching بی‌آیکون بود) → `user`.
- باگ: بعد از کلیک روی چیپ‌ها، باکس seed قدیمی می‌ماند → همگام‌سازی.

## در حال انجام
- بازطراحی کامل UI صفحه (کنسول + focus card + ۵ تب). پیش‌نویس: `docs/wip/KeywordsPage-v317-part1.qml.txt`.
