# v3.16 patch3

1. **جابه‌جایی نرم بین ایده‌ها** (AI Ideas + Content Lab): کامپوننت جدید `BlueprintStage.qml` بلوپرینت بعدی را async (Loader asynchronous، دوبافره) پشت یک veil اسکلتی با شیمر و اسپینر می‌سازد و بعد جابه‌جا می‌کند. در Content Lab انتخاب کارت دیگر کل ریل را rebuild نمی‌کند (سیگنال `activeChanged`). ستاره زدن هم دیگر کل پنل را rebind نمی‌کند (`favOn`).
2. **مدل‌های انتخابی هر Provider**: فیلد جدید `picked` در پروفایل. Fetch فقط کاتالوگ را می‌آورد؛ کاربر از لیست تیک می‌زند، با × حذف می‌کند، با کلیک روی چیپ مدل اصلی (★) را عوض می‌کند، یا شناسه را دستی تایپ و Enter می‌زند. AI Chat و AI Routing فقط همین مدل‌ها را نشان می‌دهند. مدل حذف‌شده اگر در چت pin بود، خودکار به مدل اصلی برمی‌گردد. کانفیگ‌های قدیمی مدل فعلی (و مدل pin شده‌ی چت) را نگه می‌دارند.
3. **Video Cutter**: پلیر کلیپ لوگو/نام/لینک کانال را از رکورد دانلود همان ویدیو می‌خواند (به‌جای حرف «C»)، و لینک یوتیوب با `&t=<start>s` دقیقاً از ثانیه‌ی شروع کات باز می‌شود.

فایل‌های تغییرکرده: BlueprintStage.qml (جدید)، BlueprintPane.qml، AIIdeasPage.qml، ContentLabPage.qml، AiProfileCard.qml، content_lab_vm.py، settings_vm.py، chat_vm.py، cutter_vm.py، profiles.py، fa.py
