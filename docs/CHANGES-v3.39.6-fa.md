# تغییرات نسخه 3.39.6

## رفع لگ ریز موقع سوییچ تم (تاریک ↔ روشن)

### ریشهٔ مشکل
وقتی پردهٔ Lock-on کامل می‌پوشاند (۱۵۰ms)، `applyTheme` کل پالت (۷۶ کلید) را **در یک فریم** دوباره منتشر می‌کرد.
همان یک فریم این‌ها را با هم انجام می‌داد:

1. **~۴۸۰۰ binding رنگ** در همهٔ صفحه‌های لودشده (حتی صفحه‌های مخفیِ داخل Loader) دوباره حساب می‌شدند.
2. **~۲۹۰ تا `Behavior on color / border.color / glyphColor`** همزمان یک ColorAnimation راه می‌انداختند.
   برای آیکون‌ها بدتر: هر فریمِ انیمیشن یک رنگ میانی = یک URL جدید `image://svgicon/...` = پارس و رندر SVG
   در پایتون روی GUI thread. یعنی ده‌ها آیکون × ~۱۲ فریم.
3. همهٔ آیکون‌های SVG با رنگ جدید **برای اولین بار** rasterize می‌شدند (کش خالی).
4. آیکون پنجره (۷ سایز تا ۲۵۶px) دوباره نقاشی و `setWindowIcon` می‌شد، در حالی که فقط به accent بستگی دارد.

نتیجه: یک فریم خیلی طولانی وسط حرکت لوگو/مدار پرده = همان «لگ ریز».

### رفع
- **سوییچ مرحله‌ای پالت** (`ThemeBridge.begin_staged`): فقط کلیدهایی که واقعاً عوض می‌شوند (۵۷ از ۷۶)،
  هر بار حداکثر ~۵ms، با یک فریم فاصله، پشت پردهٔ مات منتشر می‌شوند. قبل از باز شدن عنبیه
  `App.flushThemeSwap()` هرچه مانده را تمام می‌کند، پس reveal هیچ‌وقت نیمه‌کاره نیست.
- **`Tokens.themeSwapping`**: در طول سوییچ همهٔ Behaviorهای رنگ `enabled: false` می‌شوند و رنگ‌ها
  مستقیم می‌پرند (پشت پرده دیده نمی‌شود). دیگر هیچ ColorAnimation و هیچ رندر SVG فریم‌به‌فریمی نیست.
- **پیش‌گرم کردن آیکون‌ها** (`svg_icon_provider.prewarm`): ۲.۵ ثانیه بعد از اجرا، بعد از هر سوییچ،
  و وقتی موس روی دکمهٔ تم می‌رود، آیکون‌هایی که تم مقابل لازم دارد در برش‌های ۳ms در زمان بیکاری رندر می‌شوند.
  موقع سوییچ فقط cache hit داریم.
- کش آیکون‌ها LRU شد (قبلاً در ۲۰۴۸ کل کش یکجا پاک می‌شد، که می‌توانست دقیقاً وسط سوییچ بیفتد).
- آیکون پنجره فقط وقتی accent واقعاً عوض شود دوباره ساخته می‌شود.

### فایل‌ها
`qml_backend/theme_bridge.py`, `qml_backend/app_controller.py`, `qml_backend/svg_icon_provider.py`,
`main_qml.py`, `qml/Tokens.qml`, `qml/Main.qml`, `qml/components/ThemeWipe.qml`,
`qml/components/ThemeSwitch.qml` و `enabled: !Tokens.themeSwapping` روی ۲۸۷ Behavior رنگ در ۵۰+ فایل QML.

نسخه در `constants.py`، `version_info.txt` و `installer.iss` روی 3.39.6 هم‌سان شد
(دو فایل آخر هنوز 3.38.0 مانده بودند).

### تست
بدون نمایشگر:
```bash
QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py
python -m PySide6.qmllint -I app/qml app/qml/components/ThemeWipe.qml
```

### هات‌فیکس: `Slot 'QQmlPropertyMap::' not found`
بیلد اول به `QTimer.singleShot` متد bound خود `ThemeBridge` (مثل `self._drain`) می‌داد. PySide این را
«اسلاتِ روی همان QObject» فرض می‌کند و در meta-object دنبالش می‌گردد؛ meta-object یک `QQmlPropertyMap`
داینامیک است و پیدا نمی‌شود → همین خطا موقع سوییچ. حالا همهٔ تایمرها یک closure ساده پایتون می‌گیرند
(`_later`)، و اگر برشی از سوییچ به هر دلیلی خطا بدهد، بقیهٔ پالت یکجا اعمال می‌شود تا تم نیمه‌کاره نماند.
