# v3.25: حذف کامل Keyword Research + پاک‌سازی و بهینه‌سازی

## حذف بخش Keyword
- صفحه‌ی `KeywordsPage.qml`، `keywords_vm.py` و کل پکیج `app/core/keywords/` حذف شد.
- آیتم «Keyword Research» از منوی کناری، اتصال‌های `Main.qml` و ثبت VM در `main_qml.py` برداشته شد.
- ۱۵ کامپوننت QML که فقط این صفحه استفاده می‌کرد حذف شد (KeywordCascade، KeywordShortlist، VocabBrowser، IntentBoard، TopicExplorer، OpportunityMap، RegionBoard، InterestChart، EngineSplit، SignalList، Sparkline، StereoWave، TabDock، TagComposer، WatchStats) + توابع `seriesColor/SERIES_MAX` در Utils.js + آیکن `nav_keywords` + changelog های v3.19 تا v3.23 + `docs/wip`.

## شماره‌ی صفحه‌ها (مهم)
اسلات‌های خالی ۱۱ (Script Studio) و ۱۳ (Keyword) حذف شدند: Insights = 11، Video Cutter = 12، AI Chat = 13. همه‌ی ارجاع‌ها (`app_controller.py`، `Main.qml`، `Sidebar.qml`، `ContentLabPage.qml`، `notifications_vm.py`) به‌روز شد. کلیک روی اعلان Video Cutter و AI Chat حالا به صفحه‌ی خودش می‌رود.

## حذف کدهای بلااستفاده
- کل نسخه‌ی قدیمی QWidgets: `main.py`، `app/ui/window`، `app/ui/dialogs`، `app/ui/widgets`، `stylesheet.py`، `boot.py`، `content_lab_style.py`، `effects.py`، `compat.py`.
- ماژول‌های یتیم: `core/ai/ideas.py`، `core/analysis/content_lab_report.py`، کلاس `ThumbLoader`.
- کامپوننت‌های QML بی‌استفاده: GaugeArc، GridColumnsToggle، NicheCard، QuotaRing، RankedBars، ScatterChart، SectionCard، SeriesChart، StatMeterCard، PlaceholderPage؛ تابع `fmtBytes`.
- فایل‌های بی‌مصرف: `fonts/icons.ttf`، `assets/icons/*.svg`، `assets/app.png`، `assets/profile.jpg`، همه‌ی `__pycache__`.

## بهینه‌سازی
- اپ دیگر QtWidgets / QtMultimediaWidgets را موقع اجرا import نمی‌کند (قبلاً از طریق `compat.py`، `thumbs.py` و `icons.py` لود می‌شد) → شروع سریع‌تر و حافظه‌ی کمتر.
- KeywordsVM دیگر موقع استارت ساخته نمی‌شود.
- `icon_char` کش شد (هر گلیف در هر binding یک بار محاسبه می‌شود).

## تست
PySide6 در محیط ویرایش نبود؛ فقط تحلیل استاتیک (import graph، نمودار ارجاع QML، چک نام‌های تعریف‌نشده) انجام شد. روی ویندوز اجرا کن:
`QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py`
