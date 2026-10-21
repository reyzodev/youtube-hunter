# v3.41.6 — بازطراحی بریف (Dossier) + رفع باگ انتخاب متن

## ۱) بازطراحی لنز «بریف» در Snapshot Insights
فایل: `app/qml/pages/InsightsPage.qml` (فقط بخش `1 · BRIEF`؛ قرارداد InsightsVM دست نخورده)

- **Hero**: خلاصه‌ی بریف به‌صورت یک «statement» بزرگ (۲۰/۲۴/۲۸px بسته به عرض) روی یک ریل اکسنت که آرام نفس می‌کشد؛ نوار متا (provider · زمان ذخیره، کپی، تحلیل مجدد).
- **طیف اطمینان**: نوار سه‌رنگ Observed / Inferred / Needs Studio که هنگام ورود پر می‌شود + چیپ‌های legend. نوار، چیپ‌ها و فیلتر پایین همه **یک فوکوس مشترک** دارند.
- **Intent**: چهار فریم (کار بیننده، بیننده، سطح، وعده) در یک spec-sheet با جداکننده‌ی hairline، به‌جای چهار کارت شناور.
- **Signals**: همه‌ی جمله‌های برچسب‌دار با segmented control (pill لغزان)؛ در عرض زیاد سه ستون کنار هم.
- **Openings / Questions / Experiments**: تایپوگرافی درشت‌تر، فاصله‌گذاری نفس‌دار، آکاردئون تمیزتر، تب‌های فصل‌وار با hairline روشن، انیمیشن جابه‌جایی بین آزمایش‌ها و تایم‌لاین عمودی در عرض کم.
- **Pitch و Busy**: صفحه‌ی خالی دوستونه با CTA، و حالت در حال ساخت با شمارنده‌ی زمان واقعی.
- همه‌ی انیمیشن‌های تزئینی به `Tokens.appActive` گره خورده‌اند (پنجره در پس‌زمینه = بدون فریم اضافه).
- رشته‌های جدید در `app/locales/fa.py` اضافه شده‌اند.

## ۲) رفع باگ «متن انتخاب‌شده دوبار و جابه‌جا دیده می‌شود»
فایل‌ها: `app/qml/components/AppText.qml`، `app/qml_backend/text_layout_bridge.py` (جدید)، `main_qml.py`

**علت:** `AppText { selectable: true }` یک TextEdit نامرئی روی Text می‌گذارد. Text از `lineHeight` (مثلاً 1.22) پیروی می‌کند ولی TextEdit این property را ندارد و خطوط را با 1.0 می‌چیند؛ پس overlay خط‌به‌خط بالاتر می‌رفت و متنِ انتخاب‌شده با `selectedTextColor` در جای اشتباه دوباره کشیده می‌شد.

**رفع:**
- `TextLayout` (پل پایتونی جدید) همان line height را روی `QTextBlockFormat` سندِ TextEdit اعمال می‌کند ⇒ خطوط دقیقاً روی هم می‌افتند.
- `selectedTextColor` هم شفاف شد ⇒ overlay دیگر هیچ گلیفی نمی‌کشد؛ انتخاب فقط یک tint روی متن واقعی است، پس ghosting حتی در صورت اختلاف یک پیکسلی هم ممکن نیست.
- `wrapMode` بدون تغییر پاس داده می‌شود (قبلاً همیشه Wrap بود).
- این رفع روی همه‌ی ۲۷ جای `selectable: true` در برنامه اثر دارد.

## تست
```bash
QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py
python -m PySide6.qmllint -I app/qml app/qml/pages/InsightsPage.qml
```
