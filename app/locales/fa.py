"""app.locales.fa - Youtube Scrapper."""


FA_STRINGS = {

    # ── added: download output format (container / audio codec) ──
    'Video format': 'فرمت ویدیو',
    'Audio format': 'فرمت صدا',
    'Plays everywhere': 'روی همه دستگاه‌ها پخش می‌شود',
    'Any codec, no conversion': 'هر کدکی، بدون تبدیل',
    'VP9 / Opus, web-friendly': 'VP9 / Opus، مناسب وب',
    '192 kbps, plays everywhere': '۱۹۲ کیلوبیت، روی همه دستگاه‌ها پخش می‌شود',
    'AAC, no re-encode when possible': 'AAC، در صورت امکان بدون تبدیل مجدد',
    'Original YouTube audio': 'صدای اصلی یوتیوب',
    'Uncompressed, large': 'بدون فشرده‌سازی، حجم زیاد',
    'Lossless container': 'بدون افت کیفیت',
    'Converting to {fmt}…': 'در حال تبدیل به {fmt}…',

    # ── added: Niche Finder filter redesign (outlier strip, behaviour sections) ──
    'Max subscribers': 'حداکثر مشترک',
    'Min views': 'حداقل بازدید',
    'Max views': 'حداکثر بازدید',
    'Min multiplier': 'حداقل ضریب',
    'Refine current results': 'پالایش نتایج فعلی',
    'Instant': 'فوری',
    'Next search options': 'تنظیمات جست\u200cوجوی بعدی',
    'On next run': 'اجرای بعدی',
    'Re-filters the fetched pool instantly · no quota': 'همان داده\u200cهای گرفته\u200cشده را فوری دوباره فیلتر می\u200cکند · بدون سهمیه',
    'Advanced filters': 'فیلترهای پیشرفته',
    'Country': 'کشور',
    'Hide hidden-sub channels': 'پنهان\u200cکردن کانال\u200cهای بدون تعداد مشترک',
    'Deep scan': 'اسکن عمیق',
    'Ignore cache': 'نادیده\u200cگرفتن کش',
    'Slower, digs through more of each channel': 'کندتر است، از هر کانال بیشتر می\u200cکاود',
    "Skip channels that don't publish their counts": 'کانال\u200cهایی که تعداد مشترکشان را منتشر نمی\u200cکنند رد می\u200cشوند',
    'Always fetch fresh results': 'همیشه نتایج تازه گرفته شود',
    'Run a search to discover outlier videos.': 'برای کشف ویدیوهای آوتلایر یک جست\u200cوجو اجرا کنید.',

    # ── added: QML Search Archive page (master/detail, favorites, export) ──
    'Every search you have run is kept here forever — reopen it, re-filter it, export it. Zero quota.': 'هر جست\u200cوجویی که اجرا کرده\u200cاید برای همیشه اینجا نگه داشته می\u200cشود — بازش کنید، دوباره فیلترش کنید، خروجی بگیرید. بدون مصرف سهمیه.',
    'Sections': 'بخش\u200cها',
    'Videos archived': 'ویدیوی آرشیوشده',
    'Search sections…': 'جست\u200cوجوی بخش\u200cها…',
    'Nothing archived yet.': 'هنوز چیزی آرشیو نشده است.',
    'Every finished Niche Finder search lands here automatically.': 'هر جست\u200cوجوی تکمیل\u200cشده در یاب حوزه به\u200cطور خودکار اینجا ثبت می\u200cشود.',
    'Go to Niche Finder': 'رفتن به یاب حوزه',
    'No favorites yet — star videos inside a section to pin them here.': 'هنوز موردی در علاقه\u200cمندی\u200cها نیست — ویدیوها را داخل یک بخش ستاره\u200cدار کنید تا اینجا سنجاق شوند.',
    'No favorites yet — bookmark a section or star its videos to pin them here.': 'هنوز موردی در علاقه\u200cمندی\u200cها نیست — یک بخش را بوکمارک کنید یا ویدیوهایش را ستاره بزنید تا اینجا سنجاق شوند.',
    "Couldn't open that section.": 'باز کردن آن بخش ممکن نشد.',
    'No sections match this search.': 'هیچ بخشی با این جست\u200cوجو مطابقت ندارد.',
    'Updated {t}': 'به\u200cروزرسانی {t}',
    'Open section': 'بازکردن بخش',
    'favs': 'علاقه\u200cمندی',
    'videos': 'ویدیو',
    'Runs': 'اجرا',
    'runs': 'اجرا',
    'Favorites only': 'فقط علاقه\u200cمندی\u200cها',
    'Sort by': 'مرتب\u200cسازی بر اساس',
    'Latest refresh': 'تازه\u200cترین بازخوانی',
    'Most views': 'بیشترین بازدید',
    'Best multiplier': 'بهترین ضریب',
    'Newest video': 'جدیدترین ویدیو',
    'Oldest saved': 'قدیمی\u200cترین ذخیره\u200cشده',
    'No favorites in this section yet — tap the bookmark on a card to pin it.': 'هنوز علاقه\u200cمندی\u200cای در این بخش نیست — نشان کتاب\u200cنشانه روی کارت را بزنید تا سنجاق شود.',
    'This section is empty.': 'این بخش خالی است.',
    'Rename section': 'تغییر نام بخش',
    'Save': 'ذخیره',
    'Delete this section?': 'این بخش حذف شود؟',
    'This permanently removes “{k}” and its {n} archived videos.': 'این کار «{k}» و {n} ویدیوی آرشیوشده\u200cاش را برای همیشه حذف می\u200cکند.',
    'This permanently removes “{k}” and its saved videos.': 'این کار «{k}» و ویدیوهای ذخیره\u200cشده\u200cاش را برای همیشه حذف می\u200cکند.',
    'Clear the whole archive?': 'کل آرشیو پاک شود؟',
    'Every archived section and video will be permanently removed. This cannot be undone.': 'هر بخش و ویدیوی آرشیوشده برای همیشه حذف می\u200cشود. این کار بازگشت\u200cپذیر نیست.',
    'Export section': 'خروجی گرفتن از بخش',
    'Total views': 'مجموع بازدید',
    'Last refresh': 'آخرین بازخوانی',
    'Section deleted.': 'بخش حذف شد.',
    'Section renamed.': 'نام بخش تغییر کرد.',
    'Section saved to favourites.': 'بخش در علاقه‌مندی‌ها ذخیره شد.',
    'Section removed from favourites.': 'بخش از علاقه‌مندی‌ها حذف شد.',
    'Saving failed.': 'ذخیره ناموفق بود.',
    'Renaming failed.': 'تغییر نام ناموفق بود.',
    'Archive cleared.': 'آرشیو پاک شد.',
    'Clearing failed.': 'پاک\u200cسازی ناموفق بود.',
    'Deleting failed.': 'حذف ناموفق بود.',
    'Removed from archive.': 'از آرشیو حذف شد.',
    'That section has no saved rows.': 'آن بخش ردیف ذخیره\u200cشده\u200cای ندارد.',
    '"{v}" was added to Favorites.': '«{v}» به علاقه\u200cمندی\u200cها اضافه شد.',
    '"{v}" was removed from Favorites.': '«{v}» از علاقه\u200cمندی\u200cها حذف شد.',
    'This row is missing video info.': 'این ردیف اطلاعات ویدیو ندارد.',
    'This result is no longer on screen.': 'این نتیجه دیگر روی صفحه نیست.',
    'This row is no longer on screen.': 'این ردیف دیگر روی صفحه نیست.',
    'Nothing to export.': 'چیزی برای خروجی گرفتن نیست.',
    'Download started — {t}': 'دانلود شروع شد — {t}',
    'Download finished — {p}': 'دانلود تمام شد — {p}',
    'Failed': 'ناموفق',
    '{p}%': '{p}٪',
    'Clipboard is unavailable.': 'کلیپ\u200cبورد در دسترس نیست.',
    'Page {p} of {n}': 'صفحه {p} از {n}',
    '{a}–{b} of {n}': '{a}–{b} از {n}',
    'archived': 'آرشیوشده',
    'per hour': 'در ساعت',
    'engage': 'تعامل',
    'age': 'سن',
    '{s} subs': '{s} مشترک',

    # ── added: docs guide, monetization verdict, RPM model, pagination ──
    'Youtube Scrapper · Field Guide': 'یوتیوب اسکرپر · راهنمای کامل',
    'What every page does, what it costs in API quota, and which numbers are measured versus estimated.': 'هر صفحه چه کاری می\u200cکند، چقدر از سهمیه\u200cی API مصرف می\u200cکند، و کدام اعداد اندازه\u200cگیری\u200cشده و کدام تخمینی هستند.',
    'Built by Reza Cheraghi': 'ساخته\u200cی رضا چراغی',
    'Got it': 'متوجه شدم',
    'Free · no quota': 'رایگان · بدون سهمیه',
    'Spends quota': 'مصرف سهمیه',
    'Needs a Gemini key': 'نیازمند کلید جمینای',
    'What this app is': 'این برنامه چیست',
    "Youtube Scrapper is a research desk for YouTube: it finds videos that are punching far above their channel's weight, keeps every search you run, checks whether a channel is earning, and turns any of it into new video ideas with AI.": 'یوتیوب اسکرپر یک میز تحقیق برای یوتیوب است: ویدیوهایی را پیدا می\u200cکند که بسیار بالاتر از وزن کانالشان ظاهر شده\u200cاند، هر جست\u200cوجویی که اجرا می\u200cکنید را نگه می\u200cدارد، بررسی می\u200cکند کانال درآمد دارد یا نه، و هر کدام از این\u200cها را با هوش مصنوعی به ایده\u200cی ویدیوی تازه تبدیل می\u200cکند.',
    'Everything is stored locally in SQLite files next to the app, and every page works offline once its data is in — re-filtering, re-sorting and re-reading a saved search never touches the network or spends quota.': 'همه\u200cچیز به\u200cصورت محلی در فایل\u200cهای SQLite کنار برنامه ذخیره می\u200cشود و هر صفحه پس از یک\u200cبار گرفتن داده، آفلاین کار می\u200cکند — فیلتر مجدد، مرتب\u200cسازی مجدد و بازخوانی یک جست\u200cوجوی ذخیره\u200cشده هیچ\u200cگاه به شبکه نمی\u200cرود و سهمیه مصرف نمی\u200cکند.',
    'Scrapper · scrape one channel': 'Scrapper · اسکرپ یک کانال',
    'Paste a channel URL, choose what to pull (metadata, transcripts, or both) and start. Progress, per-video status and any failures stream into the Logs page while it runs; results export to CSV or Excel.': 'لینک کانال را بچسبانید، انتخاب کنید چه چیزی گرفته شود (متادیتا، زیرنویس یا هر دو) و شروع کنید. پیشرفت کار، وضعیت هر ویدیو و خطاها هم\u200cزمان در صفحه\u200cی لاگ\u200cها نمایش داده می\u200cشود؛ خروجی به CSV یا اکسل گرفته می\u200cشود.',
    "Costs quota: yes — roughly 1 unit per 50 videos listed, plus 1 per video detail batch. Transcripts are free (they don't use the API).": 'مصرف سهمیه: بله — حدود ۱ واحد برای هر ۵۰ ویدیوی فهرست\u200cشده، به\u200cعلاوه ۱ واحد برای هر دسته جزئیات ویدیو. زیرنویس\u200cها رایگان\u200cاند (از API استفاده نمی\u200cکنند).',
    'Niche Finder · the outlier hunt': 'یاب حوزه · شکار آوتلایرها',
    'This is the heart of the app. Search a keyword across all of YouTube, then filter what comes back by subscriber count, views and time window to surface the shape everyone is looking for: a tiny channel with a huge video. A 500-subscriber channel with 2M views in 30 days is a 4,000x multiplier — that is a format working, not luck.': 'این قلب برنامه است. یک کلیدواژه را در کل یوتیوب جست\u200cوجو کنید، سپس نتایج را با تعداد مشترک، بازدید و بازه\u200cی زمانی فیلتر کنید تا همان چیزی که همه دنبالش هستند بیرون بیفتد: کانالی کوچک با ویدیویی غول. کانالی با ۵۰۰ مشترک و ۲ میلیون بازدید در ۳۰ روز، ضریب ۴۰۰۰ برابری دارد — این یعنی فرمت کار می\u200cکند، نه شانس.',
    'Filtering, sorting and switching between the card grid and the table all happen locally on the pool you already fetched, so you can dig through the same search as long as you like for free.': 'فیلتر کردن، مرتب\u200cسازی و جابه\u200cجایی بین نمای کارتی و جدولی، همه به\u200cصورت محلی روی همان داده\u200cای انجام می\u200cشود که قبلاً گرفته\u200cاید؛ پس می\u200cتوانید تا هر وقت بخواهید و رایگان در همان جست\u200cوجو بکاوید.',
    'Costs quota: yes — a search is 100 units, which is why every search is archived automatically the moment it returns.': 'مصرف سهمیه: بله — هر جست\u200cوجو ۱۰۰ واحد است؛ دقیقاً به همین دلیل هر جست\u200cوجو به\u200cمحض بازگشت نتیجه، خودکار آرشیو می\u200cشود.',
    'Search Archive · nothing is ever re-bought': 'آرشیو جست\u200cوجو · هیچ\u200cچیز دوباره خریده نمی\u200cشود',
    'Every Niche Finder search lands here as its own keyword section, with its results, its filters and its window. Click a keyword to bring it back into the grid; re-run it later and the fresh numbers are merged into the section instead of replacing it, so you can watch a niche move over weeks.': 'هر جست\u200cوجوی یاب حوزه به\u200cعنوان یک بخش کلیدواژه\u200cی مستقل با نتایج، فیلترها و بازه\u200cاش اینجا می\u200cنشیند. روی کلیدواژه بزنید تا نتایجش به گرید برگردد؛ اگر بعداً همان را دوباره اجرا کنید، اعداد تازه با بخش قبلی ادغام می\u200cشوند نه اینکه جایش را بگیرند — یعنی می\u200cتوانید حرکت یک حوزه را در طول هفته\u200cها ببینید.',
    'Results are paged six rows at a time. That is not a display quirk — building three hundred result cards at once is what used to make this page stutter, so only the page you are looking at exists as widgets.': 'نتایج شش ردیف در هر صفحه نمایش داده می\u200cشوند. این فقط یک تصمیم ظاهری نیست: ساختن سیصد کارت نتیجه به\u200cصورت یک\u200cجا همان چیزی بود که این صفحه را کند و پرش\u200cدار می\u200cکرد، پس فقط همان صفحه\u200cای که می\u200cبینید واقعاً ساخته می\u200cشود.',
    'Costs quota: none. Ever.': 'مصرف سهمیه: هیچ. هرگز.',
    'AI Ideas · from research to a shoot list': 'ایده\u200cهای هوش مصنوعی · از تحقیق تا لیست ضبط',
    'Pick a keyword section, tick the videos whose format you want to borrow, and Create with AI turns them into five new ideas — each with a title, a hook line and a shooting outline you can actually film.': 'یک بخش کلیدواژه را انتخاب کنید، ویدیوهایی که فرمتشان را می\u200cخواهید الگو بگیرید تیک بزنید، و «ساخت با هوش مصنوعی» آن\u200cها را به پنج ایده\u200cی تازه تبدیل می\u200cکند — هر کدام با عنوان، جمله\u200cی قلاب و طرح فیلم\u200cبرداری قابل\u200cاجرا.',
    'Needs a Gemini API key in Settings. Uses no YouTube quota.': 'به کلید API جمینای در تنظیمات نیاز دارد. هیچ سهمیه\u200cی یوتیوبی مصرف نمی\u200cکند.',
    'Monetize Checker · is this channel earning?': 'بررسی مانیتایز · این کانال درآمد دارد؟',
    "Answers the question with a yes or a no, never a shrug. Features that only Partner Program channels can switch on — the Join button, a Store tab, Super Thanks, ad slots served on recent videos — are read live off YouTube's public pages. Finding one settles it outright.": 'به این سؤال با «بله» یا «نه» پاسخ می\u200cدهد، نه با «نمی\u200cدانم». امکاناتی که فقط کانال\u200cهای عضو برنامه\u200cی همکاری می\u200cتوانند روشن کنند — دکمه\u200cی Join، تب Store، سوپر تنکس، و اسلات\u200cهای تبلیغاتی سرو\u200cشده روی ویدیوهای اخیر — به\u200cصورت زنده از صفحات عمومی یوتیوب خوانده می\u200cشوند. پیدا شدن یکی از این\u200cها موضوع را قطعی می\u200cکند.',
    "When a channel has none of them public (which is a display choice, not a monetization one), the verdict is decided on its numbers against the real Partner Program bars and carries a certainty score, with the full checklist of what was and wasn't found shown underneath.": 'اگر هیچ\u200cکدام از این\u200cها عمومی نباشد (که یک انتخاب نمایشی است، نه نشانه\u200cی نبود درآمد)، حکم بر اساس اعداد خود کانال در برابر آستانه\u200cهای واقعی برنامه\u200cی همکاری صادر می\u200cشود و یک درصد قطعیت همراهش می\u200cآید؛ چک\u200cلیست کامل آنچه پیدا شد و آنچه پیدا نشد هم زیرش نمایش داده می\u200cشود.',
    "It also estimates RPM — what 1,000 views is actually worth to this channel — from its niche and its audience's market, and prices the revenue table off that instead of a single global CPM guess. RPM is net of YouTube's 45% cut; the CPM shown next to it is the advertiser's side, for reference.": 'همچنین RPM را تخمین می\u200cزند — اینکه هزار بازدید برای این کانال واقعاً چقدر ارزش دارد — بر اساس حوزه و بازار مخاطبش، و جدول درآمد را روی همان قیمت\u200cگذاری می\u200cکند نه یک CPM ثابت جهانی. RPM بعد از کسر ۴۵٪ سهم یوتیوب است؛ CPM کنارش، سمت آگهی\u200cدهنده است و فقط برای مقایسه.',
    'Costs quota: a few units per check.': 'مصرف سهمیه: چند واحد برای هر بررسی.',
    'History & Logs': 'تاریخچه و لاگ\u200cها',
    'History keeps every scrape and export you have run, with its row counts and file paths. Logs is the live console: colour-coded, searchable, and worth reading when a scrape stops early — the reason is always in there.': 'تاریخچه هر اسکرپ و خروجی\u200cای که گرفته\u200cاید را با تعداد ردیف\u200cها و مسیر فایل نگه می\u200cدارد. لاگ\u200cها کنسول زنده است: رنگ\u200cبندی\u200cشده، قابل جست\u200cوجو، و وقتی اسکرپی نیمه\u200cکاره متوقف می\u200cشود ارزش خواندن دارد — دلیلش همیشه همان\u200cجاست.',
    'Settings · keys and quota': 'تنظیمات · کلیدها و سهمیه',
    "Your YouTube Data API key and Gemini key live here, along with the daily quota ledger. The ledger is a local count of what this app has spent today so a long session can't quietly run you into YouTube's 10,000-unit daily cap.": 'کلید YouTube Data API و کلید جمینای شما اینجا هستند، همراه با دفتر سهمیه\u200cی روزانه. این دفتر شمارشی محلی از مصرف امروز برنامه است تا یک نشست طولانی، بی\u200cصدا شما را به سقف ۱۰٬۰۰۰ واحدی روزانه\u200cی یوتیوب نرساند.',
    "Language and theme are not on this page — they're in the quick-settings menu on the title bar, next to the minimize button, so they're reachable from anywhere in the app. Theme swaps live: the wipe you see is the new palette sweeping across the window, already fully applied inside the sweep — your open page, typed fields, results and console all survive it untouched. Changing language restarts the app.": 'زبان و پوسته در این صفحه نیستند — در منوی «تنظیمات سریع» روی نوار عنوان، کنار دکمه\u200cی کوچک\u200cکردن، قرار دارند تا از هر جای برنامه در دسترس باشند. پوسته زنده عوض می\u200cشود: موجی که می\u200cبینید همان پالت جدید است که روی پنجره کشیده می\u200cشود و درون موج کاملاً اعمال شده است — صفحه\u200cی باز، فیلدهای تایپ\u200cشده، نتایج و کنسول همه دست\u200cنخورده باقی می\u200cمانند. تغییر زبان برنامه را دوباره اجرا می\u200cکند.',
    'Getting the most out of it': 'بیشترین بهره را ببرید',
    'Search narrow, filter wide. One specific keyword plus generous filters beats a broad keyword you then have to fight — and since the pool is saved, widening the filters later is free.': 'باریک جست\u200cوجو کنید، باز فیلتر کنید. یک کلیدواژه\u200cی دقیق با فیلترهای دست\u200cودل\u200cباز، بهتر از یک کلیدواژه\u200cی کلی است که بعد باید با آن بجنگید — و چون داده ذخیره می\u200cشود، بازتر کردن فیلترها بعداً رایگان است.',
    'Trust the multiplier over the view count. 200k views on a 2M-sub channel is a quiet day; 200k on a 900-sub channel is a format you should study frame by frame.': 'به ضریب بیشتر از تعداد بازدید اعتماد کنید. ۲۰۰ هزار بازدید برای کانالی با ۲ میلیون مشترک یک روز معمولی است؛ ۲۰۰ هزار بازدید برای کانالی با ۹۰۰ مشترک، فرمتی است که باید فریم\u200cبه\u200cفریم مطالعه\u200cاش کنید.',
    'Treat every money figure here as a ballpark with its reasoning shown, not a number from YouTube. Watch hours, RPM and revenue are all modelled — the app tells you exactly what each estimate is built from so you can argue with it.': 'هر عدد مالی اینجا را یک تقریب با دلیل مشخص بدانید، نه عددی از خود یوتیوب. ساعت تماشا، RPM و درآمد همه مدل\u200cسازی\u200cشده\u200cاند — برنامه دقیقاً می\u200cگوید هر تخمین از چه ساخته شده تا بتوانید با آن بحث کنید.',
    'This channel is monetized.': 'این کانال مانیتایز است.',
    'This channel is not monetized.': 'این کانال مانیتایز نیست.',
    'Confirmed by a live signal': 'تأیید\u200cشده با سیگنال زنده',
    'Very likely': 'به\u200cاحتمال بسیار زیاد',
    'Balance of evidence': 'بر پایه\u200cی مجموع شواهد',
    'Estimate': 'تخمین',
    'CERTAINTY': 'قطعیت',
    'WHAT WAS CHECKED': 'چه چیزهایی بررسی شد',
    '{p}% certainty': '{p}٪ قطعیت',
    'Channel Memberships (the Join button) are switched on.': 'عضویت کانال (دکمه\u200cی Join) فعال است.',
    'No Join button — Channel Memberships are off, or not offered.': 'دکمه\u200cی Join نیست — عضویت کانال خاموش است یا ارائه نمی\u200cشود.',
    'A Store / merch shelf is switched on.': 'تب فروشگاه / قفسه\u200cی محصولات فعال است.',
    'No Store tab — no merch shelf on the channel.': 'تب فروشگاه نیست — قفسه\u200cی محصولی روی کانال وجود ندارد.',
    'Super Thanks (fan funding) is enabled on recent uploads.': 'سوپر تنکس (حمایت مالی هواداران) روی ویدیوهای اخیر فعال است.',
    'No Super Thanks button on the recent uploads checked.': 'دکمه\u200cی سوپر تنکس روی ویدیوهای اخیر بررسی\u200cشده پیدا نشد.',
    'YouTube served ad slots on {n} of {m} recent videos checked.': 'یوتیوب روی {n} از {m} ویدیوی اخیر بررسی\u200cشده، اسلات تبلیغ سرو کرد.',
    "No ad slots came back on the {m} recent videos checked — the logged-out player skips ads for its own reasons, so this alone doesn't mean the channel isn't monetized.": 'روی {m} ویدیوی اخیر بررسی\u200cشده اسلات تبلیغی برنگشت — پخش\u200cکننده در حالت خارج از حساب به دلایل خودش هم تبلیغ را رد می\u200cکند، پس این تنهایی به معنای نبودِ مانیتایز نیست.',
    'Creator-placed mid-roll ad breaks on {n} recent videos.': 'وقفه\u200cهای تبلیغ میان\u200cویدیویی چیده\u200cشده توسط سازنده روی {n} ویدیوی اخیر.',
    'No creator-placed mid-roll ad breaks found.': 'هیچ وقفه\u200cی تبلیغ میان\u200cویدیویی چیده\u200cشده توسط سازنده پیدا نشد.',
    '{n} subscribers — past the 1,000 needed for ads.': '{n} مشترک — بالاتر از ۱۰۰۰ مشترکِ لازم برای تبلیغات.',
    '{n} subscribers — still short of the 1,000 needed for ads.': '{n} مشترک — هنوز کمتر از ۱۰۰۰ مشترکِ لازم برای تبلیغات.',
    '{n} subscribers — the Partner Program needs 500 to apply, 1,000 for ads.': '{n} مشترک — برنامه\u200cی همکاری برای درخواست ۵۰۰ مشترک و برای تبلیغات ۱۰۰۰ مشترک می\u200cخواهد.',
    '~{n} public watch hours a year (estimated) — past the 4,000 bar.': 'حدود {n} ساعت تماشای عمومی در سال (تخمینی) — بالاتر از آستانه\u200cی ۴۰۰۰.',
    '~{n} public watch hours a year (estimated) — under the 4,000 bar.': 'حدود {n} ساعت تماشای عمومی در سال (تخمینی) — پایین\u200cتر از آستانه\u200cی ۴۰۰۰.',
    '~{n} Shorts views in the last 90 days — past the 10M that opens the Shorts route in.': 'حدود {n} بازدید شورتس در ۹۰ روز گذشته — بالاتر از ۱۰ میلیونی که مسیر شورتس را باز می\u200cکند.',
    '~{n} Shorts views in the last 90 days — short of the 10M that opens the Shorts route in.': 'حدود {n} بازدید شورتس در ۹۰ روز گذشته — کمتر از ۱۰ میلیونی که مسیر شورتس را باز می\u200cکند.',
    "Some of YouTube's pages wouldn't load for this check, so the verdict leans more on the numbers than on the page signals.": 'بعضی از صفحات یوتیوب برای این بررسی بارگذاری نشدند، پس حکم بیشتر بر اعداد تکیه دارد تا بر سیگنال\u200cهای صفحه.',
    '{n} monetization feature(s) that only Partner Program channels can switch on were found live on the channel.': '{n} قابلیت مانیتایز که فقط کانال\u200cهای عضو برنامه\u200cی همکاری می\u200cتوانند روشن کنند، به\u200cصورت زنده روی کانال پیدا شد.',
    'It is still under the 500-subscriber floor for applying to the Partner Program, so ad revenue is not possible yet.': 'کانال هنوز زیر کف ۵۰۰ مشترک برای درخواست به برنامه\u200cی همکاری است، پس درآمد تبلیغاتی فعلاً ممکن نیست.',
    'No public monetization feature is switched on, but this channel clears the Partner Program requirements and is publishing actively — the overwhelmingly likely case is that ads are running with memberships and merch simply left off.': 'هیچ قابلیت مانیتایز عمومی روشن نیست، اما این کانال شرایط برنامه\u200cی همکاری را دارد و فعالانه منتشر می\u200cکند — به\u200cاحتمال قاطع تبلیغات روی آن اجرا می\u200cشود و فقط عضویت و فروشگاه خاموش مانده\u200cاند.',
    'It meets the subscriber and watch-time bars and shows an active upload history; no opt-in feature (Join, Store, Super Thanks) is public, which is a display choice rather than a monetization one.': 'آستانه\u200cهای مشترک و زمان تماشا را رد کرده و تاریخ انتشار فعالی دارد؛ هیچ قابلیت اختیاری (Join، Store، سوپر تنکس) عمومی نیست که این یک انتخاب نمایشی است نه نشانه\u200cی نبود مانیتایز.',
    'No monetization feature is switched on, and {gap}.': 'هیچ قابلیت مانیتایزی روشن نیست، و {gap}.',
    'Nothing that requires the Partner Program is switched on, and {gap} — so ad revenue is very unlikely to be running.': 'هیچ\u200cچیزی که به برنامه\u200cی همکاری نیاز داشته باشد روشن نیست، و {gap} — پس اجرای درآمد تبلیغاتی بسیار بعید است.',
    'the channel is under 1,000 subscribers': 'کانال زیر ۱۰۰۰ مشترک است',
    'its 90-day Shorts views are short of 10M': 'بازدید شورتس ۹۰ روزه\u200cاش کمتر از ۱۰ میلیون است',
    'its estimated public watch hours are short of 4,000': 'ساعت تماشای عمومی تخمینی\u200cاش کمتر از ۴۰۰۰ است',
    "How this is decided: features that only Partner Program channels can switch on (Join, Store, Super Thanks, served ad slots) are read live off YouTube's own pages — finding one settles it. When none is public, the verdict comes from this channel's numbers against the real Partner Program bars, which is why it carries a certainty score. Not an official YouTube confirmation.": 'روش تصمیم\u200cگیری: قابلیت\u200cهایی که فقط کانال\u200cهای عضو برنامه\u200cی همکاری می\u200cتوانند روشن کنند (Join، Store، سوپر تنکس، اسلات تبلیغ سرو\u200cشده) به\u200cصورت زنده از صفحات خود یوتیوب خوانده می\u200cشوند — پیدا شدن یکی، موضوع را قطعی می\u200cکند. وقتی هیچ\u200cکدام عمومی نباشد، حکم از اعداد این کانال در برابر آستانه\u200cهای واقعی برنامه\u200cی همکاری می\u200cآید و به همین دلیل درصد قطعیت دارد. این تأیید رسمی یوتیوب نیست.',
    'Clears the Partner Program bars we can measure': 'آستانه\u200cهای قابل\u200cاندازه\u200cگیری برنامه\u200cی همکاری را رد می\u200cکند',
    'Below the 1,000-subscriber Partner Program threshold': 'زیر آستانه\u200cی ۱۰۰۰ مشترکِ برنامه\u200cی همکاری',
    'Subscribers are there; estimated public watch hours ({n}/yr) are short of 4,000': 'مشترک\u200cها کافی\u200cاند؛ ساعت تماشای عمومی تخمینی ({n} در سال) کمتر از ۴۰۰۰ است',
    'Subscribers are there; estimated 90-day Shorts views ({n}) are short of 10M': 'مشترک\u200cها کافی\u200cاند؛ بازدید شورتس ۹۰ روزه\u200cی تخمینی ({n}) کمتر از ۱۰ میلیون است',
    'Eligibility, not earnings: the Partner Program wants 1,000 subscribers plus 4,000 public watch hours in 12 months (or 10M Shorts views in 90 days), then a policy review. Watch hours are not published by any API, so the figure above is estimated from the views and lengths of recent uploads at ~45% average view duration — treat it as a ballpark, and the policy review as a coin this app cannot see.': 'شرایط پذیرش، نه درآمد: برنامه\u200cی همکاری ۱۰۰۰ مشترک به\u200cعلاوه ۴۰۰۰ ساعت تماشای عمومی در ۱۲ ماه (یا ۱۰ میلیون بازدید شورتس در ۹۰ روز) و سپس بررسی خط\u200cمشی می\u200cخواهد. ساعت تماشا در هیچ API عمومی منتشر نمی\u200cشود، پس عدد بالا از بازدید و مدت ویدیوهای اخیر با میانگین تماشای حدود ۴۵٪ تخمین زده شده — آن را تقریبی بدانید و بررسی خط\u200cمشی چیزی است که این برنامه نمی\u200cتواند ببیند.',
    'RPM · What 1,000 views is worth here': 'RPM · هزار بازدید اینجا چقدر می\u200cارزد',
    'RPM · typical': 'RPM · معمول',
    'RPM · range': 'RPM · بازه',
    'CPM · advertiser side': 'CPM · سمت آگهی\u200cدهنده',
    'per 1,000 views, in your pocket': 'به\u200cازای هر ۱۰۰۰ بازدید، در جیب شما',
    'weak month to strong month': 'از ماه ضعیف تا ماه قوی',
    'what the ad buyer pays': 'چیزی که خریدار تبلیغ می\u200cپردازد',
    'Niche read': 'حوزه\u200cی تشخیص\u200cداده\u200cشده',
    'Audience market': 'بازار مخاطب',
    'Creator share': 'سهم سازنده',
    '55% of ad revenue — RPM is already net of it': '۵۵٪ از درآمد تبلیغات — RPM از قبل خالص شده است',
    '45% of the Shorts pool — RPM is already net of it': '۴۵٪ از استخر درآمد شورتس — RPM از قبل خالص شده است',
    "{c} · {p}% of a US audience's value": '{c} · {p}٪ ارزش مخاطب آمریکایی',
    'Shorts ad pool': 'استخر تبلیغات شورتس',
    'Long-form ads': 'تبلیغات ویدیوی بلند',
    "RPM is per 1,000 VIEWS and already has YouTube's 45% cut and the views that never saw an ad taken out of it — it is the figure that matches what shows up in a creator's Studio. CPM is the advertiser's price for 1,000 impressions, shown for reference only. Both are modelled from this channel's niche and audience market; a channel's real RPM also moves with season, video length and how many mid-rolls it runs.": 'RPM به\u200cازای هر ۱۰۰۰ بازدید است و ۴۵٪ سهم یوتیوب و بازدیدهایی که هیچ تبلیغی ندیده\u200cاند از آن کسر شده — همان عددی که با آمار استودیوی سازنده می\u200cخواند. CPM قیمت آگهی\u200cدهنده برای ۱۰۰۰ نمایش است و فقط برای مقایسه آمده. هر دو از حوزه و بازار مخاطب این کانال مدل\u200cسازی شده\u200cاند؛ RPM واقعی با فصل، طول ویدیو و تعداد تبلیغ میان\u200cویدیویی هم تغییر می\u200cکند.',
    "Priced at this channel's estimated RPM of {low}–{high} per 1,000 views ({basis}, {niche}).": 'قیمت\u200cگذاری بر پایه\u200cی RPM تخمینی این کانال، {low} تا {high} به\u200cازای هر ۱۰۰۰ بازدید ({basis}، {niche}).',
    "Assumptions: earnings = estimated views x the RPM band above. View velocity comes from this channel's most recent uploads, so a channel that has just posted a hit will read high and one on a break will read low. Sponsorships, memberships and merch are NOT included — this is ad revenue only, and an estimate, not official YouTube data.": 'فرض\u200cها: درآمد = بازدید تخمینی × بازه\u200cی RPM بالا. سرعت بازدید از آخرین ویدیوهای کانال گرفته می\u200cشود، پس کانالی که همین حالا یک ویدیوی پرطرفدار گذاشته بالا خوانده می\u200cشود و کانالی که در وقفه است پایین. اسپانسر، عضویت و فروش محصول در این عدد نیست — این فقط درآمد تبلیغات است، و یک تخمین، نه داده\u200cی رسمی یوتیوب.',
    # Niche labels — MUST match app.core.rpm.NICHE_RPM_TABLE verbatim. These had
    # drifted (the table says "Tech · Software · AI" / "Education · How-to ·
    # History" / "Health · Beauty · Fitness" but the keys here were the older
    # wording), so the label fell through to English in the Persian UI. The QML
    # page now runs the label through I18n.tr(), so a mismatch shows up as raw
    # English — keep these in step with the table.
    'Finance · Investing · Crypto': 'مالی · سرمایه\u200cگذاری · کریپتو',
    'Business · Marketing · SaaS': 'کسب\u200cوکار · مارکتینگ · نرم\u200cافزار',
    'Real Estate': 'املاک',
    'Tech · Software · AI': 'تکنولوژی · نرم\u200cافزار · هوش مصنوعی',
    'Education · How-to · History': 'آموزش · راهنما · تاریخ',
    'News · Politics · Commentary': 'اخبار · سیاست · تحلیل',
    'Health · Beauty · Fitness': 'سلامت · زیبایی · تناسب اندام',
    'Beauty · Fashion · Lifestyle': 'زیبایی · مد · سبک زندگی',
    'Automotive · Lifestyle': 'خودرو · سبک زندگی',
    'Travel · Places': 'سفر · مکان\u200cها',
    'Food · Cooking': 'غذا · آشپزی',
    'Animal · Pet Stories': 'حیوانات · داستان\u200cهای حیوان خانگی',
    'Anime · Cinema · Analysis': 'انیمه · سینما · تحلیل',
    'Gaming': 'گیمینگ',
    'Entertainment · Reaction · Comedy': 'سرگرمی · واکنش · کمدی',
    'Music': 'موسیقی',
    'Kids · Family (COPPA)': 'کودک · خانواده (COPPA)',
    'General Audience': 'مخاطب عمومی',
    'Page {p} of {t}  ·  showing {a}–{b} of {n}': 'صفحه\u200cی {p} از {t}  ·  نمایش {a}–{b} از {n}',
    'Previous page': 'صفحه\u200cی قبل',
    'Next page': 'صفحه\u200cی بعد',
    'Showing the first {n}, six rows to a page — narrow the filters to reach the rest.': 'نمایش {n} مورد اول، شش ردیف در هر صفحه — برای رسیدن به بقیه فیلترها را باریک\u200cتر کنید.',
    'Gemini API key is missing.': 'کلید API جمینای وارد نشده است.',
    'Gemini API error ({code}): {msg}': 'خطای API جمینای ({code}): {msg}',
    'Network error contacting Gemini: {reason}': 'خطای شبکه هنگام ارتباط با جمینای: {reason}',
    'Gemini declined to respond ({reason}).': 'جمینای از پاسخ\u200cدادن خودداری کرد ({reason}).',
    'Gemini returned an empty response.': 'جمینای پاسخ خالی برگرداند.',
    'Idea Analysis': 'تحلیل ایده',
    'Showing previously generated analysis.': 'نمایش تحلیل تولیدشده\u200cی قبلی.',
    'Regenerate Analysis': 'تولید مجدد تحلیل',
    'Untitled': 'بدون عنوان',
    '{n} views': '{n} بازدید',
    '{r}x outlier': '{r}x پرت (آوتلایر)',
    'Shorts': 'شورتس',
    'Long-form': 'بلند (لانگ)',
    'Generate AI Analysis': 'تولید تحلیل هوش مصنوعی',
    'Powered by Gemini · results are AI-generated suggestions, always sanity-check before publishing.': 'قدرت\u200cگرفته از جمینای · نتایج پیشنهادهایی مبتنی بر هوش مصنوعی هستند، پیش از انتشار حتماً بررسی\u200cشان کنید.',
    'Click "Generate AI Analysis" to have Gemini explain why this video is outperforming and suggest angles, titles and hooks you could use.': 'روی «تولید تحلیل هوش مصنوعی» بزنید تا جمینای دلیل موفقیت این ویدیو را توضیح دهد و زاویه، عنوان و قلاب (هوک) پیشنهاد بدهد.',
    'Close': 'بستن',
    'Thinking …': 'در حال فکر کردن …',
    'Contacting Gemini …': 'در حال ارتباط با جمینای …',
    '✓ Analysis generated by Gemini.': '✓ تحلیل توسط جمینای تولید شد.',
    'Youtube Scrapper  ·  Core Control': 'یوتیوب اسکرپر  ·  کنترل مرکزی',
    'Core Control': 'کنترل مرکزی',
    'Start Scrape': 'شروع استخراج',
    'Scrapper': 'Scrapper',
    'Click to type a custom value (0–5000)': 'برای وارد کردن عدد دلخواه کلیک کنید (۰ تا ۵۰۰۰)',
    'Logs': 'گزارش\u200cها',
    'History': 'تاریخچه',
    'Delete all': 'حذف همه',
    'Delete all exports': 'حذف همه‌ی خروجی‌ها',
    'Delete all {n} exports shown here? This cannot be undone.':
        'همه‌ی {n} خروجی نمایش داده‌شده حذف شود؟ این کار قابل بازگشت نیست.',
    '{n} file(s) could not be deleted.': '{n} فایل حذف نشد.',
    'Previous page': 'صفحه‌ی قبل',
    'Next page': 'صفحه‌ی بعد',
    'Page {p} of {t}  ·  showing {a}\u2013{b} of {n}':
        'صفحه {p} از {t}  ·  نمایش {a} تا {b} از {n}',
    'Select': 'انتخاب',
    'Deselect All': 'لغو انتخاب همه',
    'Delete ({n})': 'حذف ({n})',
    'Delete selected exports': 'حذف خروجی‌های انتخاب‌شده',
    'Delete {n} selected export(s)? This cannot be undone.':
        '{n} خروجی انتخاب‌شده حذف شود؟ این کار قابل بازگشت نیست.',
    'Monetize Checker': 'بررسی مانیتایز',
    'Idea Finder': 'یابنده\u200cی ایده',
    'Ideas Board': 'برد ایده\u200cها',
    'Settings': 'تنظیمات',
    'Docs': 'مستندات',
    'Enter a channel URL and API key, pick your filters, and press Start Scrape. Watch live progress on the Logs page.': 'آدرس کانال و کلید API را وارد کنید، فیلترها را انتخاب کنید و روی شروع استخراج بزنید. پیشرفت زنده را در صفحه\u200cی گزارش\u200cها ببینید.',
    'Support': 'پشتیبانی',
    'If a scrape fails, double-check your API key quota and internet connection first.': 'اگر استخراج با خطا مواجه شد، ابتدا سهمیه\u200cی کلید API و اتصال اینترنت خود را بررسی کنید.',
    'Notifications': 'اعلان\u200cها',
    'No new notifications.': 'اعلان جدیدی وجود ندارد.',
    "You're all caught up": 'همه چیز به\u200cروز است',
    'New scrapes, monetization checks and AI ideas will show up here.': 'استخراج\u200cهای جدید، بررسی\u200cهای مانیتایز و ایده\u200cهای هوش مصنوعی اینجا نمایش داده می\u200cشوند.',
    'New Extraction Task': 'وظیفه\u200cی استخراج جدید',
    'Configure target parameters for YouTube metadata scraping. Set filters, quantity limits, and initialize the worker node.': 'پارامترهای هدف برای استخراج متادیتای یوتیوب را تنظیم کنید. فیلترها و محدودیت تعداد را مشخص کرده و گره\u200cی کاری را راه\u200cاندازی کنید.',
    'Target URL or Channel ID': 'آدرس هدف یا شناسه\u200cی کانال',
    'Search Query (Optional)': 'عبارت جستجو (اختیاری)',
    "e.g. 'python tutorial'": 'مثلاً «آموزش پایتون»',
    'Max Videos to Scrape': 'حداکثر ویدیوهای قابل استخراج',
    'Sort & Filter': 'مرتب\u200cسازی و فیلتر',
    'Most Recent': 'جدیدترین',
    'Most Popular': 'محبوب\u200cترین',
    'Most Relevant': 'مرتبط\u200cترین',
    'Output Configuration': 'تنظیمات خروجی',
    'Custom Filename': 'نام دلخواه فایل',
    'Save Location': 'محل ذخیره\u200cسازی',
    'Click Browse to select output folder ...': 'برای انتخاب پوشه\u200cی خروجی روی مرور بزنید ...',
    'System Ready': 'سیستم آماده است',
    'Initiate Scrape sequence': 'آغاز فرایند استخراج',
    'EMERGENCY STOP': 'توقف اضطراری',
    'System Archive': 'بایگانی سیستم',
    'Review or open past extraction exports saved in your selected output folder.': 'خروجی\u200cهای استخراج\u200cشده\u200cی قبلی، ذخیره\u200cشده در پوشه\u200cی خروجی، را مرور یا باز کنید.',
    'All Runs': 'همه\u200cی اجراها',
    'Completed': 'تکمیل\u200cشده',
    'Partial': 'ناقص',
    'System Configuration': 'پیکربندی سیستم',
    'Manage extraction protocols, API credentials, and application preferences.': 'پروتکل\u200cهای استخراج، اعتبارنامه\u200cهای API و ترجیحات برنامه را مدیریت کنید.',
    'Language': 'زبان',
    "Choose the app's display language. Switching languages restarts the app.": 'زبان نمایش برنامه را انتخاب کنید. تغییر زبان باعث راه\u200cاندازی مجدد برنامه می\u200cشود.',
    'API Management': 'مدیریت API',
    'GOOGLE YOUTUBE DATA API KEY': 'کلید API دیتای یوتیوب گوگل',
    'Validate Key': 'اعتبارسنجی کلید',
    'Not validated yet this session.': 'در این نشست هنوز اعتبارسنجی نشده است.',
    'AI Analysis (Gemini)': 'تحلیل هوش مصنوعی (جمینای)',
    'Used by Monetize Checker, Idea Finder and Idea Analysis to generate AI insights, outlier explanations, title ideas and hooks.': 'برای تولید بینش\u200cهای هوش مصنوعی، توضیح ویدیوهای پرت، پیشنهاد عنوان و قلاب در بررسی مانیتایز، یابنده\u200cی ایده و تحلیل ایده استفاده می\u200cشود.',
    'GEMINI API KEY': 'کلید API جمینای',
    'MODEL': 'مدل',
    'Extraction Preferences': 'ترجیحات استخراج',
    'AUTO-SAVE FREQUENCY': 'فرکانس ذخیره\u200cی خودکار',
    'Every 100 records': 'هر ۱۰۰ رکورد',
    'Every 500 records': 'هر ۵۰۰ رکورد',
    'Every 1000 records': 'هر ۱۰۰۰ رکورد',
    'At end of job only': 'فقط در پایان کار',
    'DEFAULT EXPORT FORMAT': 'قالب پیش\u200cفرض خروجی',
    'CSV (Comma Separated)': 'CSV (جدا\u200cشده با کاما)',
    'JSON Lines': 'JSON Lines',
    'XLSX (Excel)': 'XLSX (اکسل)',
    'SQLite Database': 'پایگاه\u200cداده\u200cی SQLite',
    'CONCURRENT EXTRACTION THREADS': 'نخ\u200cهای همزمان استخراج',
    'Sequential': 'ترتیبی',
    'Higher thread counts speed up scraping but may increase the likelihood of API rate limiting.': 'تعداد نخ بیشتر استخراج را سریع\u200cتر می\u200cکند، اما احتمال محدودشدن نرخ درخواست API را نیز افزایش می\u200cدهد.',
    'Save Configuration': 'ذخیره\u200cی پیکربندی',
    'Monetization Checker': 'بررسی\u200cکننده\u200cی مانیتایز',
    "Check any channel's monetization signals, estimated Partner Program eligibility, audience size and projected ad revenue.": 'سیگنال\u200cهای مانیتایز، واجدشرایط\u200cبودن تخمینی برای برنامه\u200cی همکاری، حجم مخاطب و درآمد تبلیغاتی پیش\u200cبینی\u200cشده\u200cی هر کانالی را بررسی کنید.',
    'Channel URL, @handle or name': 'آدرس کانال، @هندل یا نام',
    'Check Monetization': 'بررسی مانیتایز',
    'Content Format': 'قالب محتوا',
    'Long-form videos and Shorts are checked for different signals — choose how this channel primarily grows, or let it auto-detect from its recent uploads.': 'ویدیوهای بلند و شورتس با سیگنال\u200cهای متفاوتی بررسی می\u200cشوند — مشخص کنید این کانال عمدتاً از چه طریق رشد می\u200cکند، یا اجازه دهید بر اساس آپلودهای اخیر به\u200cطور خودکار تشخیص داده شود.',
    'Auto-detect': 'تشخیص خودکار',
    'Paste a channel URL, @handle, or channel name and press Check.': 'آدرس کانال، @هندل یا نام کانال را وارد کرده و روی بررسی بزنید.',
    'Idea Finder · Outlier Analytics': 'یابنده\u200cی ایده · تحلیل ویدیوهای پرت',
    "Scan a channel's recent uploads to find videos that are massively outperforming that channel's normal average — then save the best ones to your Ideas Board.": 'آپلودهای اخیر یک کانال را اسکن کنید تا ویدیوهایی را بیابید که بسیار فراتر از میانگین معمول آن کانال عمل کرده\u200cاند — سپس بهترین\u200cها را در برد ایده\u200cهای خود ذخیره کنید.',
    'Find Outliers': 'یافتن ویدیوهای پرت',
    'Format': 'قالب',
    'All Formats': 'همه\u200cی قالب\u200cها',
    'All': 'همه',
    'Timeframe': 'بازه\u200cی زمانی',
    'Last 90 Days': '۹۰ روز اخیر',
    'Last 30 Days': '۳۰ روز اخیر',
    'Last 7 Days': '۷ روز اخیر',
    'All Time': 'کل زمان',
    'Videos to Scan': 'تعداد ویدیو برای اسکن',
    'Last 25': '۲۵ مورد آخر',
    'Last 50': '۵۰ مورد آخر',
    'Last 100': '۱۰۰ مورد آخر',
    'Paste a channel and press Find Outliers.': 'کانالی وارد کرده و روی یافتن ویدیوهای پرت بزنید.',
    'Videos Scanned': 'ویدیوهای اسکن\u200cشده',
    'Outliers Found (≥2x)': 'ویدیوهای پرت یافت\u200cشده (≥۲x)',
    'Avg Outlier Ratio': 'میانگین نسبت پرت\u200cبودن',
    'Outlier Videos': 'ویدیوهای پرت',
    'Video Details': 'جزئیات ویدیو',
    'Outlier Ratio': 'نسبت پرت\u200cبودن',
    'Velocity (v/h)': 'سرعت (بازدید/ساعت)',
    'Published': 'زمان انتشار',
    'Action': 'عملیات',
    'Discovered Ideas Board': 'برد ایده\u200cهای کشف\u200cشده',
    'Ideas you save from the Idea Finder land here. Move them across stages as you turn them into videos.': 'ایده\u200cهایی که از یابنده\u200cی ایده ذخیره می\u200cکنید، اینجا قرار می\u200cگیرند. هنگام تبدیل آن\u200cها به ویدیو، بین مراحل جابه\u200cجایشان کنید.',
    'views': 'بازدید',
    'Analyze': 'تحلیل',
    'Select Save Folder': 'انتخاب پوشه\u200cی ذخیره\u200cسازی',
    'Balanced': 'متعادل',
    'High Performance': 'کارایی بالا',
    'Settings Saved': 'تنظیمات ذخیره شد',
    'Your extraction preferences have been updated.': 'ترجیحات استخراج شما به\u200cروزرسانی شد.',
    'Enter a key first.': 'ابتدا یک کلید وارد کنید.',
    'Validating …': 'در حال اعتبارسنجی …',
    'Key is valid.': 'کلید معتبر است.',
    'Invalid key or quota issue ({code}).': 'کلید نامعتبر یا مشکل سهمیه ({code}).',
    'Validation failed: {err}': 'اعتبارسنجی ناموفق بود: {err}',
    '✓  {msg}   Last validated: Today at {time}': '✓  {msg}   آخرین اعتبارسنجی: امروز ساعت {time}',
    'Validate this key': 'اعتبارسنجی این کلید',
    'Test / Validate': 'تست / اعتبارسنجی',
    'Not checked yet this session.': 'در این نشست هنوز بررسی نشده است.',
    'Enter a base URL first.': 'ابتدا یک آدرس (URL) پایه وارد کنید.',
    'That doesn\'t look like a valid URL — it needs to start with http:// or https://.':
        'این یک آدرس معتبر به نظر نمی\u200cرسد — باید با http:// یا https:// شروع شود.',
    'Enter an API key first.': 'ابتدا یک کلید API وارد کنید.',
    'Checking base URL …': 'در حال بررسی آدرس پایه …',
    'Base URL OK — checking API key …': 'آدرس پایه تأیید شد — در حال بررسی کلید API …',
    'Base URL is not reachable: {reason}': 'آدرس پایه در دسترس نیست: {reason}',
    'Base URL check failed: {err}': 'بررسی آدرس پایه ناموفق بود: {err}',
    'Key is valid and working.': 'کلید معتبر است و کار می\u200cکند.',
    'PROXY (optional — e.g. http://127.0.0.1:10809, your VPN/v2ray client\'s local HTTP port)':
        'پروکسی (اختیاری — مثلاً http://127.0.0.1:10809، پورت HTTP محلی وی\u200cپی\u200cان/v2ray شما)',
    'Custom/aggregator endpoints need an exact model id (e.g. "openai/gpt-4o-mini" on OpenRouter) — fill in the MODEL field first.':
        'اندپوینت\u200cهای Custom/aggregator به یک شناسه\u200cی دقیق مدل نیاز دارند (مثلاً "openai/gpt-4o-mini" در OpenRouter) — ابتدا فیلد MODEL را پر کنید.',
    'Proxy address looks wrong — it needs to be an http:// URL, e.g. http://127.0.0.1:10809 (your VPN/v2ray client\'s local HTTP port, not its SOCKS port).':
        'آدرس پروکسی نادرست به نظر می\u200cرسد — باید یک آدرس http:// باشد، مثلاً http://127.0.0.1:10809 (پورت HTTP محلی وی\u200cپی\u200cان/v2ray شما، نه پورت SOCKS آن).',
    ' (check your Proxy field — this could be a filtered/blocked connection.)':
        ' (فیلد پروکسی را بررسی کنید — ممکن است این یک اتصال فیلترشده/مسدود باشد.)',
    '{provider}: no model name is set. Aggregator/custom endpoints need an exact model id (e.g. "openai/gpt-4o-mini" on OpenRouter) — fill in the MODEL field before validating.':
        '{provider}: نام مدلی تنظیم نشده است. اندپوینت\u200cهای aggregator/custom به یک شناسه\u200cی دقیق مدل نیاز دارند (مثلاً "openai/gpt-4o-mini" در OpenRouter) — پیش از اعتبارسنجی فیلد MODEL را پر کنید.',
    '✓  {msg}   Checked: Today at {time}': '✓  {msg}   بررسی شد: امروز ساعت {time}',
    '✓  {msg}   {time}': '✓  {msg}   {time}',
    '{r} quota units available today.': '{r} واحد سهمیه امروز در دسترس است.',
    '{r} / {c} quota units left today ({u} already spent).': '{r} از {c} واحد سهمیه امروز باقی مانده ({u} واحد قبلاً مصرف شده).',
    'No quota left': 'سهمیه\u200cای باقی نمانده',
    "Every configured YouTube API key has already used up its daily quota.\n\nAdd a new key in Settings, or wait — quota resets at {t} your time.": 'همه\u200cی کلیدهای API یوتیوب پیکربندی\u200cشده سهمیه\u200cی روزانه\u200cشان را مصرف کرده\u200cاند.\n\nیک کلید جدید در تنظیمات اضافه کنید، یا صبر کنید — سهمیه ساعت {t} به وقت شما بازنشانی می\u200cشود.',
    'Add a new key': 'افزودن کلید جدید',
    "I'll wait": 'صبر می\u200cکنم',
    "Progress was saved to the checkpoint — resets at {t} your time; start the same scrape after that and choose Resume.": 'پیشرفت کار در نقطه\u200cی بازرسی ذخیره شد — ساعت {t} به وقت شما بازنشانی می\u200cشود؛ پس از آن همین استخراج را دوباره شروع کنید و «ادامه» را انتخاب کنید.',
    "Every configured YouTube API key has used up its daily quota.\n\nEverything scraped so far ({n} videos) was saved.\nQuota resets at {t} your time — add a fresh key in Settings to keep going now, or run the same scrape again after that and choose Resume to continue from here.\n\nTip: 'Most Recent' order without a search query uses far less quota than Popular/Relevant.": 'همه\u200cی کلیدهای API یوتیوب پیکربندی\u200cشده سهمیه\u200cی روزانه\u200cشان را مصرف کرده\u200cاند.\n\nهر آنچه تاکنون استخراج شده ({n} ویدیو) ذخیره شد.\nسهمیه ساعت {t} به وقت شما بازنشانی می\u200cشود — برای ادامه\u200cی همین حالا یک کلید تازه در تنظیمات اضافه کنید، یا پس از آن همین استخراج را دوباره اجرا کنید و «ادامه» را انتخاب کنید.\n\nنکته: ترتیب «جدیدترین» بدون عبارت جستجو سهمیه\u200cی بسیار کمتری نسبت به محبوب\u200cترین/مرتبط\u200cترین مصرف می\u200cکند.',
    'Warning': 'هشدار',
    'Scraping is already running!': 'استخراج هم\u200cاکنون در حال اجراست!',
    'Missing Field': 'فیلد ناقص',
    'Please enter your YouTube API Key in Settings.': 'لطفاً کلید API یوتیوب خود را در تنظیمات وارد کنید.',
    'Please enter a YouTube Channel URL.': 'لطفاً آدرس کانال یوتیوب را وارد کنید.',
    'Please select a Save Folder.': 'لطفاً یک پوشه\u200cی ذخیره\u200cسازی انتخاب کنید.',
    'Starting': 'در حال شروع',
    'Scraping in progress …': 'استخراج در حال انجام است …',
    'Stop requested — canceling operation …': 'درخواست توقف ثبت شد — در حال لغو عملیات …',
    'STOPPING …': 'در حال توقف …',
    'Idle': 'بی\u200cکار',
    'Scanning': 'در حال اسکن',
    'Complete': 'تکمیل\u200cشده',
    'Ready · Configure settings above and press Start.': 'آماده · تنظیمات بالا را انجام داده و روی شروع بزنید.',
    'Select a save folder on the Scrapper page to see extraction history here.': 'برای دیدن تاریخچه\u200cی استخراج، یک پوشه\u200cی ذخیره\u200cسازی در Scrapper انتخاب کنید.',
    'NO DATA FOUND — no exports match this filter yet.': 'داده\u200cای یافت نشد — هنوز خروجی\u200cای با این فیلتر مطابقت ندارد.',
    'PARTIAL': 'ناقص',
    'COMPLETE': 'کامل',
    'N/A': '—',
    'Size': 'حجم',
    'Rows': 'ردیف\u200cها',
    'Saved': 'زمان ذخیره',
    'Open Folder': 'باز کردن پوشه',
    'Could not open folder': 'پوشه باز نشد',
    'Analyze with AI': 'تحلیل با هوش مصنوعی',
    'Show Analysis': 'نمایش تحلیل',
    'AI Channel Analysis': 'تحلیل هوشمند کانال',
    'Analyzing your channel data with AI …': 'در حال تحلیل داده‌های کانال با هوش مصنوعی …',
    'This can take a minute or two on larger channels.': 'در کانال‌های بزرگ‌تر ممکن است یکی دو دقیقه طول بکشد.',
    'Contacting {provider} …': 'در حال ارتباط با {provider} …',
    '✓ Analysis generated · {when}': '✓ تحلیل تولید شد · {when}',
    '✓ Analysis generated.': '✓ تحلیل تولید شد.',
    'Analysis failed.': 'تحلیل ناموفق بود.',
    'Try Again': 'تلاش دوباره',
    'Regenerate Analysis': 'تولید دوباره تحلیل',
    'Copy': 'کپی',
    'Copied to clipboard.': 'در کلیپ‌بورد کپی شد.',
    'Next Video Ideas': 'ایده‌های ویدیوی بعدی',
    'Idea {n}': 'ایده {n}',
    'Title: {t}': 'عنوان: {t}',
    'Hook: {h}': 'قلاب: {h}',
    "Couldn't read any rows from this export file.": 'هیچ ردیفی از این فایل خروجی خوانده نشد.',
    "This export doesn't have enough data to analyze.": 'این خروجی داده‌ی کافی برای تحلیل ندارد.',
    'No analysis text was returned.': 'متن تحلیلی برگردانده نشد.',
    'Quick Analysis': 'تحلیل سریع',
    'Show Quick Analysis': 'نمایش تحلیل سریع',
    'Deep Analysis': 'تحلیل عمیق',
    'Show Deep Report': 'نمایش گزارش عمیق',
    'Deep AI Report': 'گزارش عمیق هوش مصنوعی',
    'Building a deep, data-grounded report…': 'در حال ساخت یک گزارش عمیق و داده‌محور…',
    'This runs a much heavier analysis and can take a few minutes.': 'این یک تحلیل بسیار سنگین‌تر است و ممکن است چند دقیقه طول بکشد.',
    'Deep report ready': 'گزارش عمیق آماده شد',
    'Opened in your browser. From there you can print it or save it as PDF.': 'در مرورگر شما باز شد. از همان‌جا می‌توانید آن را چاپ یا به‌صورت PDF ذخیره کنید.',
    'Open Report': 'باز کردن گزارش',
    'Copy File Path': 'کپی مسیر فایل',
    'File path copied.': 'مسیر فایل کپی شد.',
    'Deep report failed.': 'تولید گزارش عمیق ناموفق بود.',
    "This export doesn't have enough data for a deep report.": 'این خروجی داده‌ای کافی برای گزارش عمیق ندارد.',
    'No deep report has been generated for this export yet.': 'هنوز گزارش عمیقی برای این خروجی ساخته نشده است.',
    'Untitled': 'بدون عنوان',
    'Delete export': 'حذف خروجی',
    'Delete {name}? This cannot be undone.': '{name} حذف شود؟ این عمل قابل بازگشت نیست.',
    'Delete failed': 'حذف ناموفق بود',
    'Delete': 'حذف',
    'Cancel': 'لغو',
    'NO DATA FOUND': 'داده\u200cای یافت نشد',
    'Enter a channel URL, @handle or name first.': 'ابتدا آدرس کانال، @هندل یا نام را وارد کنید.',
    'Checking …': 'در حال بررسی …',
    'Resolving channel …': 'در حال یافتن کانال …',
    'Fewer than 500 subscribers — below the minimum needed to even apply to the YouTube Partner Program.': 'کمتر از ۵۰۰ مشترک — پایین\u200cتر از حداقل لازم برای حتی درخواست عضویت در برنامه\u200cی همکاری یوتیوب.',
    'Channel Memberships (Join button) detected on the channel page.': 'دکمه\u200cی عضویت کانال (Join) در صفحه\u200cی کانال شناسایی شد.',
    'Merch / Shopping shelf detected on the channel page.': 'قفسه\u200cی محصولات/فروشگاه در صفحه\u200cی کانال شناسایی شد.',
    "Couldn't load the channel page to check for memberships or a merch shelf (network issue, or YouTube blocked the request).": 'امکان بارگذاری صفحه\u200cی کانال برای بررسی عضویت یا قفسه\u200cی فروشگاه نبود (مشکل شبکه یا مسدودشدن درخواست توسط یوتیوب).',
    'Super Thanks (fan funding) detected on a recent video.': 'قابلیت Super Thanks (حمایت مالی هواداران) در یک ویدیوی اخیر شناسایی شد.',
    'Creator-configured mid-roll ad breaks detected on multiple recent videos.': 'تبلیغات میان\u200cویدیویی تنظیم\u200cشده توسط سازنده در چند ویدیوی اخیر شناسایی شد.',
    "Couldn't load recent video pages to check for Super Thanks or ad placements (network issue, or YouTube blocked the request).": 'امکان بارگذاری صفحات ویدیوهای اخیر برای بررسی Super Thanks یا جایگاه تبلیغات نبود (مشکل شبکه یا مسدودشدن درخواست توسط یوتیوب).',
    'No direct fan-funding signal found on recent Shorts, but the channel is over 1,000 subscribers — Fan Funding may simply be turned off while it still earns from the Shorts ad pool.': 'هیچ سیگنال مستقیم حمایت مالی هواداران در شورتس\u200cهای اخیر یافت نشد، اما کانال بیش از ۱۰۰۰ مشترک دارد — ممکن است حمایت مالی هواداران صرفاً غیرفعال باشد در حالی\u200cکه کانال از استخر تبلیغاتی شورتس درآمد کسب می\u200cکند.',
    'No direct monetization signal found, but the channel is over 1,000 subscribers.': 'سیگنال مستقیمی از مانیتایز یافت نشد، اما کانال بیش از ۱۰۰۰ مشترک دارد.',
    'No monetization signals found, and the channel is under the 1,000-subscriber Partner Program threshold.': 'هیچ سیگنال مانیتایزی یافت نشد و کانال زیر آستانه\u200cی ۱۰۰۰ مشترکِ برنامه\u200cی همکاری است.',
    'Could not resolve that channel. Try pasting the full channel URL.': 'امکان یافتن این کانال نبود. آدرس کامل کانال را وارد کنید.',
    'Channel not found.': 'کانال یافت نشد.',
    'Something went wrong.': 'مشکلی پیش آمد.',
    '✓ Loaded data for {name}': '✓ داده\u200cهای {name} بارگذاری شد',
    'No description.': 'توضیحی موجود نیست.',
    'Country: {c}': 'کشور: {c}',
    'Joined: {d}': 'تاریخ عضویت: {d}',
    'Monetized': 'مانیتایز شده',
    'Not Monetized': 'مانیتایز نشده',
    'Uncertain': 'نامشخص',
    'High confidence': 'اطمینان بالا',
    'Verified signal': 'سیگنال تأییدشده',
    'High probability': 'احتمال بالا',
    'Medium confidence': 'اطمینان متوسط',
    'Long-form path': 'مسیر ویدیوی بلند',
    'Shorts path': 'مسیر شورتس',
    'Auto-detected': 'تشخیص خودکار',
    'Manually selected': 'انتخاب دستی',
    "Based on public signals scraped from YouTube's own pages (memberships, merch shelf, Super Thanks, mid-roll ad breaks). YouTube can change its page layout at any time, so treat this as a strong estimate, not an official confirmation.": 'بر اساس سیگنال\u200cهای عمومی استخراج\u200cشده از صفحات خود یوتیوب (عضویت، قفسه\u200cی فروشگاه، Super Thanks، تبلیغات میان\u200cویدیویی). یوتیوب می\u200cتواند هر زمان چیدمان صفحاتش را تغییر دهد، پس این نتیجه را یک تخمین قوی بدانید، نه تأیید رسمی.',
    'Hidden': 'پنهان',
    'Subscribers': 'مشترکین',
    'Total Views': 'کل بازدیدها',
    'Total Videos': 'کل ویدیوها',
    'Joined': 'تاریخ عضویت',
    'Meets the typical subscriber threshold for the YouTube Partner Program': 'آستانه\u200cی معمول مشترکین برای برنامه\u200cی همکاری یوتیوب را دارد',
    'Below the typical 1,000-subscriber Partner Program threshold': 'زیر آستانه\u200cی معمول ۱۰۰۰ مشترکِ برنامه\u200cی همکاری',
    'Estimate only — actual YouTube Partner Program approval also needs 4,000 public watch hours in 12 months (or 10M Shorts views in 90 days) plus a policy review, neither of which the public API exposes. This is not a confirmation of monetization status.': 'فقط یک تخمین — تأیید واقعی برنامه\u200cی همکاری یوتیوب همچنین به ۴۰۰۰ ساعت تماشای عمومی در ۱۲ ماه (یا ۱۰ میلیون بازدید شورتس در ۹۰ روز) به\u200cعلاوه بررسی خط\u200cمشی نیاز دارد که هیچ\u200cکدام از طریق API عمومی در دسترس نیست. این تأییدی برای وضعیت مانیتایز نیست.',
    'Estimated Revenue Matrix': 'ماتریس درآمد تخمینی',
    'Estimated Revenue': 'درآمد تخمینی',
    'Estimated Shorts Revenue': 'درآمد تخمینی شورتس',
    'Based on {views} views a month': 'بر اساس {views} بازدید در ماه',
    '{niche} channels typically earn around {amt} a month at these view numbers.': 'کانال\u200cهای {niche} با این تعداد بازدید معمولاً حدود {amt} در ماه درآمد دارند.',
    'Low estimate': 'تخمین پایین',
    'Average estimate': 'تخمین میانگین',
    'High estimate': 'تخمین بالا',
    'Conservative month': 'ماه محتاطانه',
    'Most likely outcome': 'محتمل\u200cترین حالت',
    'Strong month': 'ماه پرقدرت',
    'Refine RPM': 'تنظیم دقیق RPM',
    'Reset': 'بازنشانی',
    '{n} views': '{n} بازدید',
    "How to read this: the Average is your most likely month; Low and High are weak and strong ad months. Earnings = estimated views × RPM (net of YouTube's 45% cut). Views are estimated from this channel's recent uploads and lifetime average, not reported by YouTube. Drag the slider to price it against your own Studio RPM. Sponsorships, memberships and merch are NOT included — this is ad revenue only, and an estimate.": 'نحوه\u200cی خواندن: میانگین محتمل\u200cترین ماه شماست؛ پایین و بالا ماه\u200cهای ضعیف و قوی تبلیغاتی هستند. درآمد = بازدید تخمینی × RPM (خالص پس از کسر ۴۵٪ یوتیوب). بازدیدها از آپلودهای اخیر و میانگین کل عمر کانال تخمین زده شده\u200cاند، نه داده\u200cی رسمی یوتیوب. برای تطبیق با RPM استودیوی خودتان اسلایدر را بکشید. اسپانسر، عضویت و فروش محصول در این عدد نیست — این فقط درآمد تبلیغات و یک تخمین است.',
    'Priced at Shorts ad-pool rates (~$0.02–$0.40 / 1,000 views) — this channel\'s recent uploads are mostly Shorts.': 'با نرخ استخر تبلیغاتی شورتس (تقریباً ۰.۰۲ تا ۰.۴۰ دلار به ازای هر ۱۰۰۰ بازدید) محاسبه شده — چون آپلودهای اخیر این کانال بیشتر شورتس هستند.',
    'Priced at long-form ad rates (~$2–$10 / 1,000 views) — this channel\'s recent uploads are mostly long-form videos.': 'با نرخ تبلیغاتی ویدیوهای بلند (تقریباً ۲ تا ۱۰ دلار به ازای هر ۱۰۰۰ بازدید) محاسبه شده — چون آپلودهای اخیر این کانال بیشتر ویدیوی بلند هستند.',
    'Metric': 'معیار',
    'Daily': 'روزانه',
    'Monthly': 'ماهانه',
    'Yearly': 'سالانه',
    'Estimated Earnings (Low)': 'درآمد تخمینی (کم)',
    'Estimated Earnings (Mid)': 'درآمد تخمینی (متوسط)',
    'Estimated Earnings (High)': 'درآمد تخمینی (زیاد)',
    'Estimated Views': 'بازدید تخمینی',
    "Assumptions: CPM range $2–$10 per 1,000 views. View velocity is estimated from this channel's most recent uploads; actual earnings depend on niche, audience geography and advertiser demand. This is an estimate only, not official YouTube revenue data.": 'مفروضات: بازه\u200cی CPM بین ۲ تا ۱۰ دلار به\u200cازای هر ۱۰۰۰ بازدید. سرعت بازدید بر اساس آپلودهای اخیر این کانال تخمین زده شده است؛ درآمد واقعی به حوزه\u200cی محتوا، جغرافیای مخاطب و تقاضای تبلیغ\u200cدهندگان بستگی دارد. این فقط یک تخمین است، نه داده\u200cی رسمی درآمد یوتیوب.',
    'AI Channel Insight': 'بینش هوش مصنوعی درباره\u200cی کانال',
    'Generate AI Insight': 'تولید بینش هوش مصنوعی',
    "Click Generate AI Insight for a Gemini-written read on this channel's niche, growth signals, and how it could improve monetization.": 'برای دریافت تحلیلی نوشته\u200cشده توسط جمینای درباره\u200cی حوزه\u200cی کانال، سیگنال\u200cهای رشد و راه\u200cهای بهبود مانیتایز، روی تولید بینش هوش مصنوعی بزنید.',
    'Regenerate Insight': 'تولید مجدد بینش',
    'Scanning …': 'در حال اسکن …',
    'This channel has no public uploads.': 'این کانال هیچ آپلود عمومی\u200cای ندارد.',
    '✓ Scanned {n} videos · {k} strong outliers (≥2x).': '✓ {n} ویدیو اسکن شد · {k} مورد پرتِ قوی (≥۲x).',
    'No videos matched your filters.': 'هیچ ویدیویی با فیلترهای شما مطابقت نداشت.',
    'Save to Ideas Board': 'ذخیره در برد ایده\u200cها',
    'Saved to Ideas Board': 'در برد ایده\u200cها ذخیره شد',
    '"{title}" was added to your Ideas Board (New column).': '«{title}» به برد ایده\u200cهای شما اضافه شد (ستون جدید).',
    'Already saved': 'قبلاً ذخیره شده',
    'This video is already on your Ideas Board.': 'این ویدیو از قبل در برد ایده\u200cهای شما موجود است.',
    'No ideas here yet.': 'هنوز ایده\u200cای اینجا نیست.',
    'Remove idea': 'حذف ایده',
    'Remove this idea from your board? This cannot be undone.': 'این ایده از برد شما حذف شود؟ این عمل قابل بازگشت نیست.',
    'Newest': 'جدیدترین',
    'Most Viewed': 'پربازدیدترین',
    'Scraper Started  |  Strategy: {s}': 'استخراج\u200cکننده شروع شد  |  راهبرد: {s}',
    'Canceled before start.': 'پیش از شروع لغو شد.',
    'Resolving channel: {u}': 'در حال یافتن کانال: {u}',
    'Could not resolve Channel ID.': 'شناسه\u200cی کانال یافت نشد.',
    'Error': 'خطا',
    'Could not resolve the channel from that URL.': 'کانالی از این آدرس یافت نشد.',
    'Canceled by user.': 'توسط کاربر لغو شد.',
    'Channel ID: {id}': 'شناسه\u200cی کانال: {id}',
    'Fetching up to {n} video IDs  (order: {o}) …': 'در حال دریافت حداکثر {n} شناسه\u200cی ویدیو (ترتیب: {o}) …',
    'No videos found.': 'ویدیویی یافت نشد.',
    'No Results': 'نتیجه\u200cای یافت نشد',
    'No videos were found for this channel/query.': 'برای این کانال/عبارت جستجو، ویدیویی یافت نشد.',
    '{n} videos queued.': '{n} ویدیو در صف قرار گرفت.',
    'Stopped at video {i}/{n}': 'در ویدیوی {i}/{n} متوقف شد',
    '✅ Transcript Found': '✅ رونوشت یافت شد',
    '⚠️ No Transcript (Video Saved)': '⚠️ بدون رونوشت (ویدیو ذخیره شد)',
    'Failed to get details': 'دریافت جزئیات ناموفق بود',
    '✅ Success: {ok}   ❌ Failed: {fail}   📝 Transcripts: {tc}/{total}': '✅ موفق: {ok}   ❌ ناموفق: {fail}   📝 رونوشت\u200cها: {tc}/{total}',
    'Saving ({fmt}) → {path} …': 'در حال ذخیره ({fmt}) ← {path} …',
    'Saved  |  {kb} KB  |  {n} rows': 'ذخیره شد  |  {kb} کیلوبایت  |  {n} ردیف',
    'Scraping completed successfully!': 'استخراج با موفقیت به پایان رسید!',
    'Done!': 'تمام شد!',
    'Scraped {n} videos ({suffix})\nTranscripts: {tc}/{n}\n\nFile saved to:\n{path}': '{n} ویدیو استخراج شد ({suffix})\nرونوشت\u200cها: {tc}/{n}\n\nفایل ذخیره شد در:\n{path}',
    'No data to save.': 'داده\u200cای برای ذخیره وجود ندارد.',
    'No data was extracted.': 'هیچ داده\u200cای استخراج نشد.',
    'Unexpected error: {e}': 'خطای غیرمنتظره: {e}',
    'An error occurred:\n{e}': 'خطایی رخ داد:\n{e}',
    'Checkpoint saved ({n} rows) → {name}': 'نقطه\u200cی بازرسی ذخیره شد ({n} ردیف) ← {name}',
    'Checkpoint save failed: {e}': 'ذخیره\u200cی نقطه\u200cی بازرسی ناموفق بود: {e}',
    'Saving partial data → {path} …': 'در حال ذخیره\u200cی داده\u200cی ناقص ← {path} …',
    'Partial save complete  |  {kb} KB  |  {n}/{total} videos': 'ذخیره\u200cی ناقص تکمیل شد  |  {kb} کیلوبایت  |  {n}/{total} ویدیو',
    'Partial Save': 'ذخیره\u200cی ناقص',
    'Stopped at video {cur} of {total}.\nSaved {n} records.\n\nFile:\n{path}': 'در ویدیوی {cur} از {total} متوقف شد.\n{n} رکورد ذخیره شد.\n\nفایل:\n{path}',
    'Partial save error: {e}': 'خطای ذخیره\u200cی ناقص: {e}',
    'Unexpected Error': 'خطای غیرمنتظره',
    'An unexpected error occurred, but the app has been kept open.\n\nDetails:\n': 'خطایی غیرمنتظره رخ داد، اما برنامه باز نگه داشته شد.\n\nجزئیات:\n',

    # ---- stability & resume update ----
    'Full details: {path}': 'جزئیات کامل: {path}',
    'FETCH TRANSCRIPTS': 'دریافت رونوشت (ترنسکریپت)',
    'Enabled': 'فعال',
    'Disabled (metadata only, much faster)': 'غیرفعال (فقط متادیتا، بسیار سریع‌تر)',
    'TRANSCRIPT FETCH WORKERS': 'تعداد دریافت هم‌زمان رونوشت',
    'Applies to transcript downloads only (video metadata is now fetched in batches of 50 per request). More workers = faster, but too many parallel transcript requests can get your IP temporarily blocked by YouTube.': 'فقط برای دانلود رونوشت‌ها اعمال می‌شود (متادیتای ویدیوها اکنون در دسته‌های ۵۰تایی در هر درخواست دریافت می‌شود). تعداد بیشتر = سریع‌تر، اما درخواست‌های موازی زیاد ممکن است باعث مسدودشدن موقت IP شما توسط یوتیوب شود.',
    'Scrape in progress': 'استخراج در حال اجراست',
    'A scrape is still running.\nStop it and exit? Progress is kept in the checkpoint file, so you can resume next time.': 'یک استخراج هنوز در حال اجراست.\nمتوقف شود و خارج شویم؟ پیشرفت کار در فایل نقطه‌ی بازرسی حفظ می‌شود و دفعه‌ی بعد می‌توانید ادامه دهید.',
    'Invalid Folder': 'پوشه‌ی نامعتبر',
    'The selected save folder does not exist anymore.\nPlease choose another folder.': 'پوشه‌ی ذخیره‌ی انتخاب‌شده دیگر وجود ندارد.\nلطفاً پوشه‌ی دیگری انتخاب کنید.',
    'Checkpoint found': 'نقطه‌ی بازرسی پیدا شد',
    'A checkpoint from a previous run was found:\n{name}\n({n} videos already scraped)\n\nResume from where it stopped?\n(Choosing No starts over and overwrites it.)': 'یک نقطه‌ی بازرسی از اجرای قبلی پیدا شد:\n{name}\n({n} ویدیو قبلاً استخراج شده)\n\nاز همان‌جا ادامه داده شود؟\n(انتخاب «خیر» از اول شروع می‌کند و آن را بازنویسی می‌کند.)',
    'Worker crashed — details were written to the crash log.': 'فرایند کاری دچار خطا شد — جزئیات در فایل گزارش خطا (crash.log) ثبت شد.',
    'Open File': 'باز کردن فایل',
    'Could not open file': 'فایل باز نشد',
    'Could not open folder': 'پوشه باز نشد',
    'Using uploads playlist (quota-friendly mode).': 'استفاده از پلی‌لیست آپلودها (حالت کم‌مصرف سهمیه).',
    'Using search API (costs more quota: 100 units per 50 videos).': 'استفاده از API جستجو (مصرف سهمیه‌ی بیشتر: ۱۰۰ واحد به‌ازای هر ۵۰ ویدیو).',
    'Resuming: {done} videos restored from checkpoint, {left} remaining.': 'ادامه از نقطه‌ی بازرسی: {done} ویدیو بازیابی شد، {left} ویدیو باقی مانده.',
    'Transcript fetching is disabled in Settings — metadata only.': 'دریافت رونوشت در تنظیمات غیرفعال است — فقط متادیتا.',
    'YouTube is blocking transcript requests from this IP — transcripts disabled for the rest of this run (metadata scraping continues).': 'یوتیوب درخواست‌های رونوشت از این IP را مسدود کرده — دریافت رونوشت تا پایان این اجرا غیرفعال شد (استخراج متادیتا ادامه دارد).',

    # ---- IP-block pause popup (Skip / I Changed My IP) ----
    'YouTube is blocking transcript requests from this IP.': 'یوتیوب درخواست‌های رونوشت را از این IP مسدود کرده.',
    'IP changed and verified — resuming transcript fetching.': 'آی‌پی عوض و تأیید شد — دریافت رونوشت از سر گرفته می‌شود.',
    'YouTube Blocked Your IP': 'یوتیوب آی‌پی شما را مسدود کرد',
    'Transcript requests are being blocked by YouTube.': 'درخواست‌های دریافت رونوشت توسط یوتیوب مسدود می‌شوند.',
    'YouTube is blocking transcript requests from your current IP address.\n\nChange your IP address (switch server/location in your VPN or filter-breaker), then click “I Changed My IP” to verify — or click “Skip” to continue the scrape without transcripts.': 'یوتیوب درخواست‌های دریافت رونوشت را از آی‌پی فعلی شما مسدود کرده است.\n\nآی‌پی خود را عوض کنید (سرور یا لوکیشن وی‌پی‌ان/فیلترشکن خود را عوض کنید)، سپس روی «آی‌پی را عوض کردم» بزنید تا بررسی شود — یا برای ادامه‌ی فرایند بدون رونوشت، روی «رد کردن» بزنید.',
    'Current IP: {ip}': 'آی‌پی فعلی: {ip}',
    'I Changed My IP': 'آی‌پی را عوض کردم',
    'Skip Transcripts': 'رد کردن رونوشت‌ها',
    'Checking your IP …': 'در حال بررسی آی‌پی شما …',
    "Couldn't Verify": 'امکان بررسی نبود',
    "Couldn't reach an IP-check service to verify your address (network issue). Make sure your VPN or filter-breaker is connected, then try again.": 'امکان اتصال به سرویس بررسی آی‌پی برای تأیید آدرس شما نبود (مشکل شبکه). مطمئن شوید وی‌پی‌ان یا فیلترشکن شما متصل است، سپس دوباره امتحان کنید.',
    'IP Unchanged': 'آی‌پی تغییر نکرده',
    'Your IP still looks the same ({ip}). Switch to a different server or location in your VPN or filter-breaker and try again — or click Skip.': 'آی‌پی شما هنوز همان قبلی به نظر می‌رسد ({ip}). سرور یا لوکیشن دیگری را در وی‌پی‌ان یا فیلترشکن خود انتخاب و دوباره امتحان کنید — یا روی «رد کردن» بزنید.',
    'IP Changed': 'آی‌پی عوض شد',
    'Your IP address has changed ({ip}). Resuming transcript fetching …': 'آی‌پی شما تغییر کرد ({ip}). دریافت رونوشت از سر گرفته می‌شود …',
    '✅ Metadata Saved': '✅ متادیتا ذخیره شد',
    'Unavailable (private/deleted)': 'در دسترس نیست (خصوصی/حذف‌شده)',
    'YouTube API daily quota exhausted.': 'سهمیه‌ی روزانه‌ی API یوتیوب تمام شد.',
    'Progress was saved to the checkpoint — start the same scrape after the quota resets (midnight Pacific Time) and choose Resume.': 'پیشرفت کار در نقطه‌ی بازرسی ذخیره شد — پس از بازنشانی سهمیه (نیمه‌شب به وقت اقیانوس آرام) همین استخراج را دوباره شروع کنید و «ادامه» را انتخاب کنید.',
    'Quota exhausted': 'سهمیه تمام شد',
    "Your YouTube API key has used up its daily quota.\n\nEverything scraped so far ({n} videos) was saved.\nQuota resets at midnight Pacific Time — run the same scrape again and choose Resume to continue from here.\n\nTip: 'Most Recent' order without a search query uses far less quota than Popular/Relevant.": 'کلید API یوتیوب شما سهمیه‌ی روزانه‌اش را مصرف کرده است.\n\nهر آنچه تاکنون استخراج شده ({n} ویدیو) ذخیره شد.\nسهمیه نیمه‌شب به وقت اقیانوس آرام بازنشانی می‌شود — همین استخراج را دوباره اجرا کنید و «ادامه» را بزنید.\n\nنکته: ترتیب «جدیدترین» بدون عبارت جستجو سهمیه‌ی بسیار کمتری نسبت به محبوب‌ترین/مرتبط‌ترین مصرف می‌کند.',
    'An error occurred:\n{e}\n\nScraped data was saved — you can resume this scrape later.': 'خطایی رخ داد:\n{e}\n\nداده‌های استخراج‌شده ذخیره شدند — بعداً می‌توانید این استخراج را ادامه دهید.',

    # ── Niche Finder v3 + Search Archive ──────────────────────────────
    '{n}h ago': '{n} ساعت پیش',
    '{n}d ago': '{n} روز پیش',
    '{n}mo ago': '{n} ماه پیش',
    '{n}y ago': '{n} سال پیش',
    'just now': 'همین حالا',
    'N/A': 'نامشخص',
    'Could not reach youtube.com. Check your connection or switch the source back to the official API.': 'دسترسی به youtube.com ممکن نشد. اتصال اینترنت را بررسی کنید یا منبع داده را به API رسمی برگردانید.',
    'YouTube returned a page this app could not read. Switch the source to the official API.': 'یوتیوب صفحه‌ای برگرداند که برنامه نتوانست بخواند. منبع داده را به API رسمی تغییر دهید.',
    'Niche Finder': 'یابنده‌ی نیچ',
    'Niche Finder · Outlier Discovery': 'یابنده‌ی نیچ · کشف آوت‌لایرها',
    'Search all of YouTube for a niche, then filter by subscriber count, views and time window to surface small channels pulling huge numbers — e.g. a 500-sub channel that hit 10M views in the last 30 days. Click any thumbnail or title to open it on YouTube.': 'کل یوتیوب را برای یک نیچ جست‌وجو کنید و بعد با فیلتر تعداد مشترک، بازدید و بازه‌ی زمانی، کانال‌های کوچکی را بیرون بکشید که اعداد غول‌آسا گرفته‌اند — مثلاً کانالی با ۵۰۰ مشترک که در ۳۰ روز گذشته ۱۰ میلیون بازدید خورده است. برای باز کردن در یوتیوب روی تامبنیل یا عنوان کلیک کنید.',
    'Keyword Search': 'جست‌وجوی کلیدواژه',
    'Single Channel Scan': 'اسکن یک کانال',
    'Niche keywords  (separate several with a comma)': 'کلیدواژه‌های نیچ  (چند کلیدواژه را با ویرگول جدا کنید)',
    'e.g.  faceless ai channel, reddit stories, satisfying asmr': 'مثلاً  کانال هوش مصنوعی بدون چهره، داستان‌های ردیت، ای‌اس‌ام‌آر',
    'Stop the running search': 'توقف جست‌وجوی در حال اجرا',
    'Subscribers  (min — max)': 'مشترک  (کمینه — بیشینه)',
    'e.g. 100': 'مثلاً ۱۰۰',
    'e.g. 3000': 'مثلاً ۳۰۰۰',
    'Views  (min — max)': 'بازدید  (کمینه — بیشینه)',
    'e.g. 1M': 'مثلاً ۱M',
    'any': 'بدون محدودیت',
    'e.g. 50': 'مثلاً ۵۰',
    'Deep scan (split the period into windows)': 'اسکن عمیق (شکستن بازه به پنجره‌های کوچک‌تر)',
    'Runs one search per sub-window so smaller channels surface too. Costs proportionally more search quota.': 'برای هر پنجره یک جست‌وجوی جدا می‌زند تا کانال‌های کوچک‌تر هم بالا بیایند. به همان نسبت سهمیه‌ی بیشتری مصرف می‌کند.',
    'Hide channels with hidden sub count': 'پنهان‌کردن کانال‌های با مشترک مخفی',
    'Quick presets': 'فیلترهای آماده',
    'Type a niche keyword and press Search.': 'یک کلیدواژه‌ی نیچ بنویسید و Search را بزنید.',
    'Matches': 'نتایج منطبق',
    'Hidden Gems': 'گوهرهای پنهان',
    'Best Multiplier': 'بهترین ضریب',
    'Videos': 'ویدیوها',
    'Channels': 'کانال‌ها',
    'Filter these results by word …': 'فیلتر همین نتایج با یک کلمه …',
    'Data source': 'منبع داده',
    'Official API · exact, 100 searches/day': 'API رسمی · دقیق، ۱۰۰ جست‌وجو در روز',
    'Web scrape · unlimited, no search quota': 'اسکرپ وب · نامحدود، بدون سهمیه‌ی جست‌وجو',
    'Search': 'جست‌وجو',
    'Published within': 'منتشرشده در',
    'Sort results by': 'مرتب‌سازی بر اساس',
    'Search depth': 'عمق جست‌وجو',
    'Min views ÷ subscribers': 'حداقل بازدید ÷ مشترک',
    'Language / Country': 'زبان / کشور',
    'Export': 'خروجی',
    'Export All': 'خروجی گرفتن از همه',
    'Export Selected ({n})': 'خروجی گرفتن از انتخاب‌شده‌ها ({n})',
    'Select Videos': 'انتخاب ویدیوها',
    'Pick specific videos to export instead of exporting everything shown.': 'به‌جای خروجی گرفتن از همه، ویدیوهای مشخصی را برای خروجی انتخاب کنید.',
    'Export every result currently shown.': 'خروجی گرفتن از همه‌ی نتایج نمایش داده‌شده.',
    'Export only the videos you\u2019ve checked below.': 'فقط از ویدیوهایی که در پایین تیک زده‌اید خروجی بگیرید.',
    'Select for export': 'انتخاب برای خروجی',
    'Click to include / exclude this video from the export': 'برای افزودن یا حذف این ویدیو از خروجی کلیک کنید',
    'Check at least one video to export.': 'برای خروجی گرفتن، حداقل یک ویدیو را تیک بزنید.',
    'Channel': 'کانال',
    'Views in range': 'بازدید در بازه',
    'Top Video': 'بهترین ویدیو',
    'Video': 'ویدیو',
    'Views': 'بازدید',
    'Views ÷ Subs': 'بازدید ÷ مشترک',
    'Views / hour': 'بازدید در ساعت',
    'Stopping …': 'در حال توقف …',
    'Contacting YouTube …': 'در حال ارتباط با یوتیوب …',
    'Fetching exact view counts …': 'در حال گرفتن آمار دقیق بازدید …',
    'Fetching subscriber counts …': 'در حال گرفتن تعداد مشترک‌ها …',
    'Discovered {n} candidate videos …': '{n} ویدیوی کاندید پیدا شد …',
    'Open the channel on YouTube': 'باز کردن کانال در یوتیوب',
    'hidden': 'مخفی',
    'Open on YouTube': 'باز کردن در یوتیوب',
    'Copy link': 'کپی لینک',
    'AI analysis': 'تحلیل هوش مصنوعی',
    'Export results': 'خروجی گرفتن از نتایج',
    'Scan Channel': 'اسکن کانال',
    'Searching …': 'در حال جست‌وجو …',
    'Search stopped.': 'جست‌وجو متوقف شد.',
    'live': 'زنده',
    'Search quota': 'سهمیه‌ی جست‌وجو',
    'Enter a channel URL first.': 'اول آدرس کانال را وارد کنید.',
    'Enter at least one niche keyword first.': 'اول حداقل یک کلیدواژه‌ی نیچ وارد کنید.',
    'Add your YouTube Data API key in Settings first.': 'اول کلید YouTube Data API را در تنظیمات وارد کنید.',
    'Nothing to export yet — run a search first.': 'هنوز چیزی برای خروجی گرفتن نیست — اول یک جست‌وجو بزنید.',
    'Export failed: {err}': 'خروجی گرفتن ناموفق بود: {err}',
    '✓ Exported {n} rows to {path}': '✓ {n} ردیف در {path} ذخیره شد',
    'Link copied: {url}': 'لینک کپی شد: {url}',
    '✓ {shown} of {total} results match your filters.': '✓ {shown} نتیجه از {total} نتیجه با فیلترهای شما هم‌خوانی دارد.',
    'No result matches these filters — widen the subscriber or view range. ({total} were fetched.)': 'هیچ نتیجه‌ای با این فیلترها جور نیست — بازه‌ی مشترک یا بازدید را بازتر کنید. ({total} نتیجه دریافت شده بود.)',
    'Subscriber data is unavailable — add an API key in Settings to filter by subscribers.': 'داده‌ی مشترک در دسترس نیست — برای فیلتر بر اساس مشترک، کلید API را در تنظیمات وارد کنید.',
    'Showing the top {n} — narrow the filters to see the rest.': 'فقط {n} مورد برتر نمایش داده می‌شود — برای دیدن بقیه فیلترها را دقیق‌تر کنید.',
    'This window is wider than the one you searched — press Search again to fetch it.': 'این بازه از بازه‌ای که جست‌وجو کردید بزرگ‌تر است — برای دریافت آن دوباره Search را بزنید.',
    '{n} matching videos · {v} views in range': '{n} ویدیوی منطبق · {v} بازدید در این بازه',
    'cached · {ago}': 'از کش · {ago}',
    'This search ≈ {c} of your {left} remaining searches today  ·  {u}/{t} spent': 'این جست‌وجو ≈ {c} از {left} جست‌وجوی باقی‌مانده‌ی امروز  ·  {u}/{t} مصرف‌شده',
    'Channel scan · no search quota used  ·  {u}/{t} spent today': 'اسکن کانال · بدون مصرف سهمیه‌ی جست‌وجو  ·  {u}/{t} مصرف امروز',
    'Web scrape · 0 search quota  ·  {u}/{t} spent today': 'اسکرپ وب · صفر سهمیه‌ی جست‌وجو  ·  {u}/{t} مصرف امروز',
    'YouTube API quota exhausted for today. Switch the data source to Web scrape, or try again after midnight Pacific time.': 'سهمیه‌ی API یوتیوب برای امروز تمام شد. منبع داده را روی «اسکرپ وب» بگذارید یا بعد از نیمه‌شب به وقت اقیانوس آرام دوباره تلاش کنید.',
    'This search needs about {c} search calls but only {left} are left in today\'s quota.\n\nRun it anyway? YouTube may refuse partway through.': 'این جست‌وجو حدود {c} فراخوانی لازم دارد ولی فقط {left} فراخوانی از سهمیه‌ی امروز باقی مانده است.\n\nبا این حال اجرا شود؟ ممکن است یوتیوب وسط کار جواب ندهد.',
    'Search Archive': 'آرشیو جست‌وجو',
    'Search Archive · Saved Results': 'آرشیو جست‌وجو · نتایج ذخیره‌شده',
    'Every Niche Finder search is stored here as its own keyword section. Click a keyword to bring its results back into the same grid — re-running a keyword merges the fresh numbers into the section instead of wiping it. Nothing here expires, and nothing here costs quota.': 'هر جست‌وجوی «یابنده‌ی نیچ» این‌جا به‌صورت یک بخش جداگانه برای همان کلیدواژه ذخیره می‌شود. روی هر کلیدواژه کلیک کنید تا نتایجش دوباره در همان جدول گرید نمایش داده شود — اگر همان کلیدواژه را دوباره سرچ کنید، آمار تازه با نتایج قبلی ادغام می‌شود و چیزی پاک نمی‌شود. هیچ‌چیزِ این‌جا منقضی نمی‌شود و هیچ سهمیه‌ای مصرف نمی‌کند.',
    'KEYWORD SECTIONS': 'بخش‌های کلیدواژه',
    # ── AI Ideas mini control bar: sort / format toggle / quick search /
    # quick selection actions (see _build_ai_ideas_mini_bar) ─────────────
    'Best Finds / Top Viral': 'بهترین یافته‌ها / پرطرفدارترین',
    'Long Video': 'ویدیوی بلند',
    'Sort this keyword\'s saved videos': 'مرتب‌سازی ویدیوهای ذخیره‌شده‌ی این کلیدواژه',
    'Filter titles, e.g. “Challenge” …': 'فیلتر تیترها، مثلاً «چالش» …',
    '{shown} / {total}': '{shown} / {total}',
    'Select Top 5': 'انتخاب ۵ برتر',
    'Select the top 5 videos in the current sort/filter order for AI.': 'پنج ویدیوی برتر را طبق مرتب‌سازی/فیلتر فعلی برای هوش مصنوعی انتخاب می‌کند.',
    'Clear Selection': 'پاک‌کردن انتخاب',
    'Clear all currently selected videos.': 'همه‌ی ویدیوهای انتخاب‌شده را پاک می‌کند.',
    'No videos match this filter. Clear the search or format toggle above to see this section again.': 'هیچ ویدیویی با این فیلتر مطابقت ندارد. برای دیدن دوباره‌ی این بخش، سرچ یا تاگل فرمت بالا را پاک کنید.',

    'AI Ideas': 'ایده‌های هوش مصنوعی',
    'Pick a keyword section, check the videos that inspire you, then hit "Create with AI" to turn them into 5 new ideas — each with a ready hook line and a shooting-outline script.': 'یک بخش کلیدواژه انتخاب کنید، ویدیوهایی که دوست دارید را تیک بزنید، سپس روی «ساخت با هوش مصنوعی» بزنید تا آن‌ها به ۵ ایده‌ی جدید تبدیل شوند — هرکدام با یک قلاب (هوک) آماده و متن سناریوی فیلم‌برداری.',
    'Pick a keyword section on the left to see its saved videos.': 'یک بخش کلیدواژه را از سمت چپ انتخاب کنید تا ویدیوهای ذخیره‌شده‌اش را ببینید.',
    'Create with AI': 'ساخت با هوش مصنوعی',
    'Create with AI ({n})': 'ساخت با هوش مصنوعی ({n})',
    'Show this keyword\'s saved videos': 'نمایش ویدیوهای ذخیره‌شده‌ی این کلیدواژه',
    '{n} videos saved for “{kw}”. Check the ones you want to use, then Create with AI.': '{n} ویدیو برای «{kw}» ذخیره شده است. مواردی که می‌خواهید استفاده کنید را تیک بزنید، سپس روی ساخت با هوش مصنوعی بزنید.',
    'Use for AI': 'استفاده برای هوش مصنوعی',
    'views': 'بازدید',
    '{n} reference video(s) selected. Remove any you don\'t want, or add more from this keyword\'s saved results.': '{n} ویدیوی مرجع انتخاب شده است. هرکدام را که نمی‌خواهید حذف کنید، یا از نتایج ذخیره‌شده‌ی این کلیدواژه ویدیوی دیگری اضافه کنید.',
    'Nothing selected yet — go back and check a few videos first.': 'هنوز چیزی انتخاب نشده — برگردید و چند ویدیو را تیک بزنید.',
    'Add video': 'افزودن ویدیو',
    'No more videos to add from this keyword': 'ویدیوی دیگری برای افزودن از این کلیدواژه وجود ندارد',
    'Remove this video': 'حذف این ویدیو',
    "Couldn't generate ideas": 'تولید ایده ممکن نشد',
    '{n} AI-generated ideas': '{n} ایده‌ی تولیدشده با هوش مصنوعی',
    'Regenerate': 'تولید دوباره',
    'Back to video selection': 'بازگشت به انتخاب ویدیو',
    'HOOK': 'قلاب (هوک)',
    'SCRIPT': 'سناریو',
    'Untitled idea': 'ایده‌ی بدون عنوان',
    'AI response (unstructured)': 'پاسخ هوش مصنوعی (بدون قالب‌بندی)',
    'Find a saved keyword …': 'جست‌وجوی یک کلیدواژه‌ی ذخیره‌شده …',
    'Keywords': 'کلیدواژه‌ها',
    'Clear whole archive': 'پاک‌کردن کل آرشیو',
    'Saved Results': 'نتایج ذخیره‌شده',
    'Open in Niche Finder': 'باز کردن در یابنده‌ی نیچ',
    'Load this saved pool into the Niche Finder so every filter works on it — without spending a single search call.': 'این نتایج ذخیره‌شده را در «یابنده‌ی نیچ» بارگذاری می‌کند تا همه‌ی فیلترها روی آن کار کنند — بدون مصرف حتی یک فراخوانی جست‌وجو.',
    'Run a search in the Niche Finder — it will be saved here automatically.': 'در «یابنده‌ی نیچ» یک جست‌وجو بزنید — به‌صورت خودکار همین‌جا ذخیره می‌شود.',
    'No saved search matches “{q}”.': 'هیچ جست‌وجوی ذخیره‌شده‌ای با «{q}» جور نیست.',
    'Nothing archived yet. Run a Niche Finder search and it will appear here as its own keyword section.': 'هنوز چیزی آرشیو نشده است. یک جست‌وجو در «یابنده‌ی نیچ» بزنید تا این‌جا به‌صورت یک بخش برای همان کلیدواژه ساخته شود.',
    'Show the saved results for this keyword': 'نمایش نتایج ذخیره‌شده‌ی این کلیدواژه',
    '{n} results': '{n} نتیجه',
    '{n} runs': '{n} بار اجرا',
    'Web scrape': 'اسکرپ وب',
    'Official API': 'API رسمی',
    'updated {ago}': 'به‌روزرسانی {ago}',
    'window: {n} days': 'بازه: {n} روز',
    'window: all time': 'بازه: همه‌ی زمان‌ها',
    'deep scan': 'اسکن عمیق',
    'single channel scan': 'اسکن یک کانال',
    'Show results': 'نمایش نتایج',
    'Rename this section': 'تغییر نام این بخش',
    'Section name': 'نام بخش',
    'Delete this section': 'حذف این بخش',
    'Delete section': 'حذف بخش',
    'Delete “{kw}” and all {n} results saved under it?': 'بخش «{kw}» و هر {n} نتیجه‌ی ذخیره‌شده در آن حذف شود؟',
    'Pick a keyword section on the left to see its saved results.': 'برای دیدن نتایج ذخیره‌شده، یکی از بخش‌های کلیدواژه را انتخاب کنید.',
    'Pick a keyword section first.': 'اول یک بخش کلیدواژه را انتخاب کنید.',
    'This section is empty.': 'این بخش خالی است.',
    'Showing {shown} of {total} saved results for “{kw}”.': 'نمایش {shown} نتیجه از {total} نتیجه‌ی ذخیره‌شده برای «{kw}».',
    'Remove from archive': 'حذف از آرشیو',
    'Remove all {n} saved videos of this channel from the section?': 'هر {n} ویدیوی ذخیره‌شده‌ی این کانال از این بخش حذف شود؟',
    'The archive is already empty.': 'آرشیو از قبل خالی است.',
    'This permanently deletes every saved search section. Continue?': 'این کار همه‌ی بخش‌های جست‌وجوی ذخیره‌شده را برای همیشه حذف می‌کند. ادامه می‌دهید؟',
    'from archive': 'از آرشیو',
    'Archived under “{kw}” · {new} new, {upd} refreshed.': 'در بخش «{kw}» آرشیو شد · {new} مورد جدید، {upd} مورد به‌روزرسانی‌شده.',
    '(archiving failed)': '(آرشیو کردن ناموفق بود)',
    # ── Favorites ──
    'Favorites': 'موردعلاقه‌ها',
    '{n} favorites': '{n} موردعلاقه',
    'No favorites yet. Tap the bookmark icon on any video — here or in Niche Finder — to save it here under its keyword or channel section.':
        'هنوز هیچ موردعلاقه‌ای ثبت نشده. روی آیکن نشانک هر ویدیو بزنید — این‌جا یا در «یابنده‌ی نیچ» — تا زیر همان بخش کلیدواژه یا کانالش این‌جا ذخیره شود.',
    'No favorites yet.': 'هنوز هیچ موردعلاقه‌ای ثبت نشده.',
    'Clear all favorites': 'پاک‌کردن همه‌ی موردعلاقه‌ها',
    'Un-favorite every saved video? Nothing is deleted from the archive — only the favorite flag is cleared.':
        'علاقه‌مندی همه‌ی ویدیوهای ذخیره‌شده برداشته شود؟ چیزی از آرشیو حذف نمی‌شود — فقط نشان موردعلاقه پاک می‌شود.',
    'Remove from favorites': 'حذف از موردعلاقه‌ها',
    'Remove all {n} favorited videos of this channel from Favorites? They stay in their original archive section.':
        'هر {n} ویدیوی موردعلاقه‌ی این کانال از بخش موردعلاقه‌ها حذف شود؟ آن‌ها در بخش اصلی آرشیو خود باقی می‌مانند.',
    'Remove all {n} favorited videos under “{kw}”? They stay in their original archive section — only the favorite flag is cleared.':
        'هر {n} ویدیوی موردعلاقه زیر «{kw}» حذف شود؟ آن‌ها در بخش اصلی آرشیو خود باقی می‌مانند — فقط نشان موردعلاقه پاک می‌شود.',
    'Save to Favorite': 'ذخیره در موردعلاقه‌ها',
    'Saved to Favorites': 'به موردعلاقه‌ها اضافه شد',
    '"{v}" was added to Favorites under "{g}".': '«{v}» زیر «{g}» به موردعلاقه‌ها اضافه شد.',
    '"{v}" is already in Favorites under "{g}".': '«{v}» از قبل زیر «{g}» در موردعلاقه‌هاست.',
    "Can't save yet": 'هنوز نمی‌توان ذخیره کرد',
    'This video is missing channel info, so it can\'t be filed under a favorites section.':
        'اطلاعات کانال این ویدیو موجود نیست، پس نمی‌توان آن را زیر یک بخش موردعلاقه‌ها ثبت کرد.',
    'Archive results': 'آرشیو نتایج',
    'Searches are archived automatically — press this to re-save the current pool under its keyword section.': 'جست‌وجوها به‌صورت خودکار آرشیو می‌شوند — این دکمه نتایج فعلی را دوباره در بخش همان کلیدواژه ذخیره می‌کند.',
    'Nothing to archive yet — run a search first.': 'هنوز چیزی برای آرشیو کردن نیست — اول یک جست‌وجو بزنید.',
    'Showing': 'نمایش',

    # ── Settings · API-key walkthrough ────────────────────────────────
    'How do I get an API key?': 'چطور کلید API بگیرم؟',
    'Hide the guide': 'بستن راهنما',
    'The key is free. Google gives every project 10,000 quota units a day, which is plenty for this app. Follow the six steps below — each button opens the exact page you need in your browser.': 'گرفتن کلید رایگان است. گوگل به هر پروژه روزانه ۱۰٬۰۰۰ واحد سهمیه می‌دهد که برای این برنامه بیش از کافی است. شش مرحله‌ی زیر را دنبال کنید — هر دکمه دقیقاً همان صفحه‌ی موردنیاز را در مرورگر باز می‌کند.',
    'Sign in to Google and open the Cloud Console': 'وارد حساب گوگل شوید و کنسول Google Cloud را باز کنید',
    'Any ordinary Gmail account works — no credit card, no billing account.': 'هر حساب جی‌میل معمولی کافی است — نه کارت بانکی لازم است نه حساب پرداخت.',
    'Open Console': 'باز کردن کنسول',
    'Create a project': 'یک پروژه بسازید',
    'Name it anything (e.g. “yt-scraper”) and press Create. If you already have a project, just select it in the top bar instead.': 'هر اسمی می‌خواهید بگذارید (مثلاً «yt-scraper») و Create را بزنید. اگر از قبل پروژه دارید، فقط آن را از نوار بالای صفحه انتخاب کنید.',
    'New Project': 'پروژه‌ی جدید',
    'Enable YouTube Data API v3': 'سرویس YouTube Data API v3 را فعال کنید',
    'With your project selected, press the blue ENABLE button on that page. This is the step people usually miss — without it the key returns “API not enabled”.': 'وقتی پروژه‌تان انتخاب شده است، در آن صفحه دکمه‌ی آبی ENABLE را بزنید. همین مرحله است که معمولاً فراموش می‌شود — بدون آن، کلید خطای «API not enabled» می‌دهد.',
    'Enable API': 'فعال‌سازی سرویس',
    'Create the key': 'کلید را بسازید',
    'Go to Credentials → CREATE CREDENTIALS → API key. The key appears in a popup and looks like AIzaSy… — press the copy icon next to it.': 'به Credentials بروید → CREATE CREDENTIALS → API key. کلید در یک پنجره‌ی کوچک ظاهر می‌شود و شکلی شبیه AIzaSy… دارد — آیکون کپی کنارش را بزنید.',
    'Credentials': 'صفحه‌ی Credentials',
    'Paste it in the field above, then press Validate Key': 'کلید را در کادر بالا پیست کنید و بعد Validate Key را بزنید',
    'The key is stored in your own local settings file — it never leaves your computer and is not part of the program\'s source.': 'کلید در فایل تنظیمات شخصی خودتان ذخیره می‌شود — هیچ‌وقت از کامپیوتر شما بیرون نمی‌رود و داخل سورس برنامه هم نیست.',
    'Paste key': 'پیست کردن کلید',
    'Paste the copied key into the field above': 'کلید کپی‌شده را در کادر بالا پیست می‌کند',
    'Key pasted. Press “Validate Key” to check it.': 'کلید پیست شد. برای بررسی، «Validate Key» را بزنید.',
    'The clipboard is empty — copy the key from Google Cloud first.': 'کلیپ‌بورد خالی است — اول کلید را از Google Cloud کپی کنید.',
    'Optional · restrict the key': 'اختیاری · محدود کردن کلید',
    'On the key\'s page choose “Restrict key” → API restrictions → YouTube Data API v3. If the key ever leaks, it is then useless for anything else.': 'در صفحه‌ی همان کلید گزینه‌ی «Restrict key» → API restrictions → YouTube Data API v3 را انتخاب کنید. این‌طوری اگر کلید لو برود، برای هیچ سرویس دیگری قابل استفاده نیست.',
    'Quota page': 'صفحه‌ی سهمیه',
    'Good to know · Fetching video and channel statistics costs 1 unit per 50 items, so ordinary scraping barely touches the 10,000-unit budget. Only keyword search is expensive (100 units per page — about 100 searches a day), which is exactly why the Niche Finder caches results and the Search Archive keeps them forever.': 'خوب است بدانید · گرفتن آمار ویدیو و کانال برای هر ۵۰ آیتم فقط ۱ واحد هزینه دارد، پس اسکرپ معمولی تقریباً چیزی از سهمیه‌ی ۱۰٬۰۰۰ واحدی کم نمی‌کند. فقط جست‌وجوی کلیدواژه گران است (۱۰۰ واحد برای هر صفحه — یعنی روزی حدود ۱۰۰ جست‌وجو)، و دقیقاً به همین دلیل است که Niche Finder نتایج را کش می‌کند و آرشیو جست‌وجو آن‌ها را برای همیشه نگه می‌دارد.',
    'If validation fails · “API not enabled” means step 3 was skipped · “quota exceeded” resets at midnight Pacific time · a brand-new key can take a minute or two before Google activates it.': 'اگر اعتبارسنجی رد شد · پیام «API not enabled» یعنی مرحله‌ی ۳ انجام نشده است · «quota exceeded» نیمه‌شب به وقت اقیانوس آرام صفر می‌شود · کلید تازه‌ساخته‌شده گاهی یکی دو دقیقه طول می‌کشد تا گوگل فعالش کند.',
    'A Gemini key is free too — sign in with the same Google account, press “Create API key”, then paste it below.': 'کلید جمینای هم رایگان است — با همان حساب گوگل وارد شوید، «Create API key» را بزنید و کلید را در کادر پایین پیست کنید.',
    'Get a Gemini key': 'گرفتن کلید جمینای',

    # ── added: Custom Provider card (Name / API Mode / API Key+Check / Host / Path / fetched Model list) ──
    'API KEY': 'کلید API',
    'Check': 'بررسی',
    'NAME': 'نام',
    'API MODE': 'حالت API',
    'API HOST': 'میزبان API',
    'API PATH': 'مسیر API',
    'New': 'جدید',
    'Fetch': 'دریافت',
    'No models available': 'مدلی موجود نیست',
    'Remove this model': 'حذف این مدل',
    'Add Model': 'افزودن مدل',
    'Model ID (exactly as the API expects it, e.g. "openai/gpt-4o-mini"):': 'شناسه‌ی مدل (دقیقاً همان‌طور که API انتظار دارد، مثلاً "openai/gpt-4o-mini"):',
    'Enter an API Host first.': 'ابتدا میزبان API را وارد کنید.',
    'No model selected yet — press Fetch to pull the model list from this API, or add one manually with + New.': 'هنوز مدلی انتخاب نشده — برای گرفتن فهرست مدل‌ها از این API دکمه‌ی Fetch را بزنید، یا با + New یکی را دستی اضافه کنید.',
    'Checking API Host …': 'در حال بررسی میزبان API …',
    'Fetching model list …': 'در حال دریافت فهرست مدل‌ها …',
    '✓  Found {n} model(s).': '✓  {n} مدل پیدا شد.',
    'Available Models': 'مدل‌های موجود',
    '{n} model(s) returned by this API — pick the ones you want to use.': '{n} مدل از این API برگشت — مدل‌های موردنظرتان را انتخاب کنید.',
    'Add Selected': 'افزودن انتخاب‌شده‌ها',
    'Models Added': 'مدل‌ها اضافه شدند',
    '{n} model(s) are now available.': 'اکنون {n} مدل در دسترس است.',
    '{provider} sent back a response that isn\'t valid JSON — double-check the API Host and API Path are correct for this provider.':
        '{provider} پاسخی فرستاد که JSON معتبر نیست — میزبان و مسیر API را برای این provider دوباره بررسی کنید.',

    # ── Search Archive: direct video download ──────────────────────────
    'Download video': 'دانلود ویدیو',
    'Preparing…': 'در حال آماده‌سازی…',
    'Installing required components…': 'در حال نصب اجزای موردنیاز…',
    'Merging…': 'در حال ادغام…',
    'Downloading… {pct}%': 'در حال دانلود… {pct}٪',
    'Download started': 'دانلود شروع شد',
    'Download complete': 'دانلود کامل شد',
    'Download failed': 'دانلود ناموفق بود',
    'This item has no video URL.': 'این آیتم لینک ویدیو ندارد.',
    # Shown on a row whose download is waiting for a free slot — the app runs
    # at most two downloads at once (see app.core.download._DL_GATE).
    'Waiting for another download to finish…': 'در انتظار پایان دانلود دیگر…',
}


# ── Niche Finder · Persian UI strings ────────────────────────────────────
FA_STRINGS.update({
    # page chrome
    'Niche Finder': 'یابنده‌ی نیچ',
    'Niche Finder · Outlier Discovery': 'یابنده‌ی نیچ · کشف کانال‌های آوت‌لایر',
    "Search all of YouTube for a niche, then filter by subscriber count, "
    "views and time window to surface small channels pulling huge numbers "
    "— e.g. a 500-sub channel that hit 10M views in the last 30 days. "
    "Click any thumbnail or title to open it on YouTube.":
        'کل یوتیوب را برای یک نیچ جست‌وجو کنید، سپس با فیلتر تعداد مشترک، بازدید و '
        'بازه‌ی زمانی، کانال‌های کوچکی را پیدا کنید که بازدید عظیم گرفته‌اند — مثلاً '
        'کانالی با ۵۰۰ مشترک که در ۳۰ روز گذشته ۱۰ میلیون بازدید خورده است. روی هر '
        'تامبنیل یا عنوان کلیک کنید تا در یوتیوب باز شود.',
    'Keyword Search': 'جست‌وجوی کلیدواژه',
    'Single Channel Scan': 'اسکن یک کانال',
    'Data source': 'منبع داده',
    'Official API · exact, 100 searches/day': 'API رسمی · دقیق، ۱۰۰ جست‌وجو در روز',
    'Web scrape · unlimited, no search quota': 'اسکرپ وب · نامحدود، بدون مصرف سهمیه',
    'Niche keywords  (separate several with a comma)':
        'کلیدواژه‌های نیچ  (چند مورد را با ویرگول جدا کنید)',
    'e.g.  faceless ai channel, reddit stories, satisfying asmr':
        'مثلاً:  کانال بدون چهره، داستان ردیت، ای‌اس‌ام‌آر',
    'Search': 'جست‌وجو',
    'Searching …': 'در حال جست‌وجو …',
    'Scan Channel': 'اسکن کانال',
    'Stop the running search': 'توقف جست‌وجوی در حال اجرا',
    'Stopping …': 'در حال توقف …',
    'Search stopped.': 'جست‌وجو متوقف شد.',
    'Contacting YouTube …': 'در حال اتصال به یوتیوب …',
    'Type a niche keyword and press Search.':
        'یک کلیدواژه‌ی نیچ بنویسید و دکمه‌ی جست‌وجو را بزنید.',

    # filters
    'Published within': 'منتشرشده در',
    'Sort results by': 'مرتب‌سازی بر اساس',
    'Search depth': 'عمق جست‌وجو',
    'Subscribers  (min — max)': 'تعداد مشترک  (کمینه — بیشینه)',
    'Views  (min — max)': 'تعداد بازدید  (کمینه — بیشینه)',
    'Min views ÷ subscribers': 'حداقل نسبت بازدید به مشترک',
    'Language / Country': 'زبان / کشور',
    'e.g. 100': 'مثلاً ۱۰۰',
    'e.g. 3000': 'مثلاً ۳۰۰۰',
    'e.g. 1M': 'مثلاً 1M',
    'e.g. 50': 'مثلاً ۵۰',
    'any': 'بدون محدودیت',
    'Deep scan (split the period into windows)':
        'اسکن عمیق (شکستن بازه به پنجره‌های کوچک‌تر)',
    'Runs one search per sub-window so smaller channels surface too. '
    'Costs proportionally more search quota.':
        'برای هر پنجره‌ی زمانی یک جست‌وجوی جدا اجرا می‌کند تا کانال‌های کوچک‌تر هم '
        'دیده شوند. به همان نسبت سهمیه‌ی بیشتری مصرف می‌کند.',
    'Hide channels with hidden sub count': 'پنهان‌کردن کانال‌های با مشترک مخفی',
    'Quick presets': 'فیلترهای آماده',

    # timeframes
    'Last 24 Hours': '۲۴ ساعت گذشته',
    'Last 7 Days': '۷ روز گذشته',
    'Last 30 Days': '۳۰ روز گذشته',
    'Last 90 Days': '۹۰ روز گذشته',
    'Last 6 Months': '۶ ماه گذشته',
    'Last 12 Months': '۱۲ ماه گذشته',
    'All Time': 'همه‌ی زمان‌ها',

    # sorts
    'Best Finds · Views ÷ Subs': 'بهترین یافته‌ها · بازدید ÷ مشترک',
    'Most Views': 'بیشترین بازدید',
    'Fastest Growing · Views/hour': 'سریع‌ترین رشد · بازدید در ساعت',
    'Smallest Channel First': 'کوچک‌ترین کانال اول',
    'Smallest Channel · Highest Views': 'کوچک‌ترین کانال · بیشترین بازدید',
    'Newest First': 'جدیدترین اول',
    'Most Engagement': 'بیشترین تعامل',
    'Fewest Views': 'کمترین بازدید',

    # archive · range filter flyout
    'Filter by subscriber / view range': 'فیلتر بر اساس بازه‌ی مشترک / بازدید',
    'Filter by range': 'فیلتر بر اساس بازه',
    'Clear': 'پاک کردن',
    'Apply': 'اعمال',
    'Subs {lo}–{hi}': 'مشترک {lo}–{hi}',
    'Views {lo}–{hi}': 'بازدید {lo}–{hi}',
    # 'Views' / 'Subscribers' labels reused from elsewhere in this dict.
    'Low → High': 'کم ← زیاد',
    'High → Low': 'زیاد ← کم',

    # depth
    'Fast · ~50 videos': 'سریع · حدود ۵۰ ویدیو',
    'Normal · ~100 videos': 'معمولی · حدود ۱۰۰ ویدیو',
    'Deep · ~200 videos': 'عمیق · حدود ۲۰۰ ویدیو',
    'Very deep · ~300 videos': 'خیلی عمیق · حدود ۳۰۰ ویدیو',
    'Maximum · ~500 videos': 'بیشینه · حدود ۵۰۰ ویدیو',
    'Maximum · ~700 videos': 'بیشینه · حدود ۷۰۰ ویدیو',
    # عمیق‌ترین حالت جست‌وجو — «+» یعنی کف است نه سقف
    'Deepest · 900+ videos': 'عمیق‌ترین · بیش از ۹۰۰ ویدیو',
    'Fast · 50 videos': 'سریع · ۵۰ ویدیو',
    'Normal · 100 videos': 'معمولی · ۱۰۰ ویدیو',
    'Deep · 200 videos': 'عمیق · ۲۰۰ ویدیو',
    'Very deep · 300 videos': 'خیلی عمیق · ۳۰۰ ویدیو',
    'Maximum · 700 videos': 'بیشینه · ۷۰۰ ویدیو',

    # languages / regions
    'Any language': 'هر زبانی', 'English': 'انگلیسی', 'Persian': 'فارسی',
    'Arabic': 'عربی', 'Spanish': 'اسپانیایی', 'Turkish': 'ترکی',
    'German': 'آلمانی', 'French': 'فرانسوی', 'Russian': 'روسی',
    'Hindi': 'هندی', 'Portuguese': 'پرتغالی',
    'Any country': 'هر کشوری', 'United States': 'آمریکا',
    'United Kingdom': 'بریتانیا', 'Iran': 'ایران', 'Germany': 'آلمان',
    'Turkey': 'ترکیه', 'India': 'هند', 'Brazil': 'برزیل', 'Canada': 'کانادا',
    'Australia': 'استرالیا', 'United Arab Emirates': 'امارات',

    # presets
    'Under 1K subs': 'زیر ۱ هزار مشترک',
    '1K – 10K subs': '۱ تا ۱۰ هزار مشترک',
    'Tiny channel, huge video': 'کانال کوچک، ویدیوی غول',
    '10M+ views': 'بالای ۱۰ میلیون بازدید',
    'Clear filters': 'پاک‌کردن فیلترها',

    # metrics
    'Matches': 'نتایج منطبق',
    'Hidden Gems': 'گنج‌های پنهان',
    'Gem': 'گنج',
    'Best Multiplier': 'بهترین ضریب',
    'Total Views': 'مجموع بازدید',

    # results table
    'Videos': 'ویدیوها',
    'Channels': 'کانال‌ها',
    'Filter these results by word …': 'فیلتر همین نتایج با یک کلمه …',
    'Export': 'خروجی',
    'Video': 'ویدیو',
    'Channel': 'کانال',
    'Subscribers': 'مشترک',
    'Views': 'بازدید',
    'Views ÷ Subs': 'بازدید ÷ مشترک',
    'Views / hour': 'بازدید در ساعت',
    'Published': 'انتشار',
    'Views in range': 'بازدید در بازه',
    'Top Video': 'بهترین ویدیو',
    'Action': 'عملیات',
    'hidden': 'مخفی',
    'Open': 'بازکردن',
    'Open on YouTube': 'بازکردن در یوتیوب',
    'Open the channel on YouTube': 'بازکردن کانال در یوتیوب',
    'Copy link': 'کپی لینک',
    'AI analysis': 'تحلیل هوش مصنوعی',
    'Link copied: {url}': 'لینک کپی شد: {url}',
    '{n} matching videos · {v} views in range':
        '{n} ویدیوی منطبق · {v} بازدید در این بازه',
    'cached · {ago}': 'از کش · {ago}',
    'live': 'زنده',

    # status / quota
    'Channel scan · no search quota used  ·  {u}/{t} spent today':
        'اسکن کانال · بدون مصرف سهمیه‌ی جست‌وجو  ·  امروز {u} از {t} مصرف شده',
    'Web scrape · 0 search quota  ·  {u}/{t} spent today':
        'اسکرپ وب · صفر سهمیه  ·  امروز {u} از {t} مصرف شده',
    'This search ≈ {c} of your {left} remaining searches today  ·  {u}/{t} spent':
        'این جست‌وجو حدود {c} از {left} جست‌وجوی باقی‌مانده‌ی امروز  ·  {u} از {t} مصرف شده',
    'Search quota': 'سهمیه‌ی جست‌وجو',
    "This search needs about {c} search calls but only {left} are left in "
    "today's quota.\n\nRun it anyway? YouTube may refuse partway through.":
        'این جست‌وجو حدود {c} فراخوانی لازم دارد اما فقط {left} مورد از سهمیه‌ی امروز '
        'باقی مانده است.\n\nبا این حال اجرا شود؟ ممکن است یوتیوب وسط کار پاسخ ندهد.',
    'Enter a channel URL first.': 'ابتدا آدرس کانال را وارد کنید.',
    'Enter at least one niche keyword first.':
        'ابتدا حداقل یک کلیدواژه‌ی نیچ وارد کنید.',
    'Add your YouTube Data API key in Settings first.':
        'ابتدا کلید API یوتیوب را در صفحه‌ی تنظیمات وارد کنید.',
    'YouTube API quota exhausted for today. Switch the data source to Web '
    'scrape, or try again after midnight Pacific time.':
        'سهمیه‌ی API یوتیوب برای امروز تمام شد. منبع داده را روی «اسکرپ وب» بگذارید '
        'یا بعد از نیمه‌شب به وقت اقیانوس آرام دوباره تلاش کنید.',
    '✓ {shown} of {total} results match your filters.':
        '✓ {shown} نتیجه از {total} نتیجه با فیلترهای شما مطابقت دارد.',
    'No result matches these filters — widen the subscriber or view range. '
    '({total} were fetched.)':
        'هیچ نتیجه‌ای با این فیلترها مطابقت ندارد — بازه‌ی مشترک یا بازدید را بازتر '
        'کنید. ({total} نتیجه دریافت شده بود.)',
    'Subscriber data is unavailable — add an API key in Settings to filter by '
    'subscribers.':
        'داده‌ی تعداد مشترک در دسترس نیست — برای فیلتر بر اساس مشترک، کلید API را در '
        'تنظیمات وارد کنید.',
    'Discovered {n} candidate videos …': '{n} ویدیوی کاندید پیدا شد …',
    'Fetching exact view counts …': 'در حال دریافت آمار دقیق بازدید …',
    'Fetching subscriber counts …': 'در حال دریافت تعداد مشترک کانال‌ها …',
    'Could not reach youtube.com. Check your connection or switch the source '
    'back to the official API.':
        'دسترسی به youtube.com ممکن نشد. اتصال اینترنت را بررسی کنید یا منبع داده را '
        'به API رسمی برگردانید.',
    'YouTube returned a page this app could not read. Switch the source to the '
    'official API.':
        'یوتیوب صفحه‌ای برگرداند که برنامه نتوانست بخواند. منبع داده را روی API رسمی '
        'بگذارید.',

    'Showing the top {n} — narrow the filters to see the rest.':
        'فقط {n} نتیجه‌ی برتر نمایش داده می\u200cشود — برای دیدن بقیه فیلترها را دقیق\u200cتر کنید.',
    'This window is wider than the one you searched — press Search again to fetch it.':
        'این بازه بزرگ\u200cتر از بازه\u200cای است که جست\u200cوجو کردید — برای دریافت آن دوباره جست\u200cوجو بزنید.',
    # export
    'Nothing to export yet — run a search first.':
        'هنوز چیزی برای خروجی‌گرفتن نیست — اول یک جست‌وجو انجام دهید.',
    'Export results': 'خروجی گرفتن از نتایج',
    'Export failed: {err}': 'خروجی‌گرفتن ناموفق بود: {err}',
    '✓ Exported {n} rows to {path}': '✓ {n} ردیف در {path} ذخیره شد',
})

# ── appearance / theme picker ────────────────────────────────────────────
FA_STRINGS.update({
    'Appearance': 'ظاهر برنامه',
    'Currently: {theme}': 'اکنون: {theme}',
    'Light': 'روشن',
    'Dark': 'تاریک',
    'Match Windows': 'هماهنگ با ویندوز',
    "Pick a colour theme. 'Match Windows' follows your system "
    "light/dark setting. Switching restarts the app.":
        'یک تم رنگی انتخاب کنید. گزینه‌ی «هماهنگ با ویندوز» از تنظیم روشن/تاریک '
        'سیستم پیروی می‌کند. با تغییر تم، برنامه دوباره اجرا می‌شود.',
})

# ── title bar quick settings (see QuickSettingsMenu) ─────────────────────
FA_STRINGS.update({
    'Quick Settings': 'تنظیمات سریع',
    'Theme': 'پوسته',
})

# ── card grid · filter drawer · collapsible keyword panel ────────────────
FA_STRINGS.update({
    'Filters': 'فیلترها',
    'Filters ({n})': 'فیلترها ({n})',
    'Show or hide the filters': 'نمایش یا پنهان‌کردن فیلترها',
    'Hide the filters': 'پنهان‌کردن فیلترها',
    'Remove this filter': 'حذف این فیلتر',
    '{a}–{b} subs': '{a}–{b} مشترک',
    '{a}–{b} views': '{a}–{b} بازدید',
    'Card grid': 'نمایش کارتی',
    'Compact table': 'نمایش جدولی',
    'No results yet — run a search, or widen your filters.':
        'هنوز نتیجه‌ای نیست — یک جست‌وجو بزنید یا فیلترها را بازتر کنید.',
    'VIEWS': 'بازدید',
    'V÷SUBS': 'بازدید÷مشترک',
    'SPEED': 'سرعت',
    'AGE': 'قدمت',
    'BEST ×': 'بهترین ×',
    'VIDEOS': 'ویدیوها',
    '{s} subs · {n} matching videos': '{s} مشترک · {n} ویدیوی منطبق',
    'Hide keyword sections — slide the list away so the results grid gets the full width. Click again to bring it back.': 'پنهان‌کردن بخش‌های کلیدواژه — فهرست را کنار می‌زند تا گرید نتایج تمام پهنا را بگیرد. برای بازگرداندنش دوباره بزنید.',
    'Show keyword sections — bring back the saved-search list on the left.': 'نمایش بخش‌های کلیدواژه — فهرست جست‌وجوهای ذخیره‌شده را در سمت چپ برمی‌گرداند.',
})

# ── Support card ─────────────────────────────────────────────────────────
FA_STRINGS.update({
    'Creator & maintainer of Youtube Scrapper':
        'سازنده و نگه‌دارنده‌ی یوتیوب اسکرپر',
    'Usually replies within a day': 'معمولاً ظرف یک روز پاسخ می‌دهد',
    'Hit a bug, a stuck scrape or a quota error? Send me a message on '
    'Telegram — screenshots welcome. Source, releases and issue tracker '
    'live on GitHub.':
        'به باگ، استخراجِ گیرکرده یا خطای سهمیه برخوردید؟ در تلگرام برایم '
        'پیام بفرستید — اسکرین‌شات هم بفرستید بهتر است. سورس، نسخه‌ها و '
        'پیگیری مشکلات در گیت‌هاب است.',
    'Message on Telegram': 'ارسال پیام در تلگرام',
    'GitHub': 'گیت‌هاب',
    'Copy Telegram ID': 'کپی آیدی تلگرام',
    'Copied!': 'کپی شد!',
})

# ── Live theme switching ─────────────────────────────────────────────────
FA_STRINGS.update({
    "Pick a colour theme. 'Match Windows' follows your system "
    "light/dark setting. Changes apply instantly — no restart.":
        'یک تم رنگی انتخاب کنید. گزینه‌ی «هماهنگ با ویندوز» از تنظیم روشن/تاریک '
        'سیستم پیروی می‌کند. تغییرات بلافاصله اعمال می‌شوند — بدون راه‌اندازی مجدد.',
    'Theme Updated': 'تم تغییر کرد',
    'Now using the {theme} theme.': 'اکنون از تم {theme} استفاده می‌شود.',
})

# ── Sidebar quota ring ───────────────────────────────────────────────────
FA_STRINGS.update({
    'QUOTA': 'سهمیه',
    'NO KEY': 'بدون کلید',
    'Add a YouTube API key in Settings to track quota.':
        'برای پیگیری سهمیه، یک کلید YouTube API در تنظیمات وارد کنید.',
    '{r} / {c} quota units left today  ·  {n} key(s)  ·  click for Settings':
        '{r} / {c} واحد سهمیه برای امروز باقی مانده  ·  {n} کلید  ·  کلیک برای تنظیمات',
    'Switch theme': 'تغییر پوسته',
})

# ── Custom title bar (min / max / close) ─────────────────────────────────
FA_STRINGS.update({
    'Minimize': 'کوچک کردن',
    'Maximize': 'بزرگ کردن',
    'Restore': 'بازگردانی',
    'Close': 'بستن',
})

# ── Notification center (header bell) ────────────────────────────────────
FA_STRINGS.update({
    '{n}m ago': '{n} دقیقه پیش',
    'Clear all': 'پاک‌کردن همه',
    'Dismiss': 'حذف',
    'Monetization check complete': 'بررسی مانیتایز تمام شد',
    'Monetization check failed': 'بررسی مانیتایز ناموفق بود',
    'Niche Finder search complete': 'جست‌وجوی یابنده‌ی نیچ تمام شد',
    'Niche Finder search failed': 'جست‌وجوی یابنده‌ی نیچ ناموفق بود',
    '{n} results found.': '{n} نتیجه پیدا شد.',
    'AI ideas ready': 'ایده‌های هوش مصنوعی آماده شد',
})

# ── Content Lab ─────────────────────────────────────────────────────────
FA_STRINGS.update({
    'Content Lab': 'آزمایشگاه محتوا',
    "AI-built content blueprints for every keyword and channel you've sent "
    "here from AI Ideas.":
        'طرح‌های محتوایی ساخته‌شده با هوش مصنوعی، برای هر کلیدواژه یا کانالی '
        'که از بخش ایده‌های هوش مصنوعی به اینجا فرستاده‌اید.',
    'Search Content Lab sections…': 'جست‌وجو در بخش‌های آزمایشگاه محتوا…',
    'NOTHING BUILT YET': 'هنوز چیزی ساخته نشده',
    'No sections match “{q}”.': 'هیچ بخشی با «{q}» مطابقت ندارد.',
    'Go to AI Ideas, pick a few reference videos from a keyword or channel '
    'section, then hit Create with AI — it will show up here as its own '
    'section.':
        'به بخش ایده‌های هوش مصنوعی بروید، چند ویدیوی مرجع از یک بخش کلیدواژه '
        'یا کانال انتخاب کنید و روی «ساخت با هوش مصنوعی» بزنید — نتیجه همین‌جا '
        'به‌صورت یک بخش جداگانه نمایش داده می‌شود.',
    'Open this section': 'باز کردن این بخش',
    '{n} idea(s)  ·  updated {t}': '{n} ایده  ·  به‌روزرسانی {t}',
    'View': 'مشاهده',
    'Delete this section': 'حذف این بخش',
    'Delete section': 'حذف بخش',
    'Delete “{t}” and all {n} idea(s) in it? This can\'t be undone.':
        '«{t}» و همه‌ی {n} ایده‌ی داخل آن حذف شود؟ این کار قابل بازگشت نیست.',
    'All sections': 'همه‌ی بخش‌ها',
    'All Ideas': 'همه‌ی ایده‌ها',
    'Loading Content Lab…': 'در حال بارگذاری آزمایشگاه محتوا…',
    'Could not open Content Lab. Please try again.':
        'باز کردن آزمایشگاه محتوا ممکن نشد. دوباره امتحان کنید.',
    'Untitled idea': 'ایده‌ی بدون عنوان',
    'PROMISING': 'امیدبخش',
    'AI response (unstructured)': 'پاسخ هوش مصنوعی (بدون ساختار)',
    'AI is building your content blueprint…': 'هوش مصنوعی در حال ساخت طرح محتوایی شماست…',
    "Couldn't generate ideas: {e}": 'ساخت ایده‌ها ممکن نشد: {e}',
    'AI generation failed: {e}': 'ساخت با هوش مصنوعی ناموفق بود: {e}',
    '{n} new idea(s) are ready.': '{n} ایده‌ی جدید آماده است.',
    "Couldn't regenerate this idea: {e}": 'بازسازی این ایده ممکن نشد: {e}',
    'Idea regenerated.': 'ایده دوباره ساخته شد.',
    'No favorited ideas yet — tap the bookmark on any idea to pin it here.':
        'هنوز ایده‌ی موردعلاقه‌ای نیست — روی نشانک هر ایده بزنید تا اینجا سنجاق شود.',
    'No ideas yet. Generating now…': 'هنوز ایده‌ای نیست. در حال ساخت…',
    'Pick an idea above to see its full blueprint.':
        'یکی از ایده‌های بالا را انتخاب کنید تا طرح کامل آن را ببینید.',
    'AI BLUEPRINT': 'طرح هوش مصنوعی',
    'Viral Angle': 'زاویه‌ی وایرال‌شدن',
    'Core Concept': 'مفهوم اصلی',
    'Hook Anatomy': 'ساختار قلاب (هوک)',
    'Visual (first 3s)': 'تصویر (۳ ثانیه‌ی اول)',
    'On-screen Text': 'متن روی تصویر',
    'Thumbnail Prompt': 'پرامپت تامبنیل',
    'Execution Blueprint': 'طرح اجرا',
    'Editing Style': 'سبک تدوین',
    'Assets / AI-Gen': 'منابع / تولیدشده با هوش مصنوعی',
    'Rendering': 'رندر',
    'Packaging': 'بسته‌بندی',
    'Title Framework': 'قالب عنوان',
    'Golden Timing': 'زمان‌بندی طلایی',
    'High-CTR Titles': 'عنوان‌های پرکلیک',
    'Retention Layout & Sources': 'چیدمان نگه‌داشت بیننده و منابع',
    '~{s}s total': '~{s} ثانیه در مجموع',
    'Regenerate this idea': 'بازسازی این ایده',
    'Favorite': 'موردعلاقه',
    'AI is regenerating…': 'هوش مصنوعی در حال بازسازی…',
    'REFERENCE VIDEOS USED': 'ویدیوهای مرجع استفاده‌شده',
    '+{n} more reference video(s)': '+{n} ویدیوی مرجع دیگر',

    # ── added: short/long format toggle, favorites relocation, SEO section,
    #    JSON/PDF export dialog ──
    'Short-Form': 'شورت‌فرم',
    'Long-Form': 'لانگ‌فرم',
    'Favorites Only': 'فقط موردعلاقه‌ها',
    'No short-form ideas here yet. Pick some shorter reference videos and hit Create with AI.':
        'هنوز ایده‌ی شورت‌فرمی اینجا نیست. چند ویدیوی مرجع کوتاه‌تر انتخاب کنید و «ساخت با '
        'هوش مصنوعی» را بزنید.',
    'No long-form ideas here yet. Pick some longer reference videos and hit Create with AI.':
        'هنوز ایده‌ی لانگ‌فرمی اینجا نیست. چند ویدیوی مرجع طولانی‌تر انتخاب کنید و «ساخت با '
        'هوش مصنوعی» را بزنید.',
    'Psychological Triggers': 'محرک‌های روان‌شناختی',
    'SEO & Discoverability': 'سئو و دیده‌شدن',
    'KEYWORDS': 'کلیدواژه‌ها',
    'Tags': 'تگ‌ها',
    'YouTube Description': 'توضیحات یوتیوب',
    'YOUTUBE DESCRIPTION': 'توضیحات یوتیوب',
    'Chapters / Timestamps': 'فصل‌بندی / زمان‌بندی',
    'CHAPTERS / TIMESTAMPS': 'فصل‌بندی / زمان‌بندی',
    'Export this section': 'خروجی گرفتن از این بخش',
    '{n} idea(s) in "{title}" — {s} short-form, {l} long-form.':
        '{n} ایده در «{title}» — {s} شورت‌فرم، {l} لانگ‌فرم.',
    'Raw structured data — every field, easy to reuse elsewhere.':
        'داده‌ی خام و ساخت‌یافته — همه‌ی فیلدها، برای استفاده‌ی دوباره در جای دیگر.',
    'A clean, print-ready blueprint document.': 'سندی تمیز از طرح ایده، آماده‌ی چاپ.',
    'Select All': 'انتخاب همه',
    'Select Export Folder': 'انتخاب پوشه‌ی خروجی',
    'Generate at least one idea before exporting.':
        'پیش از گرفتن خروجی، حداقل یک ایده بسازید.',
    'Exported to {folder}': 'در مسیر {folder} ذخیره شد',
    'Some exports failed:': 'گرفتن برخی خروجی‌ها ناموفق بود:',
    'CONTENT LAB — AI BLUEPRINT': 'آزمایشگاه محتوا — طرح هوش مصنوعی',
    'Exported': 'تاریخ خروجی',
    '{n} idea(s) — {s} short-form, {l} long-form': '{n} ایده — {s} شورت‌فرم، {l} لانگ‌فرم',

    # ── added: stop / resume a download (Downloads page + result cards) ──
    'Stopped': 'متوقف‌شده',
    'Stopped at {pct}%': 'متوقف در {pct}٪',
    'Resuming…': 'در حال ادامه…',
    'Resuming download…': 'در حال ادامه‌ی دانلود…',
    'That download is no longer listed.': 'آن دانلود دیگر در لیست نیست.',

    # ── added: thumbnail download from the AI Ideas reference grid ──
    'Choose where to save thumbnails': 'محل ذخیره‌ی تامبنیل‌ها را انتخاب کنید',
    'Choose a folder to save thumbnails to first.':
        'ابتدا یک پوشه برای ذخیره‌ی تامبنیل‌ها انتخاب کنید.',
    'This video has no thumbnail to download.':
        'این ویدیو تامبنیلی برای دانلود ندارد.',
    'Thumbnail saved.': 'تامبنیل ذخیره شد.',
    "Couldn't save the thumbnail.": 'ذخیره‌ی تامبنیل ممکن نشد.',

    # ── added: download stop/cancel ──
    'Stopping…': 'در حال توقف…',
    'Stopping download…': 'در حال توقف دانلود…',
    'Download stopped.': 'دانلود متوقف شد.',

    # ── added: QML Content Lab page (library + CSV analysis tabs) ──
    'Your saved blueprints, and AI channel reports from a scraped CSV.':
        'طرح‌های ذخیره‌شده‌ی شما، و گزارش‌های کانال با هوش مصنوعی از روی فایل CSV اسکرپ‌شده.',
    'Library': 'کتابخانه',
    'CSV Analysis': 'تحلیل CSV',
    'Nothing built yet': 'هنوز چیزی ساخته نشده',
    'Go to AI Ideas, generate a few blueprints, and they show up here grouped by keyword or channel.':
        'به بخش ایده‌های هوش مصنوعی بروید، چند طرح بسازید تا همین‌جا برحسب کلیدواژه یا کانال دسته‌بندی و نمایش داده شوند.',
    'No favorited blueprints in this section yet.':
        'هنوز طرح موردعلاقه‌ای در این بخش نیست.',
    'No AI provider configured — add a key in Settings to analyze a CSV.':
        'هیچ ارائه‌دهنده‌ی هوش مصنوعی تنظیم نشده — برای تحلیل CSV یک کلید در تنظیمات اضافه کنید.',
    'Turn a scraped channel export into a full AI report — real charts and top videos from your '
    'data, plus tailored analysis. Output is a self-contained HTML page you can print to PDF.':
        'خروجی اسکرپ‌شده‌ی یک کانال را به یک گزارش کامل هوش مصنوعی تبدیل کنید — نمودارهای واقعی و '
        'ویدیوهای برتر از داده‌ی خودتان، به‌همراه تحلیل اختصاصی. خروجی یک صفحه‌ی HTML مستقل است که '
        'می‌توانید آن را به PDF چاپ کنید.',
    'Choose CSV…': 'انتخاب CSV…',
    'Combine with my blueprints': 'ترکیب با طرح‌های من',
    'Optional — tick any saved blueprints to have the report sharpen them against this channel\'s real data.':
        'اختیاری — هر طرح ذخیره‌شده‌ای را تیک بزنید تا گزارش آن را با داده‌ی واقعی این کانال دقیق‌تر کند.',
    'No saved blueprints yet — generate some in AI Ideas first.':
        'هنوز طرح ذخیره‌شده‌ای نیست — ابتدا در بخش ایده‌های هوش مصنوعی چند تا بسازید.',
    '{n} picked': '{n} انتخاب‌شده',
    'LONG': 'بلند',
    'SHORT': 'کوتاه',
    'Analyze channel': 'تحلیل کانال',
    'Analyze + combine blueprints': 'تحلیل + ترکیب طرح‌ها',
    'Analyze': 'تحلیل',
    'Open report': 'باز کردن گزارش',
    'Building your channel report — this can take a few minutes. You can leave the page; the run continues.':
        'در حال ساخت گزارش کانال شما — این کار ممکن است چند دقیقه طول بکشد. می‌توانید صفحه را ترک '
        'کنید؛ اجرا ادامه می‌یابد.',
    'Choose a channel export': 'یک خروجی کانال انتخاب کنید',
    'Delete this section?': 'این بخش حذف شود؟',
    'Delete section': 'حذف بخش',
    'Analyzing …': 'در حال تحلیل …',
    'Analyzing with {p} — this can take a few minutes…':
        'در حال تحلیل با {p} — این کار ممکن است چند دقیقه طول بکشد…',
    'Analyzing with {p} and folding in {n} blueprint(s) — this can take a few minutes…':
        'در حال تحلیل با {p} و ترکیب {n} طرح — این کار ممکن است چند دقیقه طول بکشد…',
    'Ready to analyze “{f}”.': 'آماده‌ی تحلیل «{f}».',
    'A report already exists for this file — open it, or analyze again.':
        'برای این فایل قبلاً گزارشی ساخته شده — آن را باز کنید یا دوباره تحلیل کنید.',
    'Pick a channel export (.csv, .xlsx, .jsonl or .db).':
        'یک خروجی کانال انتخاب کنید (‎.csv، ‎.xlsx، ‎.jsonl یا ‎.db).',
    'Pick a channel export first.': 'ابتدا یک خروجی کانال انتخاب کنید.',
    "That file couldn't be opened.": 'باز کردن آن فایل ممکن نشد.',
    '✓ Report ready — opened in your browser.': '✓ گزارش آماده شد — در مرورگر شما باز شد.',
    'Channel report ready.': 'گزارش کانال آماده است.',
    'Analysis failed.': 'تحلیل ناموفق بود.',
    'That report is no longer on disk — analyze again.':
        'آن گزارش دیگر روی دیسک نیست — دوباره تحلیل کنید.',
    "Couldn't delete that section.": 'حذف آن بخش ممکن نشد.',
    'Section deleted.': 'بخش حذف شد.',
})

# ── Content Lab (QML page): library tab, CSV analysis tab ─────────────────
FA_STRINGS.update({
    'Your saved AI blueprints, and deep AI reports from a scraped channel CSV.':
        'بلوپرینت‌های هوش مصنوعی ذخیره‌شده‌ی شما، و گزارش‌های عمیق هوش مصنوعی از روی CSV یک کانال اسکرپ‌شده.',
    'Library': 'کتابخانه',
    'CSV Analysis': 'تحلیل CSV',
    'Nothing built yet': 'هنوز چیزی ساخته نشده',
    'Go to AI Ideas, generate a few blueprints, and they show up here as their own section.':
        'به بخش ایده‌های هوش مصنوعی بروید، چند بلوپرینت بسازید تا همین‌جا به‌صورت یک بخش جداگانه نمایش داده شوند.',
    'Open AI Ideas': 'باز کردن ایده‌های هوش مصنوعی',
    'Pick a blueprint to open its full production plan below.':
        'یک بلوپرینت را انتخاب کنید تا طرح تولید کامل آن در پایین باز شود.',
    'No favorited blueprints in this section yet.':
        'هنوز بلوپرینت موردعلاقه‌ای در این بخش نیست.',
    'Show all': 'نمایش همه',
    'Showing favorites': 'نمایش موردعلاقه‌ها',
    'Delete this blueprint?': 'این بلوپرینت حذف شود؟',
    'It will be removed from your Content Lab library for good. This cannot be undone.':
        'این بلوپرینت برای همیشه از کتابخانه‌ی آزمایشگاه محتوا حذف می‌شود. این کار قابل بازگشت نیست.',
    'Delete section?': 'این بخش حذف شود؟',
    'This deletes the section and all {n} blueprint(s) in it. This cannot be undone.':
        'این کار بخش و همه‌ی {n} بلوپرینت داخل آن را حذف می‌کند. قابل بازگشت نیست.',
    'Delete section': 'حذف بخش',
    'Open Settings': 'باز کردن تنظیمات',
})

# ── Content Lab CSV analysis: pick + run + statuses ───────────────────────
FA_STRINGS.update({
    'No AI provider configured — add a key in Settings to analyze a channel.':
        'هیچ ارائه‌دهنده‌ی هوش مصنوعی تنظیم نشده — برای تحلیل یک کانال، یک کلید در تنظیمات اضافه کنید.',
    'Analyze a scraped channel': 'تحلیل یک کانال اسکرپ‌شده',
    'Pick a channel export you scraped (CSV, Excel, JSONL or the .db file). '
    'The AI reads every row and writes a full report — why the top videos work, '
    'title patterns, best length and upload timing, and next-video ideas — as a '
    'self-contained HTML page you can print or save as PDF.':
        'یک خروجی کانال که اسکرپ کرده‌اید انتخاب کنید (CSV، اکسل، JSONL یا فایل .db). '
        'هوش مصنوعی همه‌ی ردیف‌ها را می‌خواند و یک گزارش کامل می‌نویسد — اینکه چرا ویدیوهای برتر '
        'جواب می‌دهند، الگوی عنوان‌ها، بهترین طول و زمان انتشار، و ایده‌های ویدیوی بعدی — به‌صورت '
        'یک صفحه‌ی HTML مستقل که می‌توانید چاپ یا به‌صورت PDF ذخیره کنید.',
    'Choose file…': 'انتخاب فایل…',
    'Analyze channel': 'تحلیل کانال',
    'Analyzing …': 'در حال تحلیل…',
    'Open report': 'باز کردن گزارش',
    'Reading every row and writing the report — this can take a few minutes. '
    'You can leave the page; the run continues.':
        'خواندن همه‌ی ردیف‌ها و نوشتن گزارش — ممکن است چند دقیقه طول بکشد. '
        'می‌توانید صفحه را ترک کنید؛ اجرا ادامه می‌یابد.',
    'Choose a channel export': 'انتخاب خروجی یک کانال',
    'Channel export (*.csv *.xlsx *.jsonl *.db)': 'خروجی کانال (‎*.csv *.xlsx *.jsonl *.db‎)',
    'All files (*)': 'همه‌ی فایل‌ها (*)',
})

# ── Content Lab VM messages (toasts + status lines) ───────────────────────
FA_STRINGS.update({
    'A report already exists for this file — open it, or analyze again.':
        'برای این فایل قبلاً یک گزارش ساخته شده — بازش کنید، یا دوباره تحلیل کنید.',
    'Add an AI provider key in Settings first.':
        'ابتدا یک کلید ارائه‌دهنده‌ی هوش مصنوعی در تنظیمات اضافه کنید.',
    'Analyzing with {p} — this can take a few minutes…':
        'در حال تحلیل با {p} — ممکن است چند دقیقه طول بکشد…',
    'Blueprint deleted.': 'بلوپرینت حذف شد.',
    'Blueprint rebuilt.': 'بلوپرینت دوباره ساخته شد.',
    'Channel report ready.': 'گزارش کانال آماده است.',
    "Couldn't delete that blueprint.": 'حذف آن بلوپرینت ممکن نشد.',
    "Couldn't delete that section.": 'حذف آن بخش ممکن نشد.',
    'Custom provider': 'ارائه‌دهنده‌ی سفارشی',
    'No AI provider configured.': 'هیچ ارائه‌دهنده‌ی هوش مصنوعی تنظیم نشده.',
    'Pick a channel export (.csv, .xlsx, .jsonl or .db).':
        'یک خروجی کانال انتخاب کنید (‎.csv، ‎.xlsx، ‎.jsonl یا ‎.db).',
    'Pick a channel export first.': 'ابتدا یک خروجی کانال انتخاب کنید.',
    'Ready to analyze “{f}”.': 'آماده‌ی تحلیل «{f}».',
    'Rebuild failed.': 'بازسازی ناموفق بود.',
    "That file couldn't be opened.": 'آن فایل باز نشد.',
    'That report is no longer on disk — analyze again.':
        'آن گزارش دیگر روی دیسک نیست — دوباره تحلیل کنید.',
    'The model returned nothing usable.': 'مدل چیز قابل‌استفاده‌ای برنگرداند.',
    '✓ Report ready — opened in your browser.':
        '✓ گزارش آماده است — در مرورگر شما باز شد.',
})

# ── Downloads ────────────────────────────────────────────────────────────
FA_STRINGS.update({
    'Downloads': 'دانلودها',
    'Videos downloaded from Search Archive and Niche Finder, with live progress.':
        'ویدیوهایی که از آرشیو جست‌وجو و یابنده‌ی نیچ دانلود کرده‌اید، با نمایش زنده‌ی پیشرفت.',
    'NO DOWNLOADS YET': 'هنوز دانلودی نیست',
    'Videos downloaded from Search Archive and Niche Finder will show up here, with live progress.':
        'ویدیوهایی که دانلود می‌کنید همین‌جا با نمایش زنده‌ی پیشرفت نشان داده می‌شوند.',
    'Remove': 'حذف',
    'Play': 'پخش',
    'Open video': 'باز کردن ویدیو در یوتیوب',
    'Download from a link': 'دانلود از روی لینک',
    'Paste a YouTube link (youtube.com/watch, youtu.be, /shorts/…)':
        'یک لینک یوتیوب را بچسبانید (youtube.com/watch، youtu.be، ‎/shorts/‎ …)',
    'Fetch & download': 'دریافت و دانلود',
    'Fetching…': 'در حال دریافت…',
    'Looking up video…': 'در حال یافتن ویدیو…',
    "That doesn't look like a YouTube video link.":
        'این آدرس شبیه لینک ویدیوی یوتیوب نیست.',
    'This video is already downloading.': 'این ویدیو هم‌اکنون در حال دانلود است.',
    "Couldn't fetch that video's details — check the link or your connection/proxy and try again.":
        'دریافت اطلاعات این ویدیو ممکن نشد — لینک یا اتصال/پروکسی را بررسی کنید و دوباره تلاش کنید.',
    'Updating downloader…': 'در حال به‌روزرسانی دانلودر…',
    'Retrying with another method…': 'تلاش دوباره با روشی دیگر…',
    'Trying browser cookies…': 'تلاش با کوکی مرورگر…',
    "YouTube blocked this download (bot check). Try a different VPN location, or set “Use cookies from browser” in Settings to a browser where you're signed in to YouTube, then download again.":
        'یوتیوب این دانلود را مسدود کرد (بررسی ربات). یک موقعیت VPN دیگر را امتحان کنید، یا در تنظیمات «کوکی مرورگر» را روی مرورگری که در آن به یوتیوب وارد شده‌اید تنظیم کنید و دوباره دانلود کنید.',
    "YouTube blocked this download. Close your browser (Chrome/Edge/Firefox) completely, then try the download again — the app can then use its YouTube login to get past the block.":
        'یوتیوب این دانلود را مسدود کرد. مرورگر خود (کروم/اج/فایرفاکس) را کاملاً ببندید و دوباره دانلود را امتحان کنید — آنگاه برنامه می‌تواند از لاگین یوتیوب شما برای عبور از مسدودیت استفاده کند.',
    "YouTube blocked this download (bot check). Sign in to YouTube in your browser, then set “Use cookies from browser” in Settings — or try a different VPN location — and download again.":
        'یوتیوب این دانلود را مسدود کرد (بررسی ربات). در مرورگر خود به یوتیوب وارد شوید، سپس در تنظیمات «کوکی مرورگر» را فعال کنید — یا موقعیت VPN دیگری را امتحان کنید — و دوباره دانلود کنید.',
    "YouTube only offered DRM-protected formats for this video, so it can't be downloaded. This sometimes clears up on its own — try again later, or set “Use cookies from browser” in Settings.":
        'یوتیوب برای این ویدیو فقط فرمت‌های محافظت‌شده با DRM ارائه داد، پس قابل دانلود نیست. گاهی خودبه‌خود درست می‌شود — بعداً دوباره امتحان کنید، یا در تنظیمات «کوکی مرورگر» را تنظیم کنید.',
    "DOWNLOAD COOKIES (helps with “Sign in to confirm you're not a bot” errors)":
        'کوکی دانلود (برای رفع خطای «برای تأیید ربات‌نبودن وارد شوید»)',
    'Off — no cookies': 'خاموش — بدون کوکی',
    "Pick the browser where you're signed in to YouTube. Close that browser before downloading if it locks its cookie file.":
        'مرورگری را انتخاب کنید که در آن به یوتیوب وارد شده‌اید. اگر مرورگر فایل کوکی را قفل می‌کند، پیش از دانلود آن را ببندید.',
    'Downloaded': 'دانلود شد',
    "Can't play video": 'پخش ویدیو ممکن نشد',
    "The downloaded file couldn't be found — it may have been moved or deleted.":
        'فایل دانلودشده پیدا نشد — ممکن است جابه‌جا یا حذف شده باشد.',
    'No in-app player is available on this install.':
        'پخش‌کننده‌ی داخلی روی این نسخه‌ی نصب در دسترس نیست.',
    'Choose quality': 'انتخاب کیفیت',
    'Best available': 'بهترین کیفیت موجود',
    'Highest resolution + best audio': 'بالاترین رزولوشن + بهترین صدا',
    '1080p': '۱۰۸۰p',
    'Full HD': 'فول‌اچ‌دی',
    '720p': '۷۲۰p',
    'HD — good balance of quality and size': 'اچ‌دی — تعادل خوب بین کیفیت و حجم',
    '480p': '۴۸۰p',
    'Standard definition — smallest video file': 'کیفیت استاندارد — کم‌حجم‌ترین فایل ویدیویی',
    'Audio only': 'فقط صدا',
    'MP3 — no video, smallest file': 'MP3 — بدون ویدیو، کم‌حجم‌ترین فایل',
    'RECOMMENDED': 'پیشنهادی',
    'Back 10s': '۱۰ ثانیه عقب',
    'Forward 10s': '۱۰ ثانیه جلو',
    'Mute': 'قطع صدا',
    'Unmute': 'پخش صدا',
    'Fullscreen': 'تمام‌صفحه',
    'Exit fullscreen': 'خروج از تمام‌صفحه',
})

# ── added: Downloads redesign, blueprint All/Short/Long, anti-hook, CSV keyword picker ──
FA_STRINGS.update({
    # Downloads — bulk selection + pagination + total
    'Select all': 'انتخاب همه',
    'Clear selection': 'پاک‌کردن انتخاب',
    'Delete selected ({n})': 'حذف انتخاب‌شده‌ها ({n})',
    'Remove {n} download(s)?': 'حذف {n} دانلود؟',
    'The selected entries will be removed from this list. The downloaded files on disk are not deleted.':
        'موارد انتخاب‌شده از این فهرست حذف می‌شوند. فایل‌های دانلودشده روی دیسک حذف نمی‌شوند.',
    'Removed {n} download(s).': '{n} دانلود حذف شد.',
    '{n} videos': '{n} ویدیو',
    '{shown} of {total} videos': '{shown} از {total} ویدیو',
    # Cutter — clip reel pager (v3.52)
    '{shown} of {total} clips': '{shown} از {total} کلیپ',
    # Blueprint rail — All / Short / Long tabs
    'Short': 'شورت',
    'Long': 'لانگ',
    # Anti-hook (short-form only)
    'ANTI-HOOK — {n} option(s)': 'ضدقلاب — {n} گزینه',
    'ANTI-HOOK': 'ضدقلاب',
    'A reverse-psychology opener that pushes the wrong viewer away, so the right one leans in — a swipe then feels like a loss.':
        'یک شروع مبتنی بر روان‌شناسی معکوس که مخاطب نامناسب را پس می‌زند تا مخاطب درست جذب شود — آنگاه رد کردن ویدیو مثل یک باخت حس می‌شود.',
    # CSV combine — keyword picker
    'PICK A KEYWORD / CHANNEL': 'یک کلیدواژه / کانال انتخاب کنید',
    'All keywords': 'همه‌ی کلیدواژه‌ها',
    'ALL BLUEPRINTS': 'همه‌ی بلوپرینت‌ها',
    'BLUEPRINTS IN “{k}”': 'بلوپرینت‌های «{k}»',
    'Select all here': 'انتخاب همه‌ی این‌ها',
})

# ── added: Usage & Quota redesign (template) ──
FA_STRINGS.update({
    'of {c} units': 'از {c} واحد',
    'RECENT DAILY AVERAGE': 'میانگین روزانه‌ی اخیر',
    'Units per day across the last 7 days of activity.': 'واحد در روز طی ۷ روز فعالیت اخیر.',
    'Consumption trend': 'روند مصرف',
    'Daily spend with a cumulative line — hover any day for the exact number':
        'مصرف روزانه با خط تجمعی — روی هر روز نگه دار تا عدد دقیقش را ببینی',
    '7 days': '۷ روز',
    '30 days': '۳۰ روز',
    'Peak day: {v} units': 'اوج روز: {v} واحد',
    'Where units go': 'واحدها کجا می‌روند',
    'last 30 days': '۳۰ روز اخیر',
    'units total': 'مجموع واحدها',
    'No spend recorded yet.': 'هنوز مصرفی ثبت نشده.',
    'Daily mix by call type': 'ترکیب روزانه بر اساس نوع تماس',
    'stacked, last 7 days': 'انباشته، ۷ روز اخیر',
    'spend follows the key': 'مصرف به کلید وابسته است',
    'Other calls': 'سایر تماس‌ها',
    'Untracked': 'ثبت‌نشده',
    'spend': 'مصرف',
    'cumulative': 'تجمعی',
})

# ── added: live language-switch pass — every remaining UI and backend
#    string that had no Persian text yet (QML pages, onboarding tour,
#    AI-provider errors, blueprint field labels, quota and usage copy) ──
FA_STRINGS.update({
    ' models.': ' مدل.',
    'A / B / C': 'الف / ب / پ',
    "A quick tour of the whole app — what each section does and the order you'd normally use them in. You can leave at any time with Skip, and reopen this from the ? button in the title bar.":
        'یک گشت سریع در کل برنامه — هر بخش چه کاری می‌کند و معمولاً به چه ترتیبی از آن‌ها استفاده می‌شود. هر لحظه می‌توانید با «رد کردن» بیرون بیایید و از دکمه‌ی ؟ در نوار عنوان دوباره بازش کنید.',
    'A straight yes or no — with evidence, certainty, RPM and projected revenue.':
        'یک بله یا خیر روشن — همراه با شواهد، میزان اطمینان، RPM و برآورد درآمد.',
    'AI Ideas · Blueprint Builder': 'ایده‌های هوش مصنوعی · سازنده‌ی بلوپرینت',
    'AI Ideas — turn finds into blueprints': 'ایده‌های هوش مصنوعی — تبدیل یافته‌ها به بلوپرینت',
    'AI Provider': 'سرویس‌دهنده‌ی هوش مصنوعی',
    'ALTERNATE TITLES': 'عنوان‌های جایگزین',
    'API Host OK — checking API key …': 'میزبان API سالم است — در حال بررسی کلید API …',
    'API Host is not reachable: {reason}': 'میزبان API در دسترس نیست: {reason}',
    'ASSETS NEEDED': 'چیزهایی که لازم دارید',
    'AUDIO & MUSIC': 'صدا و موسیقی',
    'Add a YouTube API key in Settings first.': 'اول در تنظیمات یک کلید API یوتیوب اضافه کنید.',
    'Add backup key': 'افزودن کلید پشتیبان',
    'Added to AI Ideas.': 'به ایده‌های هوش مصنوعی اضافه شد.',
    "Ads can't run on this channel yet, so there was nothing to ":
        'روی این کانال هنوز تبلیغ پخش نمی‌شود، پس چیزی برای ',
    'Ages': 'خیلی زیاد',
    'Already on the AI Ideas board.': 'از قبل روی تخته‌ی ایده‌های هوش مصنوعی هست.',
    'An error occurred:\n{e}\n\nScraped data was saved — you can ':
        'خطایی رخ داد:\n{e}\n\nداده‌های برداشت‌شده ذخیره شد — می‌توانید ',
    'Analyzing with {p} and folding in {n} blueprint(s) — ': 'تحلیل با {p} و ادغام {n} بلوپرینت — ',
    'Anthropic API error ({code}): {msg}': 'خطای API انتروپیک ({code}): {msg}',
    'Anthropic returned an empty response.': 'انتروپیک پاسخ خالی برگرداند.',
    'Applying …': 'در حال اعمال …',
    'Archiving failed.': 'آرشیو کردن انجام نشد.',
    'Asking {p} for {n} blueprint(s)…': 'درخواست {n} بلوپرینت از {p} …',
    'At {r} units/day, your recent average. Roughly {s} more ':
        'با {r} واحد در روز، یعنی میانگین اخیر شما. تقریباً {s} ',
    'Auto': 'خودکار',
    'Autosave Checkpoint': 'ذخیره‌ی خودکار میان‌راه',
    'BEST POSTING TIME': 'بهترین زمان انتشار',
    'Back': 'قبلی',
    'Backup key #': 'کلید پشتیبان #',
    'Be specific about the angle, tone and format you want — that is what the AI has to work with.':
        'دقیق بگویید چه زاویه، لحن و قالبی می‌خواهید — هوش مصنوعی فقط همین را در اختیار دارد.',
    'Browse': 'انتخاب پوشه',
    'Browser Cookies (for downloads)': 'کوکی مرورگر (برای دانلود)',
    'Build purely from what you describe — no videos used.':
        'فقط از توضیح خودتان ساخته می‌شود — هیچ ویدیویی استفاده نمی‌شود.',
    'Build the blueprints': 'ساختن بلوپرینت‌ها',
    'Built with an earlier version': 'با نسخه‌ی قدیمی‌تر ساخته شده',
    'CALL TO ACTION — {n} option(s)': 'فراخوان به اقدام — {n} گزینه',
    'CAPTION — {n} option(s)': 'کپشن — {n} گزینه',
    'CAPTURE PLAN': 'برنامه‌ی ضبط',
    'CHAPTERS': 'فصل‌ها',
    'CORE CONCEPT': 'ایده‌ی اصلی',
    'CPM (advertiser)': 'CPM (نرخ آگهی‌دهنده)',
    'Cache ignored': 'کش نادیده گرفته شد',
    'Certainty': 'میزان اطمینان',
    'Channel lookup': 'جست‌وجوی کانال',
    'Chart the last 30 days': 'نمودار ۳۰ روز اخیر',
    'Chart the last 7 days': 'نمودار ۷ روز اخیر',
    'Checking which qualities this video actually has…':
        'بررسی این‌که این ویدیو واقعاً چه کیفیت‌هایی دارد …',
    'Checking…': 'در حال بررسی …',
    'Clear the log view': 'پاک‌کردن نمای لاگ',
    'Clear view': 'پاک‌کردن نما',
    'Cleared the view. Your blueprints are still saved.':
        'نما پاک شد. بلوپرینت‌های شما هنوز ذخیره‌اند.',
    'Click Browse to choose …': 'برای انتخاب، «انتخاب پوشه» را بزنید …',
    'Collapse menu': 'جمع‌کردن منو',
    'Competition & content gap': 'رقابت و شکاف محتوایی',
    'Concept A': 'ایده‌ی الف',
    'Concept {x}': 'ایده‌ی {x}',
    'Copy the whole log': 'کپی کل لاگ',
    'Copy whole script': 'کپی کل متن',
    'Could not open': 'باز نشد',
    'Could not open: {e}': 'باز نشد: {e}',
    'Could not reach youtube.com. Check your connection ':
        'دسترسی به youtube.com ممکن نشد. اتصال خود را بررسی کنید ',
    'Could not resolve that channel. Try pasting ': 'این کانال شناسایی نشد. سعی کنید ',
    'Could not resolve that channel. Try pasting the ': 'این کانال شناسایی نشد. سعی کنید ',
    "Couldn't fetch that video's details — check the link or ":
        'جزئیات آن ویدیو گرفته نشد — لینک را بررسی کنید یا ',
    "Couldn't find where this blueprint is stored.": 'محل ذخیره‌ی این بلوپرینت پیدا نشد.',
    "Couldn't open the folder.": 'پوشه باز نشد.',
    "Couldn't read this video's formats — showing the ": 'قالب‌های این ویدیو خوانده نشد — در عوض ',
    'Custom / aggregator': 'سرویس اختصاصی / تجمیع‌کننده',
    'Custom AI': 'هوش مصنوعی اختصاصی',
    'Custom AI base URL is missing.': 'آدرس پایه‌ی هوش مصنوعی اختصاصی وارد نشده است.',
    'Default Save Folder': 'پوشه‌ی ذخیره‌ی پیش‌فرض',
    'Delete every export?': 'همه‌ی خروجی‌ها حذف شوند؟',
    'Delete failed: {e}': 'حذف انجام نشد: {e}',
    'Delete this export?': 'این خروجی حذف شود؟',
    'Deleted {name}.': '{name} حذف شد.',
    'Deleted {n} exports.': '{n} خروجی حذف شد.',
    'Describe the video you want to make, pick references that already perform, or both — and get full production blueprints back.':
        'ویدیویی که می‌خواهید بسازید را توصیف کنید، ویدیوهای مرجعی که از قبل عملکرد خوبی دارند را انتخاب کنید، یا هر دو — و بلوپرینت کامل تولید تحویل بگیرید.',
    'Describe your idea first.': 'اول ایده‌ی خود را توصیف کنید.',
    'Describe your idea in the box above.': 'ایده‌ی خود را در کادر بالا توصیف کنید.',
    'Done': 'پایان',
    'Download': 'دانلود',
    'Download quality': 'کیفیت دانلود',
    'Downloading…': 'در حال دانلود …',
    'EDITING & PACE': 'تدوین و ریتم',
    'ESTIMATED RUNWAY': 'برآورد دوام سهمیه',
    'Each card carries the numbers behind the find. Save it, grab the thumbnail, or download the video itself — the actions sit along the bottom of the card.':
        'هر کارت اعدادی را که آن یافته را ساخته نشان می‌دهد. می‌توانید ذخیره‌اش کنید، بندانگشتی‌اش را بگیرید، یا خود ویدیو را دانلود کنید — دکمه‌ها در پایین کارت هستند.',
    'Estimated ad revenue': 'برآورد درآمد تبلیغات',
    'Estimates only. YouTube never exposes real earnings; these are modelled from niche, audience market and public view velocity.':
        'فقط برآورد است. یوتیوب هرگز درآمد واقعی را منتشر نمی‌کند؛ این اعداد از حوزه، بازار مخاطب و سرعت بازدید عمومی مدل‌سازی شده‌اند.',
    'Every configured YouTube API key has already used up its daily ':
        'همه‌ی کلیدهای API یوتیوبی که تنظیم کرده‌اید سهمیه‌ی روزانه‌شان را تمام کرده‌اند ',
    'Every configured YouTube API key has used up its daily quota.\n\n':
        'همه‌ی کلیدهای API یوتیوبی که تنظیم کرده‌اید سهمیه‌ی روزانه‌شان را تمام کرده‌اند.\n\n',
    'Every search you run is stored here forever. Reopening one, re-filtering it or exporting it costs no quota at all.':
        'هر جست‌وجویی که اجرا می‌کنید برای همیشه اینجا می‌ماند. بازکردن، فیلترکردن دوباره یا گرفتن خروجی از آن هیچ سهمیه‌ای مصرف نمی‌کند.',
    'Every section lives here. The active one is highlighted with a red bar at the window edge. Collapse the rail with the button on the left of the title bar to give the page more room.':
        'همه‌ی بخش‌ها اینجا هستند. بخش فعال با یک نوار قرمز در لبه‌ی پنجره مشخص می‌شود. با دکمه‌ی سمت چپ نوار عنوان می‌توانید ریل را جمع کنید تا صفحه جای بیشتری بگیرد.',
    'Execution & production': 'اجرا و تولید',
    'Exhausted': 'تمام‌شده',
    'Expand menu': 'بازکردن منو',
    'Export Format': 'قالب خروجی',
    'Exported {n} rows.': '{n} ردیف خروجی گرفته شد.',
    'FILE': 'فایل',
    'FIRST 3 SECONDS — SAY THIS': 'سه ثانیه‌ی اول — این را بگویید',
    'FROM A SAVED SEARCH': 'از یک جست‌وجوی ذخیره‌شده',
    'Failed — link unavailable': 'ناموفق — لینک در دسترس نیست',
    'Fetch transcripts while scraping': 'گرفتن زیرنویس هم‌زمان با برداشت',
    'Fetching models …': 'در حال گرفتن فهرست مدل‌ها …',
    'Fetching the model list failed ({code}): {msg}':
        'گرفتن فهرست مدل‌ها انجام نشد ({code}): {msg}',
    'Filter titles …': 'فیلتر عنوان‌ها …',
    'From videos': 'از ویدیوها',
    'Full script': 'متن کامل',
    'Generating …': 'در حال ساخت …',
    'Green shots are B-roll — they exist to cover cuts, so shoot them last.':
        'پلان‌های سبز B-roll هستند — برای پوشاندن برش‌ها وجود دارند، پس آخر از همه ضبطشان کنید.',
    'HOW MANY': 'چه تعداد',
    'Heads up': 'توجه',
    'Healthy': 'سالم',
    'Heavy use': 'مصرف سنگین',
    'Hidden-sub channels shown': 'کانال‌های بدون تعداد مشترک نمایش داده می‌شوند',
    'Hook anatomy': 'کالبدشکافی هوک',
    'Idea generation failed.': 'ساخت ایده انجام نشد.',
    'In progress': 'در جریان',
    'It is still under the 500-subscriber floor for ': 'هنوز زیر آستانه‌ی ۵۰۰ مشترکِ لازم برای ',
    'It meets the subscriber and watch-time bars and ': 'شرط مشترک و ساعت تماشا را دارد و ',
    'KEYWORD SEARCHES': 'جست‌وجوهای کلیدواژه‌ای',
    'Key {n}': 'کلید {n}',
    'Keyword search': 'جست‌وجوی کلیدواژه',
    'LONG-FORM': 'بلندفرم',
    'Live Logs': 'لاگ زنده',
    'Live logs': 'لاگ زنده',
    'Load saved': 'بارکردن ذخیره‌شده',
    'Loaded ': 'بارگذاری شد ',
    'Log copied to clipboard.': 'لاگ در کلیپ‌بورد کپی شد.',
    'Manage keys': 'مدیریت کلیدها',
    'Medium': 'متوسط',
    'Model': 'مدل',
    'Monetization check failed.': 'بررسی درآمدزایی انجام نشد.',
    'My idea + videos': 'ایده‌ی من + ویدیوها',
    'My idea only': 'فقط ایده‌ی من',
    'My ideas': 'ایده‌های من',
    'NARRATION': 'روایت',
    'Needs a key before it can guess.': 'تا کلیدی نباشد نمی‌تواند حدس بزند.',
    'Network error contacting Anthropic: {reason}': 'خطای شبکه در تماس با انتروپیک: {reason}',
    'Network error contacting {provider}: {reason}': 'خطای شبکه در تماس با {provider}: {reason}',
    'Network error fetching models: {reason}': 'خطای شبکه در گرفتن فهرست مدل‌ها: {reason}',
    'New Scrape': 'برداشت تازه',
    'Next': 'بعدی',
    'Niche': 'حوزه',
    'Niche Finder — the outlier hunt': 'نیچ فایندر — شکار آوتلایرها',
    'YouTube Hunter': 'یوتیوب هانتر',
    'No AI provider configured — add a key in Settings to generate blueprints.':
        'هیچ سرویس هوش مصنوعی تنظیم نشده — برای ساخت بلوپرینت در تنظیمات یک کلید اضافه کنید.',
    'No API key yet — add one in Settings to start tracking.':
        'هنوز کلید API ندارید — برای شروع پیگیری در تنظیمات یکی اضافه کنید.',
    'No YouTube API key — set one in Settings.':
        'کلید API یوتیوب ندارید — در تنظیمات یکی وارد کنید.',
    'No activity yet. Start a scrape from the Scraper page.':
        'هنوز فعالیتی نیست. از صفحه‌ی برداشت یک اجرا شروع کنید.',
    'No activity yet. Start a scrape.': 'هنوز فعالیتی نیست. یک برداشت شروع کنید.',
    'No ad slots came back on the {m} recent videos checked — the ':
        'روی {m} ویدیوی اخیرِ بررسی‌شده هیچ جایگاه تبلیغی برنگشت — ',
    'No blueprints yet': 'هنوز بلوپرینتی نیست',
    'No download matches “{q}”. Try another title or channel.':
        'هیچ دانلودی با «{q}» نمی‌خورد. عنوان یا کانال دیگری را امتحان کنید.',
    'No exports found': 'خروجی‌ای پیدا نشد',
    'No favorited blueprints yet.': 'هنوز بلوپرینت نشان‌دار‌ی نیست.',
    'No key': 'بدون کلید',
    'No keys configured yet.': 'هنوز کلیدی تنظیم نشده.',
    'No model selected yet — press Fetch to pull the model list, or type one.':
        'هنوز مدلی انتخاب نشده — «گرفتن» را بزنید تا فهرست مدل‌ها بیاید، یا خودتان تایپ کنید.',
    'No result matches these filters — widen the subscriber or ':
        'هیچ نتیجه‌ای با این فیلترها نمی‌خورد — بازه‌ی مشترک یا ',
    'No save folder yet': 'هنوز پوشه‌ی ذخیره‌ای نیست',
    'No saved blueprints for “{kw}” yet.': 'هنوز بلوپرینت ذخیره‌شده‌ای برای «{kw}» نیست.',
    'No search-quota cost': 'بدون هزینه‌ی سهمیه‌ی جست‌وجو',
    'No spend recorded this week — nothing to burn through yet.':
        'این هفته مصرفی ثبت نشده — هنوز چیزی برای سوزاندن نیست.',
    'No videos match this filter.': 'هیچ ویدیویی با این فیلتر نمی‌خورد.',
    'Not used in this mode — switch to “My idea + videos” or “My idea only” to write a brief.':
        'در این حالت استفاده نمی‌شود — برای نوشتن بریف به «ایده‌ی من + ویدیوها» یا «فقط ایده‌ی من» بروید.',
    'Not used in this mode — the blueprints come from your brief alone.':
        'در این حالت استفاده نمی‌شود — بلوپرینت‌ها فقط از بریف شما ساخته می‌شوند.',
    'Nothing archived yet — run a Niche Finder search and it shows up here automatically.':
        'هنوز چیزی آرشیو نشده — یک جست‌وجوی نیچ فایندر اجرا کنید تا خودکار اینجا بیاید.',
    'Nothing cached yet. Every search you run gets stored, and ':
        'هنوز چیزی کش نشده. هر جست‌وجویی که اجرا کنید ذخیره می‌شود و ',
    'Nothing checked yet': 'هنوز چیزی بررسی نشده',
    'Nothing here yet': 'هنوز چیزی اینجا نیست',
    'Nothing that requires the Partner Program is switched ':
        'هیچ قابلیتی که به برنامه‌ی همکاری نیاز داشته باشد روشن ',
    'Notification': 'اطلاع',
    'OK': 'باشه',
    'ON SCREEN — {n} option(s)': 'روی تصویر — {n} گزینه',
    'OPENING': 'شروع',
    'Only the qualities this video actually has are listed. ':
        'فقط کیفیت‌هایی که این ویدیو واقعاً دارد فهرست شده‌اند. ',
    'Only the qualities this video actually has are listed. Plain sizes are exact; ≈ marks an estimate.':
        'فقط کیفیت‌هایی که این ویدیو واقعاً دارد فهرست شده‌اند. اندازه‌های بدون علامت دقیق‌اند؛ ≈ یعنی تخمینی.',
    'Only the qualities this video actually has are listed. Sizes are of the finished file; ≈ marks a conversion whose size can only be estimated.':
        'فقط کیفیت‌هایی که این ویدیو واقعاً دارد فهرست شده‌اند. حجم‌ها مربوط به فایل نهایی‌اند؛ ≈ یعنی فایل تبدیل می‌شود و حجمش تخمینی است.',
    'Open channel': 'بازکردن کانال',
    'Output & Scrape Preferences': 'خروجی و تنظیمات برداشت',
    'POSITIONING': 'جایگاه‌یابی',
    'POST': 'پست',
    'PROXY (optional)': 'پروکسی (اختیاری)',
    'PSYCHOLOGICAL TRIGGERS': 'محرک‌های روانی',
    'PUBLISH': 'انتشار',
    'Packaging & call to action': 'بسته‌بندی و فراخوان به اقدام',
    "Paste a channel URL, @handle or name above. You'll get the verdict, the signals behind it, and an RPM-based revenue range.":
        'آدرس کانال، @هندل یا نام آن را بالا بچسبانید. حکم، سیگنال‌های پشت آن، و بازه‌ی درآمد بر پایه‌ی RPM را می‌گیرید.',
    'Paste a channel URL, @handle or name and press Check.':
        'آدرس کانال، @هندل یا نام آن را بچسبانید و «بررسی» را بزنید.',
    'Paste a link above and your downloads will show up here with live progress.':
        'یک لینک بالا بچسبانید تا دانلودهایتان با پیشرفت زنده اینجا بیایند.',
    'Paste a link — everything lands on your Desktop with live progress.':
        'یک لینک بچسبانید — همه‌چیز با پیشرفت زنده روی دسکتاپ شما می‌آید.',
    'Paste your YouTube API key here, and pick an AI provider for the idea and report features. You can replay this tour any time from the bottom of this page.':
        'کلید API یوتیوب خود را اینجا بچسبانید و برای قابلیت‌های ایده و گزارش یک سرویس هوش مصنوعی انتخاب کنید. این گشت را هر وقت خواستید از پایین همین صفحه می‌توانید دوباره ببینید.',
    'Pick a keyword section, or just describe your idea below.':
        'یک بخش کلیدواژه انتخاب کنید، یا همین پایین ایده‌ی خود را توصیف کنید.',
    'Pick a saved search above to choose reference videos.':
        'برای انتخاب ویدیوهای مرجع، یکی از جست‌وجوهای ذخیره‌شده‌ی بالا را انتخاب کنید.',
    'Pick an idea to open its full production plan below.':
        'یک ایده را انتخاب کنید تا برنامه‌ی کامل تولیدش پایین باز شود.',
    'Point this at a channel URL or a keyword, set how many videos to take, and start. Everything else in the app works from what you extract here.':
        'این را روی آدرس یک کانال یا یک کلیدواژه بگذارید، تعداد ویدیوهایی که می‌خواهید تعیین کنید و شروع کنید. بقیه‌ی برنامه از همین داده‌ای که اینجا برمی‌دارید کار می‌کند.',
    'Production: {d}': 'تولید: {d}',
    'Provider': 'سرویس‌دهنده',
    'RENDER & EXPORT': 'رندر و خروجی',
    'ROWS': 'ردیف',
    'RPM / 1K views': 'RPM به ازای هر ۱۰۰۰ بازدید',
    'Ready — building from your idea alone.': 'آماده — فقط از ایده‌ی خودتان ساخته می‌شود.',
    'Ready — {n} reference video(s) selected.': 'آماده — {n} ویدیوی مرجع انتخاب شد.',
    'Real qualities and sizes are checked before you pick.':
        'کیفیت‌ها و حجم‌های واقعی قبل از انتخاب شما بررسی می‌شوند.',
    'Real-time output from the active extraction worker.': 'خروجی زنده‌ی کارگرِ برداشتِ فعال.',
    'Rebuild in full': 'بازسازی کامل',
    'Rebuilding “{t}” with the full blueprint…': 'بازسازی «{t}» با بلوپرینت کامل …',
    'Rebuilding …': 'در حال بازسازی …',
    'Reference videos': 'ویدیوهای مرجع',
    'Regenerate this blueprint': 'ساخت دوباره‌ی این بلوپرینت',
    'Remove this download?': 'این دانلود حذف شود؟',
    'Removed from downloads.': 'از دانلودها حذف شد.',
    'Reopening an archive': 'بازکردن یک آرشیو',
    'Replay the guided tour': 'دیدن دوباره‌ی گشت راهنما',
    'Resets at {t} your time': 'به وقت شما در {t} صفر می‌شود',
    'Resolving channel…': 'در حال شناسایی کانال …',
    'Result cards': 'کارت‌های نتیجه',
    'Resuming: {done} videos restored from checkpoint, ':
        'ادامه: {done} ویدیو از نقطه‌ی ذخیره برگردانده شد، ',
    'Retention pacing': 'ریتم نگه‌داشت مخاطب',
    'Reverse-engineer what the videos you picked have in common.':
        'بازمهندسیِ آن چیزی که ویدیوهای انتخاب‌شده‌ی شما در آن مشترک‌اند.',
    'Review or open past extraction exports.': 'خروجی‌های برداشت‌های گذشته را ببینید یا باز کنید.',
    'SAVED': 'ذخیره‌شده',
    'SEARCH': 'جست‌وجو',
    'SEO & discoverability': 'سئو و کشف‌شدن',
    'SHORTS': 'شورتس',
    'SIZE': 'حجم',
    'STRATEGY': 'استراتژی',
    'Save Settings': 'ذخیره‌ی تنظیمات',
    'Saved automatically — this blueprint is in your Content Lab library.':
        'خودکار ذخیره شد — این بلوپرینت در کتابخانه‌ی کانتنت لبِ شماست.',
    'Scanning recent uploads for ad breaks…': 'بررسی آپلودهای اخیر برای جایگاه‌های تبلیغ …',
    'Scraped {n} videos ({suffix})  ·  Transcripts: {tc}/{n}':
        '{n} ویدیو برداشت شد ({suffix})  ·  زیرنویس: {tc}/{n}',
    'Scraper': 'برداشت',
    'Scraper — pull the raw data': 'برداشت — گرفتن داده‌ی خام',
    'Search Archive — nothing is bought twice': 'آرشیو جست‌وجو — هیچ‌چیز دو بار خریده نمی‌شود',
    'Search all of YouTube for a niche, then filter by subscribers, views and time window to surface small channels pulling huge numbers.':
        'کل یوتیوب را برای یک حوزه جست‌وجو کنید، بعد بر اساس مشترک، بازدید و بازه‌ی زمانی فیلتر کنید تا کانال‌های کوچکی که اعداد بزرگ می‌زنند بیرون بیایند.',
    'Search all of YouTube, then filter by subscribers, views and time window. The multiplier is views divided by subscriber count — a high one means a small channel pulling numbers well above its size.':
        'کل یوتیوب را جست‌وجو کنید، بعد بر اساس مشترک، بازدید و بازه‌ی زمانی فیلتر کنید. ضریب یعنی بازدید تقسیم بر تعداد مشترک — ضریب بالا یعنی کانالی کوچک که اعدادی خیلی بالاتر از اندازه‌اش می‌زند.',
    'Search file or source': 'جست‌وجوی فایل یا منبع',
    'Search titles or channels': 'جست‌وجوی عنوان یا کانال',
    'Select a save folder on the Scraper page to see history here.':
        'برای دیدن تاریخچه، در صفحه‌ی برداشت یک پوشه‌ی ذخیره انتخاب کنید.',
    'Settings saved.': 'تنظیمات ذخیره شد.',
    'Settings — set this up first': 'تنظیمات — اول این را راه بیندازید',
    'Shot list': 'فهرست پلان‌ها',
    'Show the guided tour': 'نمایش گشت راهنما',
    'Showing the first {n} — narrow the filters to reach the rest.':
        'فقط {n} مورد اول نشان داده می‌شود — برای رسیدن به بقیه فیلترها را تنگ‌تر کنید.',
    'Skip': 'رد کردن',
    "Some of YouTube's pages wouldn't load for this check, so the ":
        'بعضی از صفحه‌های یوتیوب برای این بررسی بار نشدند، پس ',
    'Subs ≤ {v}': 'مشترک ≤ {v}',
    'Subs ≥ {v}': 'مشترک ≥ {v}',
    'Subscriber data is unavailable — add an API key ':
        'داده‌ی مشترک در دسترس نیست — یک کلید API اضافه کنید ',
    'Success': 'موفق',
    'Switch to English': 'تغییر به انگلیسی',
    'Switch to Persian': 'تغییر به فارسی',
    'Switch to dark theme': 'تغییر به تم تیره',
    'Switch to light theme': 'تغییر به تم روشن',
    'Switching language …': 'در حال تغییر زبان …',
    'TAGS': 'برچسب‌ها',
    'TARGET KEYWORDS': 'کلیدواژه‌های هدف',
    'TEXT HOOK': 'هوک متنی',
    'TITLE FORMULA': 'فرمول عنوان',
    "TODAY'S API UNITS": 'واحدهای API امروز',
    'Test these against each other rather than picking the first — thumbnail is the single biggest lever on click-through.':
        'این‌ها را به جای انتخاب اولی، در برابر هم آزمایش کنید — بندانگشتی بزرگ‌ترین اهرم روی نرخ کلیک است.',
    'That video is no longer queued.': 'آن ویدیو دیگر در صف نیست.',
    'The AI studies what these have in common and designs new videos from that pattern.':
        'هوش مصنوعی بررسی می‌کند این‌ها در چه چیزی مشترک‌اند و از همان الگو ویدیوهای تازه طراحی می‌کند.',
    'The API': 'این API',
    'The download queue with live progress. Pick a quality per video, and open the finished file or its folder straight from the row.':
        'صف دانلود با پیشرفت زنده. برای هر ویدیو یک کیفیت انتخاب کنید و فایل آماده یا پوشه‌اش را مستقیم از همان ردیف باز کنید.',
    "The file couldn't be found — it may have been ": 'فایل پیدا نشد — ممکن است ',
    "The models endpoint didn't return valid JSON — double-check ":
        'اندپوینت مدل‌ها JSON معتبر برنگرداند — دوباره بررسی کنید ',
    'The navigation rail': 'ریل ناوبری',
    'The selected save folder does not exist anymore.\n':
        'پوشه‌ی ذخیره‌ی انتخاب‌شده دیگر وجود ندارد.\n',
    'The worker reports every step here as it runs: pages fetched, retries, quota warnings and where the export was written. Copy the whole buffer or clear the view from the header buttons.':
        'کارگر هر مرحله را همین‌جا گزارش می‌دهد: صفحه‌های گرفته‌شده، تلاش‌های مجدد، هشدارهای سهمیه و محل نوشتن خروجی. با دکمه‌های سربرگ می‌توانید کل لاگ را کپی یا نما را پاک کنید.',
    'Their angle:': 'زاویه‌ی آن‌ها:',
    "This API didn't return any models.": 'این API هیچ مدلی برنگرداند.',
    'This blueprint has no full script, shot list or competitor breakdown — those came later. Rebuilding keeps the same idea and adds them.':
        'این بلوپرینت متن کامل، فهرست پلان و تحلیل رقبا ندارد — آن‌ها بعداً اضافه شدند. بازسازی همان ایده را نگه می‌دارد و این‌ها را اضافه می‌کند.',
    'This can take a few minutes — each blueprint is a full production plan. You can leave the page; the run continues.':
        'این کار می‌تواند چند دقیقه طول بکشد — هر بلوپرینت یک برنامه‌ی کامل تولید است. می‌توانید صفحه را ترک کنید؛ اجرا ادامه پیدا می‌کند.',
    'This entry will be removed from the list. The downloaded file on disk is not deleted.':
        'این مورد از فهرست حذف می‌شود. فایل دانلودشده روی دیسک حذف نمی‌شود.',
    'This file will be permanently deleted from your save folder. This cannot be undone.':
        'این فایل برای همیشه از پوشه‌ی ذخیره‌ی شما حذف می‌شود. این کار برگشت‌پذیر نیست.',
    'This permanently removes every export file in your save folder. This cannot be undone.':
        'این کار همه‌ی فایل‌های خروجی را برای همیشه از پوشه‌ی ذخیره‌ی شما حذف می‌کند. برگشت‌پذیر نیست.',
    'This section is being rebuilt in the new interface.': 'این بخش در رابط تازه بازسازی می‌شود.',
    "This video is missing channel info, so it can't be filed ":
        'این ویدیو اطلاعات کانال ندارد، پس نمی‌شود ',
    'This window is wider than the one you searched — ':
        'این پنجره از پنجره‌ای که در آن جست‌وجو کردید پهن‌تر است — ',
    'Thumbnail concepts': 'ایده‌های بندانگشتی',
    'Tick at least one reference video first.': 'اول حداقل یک ویدیوی مرجع را تیک بزنید.',
    'Tick at least one reference video.': 'حداقل یک ویدیوی مرجع را تیک بزنید.',
    'Tick the reference videos whose style you want to borrow, describe your angle, and the AI returns full blueprints: titles, hooks, structure and a shot list.':
        'ویدیوهای مرجعی که می‌خواهید سبکشان را قرض بگیرید تیک بزنید، زاویه‌ی خود را توصیف کنید، و هوش مصنوعی بلوپرینت کامل تحویل می‌دهد: عنوان، هوک، ساختار و فهرست پلان.',
    'Tick the videos whose style you want to borrow.':
        'ویدیوهایی که می‌خواهید سبکشان را قرض بگیرید تیک بزنید.',
    'Tier {n}': 'رده‌ی {n}',
    'Top 5': '۵ تای برتر',
    'Try a different search or filter — completed extractions land here automatically.':
        'جست‌وجو یا فیلتر دیگری را امتحان کنید — برداشت‌های تمام‌شده خودکار اینجا می‌آیند.',
    'Two tabs: your saved blueprint library, and CSV Analysis — hand it a scraped export and get back a complete channel report as a self-contained HTML page.':
        'دو زبانه: کتابخانه‌ی بلوپرینت‌های ذخیره‌شده‌ی شما، و تحلیل CSV — یک خروجی برداشت‌شده بدهید و یک گزارش کامل کانال به‌صورت صفحه‌ی HTML مستقل بگیرید.',
    'Unknown AI provider: {p}': 'سرویس هوش مصنوعی ناشناخته: {p}',
    'Untouched': 'دست‌نخورده',
    'Usage & Quota': 'مصرف و سهمیه',
    'VISUAL HOOK': 'هوک تصویری',
    'VOICEOVER': 'صداگذاری',
    'Validate': 'بررسی',
    'Validate AI key': 'بررسی کلید هوش مصنوعی',
    'Video stats': 'آمار ویدیو',
    'Videos to borrow style from': 'ویدیوهایی که سبکشان قرض گرفته می‌شود',
    'Views ÷ subs ≥ {v}': 'بازدید ÷ مشترک ≥ {v}',
    'Views ≤ {v}': 'بازدید ≤ {v}',
    'Views ≥ {v}': 'بازدید ≥ {v}',
    'Viral angle': 'زاویه‌ی وایرال',
    'Welcome to YouTube Hunter': 'به یوتیوب هانتر خوش آمدید',
    'What should the AI build from?': 'هوش مصنوعی از چه چیزی بسازد؟',
    'What they miss:': 'چیزی که جا انداخته‌اند:',
    'What things cost': 'هزینه‌ی هر چیز',
    'What this install has spent, and when it runs out.':
        'این نسخه چقدر مصرف کرده و کِی تمام می‌شود.',
    'Why this works': 'چرا این جواب می‌دهد',
    'Worker Threads': 'تعداد رشته‌های کاری',
    'Write your idea, pick some references, or both — then Create with AI.':
        'ایده‌ی خود را بنویسید، چند مرجع انتخاب کنید، یا هر دو — بعد «ساخت با هوش مصنوعی» را بزنید.',
    'YOUR OPENING': 'شروع شما',
    'YOUTUBE DAILY': 'سهمیه‌ی روزانه‌ی یوتیوب',
    'YouTube API Management': 'مدیریت API یوتیوب',
    'YouTube API quota exhausted for today. Switch the data source ':
        'سهمیه‌ی API یوتیوب برای امروز تمام شد. منبع داده را عوض کنید ',
    'YouTube bills in units, not in requests':
        'یوتیوب بر اساس واحد صورت‌حساب می‌دهد، نه بر اساس درخواست',
    'YouTube bills in units, not requests — a keyword search costs 100, video stats cost 1 per 50 videos. This card is always in view; click it for the full Usage & Quota breakdown.':
        'یوتیوب بر اساس واحد صورت‌حساب می‌دهد نه درخواست — یک جست‌وجوی کلیدواژه ۱۰۰ واحد و آمار ویدیو ۱ واحد به ازای هر ۵۰ ویدیو هزینه دارد. این کارت همیشه در دید است؛ برای تفکیک کامل روی آن کلیک کنید.',
    'YouTube blocked this download (bot check). Sign in to ':
        'یوتیوب این دانلود را مسدود کرد (بررسی ربات). وارد حساب شوید تا ',
    'YouTube blocked this download. Close your browser ':
        'یوتیوب این دانلود را مسدود کرد. مرورگر خود را ببندید ',
    'YouTube only offered DRM-protected formats for this ':
        'یوتیوب برای این مورد فقط قالب‌های محافظت‌شده با DRM داد ',
    'YouTube returned a page this app could not read. ':
        'یوتیوب صفحه‌ای برگرداند که این برنامه نتوانست بخواند. ',
    'Your API keys': 'کلیدهای API شما',
    'Your YouTube quota': 'سهمیه‌ی یوتیوب شما',
    'Your blueprints': 'بلوپرینت‌های شما',
    'Your idea is the subject; the videos only lend their style.':
        'ایده‌ی شما موضوع است؛ ویدیوها فقط سبکشان را قرض می‌دهند.',
    'Your idea stays the subject; these only lend their hook style, pacing and packaging.':
        'ایده‌ی شما موضوع می‌ماند؛ این‌ها فقط سبک هوک، ریتم و بسته‌بندی‌شان را قرض می‌دهند.',
    'Your idea, in your own words': 'ایده‌ی شما، به زبان خودتان',
    'active': 'فعال',
    'always free': 'همیشه رایگان',
    'done': 'انجام‌شده',
    "e.g. I want to make a series where I try a different street food every day for 30 days. Fast cuts, lots of reactions, ends on a cliffhanger about tomorrow's dish. I want the titles to feel like a challenge, not a review.":
        'مثلاً: می‌خواهم یک سری بسازم که ۳۰ روز، هر روز یک غذای خیابانی متفاوت را امتحان کنم. برش‌های سریع، واکنش زیاد، و پایان با یک تعلیق درباره‌ی غذای فردا. می‌خواهم عنوان‌ها حس چالش بدهند، نه نقد.',
    'files': 'فایل',
    'latest': 'آخرین',
    'of {n} units': 'از {n} واحد',
    'older version': 'نسخه‌ی قدیمی‌تر',
    'per 50 channels': 'هر ۵۰ کانال',
    'per 50 videos': 'هر ۵۰ ویدیو',
    'per search page': 'هر صفحه‌ی جست‌وجو',
    'rows': 'ردیف',
    'step {i} / {n}': 'گام {i} از {n}',
    'total': 'مجموع',
    'units': 'واحد',
    'views / month': 'بازدید در ماه',
    '{d} days': '{d} روز',
    '{h} hours': '{h} ساعت',
    '{n} lines': '{n} خط',
    '{n} monetization feature(s) that only Partner ':
        '{n} قابلیت درآمدزایی که فقط با برنامه‌ی همکاری ',
    '{n} new blueprint(s) generated.': '{n} بلوپرینت تازه ساخته شد.',
    '{n} saved blueprint(s) for “{kw}”.': '{n} بلوپرینت ذخیره‌شده برای «{kw}».',
    '{n} searches are cached locally. Reopening any of them from the Search Archive costs nothing — that is {u} units of quota you never have to spend twice.':
        '{n} جست‌وجو به‌صورت محلی کش شده. بازکردن هرکدام از آن‌ها از آرشیو جست‌وجو هیچ هزینه‌ای ندارد — یعنی {u} واحد سهمیه که هرگز لازم نیست دوبار خرج کنید.',
    '{n} searches left today · each API-source Niche Finder search adds one; Web scrape adds none (100 units each, the priciest call there is)':
        '{n} جست‌وجو برای امروز باقی است · هر جست‌وجوی نیچ فایندر با منبع «API» یک عدد اضافه می‌کند؛ منبع «اسکرپ» سهمیه نمی‌خورد (هر کدام ۱۰۰ واحد، گران‌ترین فراخوانی که وجود دارد)',
    '{n} subscribers — the Partner Program needs 500 to apply, ':
        '{n} مشترک — برنامه‌ی همکاری برای درخواست به ۵۰۰ نیاز دارد، ',
    '{n} videos in “{kw}”. Tick the ones to use.':
        '{n} ویدیو در «{kw}». آن‌هایی که می‌خواهید استفاده شوند را تیک بزنید.',
    '{provider} API error ({code}): {msg}': 'خطای API {provider} ({code}): {msg}',
    '{provider} API key is missing.': 'کلید API {provider} وارد نشده است.',
    '{provider} returned an empty response.': '{provider} پاسخ خالی برگرداند.',
    "{provider} sent back a response that isn't valid JSON — ":
        '{provider} پاسخی برگرداند که JSON معتبر نیست — ',
    '{provider} took longer than {timeout}s to respond, so the ':
        '{provider} بیش از {timeout} ثانیه طول داد تا پاسخ دهد، پس ',
    '{provider}: no model name is set. Aggregator/custom ':
        '{provider}: نام مدل تنظیم نشده است. اندپوینت‌های تجمیع‌کننده/اختصاصی ',
    '{p}% spent · {r} units left across {n} key(s) · one search = 100 units, any other call = 1':
        '{p}٪ مصرف شده · {r} واحد در {n} کلید باقی است · یک جست‌وجو = ۱۰۰ واحد؛ بقیه‌ی فراخوانی‌ها = ۱ واحد',
    '~{c} search calls · {left} left today': '~{c} فراخوان جست‌وجو · {left} باقی برای امروز',
    '~{n} Shorts views in the last 90 days — past the 10M that opens ':
        '~{n} بازدید شورتس در ۹۰ روز اخیر — بالاتر از ۱۰ میلیونی که ',
    '~{n} Shorts views in the last 90 days — short of the 10M that ':
        '~{n} بازدید شورتس در ۹۰ روز اخیر — کمتر از ۱۰ میلیونی که ',
    '~{n} public watch hours a year (estimated) — past the 4,000 ':
        '~{n} ساعت تماشای عمومی در سال (برآورد) — بالاتر از ۴٬۰۰۰ ',
    '~{n} public watch hours a year (estimated) — under the 4,000 ':
        '~{n} ساعت تماشای عمومی در سال (برآورد) — زیر ۴٬۰۰۰ ',
    '“{n}” will be permanently deleted from your save folder. This cannot be undone.':
        '«{n}» برای همیشه از پوشه‌ی ذخیره‌ی شما حذف می‌شود. این کار برگشت‌پذیر نیست.',
    '“{t}” will be removed from this list. The downloaded file on disk is not deleted.':
        '«{t}» از این فهرست حذف می‌شود. فایل دانلودشده روی دیسک حذف نمی‌شود.',
    '…': '…',
    '✓ Blueprint rebuilt with the full production plan.':
        '✓ بلوپرینت با برنامه‌ی کامل تولید بازسازی شد.',
    '✓ {n} blueprint(s) ready.': '✓ {n} بلوپرینت آماده شد.',
})

# ── added: AI-provider connection card (API mode, editable host/path/model,
#    endpoint preview) and the Gemini video-watching option ──
FA_STRINGS.update({
    'API mode': 'حالت API',
    'Gemini watches the top videos of a CSV before writing its report — one request per video, so it costs minutes and quota but the analysis is far more concrete.':
        'جمینای پیش از نوشتن گزارش، ویدیوهای برترِ فایل CSV را تماشا می‌کند — برای هر ویدیو یک درخواست، پس چند دقیقه و مقداری سهمیه هزینه دارد اما تحلیل خیلی مشخص‌تر می‌شود.',
    'Loaded {n} models.': '{n} مدل بارگذاری شد.',
    'Off': 'خاموش',
    'Only Google Gemini can watch videos. Switch the provider above to enable this.':
        'فقط گوگل جمینای می‌تواند ویدیو تماشا کند. برای فعال‌شدن، سرویس‌دهنده‌ی بالا را عوض کنید.',
    'PROVIDER NAME (optional)': 'نام سرویس‌دهنده (اختیاری)',
    'Requests go to: {url}': 'درخواست‌ها به این آدرس می‌روند: {url}',
    "Sends Anthropic's /v1/messages request, with the key in an x-api-key header.":
        'درخواست /v1/messages انتروپیک را می‌فرستد، با کلید در هدر x-api-key.',
    "Sends Google's generateContent request. The model id goes in the URL, so API Path is unused.":
        'درخواست generateContent گوگل را می‌فرستد. شناسه‌ی مدل داخل آدرس می‌آید، پس «مسیر API» استفاده نمی‌شود.',
    "Sends OpenAI's /chat/completions request, with the key as a bearer token.":
        'درخواست /chat/completions اوپن‌ای‌آی را می‌فرستد، با کلید به‌عنوان توکن bearer.',
    'Watch videos for CSV reports': 'تماشای ویدیوها برای گزارش‌های CSV',
    'exact model id': 'شناسه‌ی دقیق مدل',
    'not used for this API mode': 'در این حالت API استفاده نمی‌شود',
    'recommended': 'پیشنهادی',
})

# ── added: per-provider capability note on the AI Ideas / Content Lab pages ──
FA_STRINGS.update({
    'Gemini can also search the web and watch videos, so its reports and ideas draw on more than the numbers.':
        'جمینای می‌تواند وب را هم جست‌وجو کند و ویدیوها را تماشا کند، پس گزارش‌ها و ایده‌هایش به چیزی بیشتر از اعداد تکیه دارند.',
    'Ideas and reports work with {provider}; web research and video watching are Gemini-only.':
        'ایده‌ها و گزارش‌ها با {provider} کار می‌کنند؛ تحقیق وب و تماشای ویدیو فقط با جمینای ممکن است.',
})

# ── added: Gemini video-watching progress lines for the CSV report ──
FA_STRINGS.update({
    'Watching video {i} of {n} …': 'تماشای ویدیوی {i} از {n} …',
    'Writing the report …': 'در حال نوشتن گزارش …',
})

# ── added: pre-run notice on the CSV tab when Gemini will watch videos ──
FA_STRINGS.update({
    'Gemini will watch this channel\'s best videos first — Shorts in full, and the middle minutes of longer ones — so expect several minutes before the report appears.':
        'جمینای اول بهترین ویدیوهای این کانال را تماشا می‌کند — شورت‌ها را کامل و بخش میانی ویدیوهای بلند را — پس تا آماده شدن گزارش چند دقیقه طول می‌کشد.',
})

# ── added: hover tooltips on the icon-only row/card actions ──
FA_STRINGS.update({
    'Clear the search': 'پاک‌کردن جست‌وجو',
    'Copy': 'کپی',
    'Copy the link': 'کپی لینک',
    'Copy the whole log': 'کپی کل لاگ',
    'Delete this export from disk': 'حذف این خروجی از دیسک',
    'Delete this section': 'حذف این بخش',
    'Delete this section and its blueprints': 'حذف این بخش و بلوپرینت‌هایش',
    'Filter by subscriber and view range': 'فیلتر بر اساس بازه‌ی مشترک و بازدید',
    'Open on YouTube': 'بازکردن در یوتیوب',
    'Play the file': 'پخش فایل',
    'Reload the archive': 'بارگذاری دوباره‌ی آرشیو',
    'Remove from favourites': 'حذف از علاقه‌مندی‌ها',
    'Remove from this list': 'حذف از این فهرست',
    'Rename this section': 'تغییر نام این بخش',
    'Resume at the same quality': 'ادامه با همان کیفیت',
    'Save to favourites': 'ذخیره در علاقه‌مندی‌ها',
    'Send to AI Ideas as a reference': 'فرستادن به ایده‌های هوش مصنوعی به‌عنوان مرجع',
    'Show in folder': 'نمایش در پوشه',
    'Stop this download': 'توقف این دانلود',
})

# ── added: field hints (the (?) markers) on the Scraper and Settings forms ──
FA_STRINGS.update({
    'A channel URL, @handle, /channel/UC… id, or a single video URL. Leave this empty to search all of YouTube with the query instead.':
        'آدرس کانال، @هندل، شناسه‌ی /channel/UC… یا آدرس یک ویدیو. اگر خالی بگذارید، به‌جایش کل یوتیوب با عبارت جست‌وجو گشته می‌شود.',
    "An HTTP proxy for the AI requests only — YouTube calls and downloads don't use it.":
        'پروکسی HTTP فقط برای درخواست‌های هوش مصنوعی — تماس‌های یوتیوب و دانلودها از آن استفاده نمی‌کنند.',
    'From Google Cloud Console → APIs & Services → Credentials, with the YouTube Data API v3 enabled. Each key gets 10,000 quota units a day.':
        'از Google Cloud Console → APIs & Services → Credentials، با فعال‌بودن YouTube Data API v3. هر کلید روزانه ۱۰٬۰۰۰ واحد سهمیه دارد.',
    'No extension needed — the export format in Settings decides it. The sort order and a timestamp are appended, so runs never overwrite each other.':
        'پسوند لازم نیست — قالب خروجی در تنظیمات آن را تعیین می‌کند. ترتیب مرتب‌سازی و یک زمان‌مهر به انتها اضافه می‌شوند، پس اجراها هرگز روی هم نمی‌نویسند.',
    "The API root, no endpoint path. Leave it empty to use this provider's own host — useful only when you go through a proxy or mirror.":
        'ریشه‌ی API، بدون مسیر اندپوینت. اگر خالی بگذارید از میزبان خودِ همین سرویس‌دهنده استفاده می‌شود — تنها وقتی لازم است که از پروکسی یا آینه عبور می‌کنید.',
    "The endpoint under the host. Leave it empty for this API mode's default.":
        'اندپوینت زیر میزبان. اگر خالی بگذارید مقدار پیش‌فرض همین حالت API استفاده می‌شود.',
    "With a channel above, this filters that channel's videos. On its own it searches all of YouTube — which costs 100 quota units per page of results.":
        'اگر بالا یک کانال داده باشید، این عبارت ویدیوهای همان کانال را فیلتر می‌کند. تنها به‌کار برود، کل یوتیوب را می‌گردد — که برای هر صفحه از نتایج ۱۰۰ واحد سهمیه هزینه دارد.',
})

# ── added: SettingsVM option lists (passed through tr() indirectly, so the
#    I18n scan over literal tr("…") calls never flagged them) ──
FA_STRINGS.update({
    # export formats
    'CSV (.csv)': 'CSV (.csv)',
    'JSON Lines (.jsonl)': 'JSON Lines (.jsonl)',
    'Excel (.xlsx)': 'اکسل (.xlsx)',
    'SQLite (.db)': 'SQLite (.db)',
    # autosave frequency
    'Every 100 videos': 'هر ۱۰۰ ویدیو',
    'Every 500 videos': 'هر ۵۰۰ ویدیو',
    'Every 1000 videos': 'هر ۱۰۰۰ ویدیو',
    'Only at the end': 'فقط در پایان',
    # cookie source (browser names stay as-is; only "None" is a word)
    'None': 'هیچ‌کدام',
})

# ── added: revised onboarding-tour steps (nav-row → content, section by section) ──
FA_STRINGS.update({
    '1 · Scraper': '۱ · اسکرپر',
    '2 · Niche Finder': '۲ · نیچ فایندر',
    '3 · Search Archive': '۳ · آرشیو جست‌وجو',
    '4 · AI Ideas': '۴ · ایده‌های هوش مصنوعی',
    '5 · Downloads': '۵ · دانلودها',
    "Every section lives here, roughly in the order you use them: scrape data, find outliers, turn them into ideas, then download. The active section shows a red bar at the window edge. We'll walk through each one.":
        'همه‌ی بخش‌ها این‌جا هستند، تقریباً به همان ترتیبی که استفاده می‌شوند: برداشت داده، پیداکردن آوتلایرها، تبدیلشان به ایده، و بعد دانلود. بخش فعال یک نوار قرمز کنار لبه‌ی پنجره دارد. یکی‌یکی مرورشان می‌کنیم.',
    'Everything starts here: this is where you pull raw video data off YouTube.':
        'همه‌چیز از این‌جا شروع می‌شود: داده‌ی خام ویدیوها را از یوتیوب این‌جا برمی‌داری.',
    'Point it at a channel URL or a keyword, set how many videos to take, and start. The rest of the app works from what you extract here.':
        'آدرس یک کانال یا یک کلیدواژه بده، تعداد ویدیو را تعیین کن و شروع کن. بقیه‌ی برنامه از همین چیزی که این‌جا برداشت می‌کنی کار می‌کند.',
    'The core of the app — search all of YouTube and surface small channels pulling big numbers.':
        'قلب برنامه — کل یوتیوب را بگرد و کانال‌های کوچکی را که اعداد بزرگ می‌زنند بیرون بکش.',
    'Filter by subscribers, views and time window. The multiplier is views ÷ subscribers — a high one means a small channel punching well above its size.':
        'بر اساس مشترک، بازدید و بازه‌ی زمانی فیلتر کن. ضریب یعنی بازدید ÷ مشترک — ضریب بالا یعنی کانالی کوچک که خیلی بالاتر از اندازه‌اش می‌زند.',
    'Every search you run is stored here forever — reopening, re-filtering or exporting one costs no quota at all.':
        'هر جست‌وجویی که اجرا کنی برای همیشه این‌جا ذخیره می‌شود — بازکردن، فیلترکردن دوباره یا خروجی‌گرفتن از آن هیچ سهمیه‌ای نمی‌خورد.',
    'Turn the videos you found into full content blueprints with AI.':
        'ویدیوهایی که پیدا کردی را با هوش مصنوعی به بلوپرینت کامل محتوا تبدیل کن.',
    'From finds to blueprints': 'از یافته‌ها تا بلوپرینت',
    'Tick the reference videos whose style you want to borrow, describe your angle, and the AI returns titles, hooks, structure and a shot list.':
        'ویدیوهای مرجعی که سبکشان را می‌خواهی تیک بزن، زاویه‌ات را توضیح بده، و هوش مصنوعی عنوان‌ها، هوک‌ها، ساختار و فهرست پلان را برمی‌گرداند.',
    'The download queue, with live progress and a quality picker per video. Open the finished file or its folder straight from the row.':
        'صف دانلود، با پیشرفت زنده و انتخاب کیفیت برای هر ویدیو. فایل آماده یا پوشه‌اش را مستقیم از همان ردیف باز کن.',
    'YouTube bills in units, not requests — a keyword search costs 100, video stats cost 1 per 50 videos. This card is always in view; click it for the full breakdown.':
        'یوتیوب بر اساس واحد حساب می‌کند نه درخواست — یک جست‌وجوی کلیدواژه ۱۰۰ واحد، آمار ویدیو ۱ واحد برای هر ۵۰ ویدیو. این کارت همیشه جلوی چشم است؛ برای جزئیات کامل رویش کلیک کن.',
    'The outlier hunt': 'شکار آوتلایر',
})

# ── added: UI/UX fix pass (API keys card, scraper format, unsaved guard) ──
FA_STRINGS.update({
    # API keys card
    'API Management': 'مدیریت API',
    'Your YouTube Data API v3 keys, stored locally on this device.':
        'کلیدهای YouTube Data API v3 شما، به صورت محلی روی همین دستگاه ذخیره می‌شوند.',
    'Not validated': 'تأیید نشده',
    'Valid': 'معتبر',
    'Invalid': 'نامعتبر',
    'PRIMARY KEY': 'کلید اصلی',
    'Never leaves your device': 'هرگز از دستگاه شما خارج نمی‌شود',
    'Validate key': 'اعتبارسنجی کلید',
    'BACKUP KEYS': 'کلیدهای پشتیبان',
    'When the primary key runs out of daily quota mid-scrape, the app switches to the next key automatically.':
        'وقتی کلید اصلی وسط اسکرپ سهمیه روزانه‌اش تمام شود، برنامه به‌طور خودکار به کلید بعدی سوئیچ می‌کند.',
    'Check': 'بررسی',
    'Remove this key': 'حذف این کلید',
    'Add another YouTube API key': 'افزودن یک کلید YouTube API دیگر',
    'Show': 'نمایش',
    'Hide': 'پنهان',
    'Copy': 'کپی',
    'Paste': 'چسباندن',
    'Daily quota': 'سهمیه روزانه',
    'units per project, free': 'واحد برای هر پروژه، رایگان',
    'Keyword search': 'جست‌وجوی کلیدواژه',
    'units per page — the expensive call': 'واحد برای هر صفحه — فراخوانی پرهزینه',
    'Video & channel stats': 'آمار ویدیو و کانال',
    'unit per 50 items': 'واحد برای هر ۵۰ مورد',
    # راهنمای گرفتن کلید گوگل — کوتاه‌شده به دو گام (قبلاً شش گام بود)
    'How to get a key — two steps': 'چطور یک کلید بگیریم — دو گام',
    'Free, about two minutes.': 'رایگان، حدود دو دقیقه.',
    'Enable the API and create a key': 'API را فعال کنید و کلید بسازید',
    'Sign in with any Gmail account, create a project, enable YouTube Data API v3, then Credentials → Create credentials → API key. The key looks like AIzaSy…':
        'با هر حساب جیمیل وارد شوید، یک پروژه بسازید، YouTube Data API v3 را فعال کنید، سپس Credentials ← Create credentials ← API key. کلید شبیه …AIzaSy است.',
    'Open Cloud Console': 'باز کردن Cloud Console',
    'Paste it above, then validate': 'در فیلد بالا بچسبانید، سپس اعتبارسنجی کنید',
    'The key is stored in your own local settings — it never leaves this computer. Restrict it to YouTube Data API v3 on its page if you want it to be useless anywhere else.':
        'کلید در تنظیمات محلی خودتان ذخیره می‌شود — هرگز از این رایانه خارج نمی‌شود. اگر می‌خواهید جای دیگری بی‌فایده باشد، در صفحه‌اش آن را به YouTube Data API v3 محدود کنید.',
    'Enable API': 'فعال‌سازی API',
    'Enable YouTube Data API v3': 'فعال‌سازی YouTube Data API v3',
    # legacy six-step keys — kept so any older build still resolves them
    'How to get a key — six steps': 'چطور یک کلید بگیریم — شش گام',
    'Free, about three minutes.': 'رایگان، حدود سه دقیقه.',
    'Sign in to Google and open the Cloud Console':
        'وارد گوگل شوید و Cloud Console را باز کنید',
    'Any ordinary Gmail account works — no credit card, no billing account.':
        'هر حساب جیمیل معمولی کار می‌کند — بدون کارت اعتباری، بدون حساب صورت‌حساب.',
    'Open Console': 'باز کردن Console',
    'Create a project': 'ساختن یک پروژه',
    'Name it anything (e.g. "yt-scraper") and press Create. Already have one? Select it in the top bar.':
        'هر نامی بگذارید (مثلاً «yt-scraper») و Create را بزنید. از قبل دارید؟ از نوار بالا انتخابش کنید.',
    'New Project': 'پروژه جدید',
    'With your project selected, press ENABLE. This is the step people miss — without it the key returns "API not enabled".':
        'با انتخاب پروژه، ENABLE را بزنید. این همان گامی است که اغلب فراموش می‌شود — بدون آن کلید خطای «API not enabled» می‌دهد.',
    'Create the key': 'ساختن کلید',
    'Credentials → CREATE CREDENTIALS → API key. The key appears in a popup and looks like AIzaSy…':
        'Credentials ← CREATE CREDENTIALS ← API key. کلید در یک پنجره ظاهر می‌شود و شبیه …AIzaSy است.',
    'Credentials': 'اعتبارنامه‌ها',
    'Paste it in the field above, then validate': 'در فیلد بالا بچسبانید، سپس اعتبارسنجی کنید',
    'The key is stored in your own local settings — it never leaves your computer.':
        'کلید در تنظیمات محلی خودتان ذخیره می‌شود — هرگز از رایانه شما خارج نمی‌شود.',
    'Optional · restrict the key': 'اختیاری · محدود کردن کلید',
    'On the key\'s page choose Restrict key → API restrictions → YouTube Data API v3. If it ever leaks, it is useless for anything else.':
        'در صفحه کلید، Restrict key ← API restrictions ← YouTube Data API v3 را انتخاب کنید. اگر لو برود، برای هر چیز دیگری بی‌فایده است.',
    'Quota page': 'صفحه سهمیه',
    'Keyword search is the only expensive call — roughly 100 searches a day per key. Cached results and the search archive keep you well under the limit.':
        'جست‌وجوی کلیدواژه تنها فراخوانی پرهزینه است — تقریباً ۱۰۰ جست‌وجو در روز برای هر کلید. نتایج کش‌شده و آرشیو جست‌وجو شما را خیلی زیر سقف نگه می‌دارند.',
    # scraper format filter
    'All formats': 'همه فرمت‌ها',
    'Filtering for {fmt}: scanning up to {scan} videos to find {want}.':
        'فیلتر برای {fmt}: پویش تا {scan} ویدیو برای یافتن {want}.',
    # unsaved-changes guard
    'Unsaved changes': 'تغییرات ذخیره‌نشده',
    'You have unsaved changes in Settings. Save them before leaving?':
        'در تنظیمات تغییرات ذخیره‌نشده دارید. قبل از خروج ذخیره شوند؟',
    'Stay here': 'همین‌جا بمان',
    'Discard': 'نادیده گرفتن',
    'Save & continue': 'ذخیره و ادامه',
})

# ── added: in-app video player + CSV report history ──
FA_STRINGS.update({
    # video player
    'Play in the app': 'پخش در برنامه',
    'Open in your default player': 'باز کردن در پخش‌کننده پیش‌فرض',
    'Back 10s': '۱۰ ثانیه عقب',
    'Forward 10s': '۱۰ ثانیه جلو',
    'Fill the window': 'پر کردن پنجره',
    'Shrink': 'کوچک کردن',
    'Downloaded quality': 'کیفیت دانلود‌شده',
    'Downloaded': 'دانلود‌شده',
    'Subscribers hidden': 'تعداد مشترک پنهان است',
    # CSV report history
    'Reports you have built': 'گزارش‌هایی که ساخته‌اید',
    'Every report still on disk, newest first. Open one to read it again — no AI call, no quota.':
        'همه‌ی گزارش‌هایی که هنوز روی دیسک هستند، جدیدترین اول. برای خواندن دوباره بازش کنید — بدون فراخوانی هوش مصنوعی و بدون مصرف سهمیه.',
    'Channel report': 'گزارش کانال',
    'Channel + blueprints': 'کانال + بلوپرینت‌ها',
    '{n} for this file': '{n} مورد برای این فایل',
    'Reload the list': 'بارگذاری مجدد فهرست',
    '{n} blueprint(s): {list}': '{n} بلوپرینت: {list}',
    '{n} videos': '{n} ویدیو',
    '{n} watched': '{n} تماشا‌شده',
    'Delete this report?': 'این گزارش حذف شود؟',
    'The HTML report built from “{f}” will be removed from disk. The export file itself is untouched.':
        'گزارش HTML ساخته‌شده از «{f}» از دیسک حذف می‌شود. خود فایل خروجی دست‌نخورده می‌ماند.',
    'Delete report': 'حذف گزارش',
    'Delete this report': 'حذف این گزارش',
    'Report removed.': 'گزارش حذف شد.',
    'That report is no longer on disk.': 'آن گزارش دیگر روی دیسک نیست.',
    'Open': 'باز کردن',
})

# ── added: player polish, oldest sort, thumbnail sizes, form tweaks ──
FA_STRINGS.update({
    'Oldest first': 'قدیمی‌ترین اول',
    'Walking the uploads playlist backwards to find the channel\'s first videos (1 quota unit per 50).':
        'پیمایش لیست آپلودها به عقب برای یافتن نخستین ویدیوهای کانال (۱ واحد سهمیه برای هر ۵۰).',
    'Walking to the channel\'s start … {n} videos seen.':
        'در حال رفتن تا ابتدای کانال … {n} ویدیو دیده شد.',
    'Channel is very large — stopped after {n} videos, so \'oldest\' is the oldest of those.':
        'کانال بسیار بزرگ است — پس از {n} ویدیو متوقف شد، پس «قدیمی‌ترین» یعنی قدیمی‌ترینِ همان‌ها.',
    'No extension needed — the export format in Settings decides it. The sort order and a timestamp are appended, so runs never overwrite each other. Leave empty to use “youtube_data”.':
        'نیازی به پسوند نیست — قالب خروجی در تنظیمات آن را تعیین می‌کند. ترتیب مرتب‌سازی و یک برچسب زمانی اضافه می‌شود، پس اجراها هم را بازنویسی نمی‌کنند. برای استفاده از «youtube_data» خالی بگذارید.',
})

# ── added: length-split video watching for the CSV report ──
FA_STRINGS.update({
    'Watching short {i} of {n} …': 'تماشای شورت {i} از {n} …',
    'Watching long-form {i} of {n} …': 'تماشای ویدیوی بلند {i} از {n} …',
    'SHORT — watched in full': 'شورت — کامل تماشا شد',
    'LONG-FORM — watched {a}–{b} min': 'ویدیوی بلند — دقیقه‌ی {a} تا {b} تماشا شد',
})

# ── added: honest download quality + provider capability notes ──
FA_STRINGS.update({
    'No client has {want}p for this video — downloading the best it does have …':
        'هیچ روشی برای این ویدیو {want}p ندارد — بهترین کیفیت موجود دانلود می‌شود …',
    # These three were already shown by the download ladder but had never been
    # translated, so a Persian user saw English mid-download — exactly where the
    # app most needs to explain itself.
    'Only {got}p came back — retrying for {want}p …':
        'فقط {got}p برگشت — دوباره برای {want}p تلاش می‌شود …',
    'Downloaded at {got}p — YouTube had nothing higher for this video.':
        'با کیفیت {got}p دانلود شد — یوتیوب کیفیت بالاتری برای این ویدیو نداشت.',
    'No adaptive stream at that quality — trying the combined file …':
        'در آن کیفیت استریم جداگانه‌ای وجود ندارد — فایل ترکیبی امتحان می‌شود …',
    # Small, long-standing gaps found while auditing the above: the player's
    # transport tooltips and the word the download ladder substitutes into its
    # "asked for {want}" line when the pick was "best available".
    'Pause': 'توقف',
    'Quality': 'کیفیت',
    'best': 'بهترین',
    '{n} subscribers': '{n} مشترک',
    'Not confirmed for this video — you\'ll get the closest match available.':
        'برای این ویدیو تأیید نشده — نزدیک‌ترین کیفیت موجود دانلود می‌شود.',
    'Before writing a CSV report, Gemini watches the channel\'s best videos — Shorts in full, and the middle minutes of long-form ones. It takes a few minutes and costs quota, and it is what makes the report describe what the videos actually do.':
        'جمینای پیش از نوشتن گزارش CSV بهترین ویدیوهای کانال را تماشا می‌کند — شورت‌ها را کامل و بخش میانی ویدیوهای بلند را. چند دقیقه طول می‌کشد و سهمیه مصرف می‌کند، و همین است که باعث می‌شود گزارش دقیقاً بگوید ویدیوها چه کاری انجام می‌دهند.',
    'Only Google Gemini can search the web and watch videos. Reports still work with this provider, but they are written from the numbers alone.':
        'فقط گوگل جمینای می‌تواند وب را جست‌وجو کند و ویدیوها را تماشا کند. گزارش‌ها با این سرویس هم ساخته می‌شوند، اما تنها بر پایه‌ی اعداد نوشته می‌شوند.',
})

# ── added: exact-quality downloads and the fuller live progress readout ──
FA_STRINGS.update({
    'Checking the highest quality this video has…':
        'در حال بررسی بالاترین کیفیت این ویدیو …',
    'This video doesn\'t have {want}p. The highest it offers is {got}p — pick that quality instead.':
        'این ویدیو {want}p ندارد. بالاترین کیفیت موجود {got} است — همان را انتخاب کنید.',
    'Couldn\'t get {want}p for this video. Try “Best available”, or a lower quality.':
        'دریافت {want}p برای این ویدیو ممکن نشد. «بهترین کیفیت موجود» یا کیفیتی پایین‌تر را امتحان کنید.',
    'Not confirmed for this video — if it isn\'t available the download will stop.':
        'برای این ویدیو تأیید نشده — اگر موجود نباشد دانلود متوقف می‌شود.',
    'Couldn\'t read this video\'s formats — showing the standard options. If the quality you pick isn\'t available, the download will stop and say so.':
        'فرمت‌های این ویدیو خوانده نشد — گزینه‌های استاندارد نمایش داده می‌شوند. اگر کیفیتی که انتخاب می‌کنید موجود نباشد، دانلود متوقف می‌شود و همین را می‌گوید.',
    # Live row: "12.4 MB of 480 MB · 1.2 MB/s · 2m 40s left"
    '{done} of {total}': '{done} از {total}',
    '{t} left': '{t} مانده',
    'part {i} of {n}': 'تکه {i} از {n}',
    # deno (JS runtime) install dialog
    'One-time setup for YouTube downloads': 'راه‌اندازی یک‌بارهٔ دانلود یوتیوب',
    'To download from YouTube, the app needs a small component (deno). It downloads once and is then always ready.':
        'برای دانلود از یوتیوب، برنامه به یک کامپوننت کوچک (deno) نیاز دارد. یک‌بار دانلود می‌شود و بعد همیشه آماده است.',
    'Download and install': 'دانلود و نصب',
    'If you close this now, video downloads won\'t work until it finishes.':
        'اگر الان ببندید، تا پایان دانلود، دانلود ویدیو کار نمی‌کند.',
    '{done} of {total} · {pct}%': '{done} از {total} · {pct}٪',
    'Downloading… {done}': 'در حال دانلود… {done}',
    'Ready.': 'آماده.',
    'Ready — you can download now.': 'آماده شد — حالا می‌توانید دانلود کنید.',
    'Install cancelled.': 'نصب لغو شد.',
    'Couldn\'t install the component: {e}': 'نصب کامپوننت ممکن نشد: {e}',
    'To download from YouTube, the app needs a small component (deno). Open the download again and install it when asked.':
        'برای دانلود از یوتیوب، برنامه به کامپوننت کوچک deno نیاز دارد. دوباره دانلود را باز کنید و وقتی پرسیده شد نصبش کنید.',
})

# ── added: Download Engine settings card + downloader self-update ──
FA_STRINGS.update({
    'Download Engine': 'موتور دانلود',
    'JavaScript runtime ready': 'موتور جاوااسکریپت آماده است',
    'JavaScript runtime not installed': 'موتور جاوااسکریپت نصب نشده',
    'found on your system': 'روی سیستم شما پیدا شد',
    'managed by the app': 'مدیریت‌شده توسط برنامه',
    'Needed to download from YouTube. About 40 MB, one-time.':
        'برای دانلود از یوتیوب لازم است. حدود ۴۰ مگابایت، فقط یک‌بار.',
    'Install runtime': 'نصب موتور',
    'Reinstall runtime': 'نصب مجدد موتور',
    'Update downloader': 'به‌روزرسانی دانلودر',
    'Updating…': 'در حال به‌روزرسانی…',
    'Downloader updated to {v}. Restart to use it.':
        'دانلودر به {v} به‌روزرسانی شد. برای استفاده برنامه را دوباره باز کنید.',
    'Couldn\'t update the downloader: {e}': 'به‌روزرسانی دانلودر ممکن نشد: {e}',
})



# ══════════════════════════════════════════════════════════════════════
#  added: Script Studio (teleprompter) + Niche Scan
# ══════════════════════════════════════════════════════════════════════
FA_STRINGS.update({
    # ── snapshot.py: the computed verdict + bucket labels ──
    '{n} videos from only {c} channels — concentrated.':
        '{n} ویدیو از فقط {c} کانال — بازار متمرکز است.',
    '{n} videos, but one channel holds {p}% of the views.':
        '{n} ویدیو، اما یک کانال {p}٪ بازدیدها را در دست دارد.',
    '{n} videos spread across {c} channels.':
        '{n} ویدیو پخش‌شده بین {c} کانال.',
    'Outlier-driven: the average is {x}× the median, so read the median.':
        'وابسته به موارد پرت: میانگین {x} برابر میانه است، پس به میانه نگاه کنید.',
    'Views are evenly spread — the median is representative.':
        'بازدیدها یکنواخت پخش شده‌اند — میانه نماینده‌ی خوبی است.',
    'Mostly recent uploads — this is an active topic.':
        'بیشتر آپلودها تازه‌اند — موضوع فعالی است.',
    'Nothing here is from the last 30 days.':
        'هیچ‌کدام از ۳۰ روز گذشته نیستند.',
    'Under 1 min': 'کمتر از ۱ دقیقه',
    '1–3 min': '۱ تا ۳ دقیقه',
    '3–10 min': '۳ تا ۱۰ دقیقه',
    '10–20 min': '۱۰ تا ۲۰ دقیقه',
    'Over 20 min': 'بیش از ۲۰ دقیقه',
    'Last 7 days': '۷ روز گذشته',
    '8–30 days': '۸ تا ۳۰ روز',
    '1–12 months': '۱ تا ۱۲ ماه',
    'Over a year': 'بیش از یک سال',

    # ── insights.py: parser fallback ──
    'The AI reply could not be read as a structured brief. The raw response is shown below.':
        'پاسخ هوش مصنوعی به‌صورت یک بریف ساخت‌یافته خوانده نشد. متن خام پاسخ در پایین آمده است.',

    # ── studio_vm.py ──
    'That blueprint is no longer saved.': 'آن بلوپرینت دیگر ذخیره نیست.',
    'This blueprint has no script yet — rebuild it in full first.':
        'این بلوپرینت هنوز اسکریپت ندارد — اول آن را کامل بازسازی کنید.',
    '{s} over the planned length': '{s} بیشتر از طول برنامه‌ریزی‌شده',
    '{s} under the planned length': '{s} کمتر از طول برنامه‌ریزی‌شده',
    'On target': 'مطابق برنامه',
    'Calm': 'آرام',
    'Natural': 'طبیعی',
    'Fast': 'سریع',
    'Couldn\'t save the script.': 'ذخیره‌ی اسکریپت ممکن نشد.',
    'Script saved to the blueprint.': 'اسکریپت در بلوپرینت ذخیره شد.',
    # ── insights_vm.py: status lines, tiles, labels ──
    'Nothing to analyze — run a search first.':
        'چیزی برای تحلیل نیست — اول یک جست‌وجو اجرا کنید.',
    'Nothing to analyze yet — run a search first.':
        'هنوز چیزی برای تحلیل نیست — اول یک جست‌وجو اجرا کنید.',
    'These rows have nothing measurable in them.':
        'در این ردیف‌ها چیز قابل‌اندازه‌گیری وجود ندارد.',
    'This section has no rows to analyze.':
        'این بخش ردیفی برای تحلیل ندارد.',
    'Showing the saved brief for this exact result set.':
        'بریف ذخیره‌شده‌ی همین مجموعه‌ی نتایج نمایش داده می‌شود.',
    'That saved report is gone.': 'آن گزارش ذخیره‌شده وجود ندارد.',
    'Saved report, reopened.': 'گزارش ذخیره‌شده، باز شد.',
    'TYPICAL VIEWS (MEDIAN)': 'بازدید معمول (میانه)',
    'MOMENTUM / DAY': 'شتاب روزانه',
    'VISIBLE INTERACTION': 'تعامل قابل‌مشاهده',
    'CHANNELS IN THIS SET': 'کانال‌های این مجموعه',
    'average {a} · {n} of {t} rows': 'میانگین {a} · {n} از {t} ردیف',
    '  — outlier-driven': '  — وابسته به موارد پرت',
    'median, age-normalised · {n} of {t} rows dated':
        'میانه، نرمال‌شده با عمر ویدیو · {n} از {t} ردیف تاریخ دارند',
    'likes + comments ÷ views · {n} of {t} rows complete':
        'لایک + کامنت ÷ بازدید · {n} از {t} ردیف کامل',
    'top channel holds {p}% of the views':
        'کانال برتر {p}٪ بازدیدها را دارد',
    'no view data': 'داده‌ی بازدید ندارد',
    'from the videos\' own tags': 'از تگ‌های خود ویدیوها',
    'from word frequency across the titles': 'از تکرار کلمات در عنوان‌ها',
    '/h': '/ساعت',
    'View count': 'تعداد بازدید',
    'Public likes AND comments': 'لایک و کامنت عمومی، هر دو',
    'Public subscriber count': 'تعداد مشترک عمومی',
    'Duration': 'مدت',
    'Publish date': 'تاریخ انتشار',
    'Captions': 'زیرنویس',
    'HD': 'HD',
    'Analyze a result set first.': 'اول یک مجموعه نتیجه را تحلیل کنید.',
    'Add an AI provider key in Settings to generate the brief.':
        'برای ساخت بریف، در تنظیمات کلید یک سرویس هوش مصنوعی اضافه کنید.',
    'Reading the snapshot with {p} …': 'خواندن اسنپ‌شات با {p} …',
    'The brief could not be generated.': 'ساخت بریف ممکن نشد.',
    'Brief ready.': 'بریف آماده است.',
    'Brief ready. {n} claims cited videos outside this snapshot and were dropped.':
        'بریف آماده است. {n} گزاره به ویدیوهایی بیرون از این اسنپ‌شات ارجاع داده بودند و حذف شدند.',
    '{p} replied with something that isn\'t a structured brief — the raw text is shown below.':
        'پاسخ {p} یک بریف ساخت‌یافته نبود — متن خام در پایین آمده است.',
    'Snapshot brief ready.': 'بریف اسنپ‌شات آماده است.',
    'Observed': 'مشاهده‌شده',
    'Inferred': 'استنباط‌شده',
    'Needs YouTube Studio': 'نیازمند یوتیوب استودیو',
    'low': 'کم',
    'medium': 'متوسط',
    'high': 'زیاد',
    'Saved report deleted.': 'گزارش ذخیره‌شده حذف شد.',
    'No standout videos to send.': 'ویدیوی شاخصی برای ارسال نیست.',
    'Sent {n} videos to AI Ideas.': '{n} ویدیو به ایده‌های هوش مصنوعی فرستاده شد.',
    'Those videos are already on the AI Ideas board.':
        'آن ویدیوها از قبل در برد ایده‌های هوش مصنوعی هستند.',
    # ── Teleprompter.qml ──
    'No script loaded': 'اسکریپتی بارگذاری نشده',
    'Beat {i} of {n}': 'بیت {i} از {n}',
    'words': 'کلمه',
    'Edit this line': 'ویرایش این خط',
    'Copy this line': 'کپی این خط',
    'Ctrl+Enter to apply': 'Ctrl+Enter برای اعمال',
    'Pick a blueprint with a script to read it here.':
        'یک بلوپرینت با اسکریپت انتخاب کنید تا همین‌جا خوانده شود.',
    'Back to the top': 'برگشت به ابتدا',
    'Pace': 'سرعت',
    'wpm': 'کلمه در دقیقه',
    'Smaller text': 'متن کوچک‌تر',
    'Larger text': 'متن بزرگ‌تر',
    'Mirror for a beam-splitter rig  (M)':
        'آینه‌ای، برای پایه‌ی شیشه‌ی نیم‌بازتاب  (M)',
    'Timecodes and speaker labels': 'تایم‌کدها و برچسب گوینده',
    'Hide everything but the words  (F)': 'پنهان کردن همه‌چیز جز متن  (F)',
    'Undo': 'واگرد',
    'Redo': 'ازنو',
    'Save script': 'ذخیره‌ی اسکریپت',

    # ── ScriptStudioPage.qml ──
    'Script Studio': 'استودیوی اسکریپت',
    'Read a blueprint\'s script off a real teleprompter, and fix the lines that don\'t land.':
        'اسکریپت هر بلوپرینت را روی یک تله‌پرامپتر واقعی بخوانید و خط‌هایی که نمی‌گیرند را اصلاح کنید.',
    'Unsaved script edits': 'ویرایش‌های ذخیره‌نشده',
    'Generate a blueprint': 'ساخت یک بلوپرینت',
    'No scripts saved yet': 'هنوز اسکریپتی ذخیره نشده',
    'Generate blueprints on the AI Ideas page — each one comes with a timecoded, camera-ready script, and every script shows up here.':
        'در صفحه‌ی ایده‌های هوش مصنوعی بلوپرینت بسازید — هر بلوپرینت یک اسکریپت تایم‌کددار و آماده‌ی دوربین دارد و همه‌ی آن‌ها همین‌جا نمایش داده می‌شوند.',
    'CHOOSE A SCRIPT': 'یک اسکریپت انتخاب کنید',
    'Find a blueprint': 'یافتن بلوپرینت',
    'Search by title': 'جست‌وجو با عنوان',
    '{n} scripts': '{n} اسکریپت',
    '{n} beats': '{n} بیت',
    '{n} words': '{n} کلمه',
    'Read on camera': 'خواندن روی دوربین',
    # ── InsightsPage.qml: header, sections, entry points ──
    'Niche Scan': 'موضوع\u200cسنج',
    'Reading “{q}” as one set — {n} videos.':
        'خواندن «{q}» به‌عنوان یک مجموعه — {n} ویدیو.',
    'Analyze a whole search result, not one video at a time.':
        'یک نتیجه‌ی جست‌وجو را کامل تحلیل کنید، نه ویدیو به ویدیو.',
    'Saved brief · {t}': 'بریف ذخیره‌شده · {t}',
    'Send winners to AI Ideas': 'ارسال برنده‌ها به ایده‌های هوش مصنوعی',
    'Reading …': 'در حال خواندن …',
    'Re-analyze': 'تحلیل مجدد',
    'Generate brief': 'ساخت بریف',
    'Nothing analyzed yet': 'هنوز چیزی تحلیل نشده',
    'Run a search in Niche Finder and press “Analyze these results”, or open a saved section in Search Archive. This page costs no API quota — it reads rows you already have.':
        'در نیچ فایندر جست‌وجو کنید و «تحلیل این نتایج» را بزنید، یا یک بخش ذخیره‌شده را از آرشیو جست‌وجو باز کنید. این صفحه هیچ کوتای APIی مصرف نمی‌کند — همان ردیف‌هایی را می‌خواند که از قبل دارید.',
    'PREVIOUSLY ANALYZED': 'تحلیل‌شده‌های پیشین',
    'Delete this saved report': 'حذف این گزارش ذخیره‌شده',
    'WHAT THIS SET LOOKS LIKE': 'این مجموعه چه شکلی است',
    'Measured from the result rows — no AI involved, no quota spent.':
        'محاسبه‌شده از خود ردیف‌های نتیجه — بدون هوش مصنوعی و بدون مصرف کوتا.',
    'How long they are': 'چقدر طولانی‌اند',
    'median {t}': 'میانه {t}',
    'videos timed': 'ویدیو با مدت مشخص',
    'No row in this set reported a duration.':
        'هیچ ردیفی در این مجموعه مدت ویدیو را گزارش نکرده.',
    'How fresh they are': 'چقدر تازه‌اند',
    'by publish date': 'بر پایه‌ی تاریخ انتشار',
    'No row in this set reported a publish date.':
        'هیچ ردیفی در این مجموعه تاریخ انتشار ندارد.',
    'Who holds this niche': 'این نیچ دست کیست',
    'share of the views in this set': 'سهم از بازدیدهای این مجموعه',
    'Moving fastest': 'سریع‌ترین رشد',
    'views per hour since publishing': 'بازدید در ساعت از زمان انتشار',
    'No row had both views and a publish date.':
        'هیچ ردیفی هم بازدید و هم تاریخ انتشار نداشت.',
    'Reaching past their audience': 'فراتر از مخاطب خودشان',
    'views ÷ subscribers': 'بازدید ÷ مشترک',
    'No channel in this set showed a public subscriber count.':
        'هیچ کانالی در این مجموعه تعداد مشترک عمومی نشان نداده.',
    'Terms that keep coming back': 'عبارت‌هایی که تکرار می‌شوند',
    'These show what is being SUPPLIED in this niche. They are not search volume and do not prove demand.':
        'این‌ها نشان می‌دهند چه چیزی در این نیچ عرضه می‌شود. حجم جست‌وجو نیستند و تقاضا را اثبات نمی‌کنند.',

    # ── InsightsPage.qml: the AI brief ──
    'Add the written brief': 'افزودن بریف نوشتاری',
    'One AI call turns the numbers above into a research brief — audience questions, opportunity hypotheses and three testable experiments. Every statement gets labelled Observed, Inferred, or Needs YouTube Studio, so you can tell measurement from opinion.':
        'یک فراخوانی هوش مصنوعی اعداد بالا را به یک بریف پژوهشی تبدیل می‌کند — پرسش‌های مخاطب، فرضیه‌های فرصت و سه آزمایش قابل‌سنجش. هر گزاره برچسب «مشاهده‌شده»، «استنباط‌شده» یا «نیازمند یوتیوب استودیو» می‌گیرد تا اندازه‌گیری از نظر شخصی جدا بماند.',
    'No AI provider configured — add a key in Settings first.':
        'هیچ سرویس هوش مصنوعی تنظیم نشده — اول در تنظیمات یک کلید اضافه کنید.',
    'This is one long call — a full brief can take a couple of minutes.':
        'این یک فراخوانی طولانی است — ساخت یک بریف کامل ممکن است چند دقیقه طول بکشد.',
    'Raw AI reply': 'پاسخ خام هوش مصنوعی',
    'not structured': 'ساخت‌یافته نیست',
    'The brief': 'بریف',
    'VIEWER\'S JOB': 'کار بیننده',
    'THE VIEWER': 'بیننده',
    'LIKELY SURFACE': 'سطح کشف احتمالی',
    'HONEST PROMISE': 'وعده‌ی صادقانه',
    'Measured in this result set.': 'در همین مجموعه‌ی نتایج اندازه‌گیری شده.',
    'A reading of that data — a hypothesis, not a fact.':
        'یک خوانش از آن داده — یک فرضیه، نه یک واقعیت.',
    'Not public data. Only the channel owner\'s analytics can answer these.':
        'داده‌ی عمومی نیست. فقط آمار خودِ صاحب کانال به این‌ها پاسخ می‌دهد.',
    'Questions this audience is likely asking':
        'پرسش‌هایی که این مخاطب احتمالاً می‌پرسد',
    'hypotheses, not measured queries': 'فرضیه، نه جست‌وجوی اندازه‌گیری‌شده',
    'Openings worth testing': 'فرصت‌هایی که ارزش آزمایش دارند',
    'each with the reason it might be wrong': 'هرکدام با دلیلِ ممکنِ اشتباه بودنش',
    'WHY': 'چرا',
    'RISK': 'ریسک',
    'Three things to actually try': 'سه کاری که واقعاً امتحان کنید',
    'one variable each, with the metric that settles it':
        'هرکدام یک متغیر، همراه با معیاری که تعیین‌کننده است',
    'BECAUSE': 'چون',
    'EXPECTING': 'انتظار',
    'TESTING': 'در حال آزمایش',
    'MEASURE IN STUDIO': 'اندازه‌گیری در استودیو',
    'IF IT FAILS': 'اگر نگرفت',
    'Evidence ledger': 'دفتر شواهد',
    '{n} claims': '{n} گزاره',
    'Every statement above, with what it rests on and what would undermine it.':
        'هر گزاره‌ی بالا، همراه با آنچه بر آن تکیه دارد و آنچه آن را بی‌اعتبار می‌کند.',
    '{n} claims cited videos that aren\'t in this result set and were dropped.':
        '{n} گزاره به ویدیوهایی ارجاع دادند که در این مجموعه نیستند و حذف شدند.',
    'confidence: {c}': 'اطمینان: {c}',
    'What this snapshot could see': 'این اسنپ‌شات چه چیزی را می‌دید',
    'rows with each field present': 'ردیف‌هایی که هر فیلد را دارند',
    'Missing values stay missing — nothing here was filled in with a zero.':
        'مقدارهای نبود، نبود می‌مانند — هیچ‌چیز اینجا با صفر پر نشده.',
    'What it cannot tell you': 'چه چیزی را نمی‌تواند بگوید',
    'public data has hard edges': 'داده‌ی عمومی مرزهای سختی دارد',
    'Click-through rate, impressions, retention and watch time are owner-only — they are not public for anyone else\'s videos.':
        'نرخ کلیک، نمایش‌ها، نگه‌داشت و زمان تماشا فقط برای صاحب کانال است — برای ویدیوهای دیگران عمومی نیست.',
    'Where views came from (browse, suggested, search) is not public, so no result here proves a discovery surface.':
        'منبع بازدیدها (مرور، پیشنهادی، جست‌وجو) عمومی نیست، پس هیچ نتیجه‌ای اینجا سطح کشف را اثبات نمی‌کند.',
    'Subscriber counts are current and rounded, not what they were when a video was published.':
        'تعداد مشترک، عددِ امروز و گِرد شده است، نه عددِ زمان انتشار ویدیو.',
    'Search result order is a personalised, region-sensitive snapshot — not a census of the niche.':
        'ترتیب نتایج جست‌وجو یک اسنپ‌شات شخصی‌سازی‌شده و وابسته به منطقه است — سرشماری کل نیچ نیست.',
    'Analyze these results': 'تحلیل این نتایج',
    'Analyze this section': 'تحلیل این بخش',
})

# ══════════════════════════════════════════════════════════════════════
#  added: dropped-connection / timeout messages for AI provider calls
# ══════════════════════════════════════════════════════════════════════
FA_STRINGS.update({
    '{provider} took longer than {timeout}s to respond, so the request was stopped. This usually means the reply was slow to finish generating, or the connection — especially through a proxy — is degraded right now. Try again in a moment.':
        'پاسخ {provider} بیش از {timeout} ثانیه طول کشید و درخواست متوقف شد. معمولاً یعنی تولید پاسخ کند بوده، یا اتصال — بخصوص از طریق پراکسی — همین حالا افت کرده است. کمی بعد دوباره تلاش کنید.',
    'The connection to {provider} was closed mid-request. Nothing reached the model, so no request was charged. Long requests like this one are the first thing a proxy or VPN drops — if you are using one, check it is still up, then try again.':
        'اتصال به {provider} در میانه‌ی درخواست بسته شد. چیزی به مدل نرسید، پس هزینه‌ای ثبت نشده. درخواست‌های طولانی مثل این، اولین چیزی هستند که پراکسی یا VPN رها می‌کند — اگر از آن استفاده می‌کنید، ببینید همچنان بالاست، بعد دوباره تلاش کنید.',
    'The connection to {provider} was closed mid-request, and {attempts} attempts all failed. Nothing reached the model, so no request was charged. Long requests like this one are the first thing a proxy or VPN drops — if you are using one, check it is still up, then try again.':
        'اتصال به {provider} در میانه‌ی درخواست بسته شد و هر {attempts} تلاش ناموفق بود. چیزی به مدل نرسید، پس هزینه‌ای ثبت نشده. درخواست‌های طولانی مثل این، اولین چیزی هستند که پراکسی یا VPN رها می‌کند — اگر از آن استفاده می‌کنید، ببینید همچنان بالاست، بعد دوباره تلاش کنید.',
    'The models endpoint didn\'t return valid JSON — double-check the API Host and API Path.':
        'اندپوینت مدل‌ها JSON معتبر برنگرداند — آدرس هاست و مسیر API را دوباره بررسی کنید.',
    'The connection to {provider} was closed before it answered. This is a network problem rather than a bad key — if you are on a proxy or VPN, check it is still up, then try again.':
        'اتصال به {provider} پیش از پاسخ دادن بسته شد. این یک مشکل شبکه است، نه کلید نامعتبر — اگر روی پراکسی یا VPN هستید، ببینید همچنان بالاست، بعد دوباره تلاش کنید.',
})

# ══════════════════════════════════════════════════════════════════════
#  added: menu cleanup — Content Lab's third tab (the former Script Studio
#  page) and the Niche Scan brief as a third report source
# ══════════════════════════════════════════════════════════════════════
FA_STRINGS.update({
    'Teleprompter': 'تله‌پرامپتر',
    'Your saved blueprints, the AI channel report, and the teleprompter you shoot from.':
        'بلوپرینت‌های ذخیره‌شده‌ی شما، گزارش هوش مصنوعی کانال، و تله‌پرامپتری که از آن فیلم می‌گیرید.',
    'Combine with my research': 'ترکیب با تحقیق من',
    'Optional — a Niche Scan brief is research about the niche, not about this channel. Every statement keeps its label (observed / inferred / needs Studio), and the report is told the channel\'s own numbers win where the two disagree.':
        'اختیاری — بریفِ موضوع‌سنج، تحقیق درباره‌ی نیچ است، نه درباره‌ی این کانال. هر گزاره برچسب خودش را نگه می‌دارد (مشاهده‌شده / استنباطی / نیازمند استودیو)، و به گزارش گفته می‌شود هرجا این دو با هم نخوانند، عددهای خودِ کانال حرف آخر را می‌زنند.',
    'No saved research yet — analyze a search in Niche Scan and press “Generate brief”.':
        'هنوز تحقیقی ذخیره نشده — در موضوع‌سنج یک جست‌وجو را تحلیل کنید و «ساخت بریف» را بزنید.',
    'Go to Niche Scan': 'رفتن به موضوع‌سنج',
    'RESEARCH': 'تحقیق',
    '{n} videos · {t}': '{n} ویدیو · {t}',
    'Analyze + blueprints + research': 'تحلیل + بلوپرینت‌ها + تحقیق',
    'Analyze + combine research': 'تحلیل + ترکیب تحقیق',
    'Channel + blueprints + research': 'کانال + بلوپرینت‌ها + تحقیق',
    'Channel + research': 'کانال + تحقیق',
    '{n} brief(s): {list}': '{n} بریف: {list}',
    'Analyzing with {p} and folding in {b} brief(s) — this can take a few minutes…':
        'تحلیل با {p} و تلفیق {b} بریف — ممکن است چند دقیقه طول بکشد…',
    'Analyzing with {p}, folding in {n} blueprint(s) and {b} brief(s) — this can take a few minutes…':
        'تحلیل با {p}، با تلفیق {n} بلوپرینت و {b} بریف — ممکن است چند دقیقه طول بکشد…',
})

# ══════════════════════════════════════════════════════════════════════
#  added: Keyword Research page, the two-call combined report, and the
#  snapshot picker's DATA / RESEARCH distinction
# ══════════════════════════════════════════════════════════════════════
FA_STRINGS.update({
    # ── the page itself ──
    'Keyword Research': 'تحقیق کلمات کلیدی',
    'What people search for, next to what is already published for it. No API key, no quota.':
        'آن‌چه مردم جست‌وجو می‌کنند، در کنار آن‌چه همین حالا برایش منتشر شده. بدون کلید API، بدون سهمیه.',
    'Research a phrase': 'تحقیق یک عبارت',
    'Zero quota · zero AI': 'بدون سهمیه · بدون هوش مصنوعی',
    'SEED KEYWORD': 'کلمهٔ کلیدی پایه',
    'e.g. air fryer recipes': 'مثلاً دستور پخت با ایرفرایر',
    'A topic or phrase, not a full sentence. Everything else is discovered from it.':
        'یک موضوع یا عبارت، نه یک جملهٔ کامل. بقیهٔ چیزها از همین کشف می‌شود.',
    'COUNTRY': 'کشور',
    'TIMEFRAME': 'بازهٔ زمانی',
    'Last 7 days': 'هفت روز گذشته',
    'Last 30 days': 'سی روز گذشته',
    'Last 90 days': 'نود روز گذشته',
    'Last 12 months': 'دوازده ماه گذشته',
    'Last 5 years': 'پنج سال گذشته',
    'Deep expansion (a-z)': 'گسترش عمیق (a تا z)',
    'Expands the seed with every letter a-z as well as question words — about 3× the vocabulary, and roughly 20 seconds instead of 6.':
        'کلمهٔ پایه را با همهٔ حروف a تا z و کلمات پرسشی گسترش می‌دهد — حدود ۳ برابر واژگان، و تقریباً ۲۰ ثانیه به‌جای ۶ ثانیه.',
    'Question words only (how, why, best, vs…). Fast, and already enough to see the shape of the demand.':
        'فقط کلمات پرسشی (how، why، best، vs…). سریع است و همین برای دیدن شکل تقاضا کافی است.',
    'Research keyword': 'تحقیق کلمهٔ کلیدی',
    'Researching …': 'در حال تحقیق …',
    'Enter a keyword or phrase to research.': 'یک کلمهٔ کلیدی یا عبارت برای تحقیق وارد کنید.',
    'Clear Trends cache': 'پاک‌کردن کش گوگل ترندز',
    'Cached Google Trends data cleared.': 'دادهٔ کش‌شدهٔ گوگل ترندز پاک شد.',
    'Could not clear the Trends cache.': 'کش گوگل ترندز پاک نشد.',

    # ── the ranked table ──
    'Ranked for “{s}”': 'رتبه‌بندی برای «{s}»',
    '{n} of {v} suggestions measured': '{n} از {v} پیشنهاد اندازه‌گیری شد',
    'Opportunity is a weighted reading of demand × how open the field is × whether a new video can place × whether the topic is still alive. It is a judgement built from real measurements, not a measurement itself — open a row to see every part of it.':
        'فرصت، خوانشی وزن‌دار است از تقاضا × بازبودن میدان × این‌که یک ویدیوی تازه شانس دیده‌شدن دارد یا نه × این‌که موضوع هنوز زنده است یا نه. این یک قضاوت ساخته‌شده از اندازه‌گیری‌های واقعی است، نه خودِ یک اندازه‌گیری — برای دیدن تمام اجزایش یک ردیف را باز کنید.',
    'KEYWORD': 'کلمهٔ کلیدی',
    'YT': 'یوتیوب',
    'GOOGLE': 'گوگل',
    'YT LEAN': 'گرایش یوتیوب',
    'MEDIAN': 'میانه',
    'CHANNELS': 'کانال‌ها',
    'OPPORTUNITY': 'فرصت',
    'SEED': 'پایه',
    'TOO RARE TO MEASURE': 'کم‌تر از حد اندازه‌گیری',
    'EST': 'تقریبی',
    'Strong': 'قوی',
    'Fair': 'متوسط',
    'Weak': 'ضعیف',
    'Crowded': 'اشباع',
    '{u} of {n}': '{u} از {n}',
    '{n} in 30d': '{n} در ۳۰ روز',

    # ── the expanded breakdown ──
    'DEMAND': 'تقاضا',
    'OPENNESS': 'بازبودن',
    'HEADROOM': 'فضای رشد',
    'FRESHNESS': 'تازگی',
    'Relative search interest on YouTube.': 'میزان نسبی علاقهٔ جست‌وجو در یوتیوب.',
    'From autocomplete standing — Trends was throttled.':
        'از جایگاه در تکمیل خودکار — ترندز محدود شده بود.',
    'How spread the existing videos are across channels.':
        'ویدیوهای موجود چه‌قدر بین کانال‌ها پخش شده‌اند.',
    'Read off the median result, never the average.':
        'از میانهٔ نتایج خوانده می‌شود، هرگز از میانگین.',
    'Not checked.': 'بررسی نشد.',
    'This keyword wasn\'t checked against YouTube — only the strongest few are, because each check reads a real results page. Its score rests on demand alone.':
        'این کلمهٔ کلیدی با یوتیوب مقایسه نشد — فقط چند مورد قوی‌تر بررسی می‌شوند، چون هر بررسی یک صفحهٔ نتایج واقعی را می‌خواند. امتیازش تنها بر تقاضا تکیه دارد.',
    'This keyword wasn\'t checked against YouTube, so there is nothing to analyze yet.':
        'این کلمهٔ کلیدی با یوتیوب مقایسه نشد، پس هنوز چیزی برای تحلیل وجود ندارد.',
    'Read this set': 'خواندن این مجموعه',
    'Full search': 'جست‌وجوی کامل',
    'Research this instead': 'به‌جایش این را تحقیق کن',
    'appears in {h} autocomplete lists · best position {r}':
        'در {h} فهرست تکمیل خودکار دیده می‌شود · بهترین جایگاه {r}',

    # ── vocabulary + trending ──
    'Everything people type': 'هر چیزی که مردم تایپ می‌کنند',
    '{n} phrases': '{n} عبارت',
    'Real completions from YouTube\'s own suggest index. There is no search volume here — Google publishes the ranking, never the counts — so click one to measure it properly.':
        'تکمیل‌های واقعی از ایندکس پیشنهاد خودِ یوتیوب. اینجا حجم جست‌وجو وجود ندارد — گوگل رتبه‌بندی را منتشر می‌کند، هرگز شمارش را — پس روی یکی بزنید تا درست اندازه‌گیری شود.',
    'Trending right now': 'همین حالا داغ',
    'Google Trends · rising searches': 'گوگل ترندز · جست‌وجوهای صعودی',
    'What is spiking in the selected country. Broad and short-lived — useful for a fast reactive video, not for planning a series.':
        'آن‌چه در کشور انتخاب‌شده جهش کرده. کلی و کوتاه‌عمر — برای یک ویدیوی واکنشی سریع خوب است، نه برای برنامه‌ریزی یک مجموعه.',
    'Nothing loaded — press Refresh, or pick a country above.':
        'چیزی بار نشد — «تازه‌سازی» را بزنید، یا از بالا یک کشور انتخاب کنید.',
    'Start with a phrase you are considering': 'با عبارتی که در نظر دارید شروع کنید',
    'You get the phrases people actually type around it, how much of that demand is on YouTube versus Google, and — for the strongest few — what is already published for it: the median result, how many channels hold it, and how recent it is.':
        'عبارت‌هایی را می‌گیرید که مردم واقعاً پیرامون آن تایپ می‌کنند، این‌که چه بخشی از آن تقاضا در یوتیوب است و چه بخشی در گوگل، و — برای چند مورد قوی‌تر — آن‌چه همین حالا برایش منتشر شده: میانهٔ نتایج، تعداد کانال‌هایی که آن را در دست دارند، و این‌که چه‌قدر تازه است.',

    # ── status lines ──
    'Reading what people type after “{s}” …': 'خواندن آن‌چه مردم پس از «{s}» تایپ می‌کنند …',
    'Expanding “{s}” — {d} of {t} …': 'گسترش «{s}» — {d} از {t} …',
    'Measuring search interest on YouTube …': 'اندازه‌گیری علاقهٔ جست‌وجو در یوتیوب …',
    'YouTube interest — batch {d} of {t} …': 'علاقه در یوتیوب — دستهٔ {d} از {t} …',
    'Comparing against Google web search …': 'مقایسه با جست‌وجوی وب گوگل …',
    'Google interest — batch {d} of {t} …': 'علاقه در گوگل — دستهٔ {d} از {t} …',
    'Checking what is already published for “{k}” — {i} of {n} …':
        'بررسی آن‌چه همین حالا برای «{k}» منتشر شده — {i} از {n} …',
    'Starting …': 'شروع …',
    'Stopping …': 'در حال توقف …',
    'Done.': 'انجام شد.',
    'Keyword research ready.': 'تحقیق کلمات کلیدی آماده است.',
    'Keyword research failed.': 'تحقیق کلمات کلیدی شکست خورد.',
    'Nothing came back for that phrase.': 'برای آن عبارت چیزی برنگشت.',
    '{n} keywords ranked from {v} suggestions · {p} checked against what is already published.':
        '{n} کلمهٔ کلیدی از {v} پیشنهاد رتبه‌بندی شد · {p} مورد با آن‌چه منتشر شده مقایسه شد.',
    '{n} keywords ranked from {v} suggestions — but part of the data was unavailable, see the note below.':
        '{n} کلمهٔ کلیدی از {v} پیشنهاد رتبه‌بندی شد — اما بخشی از داده در دسترس نبود، یادداشت پایین را ببینید.',
    'Ranked on autocomplete standing, not measured interest':
        'رتبه‌بندی بر پایهٔ جایگاه در تکمیل خودکار، نه علاقهٔ اندازه‌گیری‌شده',
    'Part of the data was unavailable': 'بخشی از داده در دسترس نبود',
    'YouTube\'s autocomplete returned nothing for this phrase. Check the spelling, or try a broader term.':
        'تکمیل خودکار یوتیوب برای این عبارت چیزی برنگرداند. املا را بررسی کنید، یا عبارت کلی‌تری را امتحان کنید.',
    'Enter a keyword first.': 'ابتدا یک کلمهٔ کلیدی وارد کنید.',
    'A keyword cannot contain a comma when comparing terms.':
        'وقتی عبارت‌ها مقایسه می‌شوند، یک کلمهٔ کلیدی نمی‌تواند ویرگول داشته باشد.',

    # ── Trends transport errors ──
    'Google Trends is rate-limiting this connection. It does this per IP address and it clears on its own — wait a few minutes before asking for more keywords.':
        'گوگل ترندز این اتصال را محدود کرده است. این کار را بر پایهٔ IP انجام می‌دهد و خودش برطرف می‌شود — پیش از درخواست کلمات بیشتر چند دقیقه صبر کنید.',
    'Google Trends served its block page instead of data, which means this IP is being throttled. Wait a few minutes and try again.':
        'گوگل ترندز به‌جای داده صفحهٔ مسدودسازی‌اش را فرستاد، یعنی این IP محدود شده است. چند دقیقه صبر کنید و دوباره تلاش کنید.',
    'Google web-search comparison was skipped because Trends is already throttling this connection.':
        'مقایسه با جست‌وجوی وب گوگل انجام نشد، چون ترندز همین حالا این اتصال را محدود کرده است.',
    'Google Trends answered with an error ({code}).': 'گوگل ترندز با خطا پاسخ داد ({code}).',
    'Google Trends returned no readable data.': 'گوگل ترندز دادهٔ قابل‌خواندنی برنگرداند.',
    'Google Trends returned data this app could not read.':
        'گوگل ترندز داده‌ای برگرداند که این برنامه نتوانست بخواند.',
    'Could not reach Google Trends: {reason}': 'دسترسی به گوگل ترندز ممکن نشد: {reason}',
    'The connection to Google Trends was cut mid-request. If you are on a proxy or VPN, check it is still up.':
        'اتصال به گوگل ترندز در میانهٔ درخواست قطع شد. اگر روی پراکسی یا VPN هستید، ببینید همچنان بالاست.',

    # ── snapshot picker: numbers-only vs numbers+brief ──
    'DATA': 'داده',
    'Optional — a saved snapshot is research about the niche, not about this channel. A DATA row carries the measured aggregates (median vs average, momentum, length and recency mix, channel concentration); a RESEARCH row adds the written brief on top, every statement keeping its label (observed / inferred / needs Studio). The report is told the channel\'s own numbers win where the two disagree.':
        'اختیاری — یک اسنپ‌شات ذخیره‌شده تحقیق درباره‌ی نیچ است، نه درباره‌ی این کانال. ردیفِ «داده» شاخص‌های اندازه‌گیری‌شده را دارد (میانه در برابر میانگین، شتاب، ترکیب طول و تازگی، تمرکز کانال‌ها)؛ ردیفِ «تحقیق» بریفِ نوشته‌شده را هم روی آن می‌افزاید و هر گزاره برچسب خودش را نگه می‌دارد (مشاهده‌شده / استنباطی / نیازمند استودیو). به گزارش گفته می‌شود هرجا این دو با هم نخوانند، عددهای خودِ کانال حرف آخر را می‌زنند.',

    # ── the second synthesis call ──
    'Sharpening {n} blueprint(s) against this channel …':
        'تیزکردن {n} بلوپرینت بر پایهٔ داده‌های این کانال …',

    # Short, generic labels this page needs and the dictionary did not carry yet
    # (only longer variants like "Stop the running search" existed).
    'Stop': 'توقف',
    'Refresh': 'تازه‌سازی',
    'Loading …': 'در حال بارگیری …',

    # ── the Trends budget, stated in the UI rather than hidden ──
    '{m} of {n} measured on Trends · {v} suggestions found':
        '{m} از {n} مورد در ترندز اندازه‌گیری شد · {v} پیشنهاد پیدا شد',
    'Google Trends throttles per IP, so only the strongest few terms get a measured interest number. The rest are ranked on how they place in real autocomplete and — where checked — on what is already published for them.':
        'گوگل ترندز بر پایهٔ IP محدودیت می‌گذارد، پس فقط چند عبارت قوی‌تر عددِ علاقهٔ اندازه‌گیری‌شده می‌گیرند. بقیه بر پایهٔ جایگاهشان در تکمیل خودکار واقعی و — جایی که بررسی شده — بر پایهٔ آن‌چه برایشان منتشر شده رتبه‌بندی می‌شوند.',
    '{n} keywords ranked from {v} suggestions · {m} measured on Trends · {p} checked against what is already published.':
        '{n} کلمهٔ کلیدی از {v} پیشنهاد رتبه‌بندی شد · {m} مورد در ترندز اندازه‌گیری شد · {p} مورد با آن‌چه منتشر شده مقایسه شد.',

    # ── Keyword Research redesign: Highest volume / Easiest wins / Competitors
    # / Who is searching (the full table is gone) ──
    'Highest volume': 'بیشترین حجم جست‌وجو',
    'measured on Trends · relative 0–100, not counts': 'اندازه‌گیری‌شده در ترندز · نسبی ۰ تا ۱۰۰، نه تعداد',
    'Relative search interest — 100 is the busiest term in this set, not a search count. Rows marked EST rank on autocomplete standing: real phrases people type, but not measured interest. KD is derived from each keyword\'s own results, not an official score.':
        'علاقهٔ نسبی جست‌وجو — ۱۰۰ یعنی پرطرفدارترین عبارتِ این مجموعه، نه تعداد جست‌وجو. ردیف‌هایی که EST دارند بر پایهٔ رتبهٔ تکمیل خودکارند: عبارت‌های واقعی‌ای که مردم تایپ می‌کنند، اما نه علاقهٔ اندازه‌گیری‌شده. KD از نتایج خودِ همان کلمهٔ کلیدی استخراج شده، نه یک عدد رسمی.',
    'KD {n}': 'KD {n}',
    'Keyword difficulty — derived from how concentrated this keyword\'s existing results are, not an official score.':
        'سختی کلمهٔ کلیدی — از میزان تمرکز نتایج موجودِ همین کلمهٔ کلیدی استخراج شده، نه یک امتیاز رسمی.',
    'Ordered by opportunity; the bar shows how open the field is, so the bar and the figure beside it say the same thing. KD = keyword difficulty, derived from how concentrated the results\' channels are.':
        'مرتب بر پایهٔ فرصت؛ نمودار نشان می‌دهد میدان چقدر باز است، پس نمودار و عدد کنارش یک حرف می‌زنند. KD یعنی سختی کلمهٔ کلیدی، از میزان تمرکز کانال‌های دارندهٔ نتایج.',
    'open {p}%': 'باز {p}٪',

    'Selected keyword': 'کلمهٔ کلیدی انتخاب‌شده',
    'median {m} · {c}': 'میانه {m} · {c}',
    'Competitors': 'رقیب‌ها',
    'Share of this keyword\'s total views. High concentration means established channels hold the term; a spread means an open field.':
        'سهمی از کل بازدیدهای این کلمهٔ کلیدی. تمرکز بالا یعنی کانال‌های جاافتاده صاحب این عبارت‌اند؛ پراکندگی یعنی میدانی باز.',

    'Who is searching': 'چه کسی جست‌وجو می‌کند',
    'where + what they want are measured · who is inferred': 'کجا و چه می‌خواهند اندازه‌گیری‌شده است · چه کسی، استنباطی',
    'WHERE — measured': 'کجا — اندازه‌گیری‌شده',
    'WHAT THEY WANT — measured': 'چه می‌خواهند — اندازه‌گیری‌شده',
    'WHO — inferred from what serves them': 'چه کسی — استنباط از آن‌چه این تقاضا را پاسخ می‌دهد',
    'Share of the real autocomplete vocabulary that opens with each intent. A share of phrases, never of searches — Google publishes the ranking, not the counts.':
        'سهم واژگان واقعی تکمیل خودکار که با هر نیت آغاز می‌شوند. سهمی از عبارت‌ها، نه از جست‌وجوها — گوگل رتبه را منتشر می‌کند، نه تعداد را.',
    'No completion in this run opened with a question word.': 'هیچ تکمیل‌شده‌ای در این اجرا با کلمهٔ پرسشی شروع نشد.',
    'Learning': 'یادگیری',
    'Comparing': 'مقایسه',
    'Getting started': 'شروع کار',
    'Shorts among the ranking videos': 'شورتس میان ویدیوهای رتبه‌بندی‌شده',
    'Median video length': 'میانهٔ طول ویدیو',
    'Uploaded in the last 30 days': 'منتشرشده در ۳۰ روز گذشته',
    'INFERRED — from the supply data, not measured': 'استنباطی — از دادهٔ عرضه، نه اندازه‌گیری‌شده',
    'This demand is mostly served by Shorts — a feed, not a search page. Viewers are likely browsing on mobile, skews young, and reward fast payoffs.':
        'این تقاضا بیشتر با شورتس پاسخ داده می‌شود — یک فید، نه صفحهٔ جست‌وجو. بینندگان احتمالاً با موبایل مرور می‌کنند، به سمت جوان متمایل‌اند و پاداش سریع را دوست دارند.',
    'The ranking videos are short and quick — viewers want the answer now, not a deep dive, and are likely watching on mobile.':
        'ویدیوهای رتبه‌بندی‌شده کوتاه و تند هستند — بیننده همین حالا جواب را می‌خواهد، نه تحلیل عمیق را، و احتمالاً با موبایل تماشا می‌کند.',
    'A third of the ranking videos are fresh — this is an active, fast-moving topic where viewers come back for what is new.':
        'یک‌سوم ویدیوهای رتبه‌بندی‌شده تازه‌اند — موضوعی فعال و تندرو که بینندگان برای تازه‌ها به آن برمی‌گردند.',
    'The ranking videos are mostly established long-form — viewers arrive with a question and expect a considered answer.':
        'ویدیوهای رتبه‌بندی‌شده بیشتر بلندِ جاافتاده‌اند — بیننده با یک سؤال می‌آید و پاسخی سنجیده انتظار دارد.',

    # ── Archive rename dialog rebuild ──
    'Enter saves. The name shows up in the sections list and the archive header.':
        'کلید Enter ذخیره می‌کند. این نام در فهرست بخش‌ها و سربرگ آرشیو دیده می‌شود.',

    # ── Keyword Research follow-ups: shortlists, map, hints, empty states ──
    'Easiest wins': 'راحت‌ترین بردها',
    'demand for the least competition': 'تقاضا با کمترین رقابت',
    'Opportunity map': 'نقشه‌ی فرصت',
    'How the set splits': 'مجموعه چگونه تقسیم می‌شود',
    'Search interest over time': 'علاقه‌ی جست‌وجو در طول زمان',
    'YouTube search · {t}': 'جست‌وجوی یوتیوب · {t}',
    'Rising and related': 'رو به رشد و مرتبط',
    'MOST ASSOCIATED': 'مرتبط‌ترین‌ها',
    'Research this phrase instead': 'به‌جایش این عبارت را بررسی کن',
    'No interest curve came back for this run.': 'برای این اجرا هیچ منحنی علاقه‌ای برنگشت.',
    'No keyword was checked against YouTube in this run.': 'در این اجرا هیچ کلمه‌ی کلیدی با یوتیوب سنجیده نشد.',
    'No regional split came back.': 'هیچ تفکیک منطقه‌ای برنگشت.',
    'Nothing in this run carries a measured interest number.': 'هیچ‌چیز در این اجرا عدد علاقه‌ی اندازه‌گیری‌شده ندارد.',
    'Nothing was checked against YouTube in this run.': 'در این اجرا هیچ‌چیز با یوتیوب سنجیده نشد.',
    'click a dot to open its breakdown': 'روی یک نقطه بزن تا شکافته‌اش باز شود',
    'the phrase you typed': 'عبارتی که تایپ کردی',
    'discovered phrases': 'عبارت‌های کشف‌شده',
    'demand  →': 'تقاضا  →',
    'how open the field is  →': 'میدان چقدر باز است  →',
    'keywords': 'کلمه‌های کلیدی',
    'peak {v}': 'قله {v}',
    '{n} checked': '{n} سنجیده‌شده',
    '{n} ranked': '{n} رتبه‌بندی‌شده',
    "Google Trends · beside “{s}”": 'گوگل ترندز · کنار «{s}»',
    "Bands, not scores: the number behind each one is a weighted judgement, and “strong” is the claim it can actually support.":
        'باندها، نه امتیازها: عدد پشت هرکدام یک داوری وزن‌دار است و «قوی» همان ادعایی است که واقعاً می‌تواند پشتیبانی کند.',
    "Demand up, how open the field is across, dot size = how much room a new video has. Top-right is the answer: more demand than most of this set, for a field more open than most of it. Only keywords that were actually checked against YouTube appear — placing an unchecked one at zero would be a claim about competition nobody looked at.":
        'تقاضا رو به بالا، میزان باز بودن میدان در محور افقی، اندازه‌ی نقطه = فضای خالی‌ای که برای یک ویدیوی تازه هست. بالا-راست همان جواب است: تقاضای بیشتر از بیشتر این مجموعه، برای میدانی بازتر از بیشتر آن. فقط کلمه‌های کلیدی‌ای که واقعاً با یوتیوب سنجیده شده‌اند دیده می‌شوند — گذاشتن یک مورد نسنجیده روی صفر، ادعایی درباره‌ی رقابتی است که کسی نگاهش نکرده.',
    "Nothing here costs API quota. The slow part is deliberate: each keyword's competition is read off a real YouTube results page, and Google Trends is asked at a pace that keeps it answering.":
        'هیچ‌چیز اینجا سهمیه‌ی API مصرف نمی‌کند. کندی عمدی است: رقابت هر کلمه‌ی کلیدی از یک صفحه‌ی واقعی نتایج یوتیوب خوانده می‌شود و از گوگل ترندز با سرعتی سؤال می‌شود که جواب بدهد.',
    "RISING — growth, not interest. Google reports anything above 5000% as “Breakout”, so its own label is shown rather than a number derived from it.":
        'رشد — نه علاقه. گوگل هر چیزی بالای ۵۰۰۰٪ را «Breakout» گزارش می‌کند، پس برچسب خودش نشان داده می‌شود نه عددی که از آن ساخته شده باشد.',
    "Relative per head, which is Google's own definition — not “most searches happen here”. A small region that searches this constantly outranks a large one that searches it occasionally.":
        'نسبی سرانه، که همان تعریف خود گوگل است — نه «بیشترین جست‌وجوها اینجا اتفاق می‌افتد». یک منطقه‌ی کوچک که مدام این را جست‌وجو می‌کند از منطقه‌ی بزرگی که گاهی جست‌وجو می‌کند بالاتر می‌ایستد.',
    "The measured keywords on ONE shared scale — 100 is the busiest point any of them reached in this window, not a volume. Sharing a scale is the whole value of asking Trends for them together: curves fetched separately each peak at 100 and cannot be compared.":
        'کلمه‌های کلیدی اندازه‌گیری‌شده روی یک مقیاس مشترک — ۱۰۰ یعنی شلوغ‌ترین نقطه‌ای که هرکدام در این بازه دیده‌اند، نه حجم. مشترک بودن مقیاس تمام ارزش این است که ترندز را برایشان با هم پرسیده‌ایم: منحنی‌هایی که جدا گرفته شوند هرکدام در قله ۱۰۰ می‌ایستند و قابل مقایسه نیستند.',

    # ── Keyword headline tiles, tooltips, scatter labels ──
    'Best opportunity': 'بهترین فرصت',
    'Checked on YouTube': 'سنجیده‌شده با یوتیوب',
    'checked on YouTube': 'سنجیده‌شده با یوتیوب',
    'Measured on Trends': 'اندازه‌گیری‌شده در ترندز',
    'Median opportunity': 'میانه‌ی فرصت',
    'Phrases found': 'عبارت‌های پیداشده',
    'phrases found': 'عبارت‌های پیداشده',
    'Relative interest on YouTube search, 0-100 within this set.': 'علاقه‌ی نسبی در جست‌وجوی یوتیوب، ۰ تا ۱۰۰ در همین مجموعه.',
    'Typical result': 'نتیجه‌ی معمول',
    'YT {p}%': 'YT {p}٪',
    'across {n} rows': 'در {n} ردیف',
    'autocomplete fallback': 'جایگزین تکمیل خودکار',
    'demand': 'تقاضا',
    'median views': 'میانه‌ی بازدید',
    'median views, not average': 'میانه‌ی بازدید، نه میانگین',
    'openness': 'باز بودن',
    'opportunity': 'فرصت',
    'real interest data': 'داده‌ی واقعی علاقه',
    'zero quota': 'بدون سهمیه',
    '{m} min': '{m} دقیقه',
    '{n} in the sweet spot': '{n} در نقطه‌ی طلایی',

    # ── Usage ledger labels, runway, mix note ──
    '1 unit per 50 channels': '۱ واحد برای هر ۵۰ کانال',
    '1 unit per 50 videos': '۱ واحد برای هر ۵۰ ویدیو',
    '1 unit per call': '۱ واحد برای هر فراخوان',
    '100 units per search page': '۱۰۰ واحد برای هر صفحه‌ی جست‌وجو',
    'At {r} units/day, your recent average. Roughly {s} more keyword searches.': 'با {r} واحد در روز، میانگین اخیر شما. تقریباً {s} جست‌وجوی کلیدواژه‌ی دیگر.',
    'Before tracking': 'قبل از رهگیری',
    'Nothing cached yet. Every search you run gets stored, and reopening it later is free.': 'هنوز چیزی کش نشده. هر جست‌وجویی که اجرا کنید ذخیره می‌شود و بازکردن بعدی‌اش رایگان است.',
    'total known, split not recorded': 'جمع مشخص، تفکیک ثبت نشده',
    "“Before tracking” is {n} day(s) recorded before this app split spend by call type — the totals are right, the breakdown for those days was never stored. They drop out of this window on their own.":
        '«قبل از رهگیری» یعنی {n} روزی که پیش از تفکیک مصرف بر پایه‌ی نوع فراخوان ثبت شده — جمع‌ها درست‌اند، تفکیک آن روزها هرگز ذخیره نشده. خودشان از این بازه خارج می‌شوند.',

    # ── Usage page clarity: what bumps each ledger + how the page counts ──
    'How this page counts': 'این صفحه چگونه می‌شمارد',
    'Three ledgers: the search bucket (100 search calls a day), raw units per day (what YouTube actually bills), and spend per key.':
        'سه دفتر وجود دارد: سطل جست‌وجو (۱۰۰ فراخوان جست‌وجو در روز)، واحدهای خام روزانه (آن‌چه یوتیوب واقعاً حساب می‌کند)، و مصرف هر کلید.',
    'An API-source Niche Finder search bumps all three at once — bucket +1, units +100 (plus +1 per enrichment call), and the matching key row.':
        'یک جست‌وجوی نیچ فایندر با منبع API هر سه را هم‌زمان زیاد می‌کند — سطل ۱+، واحدها ۱۰۰+ (به‌علاوه ۱+ برای هر فراخوان تکمیلی)، و ردیف کلید مربوط.',
    'A Web scrape touches none of the search bucket — only +1-unit enrichment calls, and only when a key is set.':
        'اسکرپ وب به سطل جست‌وجو دست نمی‌زند — فقط فراخوان‌های تکمیلی ۱ واحدی، و فقط وقتی کلیدی تنظیم شده باشد.',

    # ── Video Cutter ──
    'Video Cutter': 'برش‌زن ویدیو',
    'Cut any part of a video — a YouTube link or a file you already have — and download just that clip, at its own quality up to 4K. The full video is never downloaded first.':
        'هر بخشی از یک ویدیو را ببر — لینک یوتیوب یا فایلی که داری — و فقط همان تکه را با کیفیت خودش تا 4K دانلود کن. کل ویدیو هرگز اول دانلود نمی‌شود.',
    'YouTube link': 'لینک یوتیوب',
    'Local file': 'فایل محلی',
    'Read video': 'خواندن ویدیو',
    'Video file': 'فایل ویدیویی',
    'Pick a file you already downloaded…': 'فایلی که قبلاً دانلود کرده‌ای انتخاب کن…',
    'Browse…': 'مرور…',
    'Read file': 'خواندن فایل',
    'Start': 'شروع',
    'End': 'پایان',
    'Cut & Download': 'برش و دانلود',
    'Cutting…': 'در حال برش…',
    'Open folder': 'باز کردن پوشه',
    'Open file': 'باز کردن فایل',
    'New clip': 'کلیپ جدید',
    'Choose a video file': 'یک فایل ویدیویی انتخاب کن',
    'Video files': 'فایل‌های ویدیویی',
    'All files': 'همه‌ی فایل‌ها',
    'Best quality': 'بهترین کیفیت',
    'highest available': 'بالاترین کیفیت موجود',
    'M:SS or seconds — Enter to set': 'دقیقه:ثانیه یا ثانیه — Enter برای ثبت',
    'Length: {d}': 'مدت: {d}',
    'Clip: {d}': 'کلیپ: {d}',
    'Original quality (stream copy)': 'کیفیت اصلی (کپی استریم)',
    'Paste a link or pick a file, then read it.': 'لینک بده یا فایل انتخاب کن، بعد بخوانش.',
    'Read the file to see its length.': 'فایل را بخوان تا مدتش معلوم شود.',
    'Clipboard is empty.': 'کلیپ‌بورد خالی است.',
    'Paste a YouTube link first.': 'اول لینک یوتیوب بده.',
    'Pick a video file first.': 'اول یک فایل ویدیویی انتخاب کن.',
    'Reading…': 'در حال خواندن…',
    'Ready — pick a segment, then cut it.': 'آماده — بازه را انتخاب کن، بعد ببر.',
    'Use seconds or M:SS — e.g. 90 or 1:30.': 'ثانیه یا دقیقه:ثانیه بنویس — مثلاً 90 یا 1:30.',
    'Stopping…': 'در حال توقف…',
    'Cut stopped.': 'برش متوقف شد.',
    'Saved.': 'ذخیره شد.',
    'Clip saved — {p}': 'کلیپ ذخیره شد — {p}',
    'Cut failed.': 'برش ناموفق بود.',
    'Could not open: {e}': 'باز نشد: {e}',
    'Cut started — {a} → {b}': 'برش شروع شد — {a} ← {b}',
    '{done} · {pct}%': '{done} · {pct}٪',
    'Reading the video…': 'در حال خواندن ویدیو…',
    'Cutting {a} → {b} …': 'برش {a} ← {b} …',
    'Bad segment times.': 'زمان‌های بازه درست نیست.',
    'The end must be after the start.': 'پایان باید بعد از شروع باشد.',
    'The start is past the end of the video.': 'شروع از انتهای ویدیو رد شده.',
    'No playable stream at that quality.': 'در این کیفیت استریم قابل پخشی نیست.',
    "Couldn't read that video.": 'آن ویدیو خوانده نشد.',
    'This video has no downloadable video stream.': 'این ویدیو استریم ویدیویی قابل دانلودی ندارد.',
    "Couldn't read this video's duration.": 'مدت این ویدیو خوانده نشد.',
    "Couldn't read that file.": 'آن فایل خوانده نشد.',
    'The cut file was not written.': 'فایل برش نوشته نشد.',
    'The cut came out empty.': 'خروجی برش خالی درآمد.',
    'Preview': 'پیش‌نمایش',
    'Set Start': 'ثبت شروع',
    'Set End': 'ثبت پایان',
    'Preview clip': 'پیش‌نمایش کلیپ',
    'Preview without sound': 'پیش‌نمایش بدون صدا',
    'Preview expired — press Read video again.': 'پیش‌نمایش منقضی شد — دوباره «خواندن ویدیو» را بزن.',
})

# ── added: plain-words live download readout ──
# The row's running line was an unlabelled run of figures ("2% · 122 MB left ·
# 471 KB/s · 4m 24s left · 2/97 frags") that a first-time viewer could not read.
# It now leads with a verb, drops the redundant second "left", and moves the
# internal part count into a hover tooltip that spells every figure out.
FA_STRINGS.update({
    'Downloading {pct}%': 'در حال دانلود {pct}٪',
    'Downloading video': 'در حال دانلود ویدیو',
    '{pct}% complete': '{pct}٪ کامل',
    '{size} · {left} left': '{size} · {left} مانده',
    'Speed {s}': 'سرعت {s}',
    'Speed {s} · {t} left': 'سرعت {s} · {t} مانده',
    'Merging the audio and video into one file…':
        'ادغام صدا و تصویر در یک فایل…',
    # The row's tooltip also uses the existing '{done} of {total}', '{t} left'
    # and 'part {i} of {n}' keys, defined above.
})

# ── added: Video Cutter page redesign ──
# The cutter is now three numbered steps (source → segment → quality & output)
# with a floating Cut bar, so the page needed a step vocabulary it did not have
# before: the three step titles, their one-line hints, the three-line "how it
# works" empty state, and the timeline instructions.
FA_STRINGS.update({
    'Source': 'منبع',
    'Give the cutter something to work on: a YouTube link, or a video file already on this PC.':
        'به برش‌زن یک منبع بده: یک لینک یوتیوب، یا یک فایل ویدیویی که همین حالا روی این کامپیوتر داری.',
    'Segment': 'بازه',
    'Click the timeline to scrub, drag the white S / E handles to move the edges, or type an exact time.':
        'روی تایم‌لاین کلیک کن تا جابه‌جا شوی، دستگیره‌های سفید S / E را بکش تا لبه‌ها جابه‌جا شوند، یا زمان دقیق را تایپ کن.',
    'Quality & output': 'کیفیت و خروجی',
    'A local file is copied at its own quality — nothing to choose. The Cut button is on the bar below.':
        'فایل محلی با کیفیت خودش کپی می‌شود — چیزی برای انتخاب نیست. دکمه‌ی برش روی نوار پایین است.',
    'Pick the quality the clip is saved at, then cut it from the bar below.':
        'کیفیتی که کلیپ با آن ذخیره می‌شود را انتخاب کن، بعد از نوار پایین برشش بزن.',
    'Drag the white S / E handles, or type an exact time below.':
        'دستگیره‌های سفید S / E را بکش، یا زمان دقیق را پایین تایپ کن.',
    'Whole video': 'کل ویدیو',
    'Clip {d}': 'کلیپ {d}',
    'Preview quality {q}': 'کیفیت پیش‌نمایش {q}',
    'How it works': 'چطور کار می‌کند',
    'Three steps, and only the piece you pick ever comes down.':
        'سه قدم، و فقط همان تکه‌ای که انتخاب می‌کنی دانلود می‌شود.',
    'Paste a YouTube link, or pick a video file you already have.':
        'یک لینک یوتیوب بچسبان، یا یک فایل ویدیویی که داری انتخاب کن.',
    "Press Read — the video's length and qualities are fetched, not the video itself.":
        'دکمه‌ی «خواندن» را بزن — فقط مدت و کیفیت‌های ویدیو گرفته می‌شود، نه خود ویدیو.',
    'Mark the segment on the timeline, pick a quality, then Cut & Download.':
        'بازه را روی تایم‌لاین مشخص کن، کیفیت را انتخاب کن، بعد «برش و دانلود» را بزن.',
})


# ── added: search-driven Niche Finder filters, file-drop + honest cutter
# errors, and the topic-themed AI report ──────────────────────────────────
# The Niche Finder ranges now steer the search itself (widening when the first
# pass lands too few matches), Single Channel Scan drops the subscriber range,
# a video file can be dropped straight onto the Cutter page, and the Cutter
# says WHY a local file could not be read instead of one vague line.
FA_STRINGS.update({
    '~{c}–{max} search calls · {left} left today':
        '~{c} تا {max} فراخوان جست‌وجو · {left} تا امروز باقی مانده',
    'Widening the search to reach your filters (pass {n}) …':
        'گسترده‌کردن جست‌وجو تا رسیدن به فیلترها (مرحله‌ی {n}) …',
    'The search was widened {n} time(s) to reach these filters.':
        'جست‌وجو {n} بار گسترده شد تا به این فیلترها برسد.',
    "These ranges drive the search itself, not just the results it already fetched. If the first pass finds too few videos that fit, the app widens the search on its own - deeper time windows, more pages - and that spends more of today's search quota. Subscribers are ignored in Single Channel Scan.":
        'این بازه‌ها خودِ جست‌وجو را هدایت می‌کنند، نه فقط نتایجی که قبلاً گرفته شده. اگر مرحله‌ی اول ویدیوهای کافی مطابق فیلتر پیدا نکند، برنامه خودش جست‌وجو را گسترده می‌کند — بازه‌های زمانی عمیق‌تر و صفحه‌های بیشتر — و این از سهمیه‌ی امروز بیشتر مصرف می‌کند. در «اسکن یک کانال»، تعداد مشترک نادیده گرفته می‌شود.',
    'Drop the video here to load it':
        'ویدیو را اینجا رها کن تا بارگذاری شود',
    'That file is no longer there — pick it again.':
        'آن فایل دیگر آنجا نیست — دوباره انتخابش کن.',
    "The video engine isn't ready yet. Open the Downloads page once so it can set itself up, then try again.":
        'موتور ویدیو هنوز آماده نیست. یک‌بار صفحه‌ی دانلودها را باز کن تا خودش را آماده کند، بعد دوباره امتحان کن.',
    'That file took too long to read — it may be on a slow or disconnected drive.':
        'خواندن آن فایل خیلی طول کشید — شاید روی درایوی کند یا قطع‌شده باشد.',
    "Couldn't read that file — it may be damaged, or in a format the video engine can't open.":
        'آن فایل خوانده نشد — ممکن است خراب باشد یا قالبی داشته باشد که موتور ویدیو نمی‌تواند بازش کند.',
})

FA_STRINGS.update({
    'The search was already widened {n} time(s).':
        'جست‌وجو قبلاً {n} بار گسترده شده است.',
})

# ── سرویس‌دهنده‌ی سفارشی (Custom) ───────────────────────────────────────────
FA_STRINGS.update({
    'PROVIDER NAME': 'نام سرویس‌دهنده',
    'What to call this endpoint in messages and errors — "9router", "OpenRouter", "My gateway". Any name you like; it is only a label.':
        'این نقطه‌ی اتصال در پیام‌ها و خطاها با چه نامی خوانده شود — «9router»، «OpenRouter»، «گیت‌وی من». هر نامی که بخواهی؛ فقط یک برچسب است.',
    'My provider': 'سرویس‌دهنده‌ی من',
    'A custom provider ships with no defaults. Fill in API HOST and an exact MODEL id below, pick the wire shape it speaks, then Validate. Any OpenAI-compatible router, aggregator or self-hosted gateway works — including ones that expose Anthropic\'s or Google\'s shape — and it is stored under its own name so your built-in provider settings stay untouched.':
        'سرویس‌دهنده‌ی سفارشی هیچ مقدار پیش‌فرضی ندارد. پایین «میزبان API» و شناسه‌ی دقیق «مدل» را پر کن، حالت API را که پشتیبانی می‌کند انتخاب کن و بعد اعتبارسنجی بزن. هر روتر، اگریگیتور یا گیت‌وی خودمیزبان سازگار با OpenAI کار می‌کند — از جمله آن‌هایی که شکل Anthropic یا Google را ارائه می‌دهند — و با نام خودش ذخیره می‌شود تا تنظیمات سرویس‌دهنده‌های داخلی دست‌نخورده بماند.',
    'Custom': 'سفارشی',
    # نام سرویس‌دهنده‌ی سفارشی وقتی کاربر نامی نگذاشته باشد
    'Custom AI': 'هوش مصنوعی سفارشی',
    'Custom provider': 'سرویس‌دهنده‌ی سفارشی',
    'set API HOST first': 'اول میزبان API را وارد کن',
})

# ── دیالوگ نصب Deno (راه‌اندازی اولیه) ─────────────────────────────────────
# این رشته‌ها قبلاً ترجمه نداشتند، پس کاربر فارسی‌زبان در همان اجرای اول یک
# پنجره‌ی نیمه‌انگلیسی می‌دید.
FA_STRINGS.update({
    'YouTube downloads need a small JavaScript runtime. Install it now — it takes a moment — and your first download will just work.':
        'دانلود از یوتیوب به یک موتور کوچک جاوااسکریپت نیاز دارد. همین حالا نصبش کن — چند لحظه بیشتر طول نمی‌کشد — و اولین دانلودت بی‌دردسر انجام می‌شود.',
    'If you skip, it installs itself the first time you download a video.':
        'اگر رد کنی، اولین باری که ویدیویی دانلود کنی خودش نصب می‌شود.',
    'JavaScript runtime for YouTube downloads (~40 MB)':
        'موتور جاوااسکریپت برای دانلود یوتیوب (حدود ۴۰ مگابایت)',
    'Ready': 'آماده',
    'Not installed': 'نصب نشده',
    'File 1 of {t} · {done} of {total} · {pct}%':
        'فایل ۱ از {t} · {done} از {total} · {pct}٪',
    'File 1 of {t} · Downloading… {done}':
        'فایل ۱ از {t} · در حال دانلود… {done}',
    'Open the Downloads page once so it can set itself up, then try again.':
        'یک‌بار صفحه‌ی دانلودها را باز کن تا خودش را آماده کند، بعد دوباره امتحان کن.',
})

# ── پک «کارِ خالق» در گزارش ترکیبی (CSV + بلوپرینت) ────────────────────────
# پنج فیلد تازه‌ای که به بخش بلوپرینت گزارش اضافه شد: چرا پخش می‌شود، کی منتشر
# شود، چه اعدادی را در ۴۸ ساعت نگاه کنند، چه چیزی آن را می‌کُشد، و بعدش چه.
FA_STRINGS.update({
    'When': 'چه زمانی',
    'Why then': 'چرا این زمان',
    'First hour': 'ساعت اول',
    'Publish plan': 'برنامهٔ انتشار',
    'Publishing time is a lever most creators never touch — this one is read off your own numbers.':
        'زمان انتشار اهرمی است که بیشتر خالق‌ها هرگز لمسش نمی‌کنند — این یکی از روی اعداد خودتان خوانده شده است.',
    'What to watch — first 48 hours': 'چه چیزهایی را نگاه کنید — ۴۸ ساعت اول',
    'Targets are read off this channel\'s own averages, not off someone else\'s benchmark.':
        'هدف‌ها از میانگین‌های خودِ همین کانال خوانده شده‌اند، نه از معیار کس دیگر.',
    'What could sink this video': 'چه چیزی می‌تواند این ویدیو را زمین بزند',
    'Named before the shoot, so they get fixed instead of explained afterwards.':
        'قبل از ضربه‌گیری نام برده شده‌اند، تا اصلاح شوند به‌جای اینکه بعداً توجیه شوند.',
    'What comes next — keep this viewer': 'بعدش چه — این بیننده را نگه دار',
    'One video is a view; a series is a subscriber.':
        'یک ویدیو یعنی یک بازدید؛ یک سری یعنی یک سابسکرایبر.',
})

# ── پچ ۶: کاتر و سازگاری با ادیتور ────────────────────────────────────────
FA_STRINGS.update({
    'Cutting {a} → {b} (re-encoding for exact sync) …':
        'در حال برش {a} → {b} (بازکدگذاری برای هم‌گام‌بودن دقیق) …',
    'Re-encode unavailable — copying the stream instead …':
        'بازکدگذاری ممکن نبود — به‌جایش جریان کپی می‌شود …',
    'Converting to H.264 MP4 for editing ({c}) …':
        'در حال تبدیل به H.264 MP4 برای ادیت ({c}) …',
    'Saved as H.264 MP4 — ready for your editor.':
        'به‌صورت H.264 MP4 ذخیره شد — آمادهٔ ادیتور شما.',
    'The conversion to H.264 did not finish.':
        'تبدیل به H.264 تمام نشد.',
    'The conversion tool is not installed yet.':
        'ابزار تبدیل هنوز نصب نشده است.',
})


# ── added: QML app — strings that were still falling through to English ──
# Found with .workbuddy-ai/audit-fa.py, which joins adjacent string literals
# (Python implicit concatenation AND QML `"a" + "b"`) before comparing against
# FA_STRINGS — a naive per-literal scan reports the FIRST fragment of every
# multi-line string and so both misses real gaps and invents fake ones.
#
# 44 keys in the shipping QML UI had no Persian at all. The worst offenders
# were the whole Monetize result panel (verdict labels, the three revenue
# bands, the standing caveat) and the Cutter's download/preview states, so a
# Persian user hit a wall of English exactly where the app is most wordy.
#
# The tier labels/notes below are the ones tr() receives through a VARIABLE
# (tr(_TIER_LABELS[...])), which no static scan can see — they are listed here
# because they are the same panel.
FA_STRINGS.update({
    # ── Monetize result panel ──────────────────────────────────────────
    'Likely per month': 'برآورد ماهانه',
    'PER YEAR': 'در سال',
    'at the same rate': 'با همان نرخ',
    'range {r}': 'بازه {r}',
    'modelled from ~{v} views / month': 'مدل‌سازی از ~{v} بازدید در ماه',
    'DAILY': 'روزانه',
    'MONTHLY': 'ماهانه',
    'YEARLY': 'سالانه',
    # RPM is the term Persian creators actually use; translating it would make
    # the chip harder to read, not easier. Listed so the coverage audit is clean.
    'RPM': 'RPM',
    'Conservative': 'محافظه‌کارانه',
    'Likely': 'محتمل',
    'Optimistic': 'خوش‌بینانه',
    "Bottom of this niche's RPM band": 'کف بازهٔ RPM این حوزه',
    'Middle of the band — the figure to plan against':
        'میانهٔ بازه — عددی که باید روی آن برنامه‌ریزی کرد',
    'Top of the band, in a good ad season': 'سقف بازه، در یک فصل تبلیغاتی خوب',
    "Ads can't run on this channel yet, so there was nothing to look for on its videos.":
        'هنوز تبلیغی روی این کانال اجرا نمی‌شود، پس چیزی برای جست‌وجو در ویدیوهایش نبود.',
    'It is still under the 500-subscriber floor for applying to the Partner Program.':
        'هنوز زیر کف ۵۰۰ مشترک برای درخواست عضویت در برنامهٔ همکاری است.',
    'It meets the subscriber and watch-time bars and shows an active upload history; no opt-in feature is public, which is a display choice.':
        'شرط مشترک و زمان تماشا را دارد و سابقهٔ فعالی از بارگذاری نشان می‌دهد؛ هیچ قابلیت انتخابی‌ای عمومی نیست، که خودش یک انتخاب نمایشی است.',
    "Estimates, not earnings. YouTube never publishes what a channel makes — these are modelled from the niche's RPM band, the audience market and public view velocity. Real figures also include memberships, Super Thanks and sponsorships, none of which are visible from outside.":
        'تخمین، نه درآمد. یوتیوب هرگز منتشر نمی‌کند یک کانال چقدر درمی‌آورد — این‌ها از بازهٔ RPM حوزه، بازار مخاطب و سرعت بازدید عمومی مدل‌سازی شده‌اند. ارقام واقعی عضویت، Super Thanks و اسپانسرشیپ را هم شامل می‌شوند که هیچ‌کدام از بیرون دیده نمی‌شوند.',

    # ── Cutter: read / preview / download states ───────────────────────
    'Finding videos': 'یافتن ویدیوها',
    'Searching YouTube for “{q}”': 'جست‌وجوی یوتیوب برای «{q}»',
    'Reading subscriber counts': 'خواندن شمار مشترکان',
    'Reading exact view counts': 'خواندن بازدیدهای دقیق',
    'Install component': 'نصب جزء',
    'Read again': 'خواندن دوباره',
    'Loading…': 'در حال بارگذاری…',
    'Loading… {p}%': 'در حال بارگذاری… {p}٪',
    '{pct}%': '{pct}٪',
    'Light preview for long video': 'پیش‌نمایش سبک برای ویدیوی بلند',
    'with sound': 'با صدا',
    'Retry preview': 'تلاش دوباره برای پیش‌نمایش',
    "Preview can't play this stream on your PC — Cut & Download still works.":
        'پیش‌نمایش نمی‌تواند این استریم را روی رایانهٔ شما پخش کند — «برش و دانلود» همچنان کار می‌کند.',
    'AV1 preview — may not play on this PC. Cut still works.':
        'پیش‌نمایش AV1 — ممکن است روی این رایانه پخش نشود. برش همچنان کار می‌کند.',
    'YouTube only showed 360p for this video — its HD qualities are hidden by a limited read.':
        'یوتیوب برای این ویدیو فقط ۳۶۰p نشان داد — کیفیت‌های HD آن پشت یک خوانش محدود پنهان مانده‌اند.',
    'Only 360p was visible — YouTube limited this read. See the Quality section below to unlock HD.':
        'فقط ۳۶۰p دیده شد — یوتیوب این خوانش را محدود کرد. برای باز کردن HD بخش «کیفیت» را در پایین ببینید.',

    # ── Clips history ──────────────────────────────────────────────────
    'Clips': 'کلیپ‌ها',
    'Remove from history': 'حذف از تاریخچه',
    'Clip removed from history.': 'کلیپ از تاریخچه حذف شد.',
    'Clips history cleared.': 'تاریخچهٔ کلیپ‌ها پاک شد.',
    'file missing': 'فایل موجود نیست',

    # ── progress / status chips ────────────────────────────────────────
    'stats read': 'آمار خوانده‌شده',
    'videos found': 'ویدیوی یافته‌شده',
    'upload slot': 'اسلات بارگذاری',

    # ── long-form progress + quota ─────────────────────────────────────
    'YouTube returned {n} videos — all it has for this keyword and window, whatever the depth. Add more keywords, separated by commas, to search deeper.':
        'یوتیوب {n} ویدیو برگرداند — هر چه برای این کلیدواژه و بازه دارد، با هر عمقی. کلیدواژه‌های بیشتری با کاما جدا کنید تا عمیق‌تر جست‌وجو شود.',
    'This run costs about {c} — results are cached, so reopening this search later is free.':
        'این اجرا حدود {c} هزینه دارد — نتایج کش می‌شوند، پس باز کردن دوبارهٔ این جست‌وجو بعداً رایگان است.',
    'Every configured YouTube API key has used up its daily quota.\n\nEverything scraped so far ({n} videos) was saved.':
        'سهمیهٔ روزانهٔ همهٔ کلیدهای API یوتیوب تمام شده است.\n\nهر چیزی که تا اینجا استخراج شد ({n} ویدیو) ذخیره شد.',

    # ── misc ───────────────────────────────────────────────────────────
    'RISKS': 'ریسک‌ها',
    'TIMING': 'زمان‌بندی',
    'SERIES': 'سری',
    # Settings → JavaScript runtime: the runtime now ships inside the installer,
    # so the source line has a third state beside PATH/managed.
    'included with the app': 'همراه خود برنامه نصب شد',
    # Dashboard scrape → transcript pause banner: YouTube IP-blocks the
    # transcript endpoint mid-run; the scrape waits for Skip or a new IP.
    'Transcripts paused — YouTube has stopped answering for this IP.':
        'زیرنویس‌ها متوقف شدند — یوتیوب دیگر به این IP جواب نمی‌دهد.',
    'So far: {f} with transcripts · {b} blocked · {n} without any':
        'تا اینجا: {f} با زیرنویس · {b} بلاک‌شده · {n} بدون زیرنویس',
    'Skip transcripts': 'بدون زیرنویس ادامه بده',
    'New IP — re-check': 'IP جدید — بررسی کن',
    'Checking IP…': 'در حال بررسی IP…',
    'Still the same IP — switch the VPN node, then press New IP again.':
        'هنوز همان IP قبلی است — نود VPN را عوض کن و دوباره «IP جدید» را بزن.',
    'IP changed — resuming transcripts.':
        'IP عوض شد — ادامه‌ی زیرنویس‌ها از سر گرفته شد.',
    'Skipping transcripts for the rest of this run.':
        'برای ادامه‌ی این اجرا از زیرنویس صرف‌نظر می‌شود.',
    'Transcripts so far: {found} found · {none} without.':
        'زیرنویس تا اینجا: {found} پیدا شد · {none} بدون زیرنویس.',
    'YouTube has stopped answering transcripts for this IP (at {vid}).':
        'یوتیوب برای این IP دیگر زیرنویس نمی‌دهد (از ویدیوی {vid}).',
    'Switch the VPN node and press New IP, or skip the rest without transcripts.':
        'نود VPN را عوض کن و «IP جدید» را بزن، یا بقیه را بدون زیرنویس ادامه بده.',
    'Transcripts skipped: {n}': 'زیرنویس‌های صرف‌نظرشده: {n}',
    "The file couldn't be found — it may have been moved or deleted.":
        'فایل پیدا نشد — ممکن است جابه‌جا یا حذف شده باشد.',

    # ── added: switchable accent colour (Settings ▸ Appearance) ──────────
    'Appearance': 'ظاهر',
    'Accent colour': 'رنگ اصلی',
    'Repaints every button, icon tile and glow — no restart.':
        'همه‌ی دکمه‌ها، کاشی‌های آیکون و تابش را دوباره رنگ می‌کند — بدون راه‌اندازی دوباره.',
    # accent names (shown in the swatch tooltips)
    'Signal': 'قرمز',
    'Amber': 'نارنجی',
    'Ocean': 'آبی',
    'Violet': 'بنفش',
    'Mint': 'سبز',
    'Aurora': 'شفق',
    'Rose': 'رز',
    'Ambient motion': 'حرکت محیطی',
    'Drifting page light and breathing glows. Turn off for a perfectly still interface.': 'نور شناور صفحه و درخشش‌های تپنده. برای رابطی کاملاً ساکن خاموشش کنید.',
})

# ── added: v5 product video card ─────────────────────────────────────────
FA_STRINGS.update({
    'outlier': 'جهش',
    'Save thumbnail': 'ذخیره‌ی تامبنیل',
    'Views ÷ subscribers — how far this video outran its channel':
        'بازدید ÷ مشترک — این ویدیو چقدر از اندازه‌ی کانالش جلو زده',
})

# ── added: v5 product copy pass ───────────────────────────────────────────
FA_STRINGS.update({
    'All systems normal': 'همه‌چیز سالم است',
    'YouTube Research Studio': 'استودیوی تحقیق یوتیوب',
    'Channel Scraper': 'استخراج کانال',
    'Pull every video from a channel or search, with full stats, ready to analyse or export.':
        'همه‌ی ویدیوهای یک کانال یا جست‌وجو را با آمار کامل بگیرید؛ آماده‌ی تحلیل یا خروجی.',
    'Start scraping': 'شروع استخراج',
    'Stop scraping': 'توقف استخراج',
    'Ready to scrape': 'آماده‌ی استخراج',
    'API keys, appearance, downloads and app preferences, all in one place.':
        'کلیدهای API، ظاهر، دانلودها و ترجیحات برنامه، همه در یک جا.',
    'Niche keywords': 'کلمات کلیدی نیچ',
    'Separate several keywords with a comma.': 'چند کلمه‌ی کلیدی را با ویرگول جدا کنید.',
})

# v6 (Studio 2026)
FA_STRINGS.update({
    'Indigo': 'نیلی',
})

# v7 (Downloads + Video Cutter studio pass)
FA_STRINGS.update({
    'Active now': 'اکنون فعال',
    'Back 10s': '۱۰ ثانیه عقب',
    'Bring a video': 'ویدیو را اضافه کنید',
    'Clear': 'پاک کردن',
    'Clear search': 'پاک کردن جست‌وجو',
    'Click the timeline to scrub, drag the S / E handles to move the edges, or type an exact time.':
        'روی تایم‌لاین کلیک کنید، دستگیره‌های S / E را بکشید، یا زمان دقیق را وارد کنید.',
    'Clip length': 'طول کلیپ',
    'Cut it out': 'برش بزنید',
    'Downloading': 'در حال دانلود',
    'Drop a video here, or click to browse': 'ویدیو را اینجا رها کنید یا برای انتخاب کلیک کنید',
    'Engine ready': 'موتور آماده است',
    'Enter to fetch': 'برای دریافت Enter بزنید',
    'Export': 'خروجی',
    'Failed': 'ناموفق',
    'Forward 10s': '۱۰ ثانیه جلو',
    'Grid view': 'نمای شبکه‌ای',
    'Inside the clip': 'داخل کلیپ',
    'Jump the preview here': 'پیش‌نمایش را به اینجا ببرید',
    'Library': 'کتابخانه',
    'List view': 'نمای فهرستی',
    'Mark the moment': 'لحظه را مشخص کنید',
    'Merging': 'در حال ترکیب',
    'Needs attention': 'نیازمند توجه',
    'No matches': 'موردی پیدا نشد',
    'Nothing running': 'چیزی در حال اجرا نیست',
    'Outside the clip': 'خارج از کلیپ',
    'Paste': 'چسباندن',
    'Paste a link': 'چسباندن لینک',
    'Playback speed': 'سرعت پخش',
    'Queued': 'در صف',
    'Reading…': 'در حال خواندن…',
    'Stopped': 'متوقف‌شده',
    'YouTube link detected': 'لینک یوتیوب شناسایی شد',
    'Your clip is ready': 'کلیپ شما آماده است',
    'selected': 'انتخاب‌شده',
    'videos in your history': 'ویدیو در تاریخچه',
    '{f} failed · {s} paused': '{f} ناموفق · {s} متوقف',
    '{n} downloading': '{n} دانلود در حال انجام',
    '{p}% overall': '{p}٪ پیشرفت کلی',
    '{p}% success rate': '{p}٪ موفقیت',
})

# ── v8 UI refresh: Niche Finder · Scraper · History · AI Ideas ──────────────
FA_STRINGS.update({
    # Niche Finder
    'Niche Finder · Outlier Radar': 'نیچ‌یاب · رادار ویدیوهای استثنایی',
    'Scanning YouTube': 'در حال اسکن یوتیوب',
    'Find small channels': 'کانال‌های کوچکی را پیدا کن',
    'pulling giant numbers.': 'که اعداد غول‌آسا می‌آورند.',
    'Search a niche, then cut by channel size, reach and the views ÷ subscribers multiplier. Every cut re-filters instantly.':
        'یک نیچ را جست‌وجو کن، بعد با اندازه‌ی کانال، بازدید و ضریب بازدید ÷ مشترک فیلترش کن. هر فیلتر فوراً اعمال می‌شود.',
    'Enter to search · separate several keywords with a comma': 'برای جست‌وجو Enter بزنید · چند کلیدواژه را با کاما جدا کنید',
    'Paste a channel URL, @handle or name · Enter to scan': 'لینک کانال، @هندل یا نام را بچسبانید · برای اسکن Enter بزنید',
    'Try': 'امتحان کنید',
    'Outlier signal': 'سیگنال ویدیوی استثنایی',
    'one click per cut · click again to clear': 'هر فیلتر با یک کلیک · کلیک دوباره برای حذف',
    'Presets': 'پیش‌تنظیم‌ها',
    'Nothing on the radar yet': 'هنوز چیزی روی رادار نیست',
    'No videos pass these filters': 'هیچ ویدیویی از این فیلترها رد نمی‌شود',
    'Type a niche in the bar above and the outliers will show up here.': 'یک نیچ در نوار بالا بنویسید تا ویدیوهای استثنایی اینجا ظاهر شوند.',
    'Nothing passes these cuts. Loosen a pill above or clear the filters to widen the net.':
        'چیزی از این فیلترها رد نمی‌شود. یکی از فیلترهای بالا را شُل کنید یا همه را پاک کنید تا تور بازتر شود.',
    'Type a niche': 'یک نیچ بنویسید',
    'Tune the signal': 'سیگنال را تنظیم کنید',
    'Open the outliers': 'استثنایی‌ها را باز کنید',
    # Scraper
    'Scraping now': 'در حال استخراج',
    'Pull a whole channel': 'یک کانال کامل را بیرون بکش',
    'into one clean sheet.': 'در یک جدول تمیز.',
    'Single video': 'یک ویدیو',
    'All of YouTube': 'کل یوتیوب',
    'Decides which videos make the cut when the channel has more than your maximum — and the row order in the export.':
        'وقتی کانال بیشتر از سقف شما ویدیو دارد، تعیین می‌کند کدام‌ها انتخاب شوند — و ترتیب ردیف‌ها در خروجی.',
    'Destination': 'مقصد',
    'Up to {n} videos · {s} · {f}': 'تا {n} ویدیو · {s} · {f}',
    'Pick a save folder first': 'اول پوشه‌ی ذخیره را انتخاب کنید',
    # History
    'Today': 'امروز',
    'Yesterday': 'دیروز',
    'Latest export': 'آخرین خروجی',
    # AI Ideas
    'Turn videos that already work': 'ویدیوهایی را که جواب داده‌اند',
    'into your next blueprint.': 'به بلوپرینت بعدی‌ات تبدیل کن.',
    'Your idea': 'ایده‌ی شما',
    'References': 'مرجع‌ها',
    'Blueprints': 'بلوپرینت‌ها',
})

# ── v9 UI refresh: Search Archive «The Vault» + Usage & Quota «Fuel dial» ──
FA_STRINGS.update({
    # Search Archive
    'Search Archive · Zero quota': 'آرشیو جست‌وجو · بدون مصرف سهمیه',
    "Every search you've run,": 'هر جست‌وجویی که انجام داده‌اید،',
    'kept forever.': 'برای همیشه نگه داشته می‌شود.',
    'Reopen it, re-filter it, export it. Reading the archive never spends a single unit.':
        'دوباره بازش کنید، دوباره فیلترش کنید، خروجی بگیرید. خواندن آرشیو حتی یک واحد هم مصرف نمی‌کند.',
    'Total runs': 'کل اجراها',
    'UNITS': 'واحد',
    '{n} shown': '{n} مورد نمایش داده شده',
    'Show all sections': 'نمایش همه‌ی بخش‌ها',
    'Free to reopen': 'بازکردن دوباره رایگان',
    # Usage & Quota
    'Usage & Quota · live ledger': 'مصرف و سهمیه · دفتر زنده',
    'Refresh now': 'به‌روزرسانی همین حالا',
    'spent today': 'مصرف امروز',
    'Plenty left': 'هنوز کلی مانده',
    'Running warm': 'مصرف بالا',
    'Almost out': 'تقریباً تمام شده',
    'No key yet': 'هنوز کلیدی نیست',
    '{p}% spent': '{p}٪ مصرف‌شده',
    'API KEYS': 'کلیدهای API',
    '{h} of {n} healthy': '{h} از {n} سالم',
    'Spend follows the key. Click to add or rotate keys in Settings.':
        'مصرف روی هر کلید ثبت می‌شود. برای افزودن یا تعویض کلید کلیک کنید.',
    'Add a key': 'افزودن کلید',
    'Add your first key': 'اولین کلیدتان را اضافه کنید',
    'units · free': 'واحد · رایگان',
    'Open Search Archive': 'بازکردن آرشیو جست‌وجو',
    'Show details': 'نمایش جزئیات',
    'Hide details': 'پنهان‌کردن جزئیات',
})


# ── added: v9 Settings redesign + AI Ideas picker refresh ──
FA_STRINGS.update({
    'SETTINGS': 'تنظیمات',
    'Find a setting …': 'جست‌وجوی تنظیمات …',
    'Theme, accent, language': 'پوسته، رنگ، زبان',
    'theme accent language motion': 'پوسته رنگ زبان حرکت تم تیره روشن',
    'YouTube API': 'API یوتیوب',
    'Keys & daily quota': 'کلیدها و سهمیهٔ روزانه',
    'youtube key quota backup': 'یوتیوب کلید سهمیه پشتیبان',
    'Model, key & routing': 'مدل، کلید و مسیریابی',
    'ai provider model proxy': 'هوش مصنوعی ارائه‌دهنده مدل پراکسی',
    'Runtime & downloader': 'محیط اجرا و دانلودر',
    'download runtime update': 'دانلود محیط اجرا به‌روزرسانی',
    'Output & Scraping': 'خروجی و استخراج',
    'Format, threads, folder': 'فرمت، رشته‌ها، پوشه',
    'output export threads folder cookies transcripts': 'خروجی فرمت رشته پوشه کوکی زیرنویس',
    'All changes saved': 'همهٔ تغییرات ذخیره شد',
    '1 key': '۱ کلید',
    '{n} keys': '{n} کلید',
    'Primary + backups rotate automatically': 'کلید اصلی و پشتیبان‌ها خودکار جابه‌جا می‌شوند',
    'Needed for every search': 'برای هر جست‌وجو لازم است',
    'Default model': 'مدل پیش‌فرض',
    'Add an API key': 'یک کلید API اضافه کنید',
    'Runtime missing': 'محیط اجرا نصب نیست',
    'One-time install, about 40 MB': 'نصب یک‌باره، حدود ۴۰ مگابایت',
    'Output': 'خروجی',
    '{n} threads': '{n} رشته',
    'Pick a save folder': 'پوشهٔ ذخیره را انتخاب کنید',
    'Make it yours. Everything here applies instantly, no restart.': 'به سلیقهٔ خودتان. همه‌چیز فوری اعمال می‌شود، بدون راه‌اندازی مجدد.',
    'Follow Windows, or pin light / dark.': 'هماهنگ با ویندوز، یا همیشه روشن / تیره.',
    'System': 'سیستم',
    'Repaints every button, icon tile and glow.': 'همهٔ دکمه‌ها، آیکون‌ها و درخشش‌ها را رنگ می‌کند.',
    'Switches the whole interface, including right-to-left layout.': 'کل رابط را عوض می‌کند، از جمله چیدمان راست‌به‌چپ.',
    'Live preview': 'پیش‌نمایش زنده',
    '3 blueprints ready': '۳ طرح آماده',
    'Generate': 'ساختن',
    'Powers AI Ideas, reports and the Content Lab.': 'موتور ایده‌های هوش مصنوعی، گزارش‌ها و آزمایشگاه محتوا.',
    'Key added': 'کلید اضافه شده',
    'Recommended': 'پیشنهادی',
    'GPT models': 'مدل‌های GPT',
    'Claude models': 'مدل‌های Claude',
    'Watches videos · web search': 'تماشای ویدیو · جست‌وجوی وب',
    'Any compatible endpoint': 'هر سرویس سازگار',
    'Paste your {p} key': 'کلید {p} را اینجا بچسبانید',
    'Fetch models': 'دریافت مدل‌ها',
    'Connection & routing': 'اتصال و مسیریابی',
    'Customised': 'سفارشی‌شده',
    'Provider defaults': 'پیش‌فرض ارائه‌دهنده',
    'Requests go to': 'درخواست‌ها ارسال می‌شوند به',
    'Copied': 'کپی شد',
    'What the downloader needs to pull streams from YouTube.': 'آنچه دانلودر برای گرفتن ویدیو از یوتیوب لازم دارد.',
    'Installing …': 'در حال نصب …',
    'Action needed': 'نیاز به اقدام',
    'Reinstall': 'نصب مجدد',
    'Downloader (yt-dlp)': 'دانلودر (yt-dlp)',
    'YouTube changes often. If downloads start failing, update first.': 'یوتیوب مدام تغییر می‌کند. اگر دانلودها خطا دادند، اول به‌روزرسانی کنید.',
    'How scrapes run, and where their files land.': 'استخراج‌ها چطور اجرا شوند و فایل‌ها کجا ذخیره شوند.',
    'File type written when a scrape finishes.': 'نوع فایلی که پایان استخراج نوشته می‌شود.',
    'Saves progress mid-scrape, so a crash or a quota wall loses nothing.': 'پیشرفت را در میانهٔ کار ذخیره می‌کند تا با خطا یا تمام‌شدن سهمیه چیزی از دست نرود.',
    'Parallel workers while scraping. Higher is faster, and heavier on your connection.': 'تعداد کارگرهای موازی. بیشتر یعنی سریع‌تر و فشار بیشتر روی اینترنت.',
    'Borrow a signed-in browser session for age-gated or members-only videos.': 'برای ویدیوهای محدود یا مخصوص اعضا از نشست واردشدهٔ مرورگر استفاده می‌کند.',
    'Richer AI reports, slightly slower scrapes.': 'گزارش‌های هوش مصنوعی غنی‌تر، استخراج کمی کندتر.',
    'Where exports and downloads are written.': 'محل ذخیرهٔ خروجی‌ها و دانلودها.',
    'Not chosen yet': 'هنوز انتخاب نشده',
    'You have unsaved changes': 'تغییرات ذخیره‌نشده دارید',
    'Ctrl+S to save': 'Ctrl+S برای ذخیره',
    'Save changes': 'ذخیرهٔ تغییرات',
    'Pick a recipe. You can switch any time, nothing is lost.': 'یک روش انتخاب کنید. هر وقت خواستید عوضش کنید، چیزی از دست نمی‌رود.',
    'Add a line:': 'افزودن سطر:',
    'Angle': 'زاویه',
    'Tone': 'لحن',
    'Hook': 'قلاب',
    'Audience': 'مخاطب',
    'Want to steer it? Add your own idea on top of the videos.': 'می‌خواهید هدایتش کنید؟ ایدهٔ خودتان را کنار ویدیوها اضافه کنید.',
    'Add my idea': 'افزودن ایدهٔ من',
    'Collapse': 'بستن',
    'Expand': 'بازکردن',
    'From a saved search': 'از یک جست‌وجوی ذخیره‌شده',
    'Pick top 5': 'انتخاب ۵ برتر',
    'Try another format or clear the title filter.': 'فرمت دیگری را امتحان کنید یا فیلتر عنوان را پاک کنید.',
    'Tip: 5 to 10 strong videos make the clearest pattern.': 'نکته: ۵ تا ۱۰ ویدیوی قوی واضح‌ترین الگو را می‌سازند.',
    'Add': 'افزودن',
})

# ── v10: perf pass + sidebar quota card + Content Lab deck ──
FA_STRINGS.update({
    'Sections': 'بخش‌ها',
    'Reports': 'گزارش‌ها',
    'AI provider': 'سرویس هوش مصنوعی',
    'Pick export': 'انتخاب فایل خروجی',
    'Add context': 'افزودن زمینه',
    'Build report': 'ساخت گزارش',
    'Optional': 'اختیاری',
    'Running': 'در حال اجرا',

    # ── added: v11 Content Lab blueprint / report studio / prompter + Monetize redesign ──
    '10M Shorts views': '۱۰ میلیون بازدید شورتس',
    '1K subscribers': '۱۰۰۰ مشترک',
    '4K watch hours': '۴۰۰۰ ساعت تماشا',
    'AI REPORT STUDIO': 'استودیوی گزارش هوش مصنوعی',
    'Ad eligibility': 'واجد شرایط تبلیغات',
    'Add an AI key to build reports': 'برای ساخت گزارش، کلید هوش مصنوعی اضافه کنید',
    'Ads on videos': 'تبلیغ روی ویدیوها',
    'BLUEPRINT MAP': 'نقشه\u200cی بلوپرینت',
    'BUILDING YOUR REPORT': 'در حال ساخت گزارش',
    'Competition': 'رقابت',
    'Copy hook': 'کپی هوک',
    'Drop in a scraped channel export. Get back real charts, the top videos, and an AI read on what to make next.': 'خروجی اسکرپ\u200cشده\u200cی کانال را بدهید؛ نمودارهای واقعی، برترین ویدیوها و تحلیل هوش مصنوعی برای محتوای بعدی را بگیرید.',
    'Edit': 'تدوین',
    'FOUND': 'پیدا شد',
    'Fold all': 'بستن همه',
    'Launch': 'انتشار',
    'Looks for': 'بررسی می\u200cکند',
    'MONETIZED': 'درآمدزا',
    'Memberships': 'عضویت\u200cها',
    'Merch shelf': 'فروشگاه مرچ',
    'Mid-roll breaks': 'تبلیغ میانی',
    'NOT FOUND': 'پیدا نشد',
    'NOT MONETIZED': 'غیر درآمدزا',
    'NOTE': 'نکته',
    'ON AIR': 'روی آنتن',
    'PLAN WITH THIS': 'با این برنامه\u200cریزی کنید',
    'Pacing': 'ریتم',
    'Page check': 'بررسی صفحه',
    'Pick a script, then press play': 'یک اسکریپت انتخاب کنید، بعد پخش را بزنید',
    'Pick an export to start': 'برای شروع یک خروجی انتخاب کنید',
    'Production': 'تولید',
    'Publish': 'انتشار',
    'READY TO CHECK': 'آماده\u200cی بررسی',
    'REPORT READY': 'گزارش آماده است',
    'Reading the channel page and its latest videos for features only Partner Program channels can switch on.': 'صفحه\u200cی کانال و آخرین ویدیوهایش را برای قابلیت\u200cهایی می\u200cخواند که فقط کانال\u200cهای عضو برنامه\u200cی شرکا می\u200cتوانند فعال کنند.',
    'Ready to build': 'آماده\u200cی ساخت',
    'Report in progress': 'گزارش در حال ساخت',
    'Risks': 'ریسک\u200cها',
    'SCANNING': 'در حال اسکن',
    'SEO': 'سئو',
    'STANDBY': 'آماده\u200cباش',
    'STEP 1 · THE EXPORT': 'مرحله ۱ · خروجی',
    'Script': 'اسکریپت',
    'Script loaded': 'اسکریپت بارگذاری شد',
    'Series': 'سری',
    'Shorts / long-form': 'شورتس / بلند',
    'Shots': 'شات\u200cها',
    'Strategy': 'استراتژی',
    'Subscriber floor': 'حداقل مشترک',
    'Super Thanks': 'سوپر تنکس',
    'TELEPROMPTER': 'تله\u200cپرامپتر',
    'The evidence': 'شواهد',
    'Thumbnails': 'تامبنیل\u200cها',
    'Unfold all': 'باز کردن همه',
    'VERDICT': 'حکم',
    'Views modelled': 'بازدید مدل\u200cشده',
    'certainty': 'اطمینان',
    'day': 'روز',
    'how it ships and what follows': 'چطور منتشر می\u200cشود و بعدش چه',
    'jump to a stage · click a stage header to fold it': 'به هر مرحله بپرید · با کلیک روی عنوان، آن را جمع کنید',
    'per day': 'در روز',
    'per month': 'در ماه',
    'per year': 'در سال',
    'planned {t}': 'برنامه\u200cریزی\u200cشده {t}',
    'read-out': 'زمان خواندن',
    'shots': 'شات',
    'stages': 'مرحله',
    'thumbnails': 'تامبنیل',
    'titles': 'عنوان',
    'what you say, shoot and cut': 'چه می\u200cگویید، چه می\u200cگیرید، چطور تدوین می\u200cکنید',
    'why it spreads and how it opens': 'چرا پخش می\u200cشود و چطور شروع می\u200cشود',
    'year': 'سال',
    '{a} of {b} signals found': '{a} از {b} سیگنال پیدا شد',
    '{n} blueprint(s)': '{n} بلوپرینت',
    '{n} research brief(s)': '{n} گزارش تحقیق',
    '{y} / year at the likely rate': '{y} در سال با نرخ محتمل',
})

# ── v12: Niche Scan "scan room" + Content Lab library redesign ──
FA_STRINGS.update({
    'Read a niche as one set': 'یک نیچ را یک‌جا بخوانید',
    'Who holds it, how long and how fresh the videos are, what is moving — measured for free from rows you already have.': 'چه کسی آن را در دست دارد، ویدیوها چقدر طولانی و تازه‌اند، چه چیزی در حال رشد است — رایگان، از ردیف‌هایی که همین حالا دارید.',
    'Search in Niche Finder': 'در نیچ‌یاب جست‌وجو کنید',
    'Press “Analyze these results”': 'روی «تحلیل این نتایج» بزنید',
    'Read the whole set here': 'کل مجموعه را اینجا بخوانید',
    'Or open a saved section in Search Archive. This page costs no API quota.': 'یا یک بخش ذخیره‌شده را از آرشیو جست‌وجو باز کنید. این صفحه هیچ سهمیه‌ای مصرف نمی‌کند.',
    'SNAPSHOT': 'اسنپ‌شات',
    '{n} channels': '{n} کانال',
    'PIPELINE': 'مراحل',
    'Measured': 'اندازه‌گیری‌شده',
    'instant · free · no AI': 'فوری · رایگان · بدون هوش مصنوعی',
    'Written brief': 'بریف نوشتاری',
    'reading with {p} …': 'در حال خواندن با {p} …',
    'reply was not structured': 'پاسخ ساختاریافته نبود',
    'one AI call': 'یک درخواست هوش مصنوعی',
    'needs an AI key': 'کلید هوش مصنوعی لازم است',
    'Evidence audited': 'بررسی شواهد',
    'after the brief': 'بعد از بریف',
    'Show less': 'نمایش کمتر',
    'AI brief': 'بریف هوش مصنوعی',
    'Evidence': 'شواهد',
    'Limits': 'محدودیت‌ها',
    'Ctrl + 1 … 4 to switch': 'Ctrl + 1 … 4 برای جابه‌جایی',
    'held by the top {n}': 'در دست {n} کانال برتر',
    'Fastest': 'سریع‌ترین',
    'Breakout': 'فراتر از مخاطب',
    'Only one video qualified for this ranking.': 'فقط یک ویدیو برای این رتبه‌بندی واجد شرایط بود.',
    'click a term to copy it': 'برای کپی روی هر عبارت بزنید',
    'One AI call: audience questions, openings worth testing and three experiments. Every statement keeps a label.': 'یک درخواست هوش مصنوعی: پرسش‌های مخاطب، فرصت‌های قابل آزمایش و سه آزمایش. هر جمله برچسب خودش را دارد.',
    'THE BRIEF': 'بریف',
    'How sure is each statement': 'هر جمله چقدر قطعی است',
    'click a class to focus it': 'برای تمرکز روی یک دسته بزنید',
    'click it again to show all': 'دوباره بزنید تا همه نمایش داده شوند',
    'Things to actually try': 'کارهایی که واقعاً باید امتحان کرد',
    'Previous': 'قبلی',
    'No evidence ledger yet': 'هنوز دفتر شواهدی وجود ندارد',
    'The ledger lists every claim the brief makes, what it rests on and what would undermine it.': 'این دفتر هر ادعای بریف را، با پشتوانه‌اش و آنچه می‌تواند نقضش کند، فهرست می‌کند.',
    'Go to the brief': 'رفتن به بریف',
    'click a claim to see its sources': 'برای دیدن منابع روی هر ادعا بزنید',
    '{n} sources': '{n} منبع',
    'RESTS ON': 'متکی بر',
    'WHAT WOULD UNDERMINE IT': 'چه چیزی نقضش می‌کند',
    'how many rows carried each field': 'چند ردیف هر فیلد را داشتند',
    "THE MODEL'S OWN CAVEATS": 'هشدارهای خود مدل',
    'Recent': 'جدیدترین',
    'Most ideas': 'بیشترین ایده',
    'Top score': 'بالاترین امتیاز',
    'A–Z': 'الفبایی',
    'blueprints': 'بلوپرینت',
    'No section matches that search': 'هیچ بخشی با این جست‌وجو پیدا نشد',
    'Try a shorter word, or clear the search to see every section.': 'کلمه‌ی کوتاه‌تری امتحان کنید یا جست‌وجو را پاک کنید تا همه‌ی بخش‌ها دیده شوند.',
    'Clear search': 'پاک کردن جست‌وجو',
    'Section': 'بخش',
    'best score': 'بهترین امتیاز',
    'average': 'میانگین',
    'short / long': 'کوتاه / بلند',
    'Top score first': 'اول بالاترین امتیاز',
    'Newest first': 'اول جدیدترین',
    'no scores yet': 'هنوز امتیازی نیست',
    'LATEST': 'آخرین',
    'updated {t}': 'به‌روزرسانی {t}',
    'avg': 'میانگین',
})


# ── v12: Video Cutter "Edit Bay" redesign (setdefault: never overrides) ──
for _k, _v in {
    'Cut the moment,': 'لحظه را ببُر،',
    'not the whole video.': 'نه کل ویدیو را.',
    'A YouTube link or a file on this PC, trimmed to the second and saved at its own quality up to 4K.': 'لینک یوتیوب یا فایلی روی همین کامپیوتر، دقیق تا ثانیه بریده و با کیفیت خودش تا 4K ذخیره می‌شود.',
    'Keyboard shortcuts': 'میانبرهای صفحه‌کلید',
    'Play / pause': 'پخش / توقف',
    'Back / forward 10s': '۱۰ ثانیه عقب / جلو',
    'Back / forward 1s': '۱ ثانیه عقب / جلو',
    'Mark Start / End at the play-head': 'علامت‌گذاری شروع / پایان روی نشانگر پخش',
    'Jump to Start / End': 'پرش به شروع / پایان',
    'Zoom the timeline to the clip': 'زوم تایم‌لاین روی کلیپ',
    'Reading the video…': 'در حال خواندن ویدیو…',
    'Paste a YouTube link above': 'لینک یوتیوب را بالا بچسبانید',
    'Only the length and qualities are fetched, not the video itself.': 'فقط طول و کیفیت‌ها خوانده می‌شود، نه خود ویدیو.',
    'The full video is never downloaded — only the part you cut.': 'کل ویدیو دانلود نمی‌شود — فقط همان بخشی که می‌بُرید.',
    'Preparing preview…': 'در حال آماده‌سازی پیش‌نمایش…',
    'Loop clip: on': 'تکرار کلیپ: روشن',
    'Loop clip: off': 'تکرار کلیپ: خاموش',
    'Show the Shorts (9:16) frame': 'نمایش کادر شورتز (9:16)',
    'How it works': 'چطور کار می‌کند',
    'Drag the brackets on the filmstrip, or press I and O at the play-head.': 'براکت‌های روی نوار فیلم را بکشید، یا روی نشانگر پخش I و O را بزنید.',
    'Pick a quality, then Cut & Download — just that clip is saved.': 'کیفیت را انتخاب کنید، بعد «برش و دانلود» — فقط همان کلیپ ذخیره می‌شود.',
    'Zoom': 'زوم',
    'Quick length from Start': 'طول سریع از نقطه‌ی شروع',
    'Whole': 'کامل',
    'Clip': 'کلیپ',
    'Timeline': 'تایم‌لاین',
    'Click to scrub · drag the brackets to trim · drag the grip to slide the clip': 'کلیک برای جابه‌جایی · کشیدن براکت‌ها برای برش · کشیدن دستگیره برای جابه‌جایی کل کلیپ',
    'Drag to slide the whole clip': 'برای جابه‌جایی کل کلیپ بکشید',
    'Cut again': 'برش دوباره',
    'Original': 'اصلی',
    'Play': 'پخش',
}.items():
    FA_STRINGS.setdefault(_k, _v)
# v16 UI polish copy
for _k, _v in {
    "Something went wrong": "یک خطا پیش آمد",
    "Done": "انجام شد",
    "Heads up": "توجه",
    "Note": "نکته",
    "Run stream": "جریان اجرا",
    "LIVE": "زنده",
    "IDLE": "آماده",
    "READY": "آماده اجرا",
    "Succeeded": "موفق",
    "Warnings": "هشدارها",
    "Errors": "خطاها",
    "Issues": "ایرادها",
    "Jump to latest": "رفتن به آخرین رویداد",
    "Viral": "ویروسی",
    "Rising": "رو به رشد",
    "Typical": "معمولی",
    "All": "همه",
}.items():
    FA_STRINGS.setdefault(_k, _v)



# ── v12 Search Archive redesign (library band, filter dock, Signal cards) ──
for _k, _v in {
    '24h': '۲۴ ساعت',
    '7d': '۷ روز',
    '30d': '۳۰ روز',
    '90d': '۹۰ روز',
    '6m': '۶ ماه',
    '12m': '۱۲ ماه',
    'An order set here overrides the Sort menu until you turn it off.': 'ترتیبی که این‌جا انتخاب کنی، تا وقتی خاموشش نکنی جای منوی مرتب‌سازی را می‌گیرد.',
    'Back to top': 'برگشت به بالا',
    'Engage': 'تعامل',
    'Favorited': 'موردعلاقه',
    'Hover a segment · click to open': 'روی هر بخش برو · برای باز کردن کلیک کن',
    'Latest': 'آخرین',
    'Nothing matches these filters.': 'هیچ نتیجه‌ای با این فیلترها جور نیست.',
    'Order': 'ترتیب',
    'Per hour': 'در ساعت',
    'Range sort active': 'مرتب‌سازی بازه فعال است',
    'Ranges': 'بازه‌ها',
    'Reset all': 'پاک کردن همه',
    'Reset filters': 'بازنشانی فیلترها',
    'Search these results': 'جست‌وجو در این نتایج',
    'Sort': 'مرتب‌سازی',
    'Subs': 'مشترک',
    'Type 1K, 2.5M … or tap a preset': 'مثلاً 1K یا 2.5M بنویس … یا یک پیش‌فرض را بزن',
    'Where your archive lives': 'آرشیوت کجا جمع شده',
    'max': 'حداکثر',
    'min': 'حداقل',
    '{n} more sections': '{n} بخش دیگر',
}.items():
    FA_STRINGS.setdefault(_k, _v)
# v16 UI polish copy
for _k, _v in {
    "Something went wrong": "یک خطا پیش آمد",
    "Done": "انجام شد",
    "Heads up": "توجه",
    "Note": "نکته",
    "Run stream": "جریان اجرا",
    "LIVE": "زنده",
    "IDLE": "آماده",
    "READY": "آماده اجرا",
    "Succeeded": "موفق",
    "Warnings": "هشدارها",
    "Errors": "خطاها",
    "Issues": "ایرادها",
    "Jump to latest": "رفتن به آخرین رویداد",
    "Viral": "ویروسی",
    "Rising": "رو به رشد",
    "Typical": "معمولی",
    "All": "همه",
}.items():
    FA_STRINGS.setdefault(_k, _v)



# ── v9 Niche Finder "Signal Console" + v10 AI Ideas "Studio Brief" ──
for _k, _v in {
    'Also on': 'فعال دیگر',
    'Any': 'همه',
    'Channel size': 'اندازه کانال',
    'Hunting for': 'دنبال چه هستی',
    'Live signal': 'سیگنال زنده',
    'Multiplier': 'ضریب',
    'Reach': 'دسترسی',
    'Recipes': 'دستورها',
    'Set the cuts first or after — every change re-filters instantly.': 'برش‌ها را قبل یا بعد از جست‌وجو تنظیم کن — هر تغییر فوری اعمال می‌شود.',
    'Views ÷ subscribers': 'بازدید ÷ مشترک',
    'multiplier': 'ضریب',
    'subscribers': 'مشترک',
    '{n} matches': '{n} نتیجه',
    'Blueprints per run': 'تعداد بلوپرینت در هر اجرا',
    'Jump to Build': 'برو به ساخت',
    'This recipe works from your videos alone': 'این دستور فقط از ویدیوهای انتخابی تو کار می‌کند',
    'web + video': 'وب + ویدیو',
}.items():
    FA_STRINGS.setdefault(_k, _v)
# v16 UI polish copy
for _k, _v in {
    "Something went wrong": "یک خطا پیش آمد",
    "Done": "انجام شد",
    "Heads up": "توجه",
    "Note": "نکته",
    "Run stream": "جریان اجرا",
    "LIVE": "زنده",
    "IDLE": "آماده",
    "READY": "آماده اجرا",
    "Succeeded": "موفق",
    "Warnings": "هشدارها",
    "Errors": "خطاها",
    "Issues": "ایرادها",
    "Jump to latest": "رفتن به آخرین رویداد",
    "Viral": "ویروسی",
    "Rising": "رو به رشد",
    "Typical": "معمولی",
    "All": "همه",
}.items():
    FA_STRINGS.setdefault(_k, _v)



# ── v14 redesign: Downloads "Dailies", quality "Ladder", prompter "On Air" ──
for _k, _v in {
    'All clear': 'همه‌چیز مرتب است',
    'Asking YouTube what this video really has': 'در حال پرسیدن از یوتیوب که این ویدیو واقعاً چه کیفیت‌هایی دارد',
    'Audio': 'صدا',
    'Beats': 'بیت‌ها',
    'Best': 'بهترین',
    'Earlier this week': 'اوایل این هفته',
    'Enter to download': 'برای دانلود Enter بزنید',
    'Faster  (+)': 'سریع‌تر  (+)',
    'Fetch qualities': 'دریافت کیفیت‌ها',
    'Live': 'در حال انجام',
    'Needs you': 'نیاز به تو',
    'Nothing failed or paused.': 'هیچ دانلودی ناموفق یا متوقف نیست.',
    'Now transferring': 'در حال دانلود',
    'Older': 'قدیمی‌تر',
    'Paste a YouTube link': 'لینک یوتیوب را اینجا بچسبانید',
    'Paste a link. It lands on your Desktop, live.': 'لینک را بچسبانید؛ فایل با پیشرفت زنده روی دسکتاپ می‌نشیند.',
    'Reading formats…': 'در حال خواندن فرمت‌ها…',
    'Resume': 'ادامه',
    'Retry': 'تلاش دوباره',
    'Show the controls  (F)': 'نمایش کنترل‌ها  (F)',
    'Slower  (−)': 'آهسته‌تر  (−)',
    'the best this video has': 'بهترین کیفیتی که این ویدیو دارد',
    'Tungsten': 'تنگستن',
    'Mon': 'دوشنبه',
    'Tue': 'سه‌شنبه',
    'Wed': 'چهارشنبه',
    'Thu': 'پنجشنبه',
    'Fri': 'جمعه',
    'Sat': 'شنبه',
    'Sun': 'یکشنبه',
}.items():
    FA_STRINGS.setdefault(_k, _v)
# v16 UI polish copy
for _k, _v in {
    "Something went wrong": "یک خطا پیش آمد",
    "Done": "انجام شد",
    "Heads up": "توجه",
    "Note": "نکته",
    "Run stream": "جریان اجرا",
    "LIVE": "زنده",
    "IDLE": "آماده",
    "READY": "آماده اجرا",
    "Succeeded": "موفق",
    "Warnings": "هشدارها",
    "Errors": "خطاها",
    "Issues": "ایرادها",
    "Jump to latest": "رفتن به آخرین رویداد",
    "Viral": "ویروسی",
    "Rising": "رو به رشد",
    "Typical": "معمولی",
    "All": "همه",
}.items():
    FA_STRINGS.setdefault(_k, _v)


# ── v15: Theatre player · Run-console scraper ─────────────────────────────
for _k, _v in {
    '100 units / 50 results': '۱۰۰ واحد / هر ۵۰ نتیجه',
    'Add a channel or video link': 'لینک کانال یا ویدیو را وارد کنید',
    'Change': 'تغییر',
    'Channel, @handle, /channel/UC… or one video': 'کانال، ‎@handle، ‎/channel/UC…‎ یا یک ویدیو',
    'Choose where the sheet lands': 'محل ذخیرهٔ فایل را انتخاب کنید',
    'How many, which first, which format': 'چند تا، به چه ترتیبی، چه فرمتی',
    'Matching': 'فیلتر',
    'Only videos matching… (optional)': 'فقط ویدیوهایی که شامل… باشند (اختیاری)',
    'Recipe': 'تنظیمات اجرا',
    'Run sheet': 'خلاصهٔ اجرا',
    'Saved as .{f}': 'ذخیره با فرمت ‎.{f}',
    'Saves to': 'ذخیره در',
    'Scraping · {p}%': 'در حال استخراج · ‎{p}%',
    'Sort order and a timestamp are appended, so runs never overwrite each other.': 'ترتیب مرتب‌سازی و زمان به نام فایل اضافه می‌شود تا اجراها روی هم ننویسند.',
    'Speed & quality': 'سرعت و کیفیت',
    'The maximum counts matching videos only — the scraper keeps reading until it has that many.': 'سقف فقط ویدیوهای منطبق را می‌شمارد؛ اسکرپر تا رسیدن به همین تعداد ادامه می‌دهد.',
    "This file can't be played here": 'این فایل اینجا پخش نمی‌شود',
    'Turn a channel into one clean, sortable sheet.': 'یک کانال را به یک جدول تمیز و قابل مرتب‌سازی تبدیل کنید.',
    'not set': 'تنظیم نشده',
    'scraped': 'استخراج شده',
    'videos per run': 'ویدیو در هر اجرا',
    'Playback speed': 'سرعت پخش',
    'Open on YouTube': 'باز کردن در یوتیوب',
}.items():
    FA_STRINGS.setdefault(_k, _v)
# v16 UI polish copy
for _k, _v in {
    "Something went wrong": "یک خطا پیش آمد",
    "Done": "انجام شد",
    "Heads up": "توجه",
    "Note": "نکته",
    "Run stream": "جریان اجرا",
    "LIVE": "زنده",
    "IDLE": "آماده",
    "READY": "آماده اجرا",
    "Succeeded": "موفق",
    "Warnings": "هشدارها",
    "Errors": "خطاها",
    "Issues": "ایرادها",
    "Jump to latest": "رفتن به آخرین رویداد",
    "Viral": "ویروسی",
    "Rising": "رو به رشد",
    "Typical": "معمولی",
    "All": "همه",
}.items():
    FA_STRINGS.setdefault(_k, _v)

# v17.2 Monetize: earnings range + "the mint" loader
for _k, _v in {
    "Finding the channel": "پیدا کردن کانال",
    "Reading its latest uploads": "خواندن آخرین آپلودهای کانال",
    "Scanning for Partner Program signals": "بررسی نشانه‌های عضویت در برنامه شرکای یوتیوب",
    "Pricing views against the niche RPM": "قیمت‌گذاری بازدیدها با RPM این حوزه",
    "Channel": "کانال",
    "Uploads": "آپلودها",
    "Signals": "نشانه‌ها",
    "Revenue": "درآمد",
    "ESTIMATING EARNINGS": "در حال برآورد درآمد",
    "step {n} of {m}": "مرحله {n} از {m}",
    "/ month": "/ ماه",
    "Monthly Estimated Earnings": "برآورد درآمد ماهانه",
    "Yearly Estimated Earnings": "برآورد درآمد سالانه",
    "likely {v}": "محتمل {v}",
}.items():
    FA_STRINGS.setdefault(_k, _v)

# v18 Settings redesign: key vault, Google key guide, AI / engine / output
for _k, _v in {
    "Key guide": "راهنمای کلید",
    "Google keys, step by step": "کلیدهای گوگل، قدم‌به‌قدم",
    "guide google key help": "راهنما گوگل کلید کمک آموزش دریافت ساخت",
    "Gentle": "ملایم",
    "Turbo": "توربو",
    "1 thread": "۱ رشته",
    "Connected": "متصل",
    "Check failed": "بررسی ناموفق",
    "Provider name": "نام سرویس‌دهنده",
    "Only a label for messages and errors, such as 9router, OpenRouter or My gateway.": "فقط یک برچسب برای پیام‌ها و خطاهاست؛ مثلاً 9router، OpenRouter یا My gateway.",
    "{p} API key": "کلید API {p}",
    "Each provider keeps its own key, so switching never loses one.": "هر سرویس‌دهنده کلید خودش را نگه می‌دارد؛ با عوض کردن سرویس‌دهنده هیچ کلیدی از دست نمی‌رود.",
    "No Gemini key yet? It is free from Google AI Studio, four steps.": "هنوز کلید Gemini نداری؟ از Google AI Studio رایگان می‌گیری، در چهار قدم.",
    "Open the guide": "باز کردن راهنما",
    "Fetching …": "در حال دریافت …",
    "Loaded": "دریافت شد",
    "Writes reports & ideas": "نوشتن گزارش و ایده",
    "Searches the web": "جست‌وجو در وب",
    "Watches the videos": "تماشای ویدیوها",
    "Google's shape puts the model in the URL, so there is no path to set.": "در ساختار گوگل نام مدل داخل آدرس است، پس مسیری برای تنظیم وجود ندارد.",
    "JAVASCRIPT RUNTIME": "محیط اجرای جاوااسکریپت",
    "yt-dlp uses it to answer YouTube's player challenge, so streams keep downloading.": "yt-dlp با آن چالش پخش‌کننده‌ی یوتیوب را حل می‌کند تا دانلود استریم‌ها متوقف نشود.",
    "DOWNLOADER": "دانلودر",
    "Updates in place, no reinstall": "به‌روزرسانی درجا، بدون نصب دوباره",
    "Folder set": "پوشه انتخاب شده",
    "Opens anywhere": "همه‌جا باز می‌شود",
    "One record per line, for code": "هر رکورد در یک خط، مناسب کدنویسی",
    "A ready-made workbook": "یک فایل اکسل آماده",
    "Query it with SQL": "با SQL کوئری بگیر",
    "Save progress every N videos, so a crash or a quota wall loses nothing.": "پیشرفت کار هر N ویدیو ذخیره می‌شود تا با کرش یا تمام شدن سهمیه چیزی از دست نرود.",
    "At the end": "در پایان",
    "SAVE TO": "ذخیره در",
    "Copy path": "کپی مسیر",
    "YouTube Data API v3 key": "کلید YouTube Data API v3",
    "Format looks right. Validate to be sure it works.": "ساختار کلید درست به نظر می‌رسد. برای اطمینان «بررسی» را بزن.",
    "Google keys start with AIza and are 39 characters long. Part of it may be missing.": "کلیدهای گوگل با AIza شروع می‌شوند و ۳۹ نویسه دارند. احتمالاً بخشی از کلید جا افتاده است.",
    "Paste the key from Google Cloud → Credentials.": "کلید را از Google Cloud ← Credentials کپی کن و اینجا بچسبان.",
    "When a key runs out of today's quota mid-scrape, the next one takes over automatically.": "اگر سهمیه‌ی امروز یک کلید وسط استخراج تمام شود، کلید بعدی خودکار جایش را می‌گیرد.",
    "Backup key from another project": "کلید پشتیبان از یک پروژه‌ی دیگر",
    "Add a backup key": "افزودن کلید پشتیبان",
    "Each extra project adds another 10,000 units a day": "هر پروژه‌ی اضافه، روزانه ۱۰٬۰۰۰ واحد دیگر اضافه می‌کند",
    "DAILY CAPACITY": "ظرفیت روزانه",
    "units / day": "واحد / روز",
    "Add a key to start searching. One free key covers about 100 keyword searches a day.": "برای شروع جست‌وجو یک کلید اضافه کن. یک کلید رایگان روزانه حدود ۱۰۰ جست‌وجوی کلیدواژه را پوشش می‌دهد.",
    "10,000 units per Google Cloud project. Keys from the same project share one pool.": "هر پروژه‌ی Google Cloud روزانه ۱۰٬۰۰۰ واحد دارد. کلیدهای یک پروژه سهمیه‌ی مشترک دارند.",
    "units / page": "واحد / صفحه",
    "unit / 50 items": "واحد / ۵۰ مورد",
    "Quota resets": "صفر شدن سهمیه",
    "Pacific time": "به وقت اقیانوس آرام",
    "How do I get a key?": "چطور کلید بگیرم؟",
    "6 steps": "۶ قدم",
    "Sign in to Google Cloud": "ورود به Google Cloud",
    "Open the Cloud Console with any Google account. On the first visit pick your country and accept the terms. No credit card or billing account is needed for this API.": "با هر حساب گوگلی Cloud Console را باز کن. در اولین ورود کشور را انتخاب کن و شرایط را بپذیر. برای این API به کارت بانکی یا حساب پرداخت نیازی نیست.",
    "Open the project picker in the top bar, choose New project, give it a name such as YouTubeHunter and press Create. Then make sure the new project is the one selected in the top bar.": "از نوار بالا انتخابگر پروژه را باز کن، New project را بزن، یک نام مثل YouTubeHunter بده و Create را بزن. بعد مطمئن شو همین پروژه‌ی جدید در نوار بالا انتخاب شده است.",
    "In the API Library open YouTube Data API v3 and press Enable. Skip this and the key still gets created, but every request fails with error 403.": "در API Library صفحه‌ی YouTube Data API v3 را باز کن و Enable را بزن. اگر این مرحله را جا بیندازی کلید ساخته می‌شود، اما همه‌ی درخواست‌ها با خطای 403 رد می‌شوند.",
    "Create the API key": "ساخت کلید API",
    "Go to Credentials, press Create credentials and choose API key. The console asks for at least one API restriction: select YouTube Data API v3. Leave the service-account option unticked and Application restrictions on None, then press Create.": "به Credentials برو، Create credentials را بزن و API key را انتخاب کن. کنسول دست‌کم یک محدودیت API می‌خواهد: YouTube Data API v3 را انتخاب کن. گزینه‌ی service account را تیک نزن، Application restrictions را روی None بگذار و Create را بزن.",
    "Copy the key": "کپی کلید",
    "The API key created dialog shows a string that starts with AIza and is 39 characters long. Copy all of it. You can show it again any time from Credentials → Show key.": "پنجره‌ی API key created رشته‌ای نشان می‌دهد که با AIza شروع می‌شود و ۳۹ نویسه دارد. همه‌اش را کپی کن. هر وقت خواستی از Credentials ← Show key دوباره می‌بینی‌اش.",
    "Paste it into YouTube Hunter": "چسباندن در یوتیوب هانتر",
    "Paste it into Primary key above, press Validate, then Save. A brand-new key or a just-enabled API can take up to 5 minutes to start working. Want more quota? Repeat steps 2 to 5 in a new project and add that key as a backup.": "کلید را در «کلید اصلی» بالا بچسبان، «بررسی» و بعد «ذخیره» را بزن. کلید تازه یا API تازه فعال‌شده ممکن است تا ۵ دقیقه طول بکشد تا کار کند. سهمیه‌ی بیشتر می‌خواهی؟ قدم‌های ۲ تا ۵ را در یک پروژه‌ی جدید تکرار کن و آن کلید را پشتیبان بگذار.",
    "Open Google AI Studio": "باز کردن Google AI Studio",
    "Sign in with your Google account and accept the terms. A brand-new account gets a default project, and often a first key, created automatically.": "با حساب گوگل وارد شو و شرایط را بپذیر. برای حساب تازه یک پروژه‌ی پیش‌فرض، و اغلب اولین کلید، خودکار ساخته می‌شود.",
    "Create an API key": "ساخت یک کلید API",
    "On the API keys page press Create API key and pick a project, or let AI Studio create one. Keys made here are auth keys, already restricted to the Gemini API, which is exactly what it now requires.": "در صفحه‌ی API keys دکمه‌ی Create API key را بزن و یک پروژه انتخاب کن، یا بگذار AI Studio خودش بسازد. کلیدهای اینجا از نوع auth key هستند و از قبل به Gemini API محدود شده‌اند؛ دقیقاً همان چیزی که الان لازم است.",
    "Copy the whole key. Keep it separate from your YouTube key: a key restricted to YouTube cannot call Gemini, and Gemini rejects unrestricted keys.": "کل کلید را کپی کن. آن را از کلید یوتیوب جدا نگه دار: کلیدی که به یوتیوب محدود شده نمی‌تواند Gemini را صدا بزند و Gemini کلیدهای بدون محدودیت را رد می‌کند.",
    "Paste it into AI Provider": "چسباندن در سرویس هوش مصنوعی",
    "Choose Gemini, paste the key, press Validate, then Save. Fetch models lists every model this key can use. The free tier is rate-limited; turning on billing for the project lifts the limits.": "Gemini را انتخاب کن، کلید را بچسبان، «بررسی» و بعد «ذخیره» را بزن. «دریافت مدل‌ها» همه‌ی مدل‌هایی را که این کلید به آن‌ها دسترسی دارد فهرست می‌کند. نسخه‌ی رایگان محدودیت سرعت دارد؛ با فعال کردن پرداخت برای پروژه این محدودیت برداشته می‌شود.",
    "YouTube Data API v3 is not enabled in this key's project. Do step 3, wait a couple of minutes, validate again.": "YouTube Data API v3 در پروژه‌ی این کلید فعال نیست. قدم ۳ را انجام بده، چند دقیقه صبر کن و دوباره «بررسی» را بزن.",
    "Today's 10,000 units are spent. Wait for the midnight Pacific reset, or add a backup key from a different project.": "۱۰٬۰۰۰ واحد امروز تمام شده. تا نیمه‌شب به وقت اقیانوس آرام صبر کن، یا یک کلید پشتیبان از پروژه‌ای دیگر اضافه کن.",
    "Part of the key is missing or has a space in it. Copy it again from Credentials → Show key.": "بخشی از کلید جا افتاده یا فاصله دارد. دوباره از Credentials ← Show key کپی‌اش کن.",
    "An application restriction (websites, IP addresses, apps) is set on the key. For a desktop app set Application restrictions to None.": "روی کلید محدودیت برنامه (وب‌سایت، IP یا اپ) گذاشته شده. برای برنامه‌ی دسکتاپ Application restrictions را روی None بگذار.",
    "The Gemini API only answers requests from supported regions. The proxy under AI Provider → Connection & routing applies to AI calls only.": "Gemini API فقط به درخواست‌های مناطق پشتیبانی‌شده پاسخ می‌دهد. پراکسی بخش سرویس هوش مصنوعی ← اتصال و مسیریابی فقط روی درخواست‌های هوش مصنوعی اعمال می‌شود.",
    "Old unrestricted or long-unused standard keys are blocked. Create a fresh key in AI Studio.": "کلیدهای قدیمی بدون محدودیت یا کلیدهایی که مدت‌ها استفاده نشده‌اند مسدود می‌شوند. در AI Studio یک کلید تازه بساز.",
    "Free-tier rate limit reached. Wait a minute, pick a lighter model, or enable billing on the project.": "به سقف سرعت نسخه‌ی رایگان رسیدی. یک دقیقه صبر کن، مدل سبک‌تری انتخاب کن یا پرداخت را برای پروژه فعال کن.",
    "No permission to create a key": "اجازه‌ی ساخت کلید نداری",
    "The project belongs to an organisation you can't manage. Create a new project that isn't tied to an organisation.": "پروژه متعلق به سازمانی است که مدیریتش با تو نیست. یک پروژه‌ی جدید بساز که به هیچ سازمانی وصل نباشد.",
    "Google key guide": "راهنمای کلیدهای گوگل",
    "The exact clicks for both Google keys YouTube Hunter uses. Free, about five minutes each.": "دقیقاً کجا کلیک کنی تا هر دو کلید گوگلِ موردنیاز یوتیوب هانتر را بگیری. رایگان، هرکدام حدود پنج دقیقه.",
    "Search, video and channel stats. Required for every scrape.": "جست‌وجو و آمار ویدیو و کانال. برای هر استخراجی لازم است.",
    "Free": "رایگان",
    "10,000 units / day": "۱۰٬۰۰۰ واحد / روز",
    "AI Ideas, CSV reports and video watching. Optional, recommended.": "ایده‌های هوش مصنوعی، گزارش CSV و تماشای ویدیو. اختیاری، اما پیشنهادی.",
    "Free tier": "نسخه‌ی رایگان",
    "Rate-limited": "با محدودیت سرعت",
    "4 steps": "۴ قدم",
    "All done": "همه انجام شد",
    "{d} of {n} done": "{d} از {n} انجام شد",
    "Reset ticks": "پاک کردن تیک‌ها",
    "Mark as not done": "علامت انجام‌نشده",
    "Mark as done": "علامت انجام‌شده",
    "Open page": "باز کردن صفحه",
    "Use Gemini": "استفاده از Gemini",
    "Go to the key field": "رفتن به فیلد کلید",
    "When something goes wrong": "وقتی چیزی درست کار نمی‌کند",
    "The error you see, and the fix": "خطایی که می‌بینی و راه‌حلش",
}.items():
    FA_STRINGS.setdefault(_k, _v)


# ═════════════════════════════════════════════════════════════════════════
#  v18.1 — strings the v17 "data-grounded blueprints" work and the v18 settings
#  redesign introduced (BlueprintPane, AI Ideas CSV exports, the Content Lab
#  library) that had no Persian yet. Found with `.workbuddy-ai/audit-fa.py`
#  filtered to the QML layer; the legacy `app/ui/window/` strings are NOT
#  translated here on purpose — that build is not shipped.
# ═════════════════════════════════════════════════════════════════════════
for _k, _v in {
    # ── BlueprintPane: section rail + stage headings ──────────────────────
    "Data pulse": "نبض داده",
    "Re-hooks": "قلاب‌های مجدد",
    "Repurpose": "بازاستفاده",
    "REAL INPUTS": "ورودی‌های واقعی",
    "REAL ROWS ONLY": "فقط ردیف‌های واقعی",
    "Median": "میانه",
    "Top": "برترین",
    "Top performer": "بهترین عملکرد",
    "Median views": "بازدید میانه",
    "Typical length": "طول معمول",
    "across the picks": "در میان انتخاب‌ها",
    "median of the picks": "میانه‌ی انتخاب‌ها",
    "{n} Shorts": "{n} شورتس",
    "Audience profile": "پروفایل مخاطب",
    "WHO THIS IS FOR": "این برای کیست",
    "PERSONA": "پرسونا",
    "PAIN POINTS": "نقاط درد",
    "DESIRES": "خواسته‌ها",
    "OBJECTIONS": "مخالفت‌ها",
    "WATCH CONTEXT": "زمینه‌ی تماشا",
    "Retention re-hooks": "قلاب‌های نگه‌داشت مخاطب",
    "ATTENTION DROPS": "افت توجه",
    "Monetization": "درآمدزایی",
    "Monetization & sponsor fit": "درآمدزایی و تناسب اسپانسر",
    "REVENUE FIT": "تناسب درآمد",
    "NATURAL PRODUCT TIE-IN": "اتصال طبیعی محصول",
    "WHY IT IS AD-SAFE": "چرا برای تبلیغ بی‌خطر است",
    "Ad-safe": "بی‌خطر برای تبلیغ",
    "Limited ads": "تبلیغ محدود",
    "Ad risk": "ریسک تبلیغ",
    "Repurpose map": "نقشه‌ی بازاستفاده",
    "ONE SHOOT, MORE DISTRIBUTION": "یک فیلم‌برداری، توزیع بیشتر",
    "PINNED COMMENT": "کامنت پین‌شده",
    "SHORTS CAPTION": "کپشن شورتس",
    "HASHTAGS": "هشتگ‌ها",
    "Evidence behind the idea": "شواهد پشت ایده",
    "Best day": "بهترین روز",
    "Best length": "بهترین طول",

    # ── AI Ideas: channel data exports ───────────────────────────────────
    "Channel data exports": "خروجی‌های داده‌ی کانال",
    "Choose channel exports": "انتخاب خروجی‌های کانال",
    "Add export": "افزودن خروجی",
    "median": "میانه",
    "Add one or more CSV exports to ground the blueprint in real views, titles, lengths and publishing patterns.":
        "یک یا چند خروجی CSV اضافه کن تا نقشه بر بازدید، عنوان، طول و الگوی انتشار واقعی بنا شود.",
    "Optional. Videos still work on their own, but exports add channel-level evidence and real performance patterns.":
        "اختیاری. ویدیوها به‌تنهایی هم کار می‌کنند، اما خروجی‌ها شواهد سطح‌کانال و الگوهای عملکرد واقعی را اضافه می‌کنند.",
    "Pick a CSV, XLSX, JSONL or DB export.":
        "یک خروجی CSV، XLSX، JSONL یا DB انتخاب کن.",
    "Pick a reference video or add a CSV export.":
        "یک ویدیوی مرجع انتخاب کن یا یک خروجی CSV اضافه کن.",
    "Pick videos or add a CSV export for the style.":
        "برای سبک، ویدیو انتخاب کن یا یک خروجی CSV اضافه کن.",
    "Ready — {n} video(s) + {c} export(s) selected.":
        "آماده — {n} ویدیو + {c} خروجی انتخاب شد.",
    "That export couldn't be opened.": "آن خروجی باز نشد.",
    "This export has no readable video rows.":
        "این خروجی ردیف ویدیوی قابل‌خواندنی ندارد.",

    # ── Content Lab: library subtitle ────────────────────────────────────
    "Your saved blueprints and the teleprompter you shoot from.":
        "نقشه‌های ذخیره‌شده‌ات و تله‌پرامپتری که با آن فیلم می‌گیری.",
}.items():
    FA_STRINGS.setdefault(_k, _v)


# ── v3.13.1: Custom provider model fetch ────────────────────────────────
for _k, _v in {
    "Fetching the model list failed ({code}): {msg}. Some providers "
    "don't let API keys list models — type the exact model id in the "
    "Model box instead; chat requests still work.":
        "گرفتن فهرست مدل‌ها انجام نشد ({code}): {msg}. بعضی سرویس‌ها اجازه‌ی "
        "گرفتن فهرست مدل با کلید API را نمی‌دهند — شناسه‌ی دقیق مدل را "
        "دستی در کادر Model بنویس؛ درخواست‌های چت همچنان کار می‌کنند.",
    "the server returned a web page instead of the API "
    "(a firewall / bot-protection block, or the Host/Path "
    "points at the website rather than its API)":
        "سرور به‌جای API یک صفحه‌ی وب برگرداند (مسدودسازی فایروال/ضدربات، "
        "یا Host/Path به خود سایت اشاره می‌کند نه API آن)",
    "not a model list": "فهرست مدل نبود",
    "no response": "پاسخی نیامد",
}.items():
    FA_STRINGS.setdefault(_k, _v)


# ── v3.14.0: AI Chat ("Scope") ──────────────────────────────────────────
for _k, _v in {
    "AI Chat": "چت هوش مصنوعی",
    "New chat": "گفتگوی تازه",
    "Conversations": "گفتگوها",
    "Search conversations": "جستجو در گفتگوها",
    "Nothing found.": "چیزی پیدا نشد.",
    "Your conversations will show up here.": "گفتگوهایت اینجا نمایش داده می‌شوند.",
    "Pinned": "سنجاق‌شده", "Today": "امروز", "This week": "این هفته", "Earlier": "قبل‌تر",
    "Yesterday": "دیروز",
    "{n} sources": "{n} منبع", "{n} msgs": "{n} پیام",
    "Pin": "سنجاق", "Unpin": "برداشتن سنجاق", "Delete": "حذف", "Rename": "تغییر نام",
    "Connected · {p}": "وصل · {p}", "No AI key yet": "هنوز کلید AI نداری",
    "AI settings": "تنظیمات هوش مصنوعی", "No model set": "مدلی تنظیم نشده",
    "Export as Markdown": "خروجی Markdown",
    "What are we <font color=\"{c}\">making</font> today?": "امروز چی <font color=\"{c}\">بسازیم</font>؟",
    "Connect an AI provider in Settings to start.": "برای شروع، یک سرویس هوش مصنوعی را در تنظیمات وصل کن.",
    "Your sources are ready. Ask away.": "منابع آماده‌اند. بپرس.",
    "Hand me a video, an export or a thumbnail — I answer with numbers.": "ویدیو، خروجی یا تامبنیل بده؛ با عدد جواب می‌دهم.",
    "Open AI settings": "باز کردن تنظیمات AI",
    "Why did this video blow up?": "چرا این ویدیو ترکاند؟",
    "Add a video from Niche Finder; I'll take the numbers apart.": "یک ویدیو از Niche Finder بده؛ عددهایش را کالبدشکافی می‌کنم.",
    "Why did this video become an outlier? Explain it with the numbers.": "این ویدیو چرا اوتلایر شد؟ با عدد توضیح بده.",
    "Read my CSV export": "خروجی CSV مرا بخوان",
    "I'll find the unsaturated sub-niches and the winning titles.": "زیرنیچ‌های اشباع‌نشده و عنوان‌های برنده را پیدا می‌کنم.",
    "Which sub-niche in this export is still not saturated?": "در این خروجی کدام زیرنیچ هنوز اشباع نشده؟",
    "Thumbnail A or B?": "تامبنیل A یا B؟",
    "Drop two images; an honest verdict with reasons.": "دو تصویر بینداز؛ نظر صادقانه با دلیل.",
    "Which thumbnail is stronger and why?": "کدام تامبنیل قوی‌تر است و چرا؟",
    "Filmable ideas": "ایده‌های قابل فیلم‌برداری",
    "Title, 5-second hook, format and length.": "عنوان، هوک ۵ ثانیه، فرمت و طول.",
    "Give me 5 filmable video ideas for this month.": "۵ ایده‌ی ویدیوی قابل فیلم‌برداری برای همین ماه بده.",
    "Copy": "کپی", "Edit": "ویرایش", "Retry": "دوباره", "Regenerate": "بازنویسی جواب",
    "Stopped": "متوقف شد", "Latest": "آخرین پیام",
    "Hook": "هوک", "Format": "فرمت", "Why it works": "چرا جواب می‌دهد",
    "Confidence {n}%": "اطمینان {n}٪", "Build in AI Ideas": "ساخت در ایده‌های AI",
    "Building idea cards…": "در حال ساخت کارت ایده‌ها…",
    "Editing your last message — the answer will be rewritten.": "در حال ویرایش آخرین پیامت؛ جواب دوباره نوشته می‌شود.",
    "Cancel": "انصراف",
    "Ask Scope… e.g. “Why did this video become an outlier?”": "از Scope بپرس… مثلاً «چرا این ویدیو اوتلایر شد؟»",
    "Video from Niche Finder": "ویدیو از Niche Finder", "File": "فایل",
    "From your latest search": "از نتایج آخرین جستجو",
    "From Search Archive": "از آرشیو جستجو", "Saved videos + transcripts": "ویدیوهای ذخیره‌شده + ترنسکریپت",
    "YouTube link": "لینک یوتیوب", "A video or a Short": "ویدیو یا شورت",
    "Share link or My Drive": "لینک اشتراکی یا My Drive",
    "Image or thumbnail": "تصویر یا تامبنیل", "For vision models": "برای مدل‌های بینایی",
    "Model for this chat": "مدل این گفتگو",
    "Chat uses the AI provider from Settings. Pick a vision-capable model to send images.": "چت از سرویس AI تنظیمات استفاده می‌کند. برای ارسال تصویر، مدلی با قابلیت بینایی انتخاب کن.",
    "Change in Settings": "تغییر در تنظیمات",
    "Scope only answers about YouTube and content creation · Enter to send · Shift+Enter for a new line": "Scope فقط درباره‌ی یوتیوب و ساخت محتوا جواب می‌دهد · Enter ارسال · Shift+Enter خط جدید",
    "of {n}k characters": "از {n} هزار کاراکتر",
    "Close to the cap — the last sources get trimmed.": "نزدیک سقف؛ منابع آخر کوتاه می‌شوند.",
    "Each source is summarised once and cached.": "هر منبع یک‌بار خلاصه و کش می‌شود.",
    "No sources yet.": "هنوز منبعی اضافه نشده.",
    "Videos": "ویدیوها", "Files": "فایل‌ها",
    "Add files — or drop them anywhere": "افزودن فایل — یا هر جا رهایش کن",
    "Add files to the conversation": "افزودن فایل به گفتگو", "Supported files": "فایل‌های پشتیبانی‌شده",
    "All files": "همه‌ی فایل‌ها", "Choose images": "انتخاب تصویر", "Images": "تصاویر",
    "Export conversation": "خروجی گفتگو",
    "Drop it and Scope reads it": "رهایش کن تا Scope بخواندش",
    "Add videos from Search Archive": "افزودن ویدیو از آرشیو جستجو",
    "Add videos from Niche Finder": "افزودن ویدیو از Niche Finder",
    "Filter by title or channel": "فیلتر با عنوان یا کانال",
    "Nothing saved in the Search Archive yet.": "هنوز چیزی در آرشیو جستجو ذخیره نشده.",
    "Run a search in Niche Finder first — its results show up here.": "اول در Niche Finder جستجو کن؛ نتایجش اینجا می‌آید.",
    "already added": "قبلاً اضافه شده", "Sorted by outlier multiplier": "مرتب‌شده بر اساس ضریب اوتلایر",
    "Add {n} video(s)": "افزودن {n} ویدیو", "Add videos": "افزودن ویدیو",
    "Add a link": "افزودن لینک", "YouTube video or Google Drive share link": "لینک ویدیوی یوتیوب یا لینک اشتراکی گوگل درایو",
    "With a YouTube API key the exact stats and subscriber count are fetched too (2 quota units).": "اگر کلید YouTube API داشته باشی، آمار دقیق و تعداد سابسکرایبر هم گرفته می‌شود (۲ واحد سهمیه).",
    "Add": "افزودن", "Import": "وارد کردن",
    "Share link (Anyone with the link)": "لینک اشتراکی (Anyone with the link)",
    "Browse My Drive (optional setup)": "مرور My Drive (تنظیم اختیاری)",
    "Create an OAuth client of type “Desktop app” in Google Cloud Console (APIs & Services → Credentials), enable the Drive API, then paste its ID and secret here once.": "در Google Cloud Console یک OAuth client از نوع «Desktop app» بساز (APIs & Services → Credentials)، Drive API را فعال کن و ID و secret آن را یک‌بار اینجا بگذار.",
    "Client ID": "Client ID", "Client secret": "Client secret", "Save": "ذخیره",
    "Connect your Google account (read-only) to pick private files from My Drive.": "حساب گوگلت را (فقط‌خواندنی) وصل کن تا فایل‌های خصوصی My Drive را انتخاب کنی.",
    "Connect Google Drive": "اتصال گوگل درایو", "Search My Drive": "جستجو در My Drive",
    "Refresh": "تازه‌سازی", "Disconnect": "قطع اتصال",
    "Delete this conversation?": "این گفتگو حذف شود؟",
    "Its messages and imported files are removed for good.": "پیام‌ها و فایل‌های واردشده‌اش برای همیشه پاک می‌شوند.",
    "Conversation deleted.": "گفتگو حذف شد.", "All conversations deleted.": "همه‌ی گفتگوها حذف شدند.",
    "Sources": "منابع", "You": "شما", "Conversation exported.": "خروجی گفتگو ذخیره شد.",
    "Export failed: {err}": "ذخیره‌ی خروجی ناموفق بود: {err}", "Copied.": "کپی شد.",
    "Reading transcript…": "در حال خواندن ترنسکریپت…", "Summarising…": "در حال خلاصه‌سازی…",
    "Could not be read": "خوانده نشد", "No transcript available": "ترنسکریپت موجود نیست",
    "Transcript read": "ترنسکریپت خوانده شد", "Ready for vision": "آماده برای بینایی",
    "Summary ready": "خلاصه آماده است", "Link": "لینک", "Export": "خروجی", "Untitled": "بی‌عنوان",
    "That's already in this conversation.": "این منبع از قبل در گفتگو هست.",
    "{n} file(s) added to the conversation.": "{n} فایل به گفتگو اضافه شد.",
    "Downloading from Google Drive…": "در حال دانلود از گوگل درایو…",
    "Paste a YouTube video link or a Google Drive link.": "لینک ویدیوی یوتیوب یا لینک گوگل درایو بگذار.",
    "Fetching the video…": "در حال گرفتن ویدیو…",
    "Couldn't read that video. Is it public?": "آن ویدیو خوانده نشد. عمومی است؟",
    "Couldn't add that.": "اضافه نشد.", "Added to the conversation.": "به گفتگو اضافه شد.",
    "{n} video(s) added to the conversation.": "{n} ویدیو به گفتگو اضافه شد.",
    "Google OAuth client saved.": "OAuth client گوگل ذخیره شد.",
    "Finish signing in in your browser…": "ورود را در مرورگر کامل کن…",
    "Loading your Drive…": "در حال بارگذاری درایو…",
    "Google Drive connected{who}.": "گوگل درایو وصل شد{who}.",
    "Add an AI provider key in Settings first.": "اول کلید سرویس AI را در تنظیمات وارد کن.",
    "Take a look at what I attached.": "این‌هایی که ضمیمه کردم را ببین.",
    "Reading {n} source(s)": "خواندن {n} منبع", "Thinking": "فکر کردن", "Writing the answer": "نوشتن جواب",
    "That file could not be found.": "آن فایل پیدا نشد.",
    "This file type isn't supported yet.": "این نوع فایل هنوز پشتیبانی نمی‌شود.",
    "That file is too large (40 MB max).": "فایل خیلی بزرگ است (حداکثر ۴۰ مگابایت).",
    "{provider} returned an empty response.": "{provider} پاسخ خالی برگرداند.",
    "Google Drive refused the download. Share the file as “Anyone with the link”, or connect your Google account.": "گوگل درایو اجازه‌ی دانلود نداد. فایل را «Anyone with the link» به اشتراک بگذار یا حساب گوگلت را وصل کن.",
    "That doesn't look like a Google Drive link.": "این لینک گوگل درایو به نظر نمی‌رسد.",
    "Google sign-in was cancelled or timed out.": "ورود به گوگل لغو شد یا زمانش تمام شد.",
    "Google Drive isn't connected.": "گوگل درایو وصل نیست.",
}.items():
    FA_STRINGS.setdefault(_k, _v)


# ── v3.14.1 — AI Chat: coach mode, data-grounded idea cards, chat → AI Ideas hand-off ──
FA_STRINGS.update({
    "Add to the chat": "به چت اضافه کن",
    "Concept": "ایده‌ی اصلی",
    "Built on: {t}": "بر پایه‌ی: {t}",
    "Idea from AI Chat — {n} source video(s) picked. Hit Generate.":
        "ایده از AI Chat — {n} ویدیوی منبع انتخاب شد. حالا Generate را بزن.",
    "Idea from AI Chat — ready to generate.": "ایده از AI Chat — آماده‌ی ساخت.",
    "Ready — building the chat idea from {n} source video(s).":
        "آماده — ایده‌ی چت با {n} ویدیوی منبع ساخته می‌شود.",
    "Ready — building the chat idea.": "آماده — ایده‌ی چت ساخته می‌شود.",
    "Coach me": "کوچم کن",
    "Tell me about your channel; I'll plan what to make next.":
        "از کانالت بگو؛ برنامه‌ی ویدیوهای بعدی را با هم می‌چینیم.",
    "Coach me: ask what you need to know about my channel, then tell me exactly what to make next and why.":
        "کوچم کن: هرچه درباره‌ی کانالم لازم داری بپرس، بعد دقیق بگو ویدیوی بعدی‌ام چه باشد و چرا.",
})


# ── v3.15 — Blueprint v12 "Production Dossier" redesign ──
FA_STRINGS.update({
    "Anti-hook": "ضدقلاب",
    "Assets needed": "منابع لازم",
    "Audio & music": "صدا و موسیقی",
    "Caption & CTA": "کپشن و دعوت به عمل",
    "Caption, hashtags and the ask": "کپشن، هشتگ و دعوت به عمل",
    "Chapters": "فصل‌ها",
    "Desires": "خواسته‌ها",
    "Editing & pace": "تدوین و ریتم",
    "First 3 seconds: say this": "۳ ثانیه‌ی اول: این را بگو",
    "Natural product tie-in": "اتصال طبیعی به محصول",
    "Next step": "مرحله‌ی بعد",
    "Objections": "اعتراض‌ها",
    "On camera": "جلوی دوربین",
    "On-screen text": "متن روی صفحه",
    "One shoot, more distribution": "یک فیلم‌برداری، انتشار بیشتر",
    "Pain points": "دردها",
    "Pinned comment": "کامنت پین‌شده",
    "Psychological triggers": "محرک‌های روانی",
    "Render & export": "رندر و خروجی",
    "Revenue fit, and where else it lives": "تناسب درآمدی، و کجاهای دیگر منتشر شود",
    "Scene & sound": "صحنه و صدا",
    "Shoot the essentials first, B-roll last": "اول شات‌های اصلی، B-roll آخر",
    "Shorts caption": "کپشن شورتس",
    "Sponsor fit": "اسپانسرهای مناسب",
    "Target keywords": "کلمات کلیدی هدف",
    "The editor's brief": "دستور کار تدوینگر",
    "The first hour after publishing": "ساعت اول بعد از انتشار",
    "The numbers it was built from": "عددهایی که ایده روی آن‌ها ساخته شده",
    "The rhythm that keeps them watching": "ریتمی که بیننده را نگه می‌دارد",
    "The whole video on one timeline": "کل ویدیو روی یک خط زمانی",
    "Thumbnails to test against each other": "تامبنیل‌هایی برای تست کنار هم",
    "Timing estimated from line length": "زمان‌بندی از روی طول جمله‌ها تخمین زده شده",
    "Title formula": "فرمول عنوان",
    "Titles": "عنوان‌ها",
    "Top pick": "پیشنهاد اول",
    "Upload slot": "زمان انتشار",
    "Visual hook": "قلاب تصویری",
    "Voice": "صدا",
    "What goes in front of the camera": "چه چیزی جلوی دوربین بیاید",
    "What others made, and where you stand": "دیگران چه ساخته‌اند و جای تو کجاست",
    "When it goes out, and the hour after": "کی منتشر شود، و ساعت بعدش",
    "Where viewers want to leave": "جاهایی که بیننده می‌خواهد برود",
    "Who this is for": "برای چه کسی است",
    "Why the data backs it": "چرا داده‌ها پشتش هستند",
    "Word for word, second by second": "کلمه به کلمه، ثانیه به ثانیه",
    "YouTube description": "توضیحات یوتیوب",
    "Your opening": "فرصت تو",
    "pushes the wrong viewer away": "بیننده‌ی اشتباه را پس می‌زند",
    "read with the sound off": "بدون صدا هم خوانده می‌شود",
    "the first frame they see": "اولین فریمی که می‌بینند",
})


# ── added: blueprint v13 cover + v5 schema pack ──
FA_STRINGS.update({'Promise': 'وعده', 'On-screen text': 'متن روی صفحه', 'Look & sound': 'ظاهر و صدا', 'Prep & gear': 'آماده\u200cسازی و تجهیزات', 'Test plan': 'برنامه تست', 'Rights': 'حق نشر', 'If it stalls': 'اگر نگرفت', 'What it promises, and when it pays off': 'چه وعده\u200cای می\u200cدهد و کی عملی می\u200cشود', 'Title, thumbnail and hook all promise': 'عنوان، تامبنیل و قلاب همه این را وعده می\u200cدهند', 'The payoff': 'نتیجه\u200cی نهایی', 'Only this version has': 'فقط این نسخه دارد', 'Every overlay, timed': 'همه\u200cی متن\u200cهای روی تصویر، با زمان', 'Copy all': 'کپی همه', 'How it looks, reads and sounds': 'چطور دیده، خوانده و شنیده می\u200cشود', 'Look': 'ظاهر', 'Type': 'تایپوگرافی', 'Captions': 'زیرنویس\u200cها', 'Music': 'موسیقی', 'Sound effects, where they hit': 'افکت\u200cهای صوتی و جایشان', 'What you need before you hit record': 'قبل از ضبط چه لازم داری', 'Prep': 'آماده\u200cسازی', 'Shoot': 'فیلمبرداری', 'Edit': 'تدوین', 'Location': 'لوکیشن', 'Gear': 'تجهیزات', 'Props': 'وسایل صحنه', 'Before you record': 'قبل از ضبط', 'Launch with this, swap when it stalls': 'با این منتشر کن، اگر نگرفت عوضش کن', 'Thumbnail to launch with': 'تامبنیل شروع', 'Title to launch with': 'عنوان شروع', 'When to swap': 'کی عوض کنیم', 'Watch first in Studio': 'اول در استودیو این را ببین', 'Copyright and Content ID': 'کپی\u200cرایت و Content ID', 'Keep it safe': 'امن نگهش دار', 'If Studio shows this in the first 48 hours': 'اگر استودیو در ۴۸ ساعت اول این را نشان داد', 'Community post teaser': 'تیزر پست کامیونیتی', 'On screen': 'روی صفحه', 'Text overlay': 'متن روی تصویر', 'The promise': 'وعده', 'Copy whole script': 'کپی کل اسکریپت', 'Blueprint score': 'امتیاز بلوپرینت', 'sum of 5 parts': 'جمع ۵ بخش', 'model estimate': 'تخمین مدل', 'Blueprint check': 'بررسی بلوپرینت', 'Timing, titles, hook length and data citations all check out.': 'زمان\u200cبندی، عنوان\u200cها، طول قلاب و استناد به داده همه درست است.', '{n}% complete': '{n}٪ کامل', 'beats': 'بیت', 'to make': 'زمان ساخت', 'Covers {t}': 'پوشش {t}', 'Hook': 'قلاب', 'Retention': 'ماندگاری', 'Packaging': 'بسته\u200cبندی', 'Novelty': 'تازگی', 'Feasibility': 'قابلیت اجرا', 'Low risk': 'ریسک کم', 'Medium risk': 'ریسک متوسط', 'High risk': 'ریسک بالا', 'Script covers the whole video': 'اسکریپت کل ویدیو را پوشش می\u200cدهد', 'Every beat has words to say': 'هر بیت متن گفتنی دارد', 'Titles fit on mobile': 'عنوان\u200cها در موبایل جا می\u200cشوند', 'Hook fits in the first 3 seconds': 'قلاب در ۳ ثانیه اول جا می\u200cشود', 'Three thumbnails to test': 'سه تامبنیل برای تست', 'Claims cite your real data': 'ادعاها به داده\u200cی واقعی استناد می\u200cکنند', 'Upload slot from your own data': 'زمان انتشار از داده\u200cی خودت', 'Score explained part by part': 'امتیاز بخش\u200cبه\u200cبخش توضیح داده شده', 'timing estimated': 'زمان\u200cبندی تخمینی', 'ends at {a} of {b}': 'در {a} از {b} تمام می\u200cشود', '{n} beat(s) are stage directions': '{n} بیت فقط توضیح صحنه است', '{n} over {m} characters': '{n} عنوان بیش از {m} کاراکتر', '{n} words, aim for {m}': '{n} کلمه، هدف {m}', '{n} cited': '{n} استناد', 'general guidance — add a CSV export to ground it': 'راهنمای کلی — برای دقیق شدن یک خروجی CSV اضافه کن'})


# ── v3.15.0: blueprint v14 (Grow act, v6 pack), chat picker filters, chat effort ──
FA_STRINGS.update({'Grow': 'رشد', 'how it ships on day one': 'روز اول چطور منتشر می\u200cشود', 'the first week, and what comes next': 'هفته\u200cی اول و قدم بعدی', 'Why now': 'چرا الان', 'How long this idea stays worth making': 'این ایده تا کی ارزش ساختن دارد', 'Evergreen': 'همیشگی', 'Seasonal': 'فصلی', 'Trending': 'ترند', 'works any month': 'هر ماهی جواب می\u200cدهد', 'has a season': 'فصل خودش را دارد', 'make it this week': 'همین هفته بساز', 'Discovery': 'کشف شدن', 'How viewers will find it': 'بیننده چطور پیدایش می\u200cکند', 'What they type into search': 'چه چیزی سرچ می\u200cکنند', 'Suggested next to': 'پیشنهاد کنار', 'Why they stop scrolling': 'چرا اسکرول را متوقف می\u200cکنند', 'Delivery': 'اجرا', 'How to say it on camera': 'جلوی دوربین چطور بگویی', 'Tone': 'لحن', 'Pace': 'سرعت', 'Energy': 'انرژی', 'Punch these words': 'این کلمه\u200cها را محکم بگو', "Don't": 'نکن', 'Cards & end screen': 'کارت\u200cها و اند اسکرین', 'Where this viewer goes next': 'بیننده بعدش کجا برود', 'Info cards on the timeline': 'کارت\u200cها روی تایم\u200cلاین', 'Info cards': 'کارت\u200cها', 'End screen points to': 'اند اسکرین به این اشاره می\u200cکند', 'Say over the last seconds': 'در ثانیه\u200cهای آخر بگو', 'Checkpoints': 'نقاط بررسی', 'What to check, and when': 'چه چیزی را کی چک کنی', "Against your channel's usual, not someone else's": 'نسبت به معمول کانال خودت، نه بقیه', 'Checked': 'بررسی شد', 'Mark as checked': 'علامت بزن', 'Open in Studio': 'در استودیو ببین', 'Reply bank': 'بانک پاسخ', "Comments you'll get, answers ready": 'کامنت\u200cهایی که می\u200cگیری، با جواب آماده', 'Copy reply': 'کپی پاسخ', '1 hour': '۱ ساعت', '24 hours': '۲۴ ساعت', '7 days': '۷ روز', 'Search this on YouTube': 'در یوتیوب جست\u200cوجو کن', 'Open on YouTube': 'باز کردن در یوتیوب', 'Find it': 'پیدا کن', 'no video link — opens a YouTube search': 'لینک ویدیو نیست، جست\u200cوجوی یوتیوب باز می\u200cشود', 'Their angle': 'زاویه\u200cی آن\u200cها', 'What they miss': 'چیزی که جا انداختند', 'All': 'همه', 'Shorts': 'شورتز', 'Long': 'بلند', 'Outlier': 'اوتلایر', 'Views': 'بازدید', 'Newest': 'جدیدترین', 'Longest': 'طولانی\u200cترین', 'With transcript': 'با ترنسکریپت', '{n} of {m} videos': '{n} از {m} ویدیو', 'Effort': 'قدرت پردازش'})


# ── v3.16.0: delete custom provider, chat model list, Lumen archive card ──
FA_STRINGS.update({
    'Default': 'پیش‌فرض',
    'Use default': 'استفاده از پیش‌فرض',
    'Delete?': 'حذف شود؟',
    'Delete this provider': 'حذف این سرویس',
    'Find a model': 'جست‌وجوی مدل',
    'No model matches.': 'مدلی پیدا نشد.',
    'No provider is set up yet. Add one in Settings.': 'هنوز سرویسی تنظیم نشده. از تنظیمات یکی اضافه کن.',
    'Manage providers': 'مدیریت سرویس‌ها',
    'Pick a vision-capable model to send images. New providers from Settings appear here automatically.':
        'برای ارسال تصویر، مدلی با قابلیت بینایی انتخاب کن. سرویس‌های جدید تنظیمات خودکار اینجا اضافه می‌شوند.',
    'Pin idea generation to one provider and model. AI Chat picks its own model and effort in the chat.':
        'تولید ایده را روی یک سرویس و مدل ثابت کن. چت هوش مصنوعی مدل و قدرت پردازش را داخل خود چت انتخاب می‌کند.',
})


# ── v3.16.0 (2): save mode, clip player ──
FA_STRINGS.update({
    'Auto-save': 'ذخیرهٔ خودکار',
    'Saving…': 'در حال ذخیره…',
    'Auto-save off. Changes wait for Save.': 'ذخیرهٔ خودکار خاموش شد. تغییرات منتظر دکمهٔ ذخیره می‌مانند.',
    'Auto-save on. Your changes were saved.': 'ذخیرهٔ خودکار روشن شد. تغییراتت ذخیره شد.',
    'Auto-save on.': 'ذخیرهٔ خودکار روشن شد.',
    'On: every change is saved by itself. Turn off to save with the Save button.':
        'روشن: هر تغییری خودش ذخیره می‌شود. خاموشش کن تا با دکمهٔ ذخیره ذخیره کنی.',
    'Off: changes wait for Save (Ctrl+S). Turn on to save automatically.':
        'خاموش: تغییرات تا زدن ذخیره (Ctrl+S) منتظر می‌مانند. روشنش کن تا خودکار ذخیره شود.',
    'Save as many providers as you like, then choose which one powers each feature. Press Save to keep your changes.':
        'هر تعداد سرویس که بخواهی ذخیره کن و انتخاب کن کدام برای هر بخش کار کند. برای نگه داشتن تغییرات، ذخیره را بزن.',
    'Play in YouTube Hunter': 'پخش داخل برنامه',
    'Clip': 'کلیپ',
})
FA_STRINGS.setdefault('Save as many providers as you like, then choose which one powers each feature. Changes here save automatically.',
                      'هر تعداد سرویس که بخواهی ذخیره کن و انتخاب کن کدام برای هر بخش کار کند. تغییرات اینجا خودکار ذخیره می‌شوند.')

# ── v3.16-p3: smooth blueprint switching + picked provider models ──
FA_STRINGS.update({
    'Loading blueprint…': 'در حال بارگذاری بلوپرینت…',
    'MODELS': 'مدل‌ها',
    '{n} added': '{n} اضافه‌شده',
    'Hide list': 'بستن لیست',
    'Pick models': 'انتخاب مدل‌ها',
    "Click to make this the provider's main model": 'کلیک کن تا مدل اصلی این سرویس شود',
    'Remove this model': 'حذف این مدل',
    'No models added yet. Tick the ones you want in the list below.': 'هنوز مدلی اضافه نشده. مدل‌های دلخواهت را از لیست پایین تیک بزن.',
    'No models added yet. Press Fetch models to load the list, or type a model id and press Enter.': 'هنوز مدلی اضافه نشده. «دریافت مدل‌ها» را بزن یا شناسه‌ی مدل را بنویس و Enter بزن.',
    'Search the fetched models, or type a model id': 'بین مدل‌های دریافت‌شده بگرد یا شناسه‌ی مدل را بنویس',
    'Type a model id, e.g. gpt-5': 'شناسه‌ی مدل را بنویس، مثلاً gpt-5',
    'Add this model': 'افزودن این مدل',
    'No fetched model matches — press Enter to add it as typed.': 'مدلی پیدا نشد؛ Enter بزن تا همین را اضافه کند.',
    'Add all {n} matches': 'افزودن هر {n} مورد',
    'Found {n} models. Tick the ones you want to add.': '{n} مدل پیدا شد. مدل‌هایی که می‌خواهی را تیک بزن.',
    # v3.16-p4 — Cutter: clip covers, channel identity, delete confirmations
    'Remove this clip?': 'این کلیپ حذف شود؟',
    '“{n}” will be removed from your clips history.': '«{n}» از تاریخچهٔ کلیپ‌ها حذف می‌شود.',
    'This clip will be removed from your clips history.': 'این کلیپ از تاریخچهٔ کلیپ‌ها حذف می‌شود.',
    'The video file itself stays on your disk.': 'خود فایل ویدیو روی دیسک شما می‌ماند.',
    'Clear every clip?': 'همهٔ کلیپ‌ها پاک شوند؟',
    'All {n} clips will be removed from your clips history.': 'هر {n} کلیپ از تاریخچهٔ کلیپ‌ها حذف می‌شوند.',
    'The video files themselves stay on your disk.': 'خود فایل‌های ویدیو روی دیسک شما می‌مانند.',
})

# ── v3.17: Keyword Lab — live autocomplete, Persian seeds, explorer, saved, recent ──
FA_STRINGS.update({
    'Live autocomplete': 'تکمیل خودکار زنده',
    'YouTube + Google suggest': 'پیشنهادهای یوتیوب و گوگل',
    'YouTube only': 'فقط یوتیوب',
    'Google': 'گوگل',
    'both': 'هر دو',
    'Start typing — real YouTube autocomplete appears here as you type.': 'شروع به تایپ کن — تکمیل خودکار واقعی یوتیوب همین‌جا ظاهر می‌شود.',
    '{n} completions on YouTube · {y} only on YouTube — video-shaped demand.': '{n} پیشنهاد در یوتیوب · {y} فقط در یوتیوب — تقاضایی که شکل ویدیو دارد.',
    'Auto-detect': 'تشخیص خودکار', 'English': 'انگلیسی', 'Persian': 'فارسی',
    '7 days': '۷ روز', '30 days': '۳۰ روز', '90 days': '۹۰ روز', '12 months': '۱۲ ماه', '5 years': '۵ سال',
    'All': 'همه', 'Ranked': 'رتبه‌بندی‌شده', 'Questions': 'سؤال‌ها', 'Comparisons': 'مقایسه‌ها', 'Buying': 'خرید', 'Long-tail': 'دم‌بلند',
    'Best opportunity': 'بهترین فرصت', 'Highest demand': 'بیشترین تقاضا', 'Autocomplete strength': 'قدرت تکمیل خودکار', 'A–Z': 'الفبایی',
    'Question': 'سؤال', 'Comparison': 'مقایسه', 'Learning': 'یادگیری', 'DIY / free': 'خودت‌انجام‌بده / رایگان',
    'just now': 'همین الان', '{n} min ago': '{n} دقیقه پیش', '{n} h ago': '{n} ساعت پیش', '{n} d ago': '{n} روز پیش',
    'new': 'تازه', 'peaked {d}': 'اوج در {d}', '{n} phrases': '{n} عبارت',
    'Saved reading · {t}': 'خوانش ذخیره‌شده · {t}',
    'Reopened a saved reading — re-run it for fresh numbers.': 'خوانش ذخیره‌شده باز شد — برای عددهای تازه دوباره اجرا کن.',
    'That saved reading is no longer available.': 'این خوانش ذخیره‌شده دیگر در دسترس نیست.',
    '{n} keywords copied.': '{n} کلمه کپی شد.',
    '{n} tags copied — paste them into YouTube Studio.': '{n} تگ کپی شد — در YouTube Studio بچسبان.',
    'Nothing to copy.': 'چیزی برای کپی نیست.', 'The clipboard is not available.': 'کلیپ‌بورد در دسترس نیست.',
    'Removed from saved keywords.': 'از کلمات ذخیره‌شده حذف شد.', 'Saved “{k}”.': '«{k}» ذخیره شد.',
    'Any country': 'هر کشوری',
})


# ── v3.18 — Keyword Lab: two engines (YouTube × Google), new result page ──
FA_STRINGS.update({
    'Not ranked': 'رتبه‌بندی‌نشده',
    'Google only': 'فقط گوگل',
    'Both engines': 'هر دو موتور',
    'Overview': 'نمای کلی',
    'YouTube vs Google': 'یوتیوب در برابر گوگل',
    'Ideas': 'ایده‌ها',
    'Export keywords': 'خروجی کلمات کلیدی',
    'Export saved keywords': 'خروجی کلمات ذخیره‌شده',
    'Remove from saved': 'حذف از ذخیره‌شده‌ها',
    'Save keyword': 'ذخیرهٔ کلمه',
    'What people search on YouTube and Google, next to what is already published for it. No API key, no quota.':
        'آنچه مردم در یوتیوب و گوگل جست‌وجو می‌کنند، کنار آنچه برایش منتشر شده. بدون کلید API، بدون سهمیه.',
    'A topic or phrase — e.g. air fryer recipes': 'یک موضوع یا عبارت — مثلاً آموزش آشپزی',
    'Research': 'تحقیق کن',
    'AUTOCOMPLETE LANGUAGE': 'زبان تکمیل خودکار',
    'THE PHRASE YOU TYPED': 'عبارتی که تایپ کردی',
    'SELECTED KEYWORD': 'کلمهٔ انتخاب‌شده',
    'KD': 'سختی',
    'Trend': 'روند',
    'Fresh': 'تازه',
    'Intent': 'نیت',
    'ENGINE SPLIT': 'سهم موتورها',
    '{p}% of this demand is on YouTube': '{p}٪ این تقاضا در یوتیوب است',
    'Not measured on both engines in this run': 'در این اجرا روی هر دو موتور اندازه‌گیری نشد',
    'YouTube curve': 'منحنی یوتیوب',
    'Google curve': 'منحنی گوگل',
    'Shared scale': 'مقیاس مشترک',
    'Shape': 'شکل',
    'peak': 'اوج',
    "Shape view: every line on its own peak, so a quiet phrase's curve is visible beside a loud seed. Heights are NOT comparable in this view — the tooltip still shows the real shared-scale value.":
        'نمای شکل: هر خط روی اوج خودش، تا منحنی یک عبارت کم‌صدا کنار seed پرصدا دیده شود. ارتفاع‌ها در این نما قابل مقایسه نیستند — تولتیپ همچنان مقدار واقعی مقیاس مشترک را نشان می‌دهد.',
    'One shared Trends scale — 100 is the busiest point any of these reached in this window, not a volume. Switch to Shape to compare curves that the seed squashes flat.':
        'یک مقیاس مشترک Trends — ۱۰۰ شلوغ‌ترین نقطه‌ای است که هر کدام در این بازه رسیده‌اند، نه حجم جست‌وجو. برای مقایسهٔ منحنی‌هایی که seed صافشان کرده، «شکل» را بزن.',
    'top-right = more demand, more open · click a dot': 'بالا-راست = تقاضای بیشتر، رقابت بازتر · روی نقطه کلیک کن',
    'Difficulty spread': 'پخش سختی',
    'KD, derived': 'سختی، محاسبه‌شده',
    "{n} keywords weren't checked on YouTube and are left out rather than counted as easy. KD = how concentrated each keyword's results are across channels.":
        '{n} کلمه در یوتیوب بررسی نشد و به‌جای «آسان» شمرده‌شدن، کنار گذاشته شد. سختی = میزان تمرکز نتایج هر کلمه بین کانال‌ها.',
    "KD = how concentrated each keyword's results are across channels — derived, not an official score.":
        'سختی = میزان تمرکز نتایج هر کلمه بین کانال‌ها — محاسبه‌شده، نه امتیاز رسمی.',
    'Who ranks on YouTube right now': 'چه کسی الان در یوتیوب رتبه دارد',
    "Read off the same free results-page check the score used, strongest first. ×N = views against this keyword's median result. Click a card to open it on YouTube.":
        'از همان بررسی رایگان صفحهٔ نتایج که امتیاز از آن آمده، قوی‌ترین اول. ×N = بازدید نسبت به میانهٔ نتایج این کلمه. روی کارت کلیک کن تا در یوتیوب باز شود.',
    'Who holds it': 'دست چه کسی است',
    'share of views': 'سهم بازدید',
    'High concentration means established channels hold the term; a spread means an open field.':
        'تمرکز بالا یعنی کانال‌های جاافتاده این کلمه را گرفته‌اند؛ پخش‌بودن یعنی میدان باز است.',
    'relative 0–100, not counts': 'نسبی ۰ تا ۱۰۰، نه تعداد',
    '100 is the busiest term in this set. Rows showing — rank on autocomplete standing: real phrases people type, not measured interest.':
        '۱۰۰ پرجست‌وجوترین کلمهٔ این مجموعه است. ردیف‌های «—» بر اساس جایگاه تکمیل خودکار رتبه گرفته‌اند: عبارت‌های واقعی، نه علاقهٔ اندازه‌گیری‌شده.',
    'Ordered by opportunity; the bar shows how open the field is. Click a row to open it in the hero above.':
        'مرتب‌شده بر اساس فرصت؛ نوار باز بودن میدان را نشان می‌دهد. روی ردیف کلیک کن تا در کارت اصلی بالا باز شود.',
    'Keyword explorer': 'کاوشگر کلمات',
    '{v} of {n}': '{v} از {n}',
    'Filter phrases …': 'فیلتر عبارت‌ها …',
    'TREND': 'روند',
    'INTENT': 'نیت',
    'Open in the hero': 'باز کردن در کارت اصلی',
    'Not measured yet — click to research it': 'هنوز اندازه‌گیری نشده — برای تحقیق کلیک کن',
    'seed': 'seed',
    'No phrase matches this filter.': 'هیچ عبارتی با این فیلتر جور نیست.',
    'Ranked rows carry real readings; the rest are real autocomplete phrases nobody measured yet — “—” instead of a borrowed number. YT / GOOGLE = Trends interest 0–100 on each engine. Export writes exactly this view (CSV / Excel), or the whole reading as a JSON report.':
        'ردیف‌های رتبه‌دار عدد واقعی دارند؛ بقیه عبارت‌های واقعی تکمیل خودکارند که هنوز اندازه‌گیری نشده‌اند — «—» به‌جای عدد قرضی. YT / GOOGLE = علاقهٔ Trends ۰ تا ۱۰۰ روی هر موتور. خروجی دقیقاً همین نما را می‌نویسد (CSV / Excel) یا کل گزارش را به‌صورت JSON.',
    'WHERE THIS DEMAND LIVES': 'این تقاضا کجاست',
    'The average YouTube share across every keyword measured on both engines. Each engine was asked for the same terms in one Trends batch anchored on your seed, so only the SHARE crosses engines honestly — never the raw 0–100.':
        'میانگین سهم یوتیوب در همهٔ کلماتی که روی هر دو موتور اندازه‌گیری شدند. هر موتور برای همان کلمات در یک دستهٔ Trends لنگرشده روی seed پرسیده شد، پس فقط «سهم» صادقانه بین موتورها قابل مقایسه است — نه عدد خام ۰ تا ۱۰۰.',
    'Only YouTube suggests': 'فقط یوتیوب پیشنهاد می‌دهد',
    'video-shaped demand': 'تقاضای ویدیویی',
    'Both engines suggest': 'هر دو موتور پیشنهاد می‌دهند',
    'evergreen core': 'هستهٔ همیشه‌سبز',
    'Only Google suggests': 'فقط گوگل پیشنهاد می‌دهد',
    'web-shaped — articles beat videos': 'متنی — مقاله از ویدیو جلوتر است',
    'Engine split per keyword': 'سهم موتورها برای هر کلمه',
    '{n} measured': '{n} اندازه‌گیری‌شده',
    'one engine only': 'فقط یک موتور',
    'Red = Trends interest on YouTube search, blue = on Google web search. A YouTube-heavy phrase is one people want to WATCH; a Google-heavy one they mostly want to READ — film the first, think twice about the second.':
        'قرمز = علاقهٔ Trends در جست‌وجوی یوتیوب، آبی = در جست‌وجوی وب گوگل. عبارت یوتیوب‌محور را مردم می‌خواهند «ببینند»؛ عبارت گوگل‌محور را بیشتر می‌خواهند «بخوانند» — اولی را بساز، دربارهٔ دومی دوباره فکر کن.',
    'Only on YouTube': 'فقط در یوتیوب',
    'On both engines': 'در هر دو موتور',
    'Only on Google': 'فقط در گوگل',
    'Nothing here for this phrase.': 'برای این عبارت چیزی اینجا نیست.',
    'Rising on YouTube': 'در حال رشد در یوتیوب',
    'Rising on Google': 'در حال رشد در گوگل',
    'Google Trends · related': 'Google Trends · مرتبط',
    'RISING — growth, not interest': 'در حال رشد — رشد، نه میزان علاقه',
    'Google reports anything above 5000% as “Breakout”, so its own label is shown.':
        'گوگل هر چیزی بالای ۵۰۰۰٪ را «Breakout» گزارش می‌کند، پس برچسب خودش نمایش داده می‌شود.',
    'Where — on YouTube': 'کجا — در یوتیوب',
    'Where — on Google': 'کجا — در گوگل',
    'No Google reading came back for this run — Trends was throttling, or this is a run saved before v3.18. Re-run the phrase to fill this tab.':
        'برای این اجرا دادهٔ گوگلی برنگشت — یا Trends محدود کرده بود، یا این اجرا قبل از نسخهٔ ۳٫۱۸ ذخیره شده. عبارت را دوباره اجرا کن تا این تب پر شود.',
    'Questions people ask': 'سؤال‌هایی که مردم می‌پرسند',
    '{n} questions': '{n} سؤال',
    "Every one is a title that states the viewer's job outright. Click to research it; the copy icon takes the phrase as-is.":
        'هر کدام عنوانی است که نیاز بیننده را صریح می‌گوید. برای تحقیق کلیک کن؛ آیکون کپی خود عبارت را برمی‌دارد.',
    'Sub-topics': 'زیرموضوع‌ها',
    'a series, not a video': 'یک سری، نه یک ویدیو',
    'Tag pack': 'پک تگ',
    "The strongest phrases packed into YouTube's 500-character tag field, counted the way Studio counts it.":
        'قوی‌ترین عبارت‌ها، جاشده در فیلد ۵۰۰ کاراکتری تگ یوتیوب — همان‌طور که Studio می‌شمارد.',
    '{n} tags': '{n} تگ',
    'Copy tags': 'کپی تگ‌ها',
    "Real completions from YouTube's own suggest index, ranked by how many expansions lead to them (×N). No search volume — Google publishes the ranking, never the counts.":
        'تکمیل‌های واقعی از ایندکس پیشنهاد خود یوتیوب، رتبه‌بندی بر اساس تعداد گسترش‌هایی که به آن می‌رسند (×N). حجم جست‌وجو نیست — گوگل رتبه را منتشر می‌کند، نه تعداد را.',
    'Where they are': 'کجا هستند',
    'measured · YouTube search': 'اندازه‌گیری‌شده · جست‌وجوی یوتیوب',
    "Relative per head, which is Google's own definition — not “most searches happen here”.":
        'نسبی به ازای جمعیت، طبق تعریف خود گوگل — نه «بیشترین جست‌وجو اینجاست».',
    'What they want': 'چه می‌خواهند',
    'measured · autocomplete': 'اندازه‌گیری‌شده · تکمیل خودکار',
    'A share of phrases, never of searches — Google publishes the ranking, not the counts.':
        'سهمی از عبارت‌ها، نه از جست‌وجوها — گوگل رتبه را منتشر می‌کند، نه تعداد را.',
    'Who they are': 'چه کسانی هستند',
    'inferred from what serves them': 'استنباط از محتوایی که به آن‌ها می‌رسد',
    'Saved keywords': 'کلمات ذخیره‌شده',
    'from “{s}”': 'از «{s}»',
    'Star any keyword (hero, explorer) to keep it here between sessions.':
        'هر کلمه‌ای را (در کارت اصلی یا کاوشگر) ستاره بزن تا بین جلسه‌ها اینجا بماند.',
    'Recent runs': 'اجراهای اخیر',
    'reopen without a new request': 'بازکردن بدون درخواست جدید',
    'Forget': 'فراموش کن',
    'Runs you make are kept here.': 'اجراهایت اینجا نگه داشته می‌شوند.',
    'Two engines. One answer.': 'دو موتور. یک جواب.',
    "Type a phrase you're considering. You get what people type on YouTube and Google, how the demand splits between them, and — for the strongest few — who already ranks, how open the field is, and how fresh it is.":
        'عبارتی که در ذهن داری را تایپ کن. می‌بینی مردم در یوتیوب و گوگل چه تایپ می‌کنند، تقاضا بینشان چطور تقسیم شده، و برای قوی‌ترین‌ها — چه کسی الان رتبه دارد، میدان چقدر باز است و چقدر تازه است.',
    'today': 'امروز',
    '{n} d': '{n} روز',
    '{n} mo': '{n} ماه',
    '{n} y': '{n} سال',
    '{p}% YouTube': '{p}٪ یوتیوب',
    '{p}% Google': '{p}٪ گوگل',
    'Even split': 'تقسیم مساوی',
    "Google comparison didn't run this time": 'این بار مقایسهٔ گوگل اجرا نشد',
    'A YouTube-first topic': 'موضوعی یوتیوب‌محور',
    'A Google-first topic': 'موضوعی گوگل‌محور',
    'Searched on both engines': 'روی هر دو موتور جست‌وجو می‌شود',
    'YouTube lean': 'گرایش به یوتیوب',
    'curves heading up': 'منحنی‌های رو به بالا',
    'Report saved as JSON.': 'گزارش به‌صورت JSON ذخیره شد.',
    "Reading Google's autocomplete for “{s}” …": 'خواندن تکمیل خودکار گوگل برای «{s}» …',
    'Very easy': 'خیلی آسان',
    'Possible': 'شدنی',
    'Very hard': 'خیلی سخت',
})


# ── added: v3.19 Keyword Lab 2026 — result tabs redesign + searcher age ──
FA_STRINGS.update({
    'Bookmarked': 'ذخیره‌شده',
    'seed phrase': 'عبارت اصلی',
    'The phrase you typed': 'عبارتی که تایپ کردی',
    '{n} phrases read': '{n} عبارت خوانده شد',
    'Video ideas': 'ایدهٔ ویدیو',
    'Demand': 'تقاضا',
    'Openness': 'فضای خالی',
    'Headroom': 'سقف بازدید',
    'Freshness': 'تازگی',
    'Engine split': 'سهم موتورها',
    'Searcher age': 'سن جست‌وجوگر',
    'estimated': 'تخمینی',
    'Estimated from the words and the videos — see the Audience tab': 'تخمین از روی کلمات و ویدیوها — جزئیات در تب مخاطب',
    'No interest curve came back for this keyword.': 'برای این کلیدواژه منحنی علاقه‌ای برنگشت.',
    "each curve's shape · height = that engine's share": 'شکل هر منحنی · ارتفاع = سهم همان موتور',
    'Google Trends, relative 0–100': 'گوگل ترندز، نسبی ۰ تا ۱۰۰',
    'every row is a real YouTube or Google autocomplete phrase': 'هر ردیف یک عبارت واقعی از تکمیل خودکار یوتیوب یا گوگل است',
    'age {a}': 'سن {a}',
    "The age tag is an estimate from the phrase's own words and videos, never a measurement.": 'برچسب سن تخمینی است از کلمات و ویدیوهای همان عبارت، نه یک اندازه‌گیری.',
    'Which engine each phrase leans to': 'هر عبارت به کدام موتور گرایش دارد',
    'click a row to open it in the hero': 'روی هر ردیف بزن تا بالای صفحه باز شود',
    'the best video titles': 'بهترین عنوان‌های ویدیو',
    'chapters and descriptions': 'برای فصل‌بندی و توضیحات',
    'every one is a ready title — click to research it': 'هر کدام یک عنوان آماده است — بزن تا تحقیقش کنی',
    'a series, not a video · pick one to see its phrases': 'یک سری، نه یک ویدیو · یکی را انتخاب کن تا عبارت‌هایش را ببینی',
    'How old are the people searching this?': 'کسانی که این را جست‌وجو می‌کنند چند سال دارند؟',
    'years': 'سال',
    'median age': 'میانهٔ سنی',
    'How sure': 'میزان اطمینان',
    'Low': 'کم',
    'Medium': 'متوسط',
    'High': 'زیاد',
    'the pale band behind each bar is its likely range': 'نوار کم‌رنگ پشت هر ستون، بازهٔ محتمل آن است',
    'Which age each phrase leans to': 'هر عبارت به کدام سن می‌خورد',
    'only phrases whose own words or videos say something are placed · colour = opportunity': 'فقط عبارت‌هایی که کلمات یا ویدیوهایشان نشانه‌ای دارند · رنگ = فرصت',
    'Why this estimate': 'چرا این تخمین',
    'ESTIMATED — Google does not publish searcher age': 'تخمینی — گوگل سن جست‌وجوگرها را منتشر نمی‌کند',
    "Neither YouTube autocomplete nor Google Trends publishes the age of searchers — only YouTube Studio knows, and only for your own channel. This reading starts from YouTube's general audience and moves it with life-stage words (school, career, family, retirement), the Shorts share and length of the videos that rank, and learning intent.":
        'نه تکمیل خودکار یوتیوب و نه گوگل ترندز سن جست‌وجوگرها را منتشر نمی‌کنند — فقط یوتیوب استودیو آن را می‌داند، آن هم فقط برای کانال خودت. این تخمین از مخاطب عمومی یوتیوب شروع می‌کند و با کلمات مرحلهٔ زندگی (مدرسه، شغل، خانواده، بازنشستگی)، سهم Shorts و طول ویدیوهای برتر، و نیت یادگیری جابه‌جا می‌شود.',
    'How they watch': 'چطور تماشا می‌کنند',
    'measured · the videos that rank': 'سنجیده · ویدیوهای برتر',
    'Nothing saved yet — star a keyword in the hero or the explorer.': 'هنوز چیزی ذخیره نشده — در بالای صفحه یا کاوشگر به یک کلیدواژه ستاره بزن.',
    'Most of this demand likely comes from {a}-year-olds.': 'احتمالاً بیشتر این تقاضا از افراد {a} ساله می‌آید.',
    "Nothing in this run moves the estimate — it is YouTube's general audience.": 'هیچ سیگنالی در این اجرا تخمین را جابه‌جا نکرد — این همان مخاطب عمومی یوتیوب است.',
    'School & gaming words': 'کلمات مدرسه و بازی',
    'University words': 'کلمات دانشگاهی',
    'Career & skill words': 'کلمات شغل و مهارت',
    'Family & home words': 'کلمات خانواده و خانه',
    'Health & retirement words': 'کلمات سلامت و بازنشستگی',
    'Shorts share': 'سهم Shorts',
    'Video length': 'طول ویدیو',
    'Learning intent': 'نیت یادگیری',
    'younger': 'جوان‌تر',
    'older': 'مسن‌تر',
    'centre': 'مرکز',
    '{p}% of the ranking videos are Shorts': '{p}٪ ویدیوهای برتر Shorts هستند',
    'median {m} min': 'میانه {m} دقیقه',
    '{p}% of phrases are learning phrases': '{p}٪ عبارت‌ها آموزشی‌اند',
    '{a}–{b}%': '{a} تا {b}٪',
    '13–17': '۱۳ تا ۱۷',
    '18–24': '۱۸ تا ۲۴',
    '25–34': '۲۵ تا ۳۴',
    '35–44': '۳۵ تا ۴۴',
    '45–54': '۴۵ تا ۵۴',
    '55+': 'بالای ۵۵',
})


# ── v3.20 — Keyword Lab: one demand index, readable shortlists ──────────
FA_STRINGS.update({
    'Easy': 'آسان',
    'Hard': 'سخت',
    'Curve of “{s}” — Google Trends only measures the top few phrases, so this one has no curve of its own.': 'منحنیِ «{s}» — گوگل ترندز فقط چند عبارت برتر را می\u200cسنجد، پس این عبارت منحنی مخصوص خودش را ندارد.',
    "Score = demand × how open the field is. Competition wasn't checked for this phrase, so it counts at half weight.": 'امتیاز = تقاضا × میزان باز بودن بازار. رقابتِ این عبارت بررسی نشده، پس با نصف وزن حساب شده.',
    'Score = demand × how open the field is (channels, headroom, freshness).': 'امتیاز = تقاضا × میزان باز بودن بازار (تعداد کانال\u200cها، سقف بازدید، تازگی).',
    'Competition not checked for this phrase.': 'رقابتِ این عبارت بررسی نشده.',
    'not checked': 'بررسی نشده',
    'typical': 'معمولاً',
    'est.': 'تخمینی',
    'Best openings': 'بهترین فرصت\u200cها',
    'score 0–100 = demand × how open the field is': 'امتیاز ۰ تا ۱۰۰ = تقاضا × میزان باز بودن بازار',
    'Most searched': 'پرجست\u200cوجوترین\u200cها',
    'demand index 0–100 · autocomplete + Google Trends · not a search count': 'شاخص تقاضا ۰ تا ۱۰۰ · تکمیل خودکار + گوگل ترندز · تعداد جست\u200cوجو نیست',
    'Nothing came back for this run.': 'در این اجرا چیزی برنگشت.',
    "est. = Google Trends didn't measure this phrase (it only measures the top few per run), so its demand comes from autocomplete alone.": 'تخمینی = گوگل ترندز این عبارت را نسنجیده (در هر اجرا فقط چند عبارت برتر را می\u200cسنجد)، پس تقاضایش فقط از تکمیل خودکار آمده.',
    'seed curve': 'منحنی عبارت اصلی',
    'search interest over time · shape, not volume': 'علاقهٔ جست\u200cوجو در طول زمان · شکل منحنی، نه حجم',
    'No Google Trends curve this run (Google limits how often it answers). Demand below comes from YouTube autocomplete — still real phrases people type.': 'در این اجرا منحنی گوگل ترندز نیامد (گوگل تعداد درخواست\u200cها را محدود می\u200cکند). تقاضای زیر از تکمیل خودکار یوتیوب آمده — همچنان عبارت\u200cهای واقعی\u200cای که مردم تایپ می\u200cکنند.',
    'Try again': 'دوباره امتحان کن',
    'Typical video gets': 'یک ویدیوی معمولی می\u200cگیرد',
    'Difficulty (KD)': 'سختی (KD)',
    'real YouTube autocomplete · bars = how strongly autocomplete suggests it · click one to research it': 'تکمیل خودکار واقعی یوتیوب · میله\u200cها = چقدر قوی پیشنهاد می\u200cشود · برای تحقیق روی هر کدام کلیک کن',
    'Score': 'امتیاز',
    '0–100 · is it worth a video? demand × open field': '۰ تا ۱۰۰ · ارزش ساختن ویدیو دارد؟ تقاضا × بازار باز',
    '0–100 · how much people search it, relative to this set': '۰ تا ۱۰۰ · چقدر جست\u200cوجو می\u200cشود، نسبت به همین مجموعه',
    '0–100 · how hard to rank · easy ≤ 40 < medium ≤ 60 < hard': '۰ تا ۱۰۰ · رتبه گرفتن چقدر سخت است · آسان ≤ ۴۰ < متوسط ≤ ۶۰ < سخت',
    'not measured by Google Trends': 'با گوگل ترندز سنجیده نشده',
})


# v3.21 — keyword boards redesign
FA_STRINGS.update({'Who suggests what': 'کدام موتور چه پیشنهاد می\u200cدهد', 'Only YouTube': 'فقط یوتیوب', 'Both': 'هر دو', 'Only Google': 'فقط گوگل', "What's rising around it": 'چه چیزی کنارش داغ شده', 'Breakout': 'انفجاری', "Where it's searched": 'کجا جست\u200cوجو می\u200cشود', 'Load regions': 'خواندن مناطق', 'per head, not a count': 'سرانه، نه تعداد', 'Strongest region': 'قوی\u200cترین منطقه', 'Copy all': 'کپی همه', 'SUB-TOPIC': 'زیرموضوع', 'FORMAT SERIES': 'سری قالبی', 'A series of {n} videos — one per phrase': 'یک سری {n} ویدیویی — هر عبارت یک ویدیو', 'tags': 'تگ', 'characters, counted like Studio': 'کاراکتر، با شمارش استودیو', 'Reset': 'بازنشانی', 'Removed:': 'حذف\u200cشده:', 'Restore': 'بازگردانی', "UP NEXT — didn't fit · click to pin one in": 'بعدی\u200cها — جا نشدند · کلیک کن تا اضافه شود', 'Drop this tag — the next one moves in': 'این تگ را حذف کن — بعدی جایش می\u200cآید', 'Strongest': 'قوی\u200cترین', 'Longest': 'بلندترین', 'Show fewer': 'نمایش کمتر', 'Show all {n}': 'نمایش همهٔ {n}', 'No phrase matches that filter.': 'هیچ عبارتی با این فیلتر نمی\u200cخواند.', 'No stated intent': 'بدون نیت مشخص', 'What they actually type': 'چیزی که واقعاً تایپ می\u200cکنند', '{n} of the phrases people type': '{n} عبارت از عبارت\u200cهایی که تایپ می\u200cکنند', 'hottest': 'داغ\u200cترین', 'Shorts': 'شورتس', 'Typical length': 'طول معمول', 'Fresh uploads': 'آپلودهای تازه', 'long-form': 'بلند', 'mixed': 'ترکیبی', 'a Shorts feed': 'فید شورتس', 'quick answers': 'جواب سریع', 'explainers': 'توضیحی', 'deep dives': 'عمیق', 'fast-moving': 'پرتحرک', 'steady': 'پایدار', 'evergreen': 'همیشگی', 'format': 'قالب', 'subject': 'موضوع', 'Google rates these regions level — the phrase is searched evenly, so no single region leads.': 'گوگل این مناطق را هم\u200cسطح می\u200cداند — هیچ منطقه\u200cای جلو نیست.', 'Not enough searches for Google to split this phrase by region.': 'جست\u200cوجو برای تفکیک منطقه\u200cای کافی نیست.', 'Reading regions from Google Trends …': 'در حال خواندن مناطق از گوگل ترندز …'})


# v3.22 — search interest + opportunity map redesign, calibrated demand
FA_STRINGS.update({
    "too quiet": "خیلی کم برای قضاوت",
    "< 1% of seed": "کمتر از ۱٪ کلیدواژه‌ی اصلی",
    "{p}% of seed": "{p}٪ کلیدواژه‌ی اصلی",
    "difficulty": "سختی",
    "views / day": "بازدید در روز",
    "channels": "کانال‌ها",
    "Sweet spot": "نقطه‌ی طلایی",
    "wanted · winnable": "پرتقاضا · قابل‌رقابت",
    "Worth a fight": "ارزش جنگیدن دارد",
    "wanted · crowded": "پرتقاضا · شلوغ",
    "Quiet niche": "نیچ کم‌صدا",
    "open · fewer searches": "باز · جست‌وجوی کمتر",
    "crowded · fewer searches": "شلوغ · جست‌وجوی کمتر",
    "Search interest": "علاقه‌ی جست‌وجو",
    "Google Trends · relative, not a search count": "گوگل ترندز · نسبی، نه تعداد جست‌وجو",
    "Log": "لگاریتمی",
    "Linear": "خطی",
    "avg interest · {s}": "میانگین علاقه · {s}",
    "first vs last third": "یک‌سوم اول در برابر آخر",
    "busiest week": "شلوغ‌ترین هفته",
    "biggest phrase · {k}": "بزرگ‌ترین عبارت · {k}",
    "biggest discovered phrase": "بزرگ‌ترین عبارت کشف‌شده",
    "still collecting": "هنوز در حال جمع‌آوری",
    "under Trends' floor": "زیر کف ترندز",
    "Next to the seed this phrase never reaches 1 on Google's 0–100 scale, so Trends can't draw it here. Switch to Shape to see its curve on its own.":
        "کنار کلیدواژه‌ی اصلی، این عبارت در مقیاس ۰ تا ۱۰۰ گوگل هیچ‌وقت به ۱ نمی‌رسد، پس ترندز نمی‌تواند اینجا رسمش کند. برای دیدن منحنی خودش «شکل» را بزن.",
    "Shape: every line on its own peak, so curves can be compared but heights can't. The tooltip still prints the real shared-scale value.":
        "شکل: هر خط روی اوج خودش؛ شکل منحنی‌ها قابل مقایسه است، ارتفاع‌ها نه. راهنما هنوز مقدار واقعی مقیاس مشترک را نشان می‌دهد.",
    "Log scale on one shared Trends batch: lines stay comparable, and a phrase at 3 is still visible next to a seed at 90. Dashed = the week still being collected.":
        "مقیاس لگاریتمی روی یک دسته‌ی مشترک ترندز: خط‌ها قابل مقایسه می‌مانند و عبارتی با مقدار ۳ کنار کلیدواژه‌ای با ۹۰ هم دیده می‌شود. خط‌چین = هفته‌ای که هنوز جمع‌آوری می‌شود.",
    "Linear, one shared Trends batch: 100 is the busiest week any of these reached. Dashed = the week still being collected.":
        "خطی، یک دسته‌ی مشترک ترندز: ۱۰۰ شلوغ‌ترین هفته‌ای است که هر کدام از این‌ها رسیده. خط‌چین = هفته‌ای که هنوز جمع‌آوری می‌شود.",
    "right = easier to rank · up = more demand · size = views per day": "راست = رتبه‌گرفتن آسان‌تر · بالا = تقاضای بیشتر · اندازه = بازدید در روز",
    "easier to rank  →": "رتبه‌گرفتن آسان‌تر  →",
    "↑  demand": "↑  تقاضا",
    "Make next": "ویدیوی بعدی",
    "in the sweet spot": "در نقطه‌ی طلایی",
    "next best score": "بهترین امتیاز بعدی",
    "ringed = the phrase you typed": "حلقه‌دار = عبارتی که تایپ کردی",
    "hollow = demand estimated": "توخالی = تقاضای تخمینی",
    "demand index 0–100 · Trends vs the seed + views per day · not a search count":
        "شاخص تقاضا ۰ تا ۱۰۰ · ترندز نسبت به کلیدواژه‌ی اصلی + بازدید روزانه · نه تعداد جست‌وجو",
})


# v3.23 — markets, regions, Google curve, measured age
FA_STRINGS.update({
    "Worldwide": "سراسر جهان",
    "by country · worldwide": "به تفکیک کشور · سراسر جهان",
    "measured · YouTube search · by country, worldwide": "اندازه‌گیری‌شده · جست‌وجوی یوتیوب · به تفکیک کشور، سراسر جهان",
    "Load Google curve": "بارگذاری منحنی گوگل",
    "Re-run in {c}": "اجرای دوباره در {c}",
    "measured · DataForSEO": "اندازه‌گیری‌شده · DataForSEO",
    "Measured · DataForSEO": "اندازه‌گیری‌شده · DataForSEO",
    "Measured: most of the people searching this are {a}.": "اندازه‌گیری‌شده: بیشتر جست‌وجوکننده‌های این عبارت {a} هستند.",
    "Reading measured age from DataForSEO …": "در حال خواندن سن واقعی از DataForSEO …",
    "Reading the Google web-search curve …": "در حال خواندن منحنی جست‌وجوی گوگل …",
    "This run has no Google web-search curve — Trends was throttling when it ran. Load it now.": "این اجرا منحنی جست‌وجوی گوگل ندارد — ترندز موقع اجرا محدود کرده بود. الان بارگذاری کن.",
    "Google Trends is throttling this connection — wait a minute, then load the Google curve again.": "گوگل ترندز این اتصال را محدود کرده — یک دقیقه صبر کن و دوباره منحنی گوگل را بارگذاری کن.",
    "Couldn't load the Google curve yet.": "منحنی گوگل هنوز بارگذاری نشد.",
    "Google Trends sent no web-search reading.": "گوگل ترندز دادهٔ جست‌وجوی وب نفرستاد.",
    "Most of the searching for this phrase comes from {top}, but this run measured demand inside {here}. Re-run it in {top} or Worldwide for numbers that match its real audience.": "بیشتر جست‌وجوی این عبارت از {top} است، ولی این اجرا تقاضا را داخل {here} اندازه گرفته. برای عددهای درست، در {top} یا سراسر جهان دوباره اجرا کن.",
    "This run was saved before v3.23 — its map shows states inside {c}, not the countries searching it. Re-read it.": "این اجرا قبل از v3.23 ذخیره شده — نقشه‌اش استان‌های داخل {c} است، نه کشورهای جست‌وجوکننده. دوباره بخوان.",
})


# v3.23b — measured age panel, country prior
FA_STRINGS.update({
    "Where the searchers live": "کشور جست‌وجوکننده‌ها",
    "{c} · population median age {m}": "{c} · میانه‌ی سنی جمعیت {m}",
    "worldwide": "سراسر جهان",
    "{m}% men · {f}% women": "{m}٪ مرد · {f}٪ زن",
    "Measured age": "سن اندازه‌گیری‌شده",
    "Make the age real": "سن واقعی را بخوان",
    "DataForSEO API login (email)": "لاگین API دیتافورسئو (ایمیل)",
    "API password": "رمز API",
    "Connect": "اتصال",
    "Disconnect": "قطع اتصال",
    "Read measured age": "خواندن سن واقعی",
    "Measured age loaded.": "سن واقعی بارگذاری شد.",
    "DataForSEO connected.": "DataForSEO وصل شد.",
    "DataForSEO disconnected.": "اتصال DataForSEO قطع شد.",
    "Couldn't save: {e}": "ذخیره نشد: {e}",
    "Connected. Read the measured age split for this phrase.": "وصل است. تفکیک سنی واقعی این عبارت را بخوان.",
    "The age below is an estimate. Connect DataForSEO (about $0.0025 per phrase, your own account) to replace it with the measured split.": "سن پایین تخمینی است. با وصل کردن DataForSEO (حدود ۰.۰۰۲۵ دلار برای هر عبارت، با حساب خودت) تفکیک سنی واقعی جایش می‌نشیند.",
    "DataForSEO rejected the login or password. Check them under API Access in your DataForSEO dashboard.": "DataForSEO لاگین یا رمز را قبول نکرد. از بخش API Access داشبوردت چک کن.",
    "DataForSEO has no age data for this phrase — it is too small for its panel. The estimate below stays.": "DataForSEO برای این عبارت دادهٔ سنی ندارد (حجمش کم است). تخمین پایین می‌ماند.",
    "DataForSEO didn't answer this time. Try again in a moment.": "DataForSEO این بار جواب نداد. چند لحظه بعد دوباره امتحان کن.",
})

# ── v3.24: where they are — cities / provinces / countries; Trends backoff ──
FA_STRINGS.update({
    "Cities": "شهرها",
    "Countries": "کشورها",
    "States / provinces": "استان‌ها / ایالت‌ها",
    "Provinces · {c}": "استان‌ها · {c}",
    "inside {c}": "داخل {c}",
    "measured · {e} search · {s} · strongest first": "واقعی · جست‌وجوی {e} · {s} · از بیشترین",
    "measured · Google Trends · per head, not a count": "واقعی · گوگل ترندز · سرانه، نه تعداد",
    "Google Trends has no city split for this phrase yet.": "گوگل ترندز هنوز برای این عبارت تفکیک شهری ندارد.",
    "No state / province split came back for this phrase.": "برای این عبارت تفکیک استانی برنگشت.",
    "YouTube search is too thin for Google Trends to split this phrase by place, so this board reads Google web search instead — same people, same language, a bigger sample.": "جست‌وجوی یوتیوب برای تفکیک مکانی این عبارت در گوگل ترندز کافی نیست، برای همین این بخش از جست‌وجوی وب گوگل می‌خواند (همان مخاطب، همان زبان، نمونهٔ بزرگ‌تر).",
    "Google Trends is rate-limiting — retrying the regions in {n} s …": "گوگل ترندز محدودیت گذاشته — تلاش دوباره برای مناطق تا {n} ثانیه دیگر …",
    "Google Trends is rate-limiting this connection — retrying the regions automatically in a minute …": "گوگل ترندز روی این اتصال محدودیت گذاشته — یک دقیقه دیگر مناطق خودکار دوباره خوانده می‌شوند …",
    # v3.26: deno install errors, save locations
    "Couldn't download it": 'دانلود نشد',
    'Turn on your VPN (or set its HTTP proxy in Settings) and try again — or pick a deno.exe / deno zip you already have.': 'VPN را روشن کنید (یا پراکسی HTTP آن را در تنظیمات وارد کنید) و دوباره امتحان کنید — یا فایل deno.exe / زیپ deno که دارید را انتخاب کنید.',
    'From file…': 'از فایل…',
    'Pick deno.exe or the deno zip': 'deno.exe یا فایل زیپ deno را انتخاب کنید',
    'deno runtime': 'رانتایم deno',
    'your file': 'فایل شما',
    "installed, but the app still can't find it": 'نصب شد، ولی برنامه هنوز پیدایش نمی\u200cکند',
    'Unknown error': 'خطای ناشناخته',
    'Save Locations': 'محل ذخیره\u200cسازی',
    'Pick a separate home for downloaded videos and thumbnails.': 'برای ویدیوها و تامبنیل\u200cهای دانلودی، پوشه جدا انتخاب کنید.',
    'THUMBNAILS': 'تامبنیل\u200cها',
    'Choose': 'انتخاب',
    'Back to default': 'بازگشت به پیش\u200cفرض',
    'Asked the first time you save one': 'اولین بار که ذخیره کنید پرسیده می\u200cشود',
    'Choose where videos are saved': 'محل ذخیره ویدیوها را انتخاب کنید',
    'Choose where thumbnails are saved': 'محل ذخیره تامبنیل\u200cها را انتخاب کنید',
})


# v3.28: IP / country gate (GeoGateDialog)
FA_STRINGS.update({'Checking your connection …': 'در حال بررسی اتصال شما …', "Paused · this IP can't reach YouTube": 'متوقف · این IP به یوتیوب دسترسی ندارد', "Connection looks good — you're coming from {c}.": 'اتصال اوکی است — IP شما از {c} است.', 'Connection': 'اتصال', 'a filtered country': 'کشوری که یوتیوب در آن فیلتر است', 'Your connection': 'اتصال شما', 'YouTube API': 'API یوتیوب', 'Checking your route …': 'در حال بررسی مسیر …', 'Route open · via {c}': 'مسیر باز است · از {c}', "Couldn't verify the route · carrying on": 'مسیر تأیید نشد · ادامه می\u200cدهیم', 'Blocked at the border · {c}': 'مسدود در مرز · {c}', "You're through.": 'وصل شدید.', "This scrape won't run on your IP": 'با IP فعلی شما اسکرپ انجام نمی\u200cشود', 'Your IP is in {c}': 'IP شما برای {c} است', 'Starting your scrape now.': 'اسکرپ همین الان شروع می\u200cشود.', 'YouTube is reachable from this connection. Enjoy.': 'یوتیوب از این اتصال در دسترس است.', "Google's YouTube API refuses every request from {c}, so this run would stop at the first call and save nothing.": 'API یوتیوب گوگل همه درخواست\u200cهای {c} را رد می\u200cکند؛ این اسکرپ در همان درخواست اول متوقف می\u200cشود و چیزی ذخیره نمی\u200cشود.', "YouTube is filtered there, so scraping, Niche Finder, downloads and transcripts can't get through on this connection.": 'یوتیوب آنجا فیلتر است، پس اسکرپر، نیچ فایندر، دانلود و زیرنویس\u200cها با این اتصال کار نمی\u200cکنند.', 'Turn your VPN on in TUN / system-wide mode': 'VPN را در حالت TUN / کل سیستم روشن کنید', '"System proxy" mode only covers the browser. The scraper needs the whole system tunnelled.': 'حالت «System proxy» فقط مرورگر را پوشش می\u200cدهد؛ اسکرپر به تونل کل سیستم نیاز دارد.', "Or paste your VPN's HTTP proxy in Settings": 'یا پراکسی HTTP فیلترشکن را در تنظیمات وارد کنید', 'Covers downloads, transcripts and AI. Scraping still needs TUN mode.': 'برای دانلود، زیرنویس و هوش مصنوعی کافی است؛ اسکرپ همچنان حالت TUN می\u200cخواهد.', 'Your Settings proxy exits in {w}, so downloads are fine — but the YouTube API still leaves from {c}.': 'پراکسی تنظیمات از {w} خارج می\u200cشود و دانلودها مشکلی ندارند — ولی API یوتیوب هنوز از {c} وصل می\u200cشود.', 'Skip for now': 'فعلاً رد شو', 'Scrape anyway': 'در هر صورت اسکرپ کن', 'Proxy settings': 'تنظیمات پراکسی', 'Checking …': 'در حال بررسی …', 'Check again': 'بررسی دوباره'})

# v3.29: transcript turbo
FA_STRINGS.update({
    '×{n} transcripts': '×{n} ترنسکریپت هم‌زمان',
    'Transcripts: {n} in parallel{t}': 'ترنسکریپت: {n} تا هم‌زمان{t}',
})

# ── added: Usage & Quota v10 — "Equalizer" trend + "Spectrum" unit mix ──
FA_STRINGS.update({
    'CONSUMPTION': 'مصرف',
    'units in the last {d} days': 'واحد در {d} روز اخیر',
    'Peak': 'اوج',
    'Avg / day': 'میانگین / روز',
    'Active days': 'روزهای فعال',
    'Running total': 'مجموع تجمعی',
    'Hover a day for exact numbers': 'روی هر روز نگه دار تا عدد دقیق را ببینی',
    'Nothing spent in this window': 'در این بازه مصرفی نبوده',
    'WHERE UNITS GO': 'واحدها کجا می‌روند',
    '{name} drives {p} of your spend': '{p} از مصرف تو مال {name} است',
})

# ── added: Usage & Quota v11 — API keys "Cells" + price list "Weights" ──
FA_STRINGS.update({
    'API KEYS': 'کلیدهای API',
    'units left today': 'واحد باقی‌مانده‌ی امروز',
    'left': 'باقی‌مانده',
    '{p}% used': '{p}٪ مصرف‌شده',
    '+10K units a day per key': 'هر کلید +۱۰ هزار واحد در روز',
    'WHAT THINGS COST': 'هزینه‌ی هر کار',
    'One keyword search costs as much as {n} video lookups': 'یک جست‌وجوی کلیدواژه به اندازه‌ی {n} بار گرفتن آمار ویدیو هزینه دارد',
    'YouTube bills in units': 'یوتیوب بر اساس واحد حساب می‌کند',
    'Free': 'رایگان',
    'units saved': 'واحد صرفه‌جویی‌شده',
    '{n} searches cached locally · reopening them is free': '{n} جست‌وجو به‌صورت محلی ذخیره شده · باز کردن دوباره‌شان رایگان است',
})


# ── v3.36: connection gate redesign + Persian copy pass for beginners ──
# One term per idea: استخراج (scrape) · موضوع‌یاب (Niche Finder) · طرح (blueprint)
# · استثنایی (outlier) · درآمدزایی (monetization). Overrides earlier entries.
FA_STRINGS.update({
    'Run a search to discover outlier videos.': 'برای کشف ویدیوهای استثنایی یک جست\u200cوجو اجرا کنید.',
    'Every finished Niche Finder search lands here automatically.': 'هر جست\u200cوجوی تکمیل\u200cشده در موضوع\u200cیاب به\u200cطور خودکار اینجا ثبت می\u200cشود.',
    'Go to Niche Finder': 'رفتن به موضوع\u200cیاب',
    'Youtube Scrapper · Field Guide': 'یوتیوب هانتر · راهنمای کامل',
    "Youtube Scrapper is a research desk for YouTube: it finds videos that are punching far above their channel's weight, keeps every search you run, checks whether a channel is earning, and turns any of it into new video ideas with AI.": 'یوتیوب هانتر یک میز تحقیق برای یوتیوب است: ویدیوهایی را پیدا می\u200cکند که بسیار بالاتر از وزن کانالشان ظاهر شده\u200cاند، هر جست\u200cوجویی که اجرا می\u200cکنید را نگه می\u200cدارد، بررسی می\u200cکند کانال درآمد دارد یا نه، و هر کدام از این\u200cها را با هوش مصنوعی به ایده\u200cی ویدیوی تازه تبدیل می\u200cکند.',
    'Scrapper · scrape one channel': 'Scrapper · استخراج یک کانال',
    'Niche Finder · the outlier hunt': 'موضوع\u200cیاب · شکار ویدیوهای استثنایی',
    'Every Niche Finder search lands here as its own keyword section, with its results, its filters and its window. Click a keyword to bring it back into the grid; re-run it later and the fresh numbers are merged into the section instead of replacing it, so you can watch a niche move over weeks.': 'هر جست\u200cوجوی موضوع\u200cیاب به\u200cعنوان یک بخش کلیدواژه\u200cی مستقل با نتایج، فیلترها و بازه\u200cاش اینجا می\u200cنشیند. روی کلیدواژه بزنید تا نتایجش به گرید برگردد؛ اگر بعداً همان را دوباره اجرا کنید، اعداد تازه با بخش قبلی ادغام می\u200cشوند نه اینکه جایش را بگیرند — یعنی می\u200cتوانید حرکت یک حوزه را در طول هفته\u200cها ببینید.',
    'Monetize Checker · is this channel earning?': 'بررسی درآمدزایی · این کانال درآمد دارد؟',
    'History keeps every scrape and export you have run, with its row counts and file paths. Logs is the live console: colour-coded, searchable, and worth reading when a scrape stops early — the reason is always in there.': 'تاریخچه هر استخراج و خروجی\u200cای که گرفته\u200cاید را با تعداد ردیف\u200cها و مسیر فایل نگه می\u200cدارد. لاگ\u200cها کنسول زنده است: رنگ\u200cبندی\u200cشده، قابل جست\u200cوجو، و وقتی استخراجی نیمه\u200cکاره متوقف می\u200cشود ارزش خواندن دارد — دلیلش همیشه همان\u200cجاست.',
    'This channel is monetized.': 'این کانال درآمدزا است.',
    'This channel is not monetized.': 'این کانال درآمدزا نیست.',
    "No ad slots came back on the {m} recent videos checked — the logged-out player skips ads for its own reasons, so this alone doesn't mean the channel isn't monetized.": 'روی {m} ویدیوی اخیر بررسی\u200cشده اسلات تبلیغی برنگشت — پخش\u200cکننده در حالت خارج از حساب به دلایل خودش هم تبلیغ را رد می\u200cکند، پس این تنهایی به معنای نبودِ درآمدزایی نیست.',
    '{n} monetization feature(s) that only Partner Program channels can switch on were found live on the channel.': '{n} قابلیت درآمدزایی که فقط کانال\u200cهای عضو برنامه\u200cی همکاری می\u200cتوانند روشن کنند، به\u200cصورت زنده روی کانال پیدا شد.',
    'No public monetization feature is switched on, but this channel clears the Partner Program requirements and is publishing actively — the overwhelmingly likely case is that ads are running with memberships and merch simply left off.': 'هیچ قابلیت درآمدزایی عمومی روشن نیست، اما این کانال شرایط برنامه\u200cی همکاری را دارد و فعالانه منتشر می\u200cکند — به\u200cاحتمال قاطع تبلیغات روی آن اجرا می\u200cشود و فقط عضویت و فروشگاه خاموش مانده\u200cاند.',
    'It meets the subscriber and watch-time bars and shows an active upload history; no opt-in feature (Join, Store, Super Thanks) is public, which is a display choice rather than a monetization one.': 'آستانه\u200cهای مشترک و زمان تماشا را رد کرده و تاریخ انتشار فعالی دارد؛ هیچ قابلیت اختیاری (Join، Store، سوپر تنکس) عمومی نیست که این یک انتخاب نمایشی است نه نشانه\u200cی نبود درآمدزایی.',
    'No monetization feature is switched on, and {gap}.': 'هیچ قابلیت درآمدزایی روشن نیست، و {gap}.',
    '{r}x outlier': '{r}× بیشتر از حد معمول',
    'Youtube Scrapper  ·  Core Control': 'یوتیوب هانتر  ·  کنترل مرکزی',
    'Monetize Checker': 'بررسی درآمدزایی',
    'New scrapes, monetization checks and AI ideas will show up here.': 'استخراج\u200cهای جدید، بررسی\u200cهای درآمدزایی و ایده\u200cهای هوش مصنوعی اینجا نمایش داده می\u200cشوند.',
    'Used by Monetize Checker, Idea Finder and Idea Analysis to generate AI insights, outlier explanations, title ideas and hooks.': 'برای تولید بینش\u200cهای هوش مصنوعی، توضیح ویدیوهای پرت، پیشنهاد عنوان و قلاب در بررسی درآمدزایی، یابنده\u200cی ایده و تحلیل ایده استفاده می\u200cشود.',
    'Monetization Checker': 'بررسی درآمدزایی',
    "Check any channel's monetization signals, estimated Partner Program eligibility, audience size and projected ad revenue.": 'سیگنال\u200cهای درآمدزایی، واجدشرایط\u200cبودن تخمینی برای برنامه\u200cی همکاری، حجم مخاطب و درآمد تبلیغاتی پیش\u200cبینی\u200cشده\u200cی هر کانالی را بررسی کنید.',
    'Check Monetization': 'بررسی درآمدزایی',
    'No direct monetization signal found, but the channel is over 1,000 subscribers.': 'سیگنال مستقیمی از درآمدزایی یافت نشد، اما کانال بیش از ۱۰۰۰ مشترک دارد.',
    'No monetization signals found, and the channel is under the 1,000-subscriber Partner Program threshold.': 'هیچ سیگنال درآمدزایی یافت نشد و کانال زیر آستانه\u200cی ۱۰۰۰ مشترکِ برنامه\u200cی همکاری است.',
    'Monetized': 'درآمدزا',
    'Not Monetized': 'بدون درآمد',
    'Estimate only — actual YouTube Partner Program approval also needs 4,000 public watch hours in 12 months (or 10M Shorts views in 90 days) plus a policy review, neither of which the public API exposes. This is not a confirmation of monetization status.': 'فقط یک تخمین — تأیید واقعی برنامه\u200cی همکاری یوتیوب همچنین به ۴۰۰۰ ساعت تماشای عمومی در ۱۲ ماه (یا ۱۰ میلیون بازدید شورتس در ۹۰ روز) به\u200cعلاوه بررسی خط\u200cمشی نیاز دارد که هیچ\u200cکدام از طریق API عمومی در دسترس نیست. این تأییدی برای وضعیت درآمدزایی نیست.',
    "Click Generate AI Insight for a Gemini-written read on this channel's niche, growth signals, and how it could improve monetization.": 'برای دریافت تحلیلی نوشته\u200cشده توسط جمینای درباره\u200cی حوزه\u200cی کانال، سیگنال\u200cهای رشد و راه\u200cهای بهبود درآمدزایی، روی تولید بینش هوش مصنوعی بزنید.',
    'Niche Finder': 'موضوع\u200cیاب',
    'Niche Finder · Outlier Discovery': 'موضوع\u200cیاب · کشف کانال\u200cهای استثنایی',
    'Search all of YouTube for a niche, then filter by subscriber count, views and time window to surface small channels pulling huge numbers — e.g. a 500-sub channel that hit 10M views in the last 30 days. Click any thumbnail or title to open it on YouTube.': 'کل یوتیوب را برای یک موضوع جست\u200cوجو کنید، سپس با فیلتر تعداد مشترک، بازدید و بازه\u200cی زمانی، کانال\u200cهای کوچکی را پیدا کنید که بازدید عظیم گرفته\u200cاند — مثلاً کانالی با ۵۰۰ مشترک که در ۳۰ روز گذشته ۱۰ میلیون بازدید خورده است. روی هر تامبنیل یا عنوان کلیک کنید تا در یوتیوب باز شود.',
    'Niche keywords  (separate several with a comma)': 'کلیدواژه\u200cهای موضوع  (چند مورد را با ویرگول جدا کنید)',
    'Type a niche keyword and press Search.': 'یک کلیدواژه\u200cی موضوع بنویسید و دکمه\u200cی جست\u200cوجو را بزنید.',
    'Web scrape · unlimited, no search quota': 'استخراج از وب · نامحدود، بدون مصرف سهمیه',
    'Enter at least one niche keyword first.': 'ابتدا حداقل یک کلیدواژه\u200cی موضوع وارد کنید.',
    'Web scrape · 0 search quota  ·  {u}/{t} spent today': 'استخراج از وب · صفر سهمیه  ·  امروز {u} از {t} مصرف شده',
    'YouTube API quota exhausted for today. Switch the data source to Web scrape, or try again after midnight Pacific time.': 'سهمیه\u200cی API یوتیوب برای امروز تمام شد. منبع داده را روی «استخراج از وب» بگذارید یا بعد از نیمه\u200cشب به وقت اقیانوس آرام دوباره تلاش کنید.',
    'Every Niche Finder search is stored here as its own keyword section. Click a keyword to bring its results back into the same grid — re-running a keyword merges the fresh numbers into the section instead of wiping it. Nothing here expires, and nothing here costs quota.': 'هر جست\u200cوجوی «موضوع\u200cیاب» این\u200cجا به\u200cصورت یک بخش جداگانه برای همان کلیدواژه ذخیره می\u200cشود. روی هر کلیدواژه کلیک کنید تا نتایجش دوباره در همان جدول گرید نمایش داده شود — اگر همان کلیدواژه را دوباره سرچ کنید، آمار تازه با نتایج قبلی ادغام می\u200cشود و چیزی پاک نمی\u200cشود. هیچ\u200cچیزِ این\u200cجا منقضی نمی\u200cشود و هیچ سهمیه\u200cای مصرف نمی\u200cکند.',
    'Open in Niche Finder': 'باز کردن در موضوع\u200cیاب',
    'Load this saved pool into the Niche Finder so every filter works on it — without spending a single search call.': 'این نتایج ذخیره\u200cشده را در «موضوع\u200cیاب» بارگذاری می\u200cکند تا همه\u200cی فیلترها روی آن کار کنند — بدون مصرف حتی یک فراخوانی جست\u200cوجو.',
    'Run a search in the Niche Finder — it will be saved here automatically.': 'در «موضوع\u200cیاب» یک جست\u200cوجو بزنید — به\u200cصورت خودکار همین\u200cجا ذخیره می\u200cشود.',
    'Nothing archived yet. Run a Niche Finder search and it will appear here as its own keyword section.': 'هنوز چیزی آرشیو نشده است. یک جست\u200cوجو در «موضوع\u200cیاب» بزنید تا این\u200cجا به\u200cصورت یک بخش برای همان کلیدواژه ساخته شود.',
    'Web scrape': 'استخراج از وب',
    'No favorites yet. Tap the bookmark icon on any video — here or in Niche Finder — to save it here under its keyword or channel section.': 'هنوز هیچ موردعلاقه\u200cای ثبت نشده. روی آیکن نشانک هر ویدیو بزنید — این\u200cجا یا در «موضوع\u200cیاب» — تا زیر همان بخش کلیدواژه یا کانالش این\u200cجا ذخیره شود.',
    'Good to know · Fetching video and channel statistics costs 1 unit per 50 items, so ordinary scraping barely touches the 10,000-unit budget. Only keyword search is expensive (100 units per page — about 100 searches a day), which is exactly why the Niche Finder caches results and the Search Archive keeps them forever.': 'خوب است بدانید · گرفتن آمار ویدیو و کانال برای هر ۵۰ آیتم فقط ۱ واحد هزینه دارد، پس استخراج معمولی تقریباً چیزی از سهمیه\u200cی ۱۰٬۰۰۰ واحدی کم نمی\u200cکند. فقط جست\u200cوجوی کلیدواژه گران است (۱۰۰ واحد برای هر صفحه — یعنی روزی حدود ۱۰۰ جست\u200cوجو)، و دقیقاً به همین دلیل است که Niche Finder نتایج را کش می\u200cکند و آرشیو جست\u200cوجو آن\u200cها را برای همیشه نگه می\u200cدارد.',
    'Creator & maintainer of Youtube Scrapper': 'سازنده و نگه\u200cدارنده\u200cی یوتیوب هانتر',
    'Monetization check complete': 'بررسی درآمدزایی تمام شد',
    'Monetization check failed': 'بررسی درآمدزایی ناموفق بود',
    'Niche Finder search complete': 'جست\u200cوجوی موضوع\u200cیاب تمام شد',
    'Niche Finder search failed': 'جست\u200cوجوی موضوع\u200cیاب ناموفق بود',
    'Your saved blueprints, and AI channel reports from a scraped CSV.': 'طرح\u200cهای ذخیره\u200cشده\u200cی شما، و گزارش\u200cهای کانال با هوش مصنوعی از روی فایل CSV استخراج\u200cشده.',
    'No favorited blueprints in this section yet.': 'هنوز طرح موردعلاقه\u200cای در این بخش نیست.',
    'Turn a scraped channel export into a full AI report — real charts and top videos from your data, plus tailored analysis. Output is a self-contained HTML page you can print to PDF.': 'خروجی استخراج\u200cشده\u200cی یک کانال را به یک گزارش کامل هوش مصنوعی تبدیل کنید — نمودارهای واقعی و ویدیوهای برتر از داده\u200cی خودتان، به\u200cهمراه تحلیل اختصاصی. خروجی یک صفحه\u200cی HTML مستقل است که می\u200cتوانید آن را به PDF چاپ کنید.',
    'Your saved AI blueprints, and deep AI reports from a scraped channel CSV.': 'طرح\u200cهای هوش مصنوعی ذخیره\u200cشده\u200cی شما، و گزارش\u200cهای عمیق هوش مصنوعی از روی CSV یک کانال استخراج\u200cشده.',
    'Go to AI Ideas, generate a few blueprints, and they show up here as their own section.': 'به بخش ایده\u200cهای هوش مصنوعی بروید، چند طرح بسازید تا همین\u200cجا به\u200cصورت یک بخش جداگانه نمایش داده شوند.',
    'Pick a blueprint to open its full production plan below.': 'یک طرح را انتخاب کنید تا طرح تولید کامل آن در پایین باز شود.',
    'Delete this blueprint?': 'این طرح حذف شود؟',
    'It will be removed from your Content Lab library for good. This cannot be undone.': 'این طرح برای همیشه از کتابخانه\u200cی آزمایشگاه محتوا حذف می\u200cشود. این کار قابل بازگشت نیست.',
    'This deletes the section and all {n} blueprint(s) in it. This cannot be undone.': 'این کار بخش و همه\u200cی {n} طرح داخل آن را حذف می\u200cکند. قابل بازگشت نیست.',
    'Analyze a scraped channel': 'تحلیل یک کانال استخراج\u200cشده',
    'Pick a channel export you scraped (CSV, Excel, JSONL or the .db file). The AI reads every row and writes a full report — why the top videos work, title patterns, best length and upload timing, and next-video ideas — as a self-contained HTML page you can print or save as PDF.': 'یک خروجی کانال که استخراج کرده\u200cاید انتخاب کنید (CSV، اکسل، JSONL یا فایل .db). هوش مصنوعی همه\u200cی ردیف\u200cها را می\u200cخواند و یک گزارش کامل می\u200cنویسد — اینکه چرا ویدیوهای برتر جواب می\u200cدهند، الگوی عنوان\u200cها، بهترین طول و زمان انتشار، و ایده\u200cهای ویدیوی بعدی — به\u200cصورت یک صفحه\u200cی HTML مستقل که می\u200cتوانید چاپ یا به\u200cصورت PDF ذخیره کنید.',
    'Blueprint deleted.': 'طرح حذف شد.',
    'Blueprint rebuilt.': 'طرح دوباره ساخته شد.',
    "Couldn't delete that blueprint.": 'حذف آن طرح ممکن نشد.',
    'Videos downloaded from Search Archive and Niche Finder, with live progress.': 'ویدیوهایی که از آرشیو جست\u200cوجو و موضوع\u200cیاب دانلود کرده\u200cاید، با نمایش زنده\u200cی پیشرفت.',
    'ALL BLUEPRINTS': 'همه\u200cی طرح\u200cها',
    'BLUEPRINTS IN “{k}”': 'طرح\u200cهای «{k}»',
    'AI Ideas · Blueprint Builder': 'ایده\u200cهای هوش مصنوعی · سازنده\u200cی طرح',
    'AI Ideas — turn finds into blueprints': 'ایده\u200cهای هوش مصنوعی — تبدیل یافته\u200cها به طرح',
    'An error occurred:\n{e}\n\nScraped data was saved — you can ': 'خطایی رخ داد:\n{e}\n\nداده\u200cهای استخراج\u200cشده ذخیره شد — می\u200cتوانید ',
    'Analyzing with {p} and folding in {n} blueprint(s) — ': 'تحلیل با {p} و ادغام {n} طرح — ',
    'Asking {p} for {n} blueprint(s)…': 'درخواست {n} طرح از {p} …',
    'Build the blueprints': 'ساختن طرح\u200cها',
    'Cleared the view. Your blueprints are still saved.': 'نما پاک شد. طرح\u200cهای شما هنوز ذخیره\u200cاند.',
    "Couldn't find where this blueprint is stored.": 'محل ذخیره\u200cی این طرح پیدا نشد.',
    'Describe the video you want to make, pick references that already perform, or both — and get full production blueprints back.': 'ویدیویی که می\u200cخواهید بسازید را توصیف کنید، ویدیوهای مرجعی که از قبل عملکرد خوبی دارند را انتخاب کنید، یا هر دو — و طرح کامل تولید تحویل بگیرید.',
    'Fetch transcripts while scraping': 'گرفتن زیرنویس هم\u200cزمان با استخراج',
    'New Scrape': 'استخراج تازه',
    'Niche Finder — the outlier hunt': 'موضوع\u200cیاب — شکار ویدیوهای استثنایی',
    'No AI provider configured — add a key in Settings to generate blueprints.': 'هیچ سرویس هوش مصنوعی تنظیم نشده — برای ساخت طرح در تنظیمات یک کلید اضافه کنید.',
    'No activity yet. Start a scrape from the Scraper page.': 'هنوز فعالیتی نیست. از صفحه\u200cی استخراج یک اجرا شروع کنید.',
    'No activity yet. Start a scrape.': 'هنوز فعالیتی نیست. یک استخراج شروع کنید.',
    'No blueprints yet': 'هنوز طرحی نیست',
    'No favorited blueprints yet.': 'هنوز طرح نشان\u200cدار\u200cی نیست.',
    'No saved blueprints for “{kw}” yet.': 'هنوز طرح ذخیره\u200cشده\u200cای برای «{kw}» نیست.',
    'Not used in this mode — the blueprints come from your brief alone.': 'در این حالت استفاده نمی\u200cشود — طرح\u200cها فقط از بریف شما ساخته می\u200cشوند.',
    'Nothing archived yet — run a Niche Finder search and it shows up here automatically.': 'هنوز چیزی آرشیو نشده — یک جست\u200cوجوی موضوع\u200cیاب اجرا کنید تا خودکار اینجا بیاید.',
    'Output & Scrape Preferences': 'خروجی و تنظیمات استخراج',
    'Real-time output from the active extraction worker.': 'خروجی زنده\u200cی کارگرِ استخراجِ فعال.',
    'Rebuilding “{t}” with the full blueprint…': 'بازسازی «{t}» با طرح کامل …',
    'Regenerate this blueprint': 'ساخت دوباره\u200cی این طرح',
    'Review or open past extraction exports.': 'خروجی\u200cهای استخراج\u200cهای گذشته را ببینید یا باز کنید.',
    'Saved automatically — this blueprint is in your Content Lab library.': 'خودکار ذخیره شد — این طرح در کتابخانه\u200cی کانتنت لبِ شماست.',
    'Scraped {n} videos ({suffix})  ·  Transcripts: {tc}/{n}': '{n} ویدیو استخراج شد ({suffix})  ·  زیرنویس: {tc}/{n}',
    'Scraper': 'استخراج ویدیو',
    'Scraper — pull the raw data': 'استخراج — گرفتن داده\u200cی خام',
    'Select a save folder on the Scraper page to see history here.': 'برای دیدن تاریخچه، در صفحه\u200cی استخراج یک پوشه\u200cی ذخیره انتخاب کنید.',
    'This blueprint has no full script, shot list or competitor breakdown — those came later. Rebuilding keeps the same idea and adds them.': 'این طرح متن کامل، فهرست پلان و تحلیل رقبا ندارد — آن\u200cها بعداً اضافه شدند. بازسازی همان ایده را نگه می\u200cدارد و این\u200cها را اضافه می\u200cکند.',
    'This can take a few minutes — each blueprint is a full production plan. You can leave the page; the run continues.': 'این کار می\u200cتواند چند دقیقه طول بکشد — هر طرح یک برنامه\u200cی کامل تولید است. می\u200cتوانید صفحه را ترک کنید؛ اجرا ادامه پیدا می\u200cکند.',
    'Tick the reference videos whose style you want to borrow, describe your angle, and the AI returns full blueprints: titles, hooks, structure and a shot list.': 'ویدیوهای مرجعی که می\u200cخواهید سبکشان را قرض بگیرید تیک بزنید، زاویه\u200cی خود را توصیف کنید، و هوش مصنوعی طرح کامل تحویل می\u200cدهد: عنوان، هوک، ساختار و فهرست پلان.',
    'Try a different search or filter — completed extractions land here automatically.': 'جست\u200cوجو یا فیلتر دیگری را امتحان کنید — استخراج\u200cهای تمام\u200cشده خودکار اینجا می\u200cآیند.',
    'Two tabs: your saved blueprint library, and CSV Analysis — hand it a scraped export and get back a complete channel report as a self-contained HTML page.': 'دو زبانه: کتابخانه\u200cی طرح\u200cهای ذخیره\u200cشده\u200cی شما، و تحلیل CSV — یک خروجی استخراج\u200cشده بدهید و یک گزارش کامل کانال به\u200cصورت صفحه\u200cی HTML مستقل بگیرید.',
    'Your blueprints': 'طرح\u200cهای شما',
    '{n} new blueprint(s) generated.': '{n} طرح تازه ساخته شد.',
    '{n} saved blueprint(s) for “{kw}”.': '{n} طرح ذخیره\u200cشده برای «{kw}».',
    '{n} searches left today · each API-source Niche Finder search adds one; Web scrape adds none (100 units each, the priciest call there is)': '{n} جست\u200cوجو برای امروز باقی است · هر جست\u200cوجوی موضوع\u200cیاب با منبع «API» یک عدد اضافه می\u200cکند؛ منبع «استخراج» سهمیه نمی\u200cخورد (هر کدام ۱۰۰ واحد، گران\u200cترین فراخوانی که وجود دارد)',
    '✓ Blueprint rebuilt with the full production plan.': '✓ طرح با برنامه\u200cی کامل تولید بازسازی شد.',
    '✓ {n} blueprint(s) ready.': '✓ {n} طرح آماده شد.',
    'Delete this section and its blueprints': 'حذف این بخش و طرح\u200cهایش',
    '1 · Scraper': '۱ · استخراج',
    '2 · Niche Finder': '۲ · موضوع\u200cیاب',
    "Every section lives here, roughly in the order you use them: scrape data, find outliers, turn them into ideas, then download. The active section shows a red bar at the window edge. We'll walk through each one.": 'همه\u200cی بخش\u200cها این\u200cجا هستند، تقریباً به همان ترتیبی که استفاده می\u200cشوند: استخراج داده، پیداکردن ویدیوهای استثنایی، تبدیلشان به ایده، و بعد دانلود. بخش فعال یک نوار قرمز کنار لبه\u200cی پنجره دارد. یکی\u200cیکی مرورشان می\u200cکنیم.',
    'Point it at a channel URL or a keyword, set how many videos to take, and start. The rest of the app works from what you extract here.': 'آدرس یک کانال یا یک کلیدواژه بده، تعداد ویدیو را تعیین کن و شروع کن. بقیه\u200cی برنامه از همین چیزی که این\u200cجا استخراج می\u200cکنی کار می\u200cکند.',
    'Turn the videos you found into full content blueprints with AI.': 'ویدیوهایی که پیدا کردی را با هوش مصنوعی به طرح کامل محتوا تبدیل کن.',
    'From finds to blueprints': 'از یافته\u200cها تا طرح',
    'The outlier hunt': 'شکار استثنایی',
    'When the primary key runs out of daily quota mid-scrape, the app switches to the next key automatically.': 'وقتی کلید اصلی وسط استخراج سهمیه روزانه\u200cاش تمام شود، برنامه به\u200cطور خودکار به کلید بعدی سوئیچ می\u200cکند.',
    'Channel + blueprints': 'کانال + طرح\u200cها',
    '{n} blueprint(s): {list}': '{n} طرح: {list}',
    'That blueprint is no longer saved.': 'آن طرح دیگر ذخیره نیست.',
    'This blueprint has no script yet — rebuild it in full first.': 'این طرح هنوز اسکریپت ندارد — اول آن را کامل بازسازی کنید.',
    'Script saved to the blueprint.': 'اسکریپت در طرح ذخیره شد.',
    'Pick a blueprint with a script to read it here.': 'یک طرح با اسکریپت انتخاب کنید تا همین\u200cجا خوانده شود.',
    "Read a blueprint's script off a real teleprompter, and fix the lines that don't land.": 'اسکریپت هر طرح را روی یک تله\u200cپرامپتر واقعی بخوانید و خط\u200cهایی که نمی\u200cگیرند را اصلاح کنید.',
    'Generate a blueprint': 'ساخت یک طرح',
    'Generate blueprints on the AI Ideas page — each one comes with a timecoded, camera-ready script, and every script shows up here.': 'در صفحه\u200cی ایده\u200cهای هوش مصنوعی طرح بسازید — هر طرح یک اسکریپت تایم\u200cکددار و آماده\u200cی دوربین دارد و همه\u200cی آن\u200cها همین\u200cجا نمایش داده می\u200cشوند.',
    'Find a blueprint': 'یافتن طرح',
    'Run a search in Niche Finder and press “Analyze these results”, or open a saved section in Search Archive. This page costs no API quota — it reads rows you already have.': 'در موضوع\u200cیاب جست\u200cوجو کنید و «تحلیل این نتایج» را بزنید، یا یک بخش ذخیره\u200cشده را از آرشیو جست\u200cوجو باز کنید. این صفحه هیچ کوتای APIی مصرف نمی\u200cکند — همان ردیف\u200cهایی را می\u200cخواند که از قبل دارید.',
    'Who holds this niche': 'این موضوع دست کیست',
    'These show what is being SUPPLIED in this niche. They are not search volume and do not prove demand.': 'این\u200cها نشان می\u200cدهند چه چیزی در این موضوع عرضه می\u200cشود. حجم جست\u200cوجو نیستند و تقاضا را اثبات نمی\u200cکنند.',
    'Search result order is a personalised, region-sensitive snapshot — not a census of the niche.': 'ترتیب نتایج جست\u200cوجو یک اسنپ\u200cشات شخصی\u200cسازی\u200cشده و وابسته به منطقه است — سرشماری کل موضوع نیست.',
    'Your saved blueprints, the AI channel report, and the teleprompter you shoot from.': 'طرح\u200cهای ذخیره\u200cشده\u200cی شما، گزارش هوش مصنوعی کانال، و تله\u200cپرامپتری که از آن فیلم می\u200cگیرید.',
    "Optional — a Niche Scan brief is research about the niche, not about this channel. Every statement keeps its label (observed / inferred / needs Studio), and the report is told the channel's own numbers win where the two disagree.": 'اختیاری — بریفِ موضوع‌سنج، تحقیق درباره\u200cی موضوع است، نه درباره\u200cی این کانال. هر گزاره برچسب خودش را نگه می\u200cدارد (مشاهده\u200cشده / استنباطی / نیازمند استودیو)، و به گزارش گفته می\u200cشود هرجا این دو با هم نخوانند، عددهای خودِ کانال حرف آخر را می\u200cزنند.',
    'Analyze + blueprints + research': 'تحلیل + طرح\u200cها + تحقیق',
    'Channel + blueprints + research': 'کانال + طرح\u200cها + تحقیق',
    'Analyzing with {p}, folding in {n} blueprint(s) and {b} brief(s) — this can take a few minutes…': 'تحلیل با {p}، با تلفیق {n} طرح و {b} بریف — ممکن است چند دقیقه طول بکشد…',
    "Optional — a saved snapshot is research about the niche, not about this channel. A DATA row carries the measured aggregates (median vs average, momentum, length and recency mix, channel concentration); a RESEARCH row adds the written brief on top, every statement keeping its label (observed / inferred / needs Studio). The report is told the channel's own numbers win where the two disagree.": 'اختیاری — یک اسنپ\u200cشات ذخیره\u200cشده تحقیق درباره\u200cی موضوع است، نه درباره\u200cی این کانال. ردیفِ «داده» شاخص\u200cهای اندازه\u200cگیری\u200cشده را دارد (میانه در برابر میانگین، شتاب، ترکیب طول و تازگی، تمرکز کانال\u200cها)؛ ردیفِ «تحقیق» بریفِ نوشته\u200cشده را هم روی آن می\u200cافزاید و هر گزاره برچسب خودش را نگه می\u200cدارد (مشاهده\u200cشده / استنباطی / نیازمند استودیو). به گزارش گفته می\u200cشود هرجا این دو با هم نخوانند، عددهای خودِ کانال حرف آخر را می\u200cزنند.',
    'Sharpening {n} blueprint(s) against this channel …': 'تیزکردن {n} طرح بر پایهٔ داده\u200cهای این کانال …',
    'An API-source Niche Finder search bumps all three at once — bucket +1, units +100 (plus +1 per enrichment call), and the matching key row.': 'یک جست\u200cوجوی موضوع\u200cیاب با منبع API هر سه را هم\u200cزمان زیاد می\u200cکند — سطل ۱+، واحدها ۱۰۰+ (به\u200cعلاوه ۱+ برای هر فراخوان تکمیلی)، و ردیف کلید مربوط.',
    'A Web scrape touches none of the search bucket — only +1-unit enrichment calls, and only when a key is set.': 'استخراج از وب به سطل جست\u200cوجو دست نمی\u200cزند — فقط فراخوان\u200cهای تکمیلی ۱ واحدی، و فقط وقتی کلیدی تنظیم شده باشد.',
    'Niche keywords': 'کلمات کلیدی موضوع',
    'Niche Finder · Outlier Radar': 'موضوع\u200cیاب · رادار ویدیوهای استثنایی',
    'Search a niche, then cut by channel size, reach and the views ÷ subscribers multiplier. Every cut re-filters instantly.': 'یک موضوع را جست\u200cوجو کن، بعد با اندازه\u200cی کانال، بازدید و ضریب بازدید ÷ مشترک فیلترش کن. هر فیلتر فوراً اعمال می\u200cشود.',
    'Type a niche in the bar above and the outliers will show up here.': 'یک موضوع در نوار بالا بنویسید تا ویدیوهای استثنایی اینجا ظاهر شوند.',
    'Type a niche': 'یک موضوع بنویسید',
    'into your next blueprint.': 'به طرح بعدی\u200cات تبدیل کن.',
    'Blueprints': 'طرح\u200cها',
    'BLUEPRINT MAP': 'نقشه\u200cی طرح',
    'Drop in a scraped channel export. Get back real charts, the top videos, and an AI read on what to make next.': 'خروجی استخراج\u200cشده\u200cی کانال را بدهید؛ نمودارهای واقعی، برترین ویدیوها و تحلیل هوش مصنوعی برای محتوای بعدی را بگیرید.',
    '{n} blueprint(s)': '{n} طرح',
    'Read a niche as one set': 'یک موضوع را یک\u200cجا بخوانید',
    'Search in Niche Finder': 'در موضوع\u200cیاب جست\u200cوجو کنید',
    'blueprints': 'طرح',
    'Blueprints per run': 'تعداد طرح در هر اجرا',
    'The maximum counts matching videos only — the scraper keeps reading until it has that many.': 'سقف فقط ویدیوهای منطبق را می\u200cشمارد؛ استخراج تا رسیدن به همین تعداد ادامه می\u200cدهد.',
    'Why did this video become an outlier? Explain it with the numbers.': 'این ویدیو چرا استثنایی شد؟ با عدد توضیح بده.',
    "I'll find the unsaturated sub-niches and the winning titles.": 'زیرموضوع\u200cهای اشباع\u200cنشده و عنوان\u200cهای برنده را پیدا می\u200cکنم.',
    'Which sub-niche in this export is still not saturated?': 'در این خروجی کدام زیرموضوع هنوز اشباع نشده؟',
    'Ask Scope… e.g. “Why did this video become an outlier?”': 'از Scope بپرس… مثلاً «چرا این ویدیو استثنایی شد؟»',
    'Sorted by outlier multiplier': 'مرتب\u200cشده بر اساس ضریب استثنایی',
    'Blueprint score': 'امتیاز طرح',
    'Blueprint check': 'بررسی طرح',
    'Outlier': 'استثنایی',
    'Loading blueprint…': 'در حال بارگذاری طرح…',
    'Quiet niche': 'موضوع کم\u200cصدا',
    "This scrape won't run on your IP": 'با IP فعلی شما استخراج انجام نمی\u200cشود',
    'Starting your scrape now.': 'استخراج همین الان شروع می\u200cشود.',
    "Google's YouTube API refuses every request from {c}, so this run would stop at the first call and save nothing.": 'یوتیوب هر درخواستی را که از {c} بیاید رد می\u200cکند؛ این استخراج همان اول متوقف می\u200cشود و چیزی ذخیره نمی\u200cشود.',
    "YouTube is filtered there, so scraping, Niche Finder, downloads and transcripts can't get through on this connection.": 'یوتیوب آنجا فیلتر است، پس استخراج، موضوع\u200cیاب، دانلود و زیرنویس\u200cها با این اتصال کار نمی\u200cکنند.',
    '"System proxy" mode only covers the browser. The scraper needs the whole system tunnelled.': 'حالت «System proxy» فقط مرورگر را پوشش می\u200cدهد؛ استخراج به تونل کل سیستم نیاز دارد.',
    'Covers downloads, transcripts and AI. Scraping still needs TUN mode.': 'برای دانلود، زیرنویس و هوش مصنوعی کافی است؛ استخراج همچنان حالت TUN می\u200cخواهد.',
    'Scrape anyway': 'در هر حال استخراج کن',
    'Checking connection …': 'در حال بررسی اتصال…',
    'Connected': 'وصل شد',
    'No internet': 'اینترنت قطع است',
    'YouTube is blocked': 'یوتیوب فیلتر است',
    "You're through.": 'وصل شدی!',
    "Extraction can't run on this connection": 'با این اتصال، استخراج انجام نمی\u200cشود',
    'Your internet is down': 'اینترنت قطع است',
    "Your internet can't reach YouTube": 'اینترنتت به یوتیوب وصل نمی\u200cشود',
    'This run would stop at the first request.': 'این اجرا همان اول متوقف می\u200cشود.',
    "The app won't work until you connect.": 'تا وصل نشوی، برنامه کار نمی\u200cکند.',
    'YouTube is reachable from this connection. Enjoy.': 'یوتیوب در دسترس است. شروع کن!',
    'Not one server answered. Either the internet is cut, or only the domestic network is reachable right now.': 'هیچ سروری جواب نداد. یا اینترنت قطع است، یا الان فقط اینترنت داخلی (ملی) در دسترس است.',
    'Your IP is in {c}, where YouTube is filtered. Extraction, search, downloads and subtitles all need YouTube.': 'آی\u200cپی تو مربوط به {c} است و یوتیوب آن\u200cجا فیلتر است. استخراج، جست\u200cوجو، دانلود و زیرنویس همه به یوتیوب نیاز دارند.',
    'Check your Wi-Fi or cable': 'وای\u200cفای یا کابل اینترنت را چک کن',
    'Make sure the computer itself is online.': 'مطمئن شو خود سیستم به اینترنت وصل است.',
    'Turn your VPN on (TUN mode)': 'VPN را روشن کن (حالت TUN)',
    "In v2rayN, Hiddify or a similar app pick TUN / system-wide mode. “System proxy” alone isn't enough.": 'در v2rayN، Hiddify یا برنامه\u200cهای مشابه، حالت TUN (کل سیستم) را انتخاب کن. حالت «System proxy» به\u200cتنهایی کافی نیست.',
    'Press “Check again”': 'دکمه\u200cی «دوباره بررسی کن» را بزن',
    "Once you're through, this screen closes on its own.": 'اگر وصل شده باشی، این صفحه خودش بسته می\u200cشود.',
    'Check again': 'دوباره بررسی کن',
    'Checking …': 'در حال بررسی…',
    'Proxy settings': 'تنظیمات پروکسی',
    'Cancel': 'لغو',
    "Skip — I know the app won't work": 'رد شدن (می\u200cدانم برنامه کار نمی\u200cکند)',
    'You': 'شما',
    'a filtered country': 'یک کشور فیلترشده',
    "The app can't reach YouTube right now. Click to see how to fix it.": 'برنامه الان به یوتیوب دسترسی ندارد. برای دیدن راه\u200cحل کلیک کن.',
    'Computing data-driven insights …': 'در حال محاسبه\u200cی تحلیل\u200cهای داده\u200cمحور…',
    'Unknown error.': 'خطای ناشناخته.',
    'Downloading the {q} file, then cutting…': 'در حال دانلود فایل {q} و بعد برش…',
    'The download came out empty.': 'فایل دانلودشده خالی است.',
    'Trying full download instead…': 'به\u200cجایش دانلود کامل امتحان می\u200cشود…',
    'Retrying with another stream ({i}/{n}) …': 'تلاش دوباره با یک جریان دیگر ({i}/{n})…',
    'Merging compatibility mode …': 'ادغام در حالت سازگاری…',
    'Refreshing streams…': 'به\u200cروزرسانی جریان\u200cها…',
    'Add a Google OAuth client ID first (Setup).': 'اول یک Client ID گوگل (OAuth) اضافه کن (بخش راه\u200cاندازی).',
    'Connection cancelled.': 'اتصال لغو شد.',
    'Google sign-in failed: {msg}': 'ورود به گوگل ناموفق بود: {msg}',
    'Google Drive error ({code}).': 'خطای گوگل درایو ({code}).',
    'Google Drive took too long to answer.': 'گوگل درایو خیلی دیر جواب داد.',
    "Couldn't reach Google Drive: {reason}": 'اتصال به گوگل درایو ممکن نشد: {reason}',
    'Verified': 'تأیید شد',
    'Needs a host': 'آدرس سرور لازم است',
    'Required for a custom provider.': 'برای سرویس سفارشی لازم است.',
    'API key (optional for local gateways)': 'کلید API (برای سرور محلی اختیاری است)',
    'API key': 'کلید API',
    '{n} available': '{n} مورد موجود',
    'Make default': 'پیش\u200cفرض کن',
    'Duplicate': 'کپی بگیر',
    'Hide connection': 'پنهان\u200cکردن اتصال',
    'Click again to remove': 'برای حذف دوباره کلیک کن',
    '{p} is not set up': '{p} هنوز تنظیم نشده',
    'PROVIDER': 'سرویس',
    "Provider's model": 'مدل سرویس',
    'EFFORT': 'میزان دقت',
    'AI Providers': 'سرویس\u200cهای هوش مصنوعی',
    'Providers, routing & effort': 'سرویس\u200cها، مسیردهی و دقت',
    '1 ready': '۱ آماده',
    '{n} ready': '{n} آماده',
    'Your providers': 'سرویس\u200cهای شما',
    'Each one keeps its own host, key and model. Star one as the default.': 'هر کدام آدرس، کلید و مدل خودش را دارد. یکی را با ستاره پیش\u200cفرض کن.',
    'Add provider': 'افزودن سرویس',
    'Start from': 'شروع از',
    'Local': 'محلی',
    'Which AI does what': 'کدام هوش مصنوعی چه کاری کند',
    'Daily spend': 'مصرف روزانه',
    'Default provider': 'سرویس پیش\u200cفرض',
    'Custom endpoint': 'آدرس سفارشی',
    '{name} copy': 'کپی {name}',
    'Removed {name}.': '{name} حذف شد.',
    'Default ({name})': 'پیش\u200cفرض ({name})',
    'The provider returned no models.': 'این سرویس هیچ مدلی برنگرداند.',
    'Set API HOST first.': 'اول آدرس سرور (API HOST) را وارد کن.',
    'Search Archive': 'جست\u200cوجوهای ذخیره\u200cشده',
    'AI Ideas': 'ایده\u200cساز هوشمند',
    'Video Cutter': 'برش ویدیو',
    'Niche Scan': 'موضوع\u200cسنج',
    'YOUTUBE DAILY': 'سهمیه\u200cی امروز',
    'Channel, @handle, /channel/UC… or one video': 'لینک کانال، آیدی کانال (با @) یا لینک یک ویدیو',
})

# v3.38 — theme lock-on label
FA_STRINGS.update({
    'Dark mode': 'حالت تاریک',
    'Light mode': 'حالت روشن',
})

# v3.39 — audience match (language/country), hunt scope, scoreboard context
FA_STRINGS.update({
    'Indonesian': 'اندونزیایی',
    'Japanese': 'ژاپنی',
    'Korean': 'کره\u200cای',
    'Chinese (Simplified)': 'چینی (ساده)',
    'Chinese (Traditional)': 'چینی (سنتی)',
    'Vietnamese': 'ویتنامی',
    'Italian': 'ایتالیایی',
    'Thai': 'تایلندی',
    'Filipino': 'فیلیپینی',
    'Bengali': 'بنگالی',
    'Urdu': 'اردو',
    'Polish': 'لهستانی',
    'Ukrainian': 'اوکراینی',
    'Dutch': 'هلندی',
    'Malay': 'مالایی',
    'Tamil': 'تامیلی',
    'Telugu': 'تلوگو',
    'Marathi': 'مراتی',
    'Gujarati': 'گجراتی',
    'Kannada': 'کانادا',
    'Malayalam': 'مالایالم',
    'Punjabi': 'پنجابی',
    'Romanian': 'رومانیایی',
    'Greek': 'یونانی',
    'Czech': 'چکی',
    'Hungarian': 'مجاری',
    'Swedish': 'سوئدی',
    'Danish': 'دانمارکی',
    'Norwegian': 'نروژی',
    'Finnish': 'فنلاندی',
    'Hebrew': 'عبری',
    'Azerbaijani': 'آذربایجانی',
    'Kurdish': 'کردی',
    'Pashto': 'پشتو',
    'Swahili': 'سواحیلی',
    'Nepali': 'نپالی',
    'Sinhala': 'سینهالی',
    'Burmese': 'برمه\u200cای',
    'Khmer': 'خمری',
    'Georgian': 'گرجی',
    'Armenian': 'ارمنی',
    'Amharic': 'امهری',
    'Kazakh': 'قزاقی',
    'Uzbek': 'ازبکی',
    'Serbian': 'صربی',
    'Bulgarian': 'بلغاری',
    'Slovak': 'اسلواکی',
    'Croatian': 'کرواتی',
    'Indonesia': 'اندونزی',
    'Mexico': 'مکزیک',
    'Japan': 'ژاپن',
    'Russia': 'روسیه',
    'France': 'فرانسه',
    'Philippines': 'فیلیپین',
    'Vietnam': 'ویتنام',
    'South Korea': 'کره جنوبی',
    'Pakistan': 'پاکستان',
    'Egypt': 'مصر',
    'Saudi Arabia': 'عربستان',
    'Thailand': 'تایلند',
    'Spain': 'اسپانیا',
    'Italy': 'ایتالیا',
    'Argentina': 'آرژانتین',
    'Colombia': 'کلمبیا',
    'Chile': 'شیلی',
    'Peru': 'پرو',
    'Venezuela': 'ونزوئلا',
    'Portugal': 'پرتغال',
    'Netherlands': 'هلند',
    'Belgium': 'بلژیک',
    'Switzerland': 'سوئیس',
    'Austria': 'اتریش',
    'Poland': 'لهستان',
    'Ukraine': 'اوکراین',
    'Romania': 'رومانی',
    'Greece': 'یونان',
    'Czechia': 'چک',
    'Hungary': 'مجارستان',
    'Sweden': 'سوئد',
    'Norway': 'نروژ',
    'Denmark': 'دانمارک',
    'Finland': 'فنلاند',
    'Ireland': 'ایرلند',
    'New Zealand': 'نیوزیلند',
    'South Africa': 'آفریقای جنوبی',
    'Nigeria': 'نیجریه',
    'Kenya': 'کنیا',
    'Morocco': 'مراکش',
    'Algeria': 'الجزایر',
    'Iraq': 'عراق',
    'Jordan': 'اردن',
    'Qatar': 'قطر',
    'Kuwait': 'کویت',
    'Israel': 'اسرائیل',
    'Afghanistan': 'افغانستان',
    'Bangladesh': 'بنگلادش',
    'Sri Lanka': 'سری\u200cلانکا',
    'Nepal': 'نپال',
    'Malaysia': 'مالزی',
    'Singapore': 'سنگاپور',
    'Taiwan': 'تایوان',
    'Hong Kong': 'هنگ\u200cکنگ',
    'Azerbaijan': 'آذربایجان',
    'Kazakhstan': 'قزاقستان',
    'Uzbekistan': 'ازبکستان',
    'Georgia': 'گرجستان',
    'Armenia': 'ارمنستان',
    'Serbia': 'صربستان',
    'Bulgaria': 'بلغارستان',
    'Croatia': 'کرواسی',
    'Slovakia': 'اسلواکی',
    'Ethiopia': 'اتیوپی',
    'Cambodia': 'کامبوج',
    'Myanmar': 'میانمار',
    'Broad': 'گسترده',
    'Smart': 'هوشمند',
    'Strict': 'سخت\u200cگیرانه',
    'Audience match': 'تطبیق مخاطب',
    'Hunting': 'در حال شکار',
    'Filters the current results instantly and steers the next search': 'نتایج فعلی را فوری فیلتر می\u200cکند و جست\u200cوجوی بعدی را هم هدایت می\u200cکند',
    'Off. Results come from every language and country.': 'خاموش. نتایج از همهٔ زبان\u200cها و کشورها می\u200cآیند.',
    'Keeps videos in {lang} from channels based in {country}.': 'فقط ویدیوهای {lang} از کانال\u200cهای مستقر در {country} می\u200cمانند.',
    'Keeps videos in {lang}.': 'فقط ویدیوهای {lang} می\u200cمانند.',
    'Keeps videos from channels based in {country}.': 'فقط ویدیوهای کانال\u200cهای مستقر در {country} می\u200cمانند.',
    'Broad: only drops videos that clearly point elsewhere; unknowns stay.': 'گسترده: فقط ویدیوهایی که آشکارا مال جای دیگری\u200cاند حذف می\u200cشوند؛ نامعلوم\u200cها می\u200cمانند.',
    "Smart: needs real evidence (declared audio language, the title's own language, the channel's registered country).": 'هوشمند: مدرک واقعی لازم است (زبان صدای اعلام\u200cشده، زبان خود عنوان، کشور ثبت\u200cشدهٔ کانال).',
    'Strict: only videos the creator explicitly declared. Fewest results, zero guesses.': 'سخت\u200cگیرانه: فقط ویدیوهایی که سازنده صریحاً اعلام کرده. کمترین نتیجه، بدون حدس.',
    '{lang} is not a main language in {country}, so expect very few results.': '{lang} زبان اصلی {country} نیست؛ نتایج خیلی کمی انتظار داشته باش.',
    '{dim}: {v} verified, {l} inferred': '{dim}: {v} تأییدشده، {l} استنباطی',
    ', {u} unknown': '، {u} نامعلوم',
    '{n} filtered out by language/country': '{n} مورد با فیلتر زبان/کشور حذف شد',
    '(Broad would keep {u} more with weaker evidence)': '(حالت گسترده {u} مورد دیگر با مدرک ضعیف\u200cتر را نگه می\u200cداشت)',
    'of {n} fetched': 'از {n} مورد دریافتی',
    '{p}% of matches': '{p}٪ از نتایج',
    'avg {v} per video': 'میانگین {v} برای هر ویدیو',
})

# ── v3.39.5: AI Ideas — BlueprintForge (generating state) ──
FA_STRINGS.update({
    'AI Forge': 'کارگاه AI',
    'Forging 1 blueprint': 'در حال ساخت ۱ طرح',
    'Forging {n} blueprints': 'در حال ساخت {n} طرح',
    'Reading references': 'خواندن رفرنس‌ها',
    'Finding the pattern': 'پیدا کردن الگو',
    'Drafting hooks & script': 'نوشتن هوک و سناریو',
    'Polishing the blueprint': 'صیقل دادن طرح',
})

# ── v3.39.7: AI Ideas — Stop generating ──
FA_STRINGS.update({
    'Stop generating': 'توقف ساخت',
    'Generation stopped.': 'ساخت متوقف شد.',
})

# ── v3.39.8: Niche Scan — "shape of the set" redesign ──
FA_STRINGS.update({
    'length of each video': 'طول هر ویدیو',
    'median length': 'میانه‌ی طول',
    'most common length': 'رایج‌ترین طول',
    '{n} of {t} videos reported a length': '{n} از {t} ویدیو طول مشخص داشتند',
    'from the last 30 days': 'از ۳۰ روز اخیر',
    'published this week': 'در همین هفته منتشر شده‌اند',
    '{n} of {t} videos had a publish date': '{n} از {t} ویدیو تاریخ انتشار داشتند',
    'One channel dominates': 'یک کانال مسلط است',
    'A few channels lead': 'چند کانال جلودارند',
    'Open field': 'میدان باز',
    'of the views go to the #1 channel': 'از بازدیدها مال کانال اول است',
    'Hard to break in: one channel takes most of the attention.': 'ورود سخت است: یک کانال بیشترِ توجه را می‌گیرد.',
    'A handful of channels share most of the views.': 'چند کانال بیشترِ بازدیدها را بین خود تقسیم کرده‌اند.',
    'Views are spread out, there is room for a new channel.': 'بازدیدها پخش است؛ جا برای یک کانال تازه هست.',
    'channels': 'کانال',
    'top 3': 'سه کانال اول',
    'everyone else': 'بقیه',
})

# ── v3.40: away notices (desktop toasts) ──
FA_STRINGS.update({
    'now': 'همین الان',
    'View in app': 'مشاهده در برنامه',
    'App': 'برنامه',
    'Your video is saved and ready to watch.': 'ویدیو ذخیره شد و آماده‌ی تماشاست.',
    'Scrape complete': 'استخراج تمام شد',
    'Niche search complete': 'جست‌وجوی موضوع تمام شد',
    'Clip ready': 'کلیپ آماده است',
    'Blueprints ready': 'طرح‌ها آماده‌اند',
    "Scope couldn't answer": 'اسکوپ نتوانست جواب بدهد',
    'Scope replied': 'اسکوپ جواب داد',
    'Download engine ready': 'موتور دانلود آماده است',
    'Desktop notifications': 'اعلان روی دسکتاپ',
    "When a scrape, download or AI job finishes while you're in another app, a notice slides into the corner of your screen.":
        'وقتی استخراج، دانلود یا کار هوش مصنوعی تمام شود و شما در برنامه‌ی دیگری باشید، یک اعلان در گوشه‌ی صفحه ظاهر می‌شود.',
    'Notification sound': 'صدای اعلان',
    'Play your Windows notification sound with each notice.': 'همراه هر اعلان، صدای اعلان ویندوز پخش شود.',

    # ── added: v3.40.1 premium right-click edit menu ──
    'Cut': 'برش',
    # ── added: v3.41 live activity (progress card while away) ──
    'Live progress while away': 'نمایش زنده‌ی پیشرفت وقتی بیرون از برنامه‌اید',
    "A download or cut still running when you switch apps follows you as a live card in the corner. Close it and you'll still get a notice when it's done.": 'اگر وسط دانلود یا برش به برنامه‌ی دیگری بروید، یک کارت زنده گوشه‌ی صفحه همراهتان می‌آید. اگر ببندیدش، باز هم وقتی کار تمام شد خبرتان می‌کنیم.',
    'Working on it…': 'در حال انجام…',
    'How I built a channel in 30 days': 'چطور در ۳۰ روز یک کانال ساختم',
})


# ── the remaining untranslated error strings (cutter / download / Drive) ──
FA_STRINGS.update({
    "Your browser cookies couldn't be read either — close that browser, or set Download cookies to None in Settings.": "کوکی‌های مرورگر هم خوانده نشد — آن مرورگر را کامل ببند، یا در تنظیمات «کوکی دانلود» را روی None بگذار.",
    "The stream stalled (no data for a while). Check your connection and try again.": "استریم قطع شد (مدتی داده‌ای نرسید). اتصال را بررسی کن و دوباره امتحان کن.",
    "Couldn't get {want}p for this clip right now (highest visible: {top}p). YouTube sometimes limits high resolutions — wait a minute and cut again, or pick {top}p.": "الان {want}p برای این کلیپ به دست نیامد (بالاترین موجود: {top}p). یوتیوب بعضی وقت‌ها رزولوشن بالا را محدود می‌کند — یک دقیقه صبر کن و دوباره برش بزن، یا {top}p را انتخاب کن.",
    "YouTube blocked this download (bot check). Close your browser completely and try again — or set “Use cookies from browser” in Settings, or try a different VPN location.": "یوتیوب این دانلود را بلاک کرد (چک ربات). مرورگر را کامل ببند و دوباره امتحان کن — یا در تنظیمات «استفاده از کوکی مرورگر» را روشن کن، یا لوکیشن VPN را عوض کن.",
    "The browser's cookies couldn't be read. Close the browser completely (Chrome/Edge/Firefox) and try again, or set another browser in Settings.": "کوکی‌های مرورگر خوانده نشد. مرورگر را کامل ببند (کروم/اج/فایرفاکس) و دوباره امتحان کن، یا در تنظیمات مرورگر دیگری انتخاب کن.",
    "This video doesn't have {want}p. The highest it offers is {got} — pick that quality instead.": "این ویدیو {want}p ندارد. بالاترین کیفیتی که دارد {got} است — همان را انتخاب کن.",
    "That's a folder link — open the folder and share a single file instead, or connect your Google account to browse it.": "این لینک یک پوشه است — پوشه را باز کن و یک فایل تکی به اشتراک بگذار، یا حساب گوگلت را وصل کن تا داخلش را ببینی.",
    "Google didn't return a refresh token. Remove YouTube Hunter from your Google account's third-party access and try again.": "گوگل refresh token نداد. YouTube Hunter را از دسترسی‌های شخص ثالث حساب گوگلت حذف کن و دوباره امتحان کن.",
    "ai provider model proxy routing effort": "سرویس‌دهندهٔ هوش مصنوعی مدل پراکسی مسیریابی تلاش",
})

# ── added: v3.41 redesigned guided tour ──
FA_STRINGS.update({
    "A quick walk through the whole app, in the order you'll actually use it. Leave anytime with Esc, and replay it from the ? button.":
        'یک گشت سریع در کل برنامه، به همان ترتیبی که واقعاً با آن کار می‌کنی. هر وقت خواستی با Esc خارج شو و از دکمه‌ی ? دوباره ببینش.',
    'Start the tour': 'شروع گشت',
    'Not now': 'فعلاً نه',
    'Finish': 'تمام',
    'Skip tour': 'رد کردن راهنما',
    '{n} stops': '{n} ایستگاه',
    'about a minute': 'حدود یک دقیقه',
})

# ── added: v3.41.1 redesigned notifications tray ──
FA_STRINGS.update({
    'Earlier': 'قبلی‌تر',
    'Alerts': 'هشدارها',
    'Nothing new': 'خبر تازه‌ای نیست',
    'Notification settings': 'تنظیمات اعلان',
    '{n} new': '{n} مورد جدید',
    'No alerts. All clear.': 'هیچ هشداری نیست. همه چیز مرتب است.',
    'Finished scrapes, downloads and AI jobs will land here.': 'استخراج‌ها، دانلودها و کارهای هوش مصنوعی که تمام شوند، اینجا می‌آیند.',

    # ── added v3.41.4: PO Token helper ──
    'PO TOKEN HELPER': 'دستیار PO Token',
    'Optional': 'اختیاری',
    'Off': 'خاموش',
    'Active': 'فعال',
    'Proves to YouTube that requests come from a real browser. Helps on VPN or flagged networks where downloads hit 403 or only 360p shows. About 44 MB.': 'به یوتیوب ثابت می‌کند درخواست‌ها از یک مرورگر واقعی است. روی VPN یا شبکه‌های پرچم‌خورده که دانلود 403 می‌گیرد یا فقط 360p نشان داده می‌شود کمک می‌کند. حدود ۴۴ مگابایت.',
    'Not needed on most networks': 'روی بیشتر شبکه‌ها لازم نیست',
    'Install helper': 'نصب دستیار',
    'PO Token helper installed.': 'دستیار PO Token نصب شد.',
    "Couldn't install the PO Token helper: {e}": 'نصب دستیار PO Token ناموفق بود: {e}',
})

FA_STRINGS.update({
    # ── added v3.41.5: PO Token helper is required ──
    'YouTube downloads need two required components: a small JavaScript runtime and the PO Token helper. Install them now and your first download will just work.':
        'دانلود از یوتیوب به دو جزء ضروری نیاز دارد: یک موتور کوچک جاوااسکریپت و دستیار PO Token. همین حالا نصبشان کنید تا اولین دانلود بی‌دردسر انجام شود.',
    'PO Token helper for YouTube downloads (~44 MB)': 'دستیار PO Token برای دانلود یوتیوب (حدود ۴۴ مگابایت)',
    'Both are required. If you skip, downloads stay locked and this setup opens again the first time you download a video.':
        'هر دو ضروری‌اند. اگر رد کنید، دانلود قفل می‌ماند و اولین باری که ویدیویی دانلود کنید این پنجره دوباره باز می‌شود.',
    'File 2 of {t} · PO Token helper · {pct}%': 'فایل ۲ از {t} · دستیار PO Token · {pct}%',
    'Pick bgutil-pot.exe': 'انتخاب فایل bgutil-pot.exe',
    'PO Token helper': 'دستیار PO Token',
    'PO Token helper missing': 'دستیار PO Token نصب نیست',
    'Required, about 44 MB': 'ضروری، حدود ۴۴ مگابایت',
    'Required': 'ضروری',
    'Required to download from YouTube. About 44 MB, one-time.': 'برای دانلود از یوتیوب ضروری است. حدود ۴۴ مگابایت، یک‌بار.',
    "Proves to YouTube that requests come from a real browser, so downloads don't hit 403 or get stuck at 360p.":
        'به یوتیوب ثابت می‌کند درخواست‌ها از یک مرورگر واقعی است تا دانلود به خطای 403 نخورد یا روی 360p گیر نکند.',
    'The PO Token helper is required for YouTube downloads. Install it from the setup dialog or Settings → Download Engine.':
        'دستیار PO Token برای دانلود از یوتیوب ضروری است. از پنجرهٔ راه‌اندازی یا تنظیمات ← موتور دانلود نصبش کنید.',
    'JavaScript runtime installed. The PO Token helper is still required.': 'موتور جاوااسکریپت نصب شد. دستیار PO Token هنوز لازم است.',
})

FA_STRINGS.update({
    # ── added v3.41.5: live connection monitor ──
    "YouTube isn't answering": 'یوتیوب جواب نمی‌دهد',
    "Downloads can't run on this connection": 'با این اتصال دانلود انجام نمی‌شود',
    'The download would fail before the first byte.': 'دانلود قبل از رسیدن اولین بایت شکست می‌خورد.',
    'YouTube is reachable again. Start your download.': 'یوتیوب دوباره در دسترس است. دانلود را شروع کنید.',
    'Your internet works, but YouTube refuses requests from this IP ({c}). This VPN server is probably blocked by YouTube — switch to another server or location.':
        'اینترنت شما وصل است، اما یوتیوب درخواست‌های این IP ({c}) را رد می‌کند. احتمالاً این سرور VPN توسط یوتیوب بلاک شده؛ سرور یا کشور دیگری انتخاب کنید.',
    "Your internet works, but YouTube doesn't answer from this IP ({c}). It is filtered on this network or blocked by YouTube — switch your VPN on, or pick another server.":
        'اینترنت شما وصل است، اما یوتیوب از این IP ({c}) جواب نمی‌دهد. یا روی این شبکه فیلتر است یا یوتیوب آن را بلاک کرده؛ VPN را روشن کنید یا سرور دیگری انتخاب کنید.',
    'Switch VPN server or location': 'سرور یا کشور VPN را عوض کنید',
    'Pick a different country or server in your VPN app. Keep TUN / system-wide mode on.':
        'در برنامهٔ VPN کشور یا سرور دیگری انتخاب کنید. حالت TUN / سراسری را روشن نگه دارید.',
    "The app keeps checking in the background. Once you're through, this screen closes on its own.":
        'برنامه پشت صحنه مدام اتصال را چک می‌کند. وقتی وصل شدید، این صفحه خودش بسته می‌شود.',
    'Internet connection lost.': 'اتصال اینترنت قطع شد.',
    'YouTube stopped answering from this IP.': 'یوتیوب دیگر از این IP جواب نمی‌دهد.',
    'Your IP is now in {c}, where YouTube is filtered.': 'IP شما الان در {c} است که یوتیوب آنجا فیلتر است.',
    'Connection is back — YouTube is reachable again.': 'اتصال برگشت؛ یوتیوب دوباره در دسترس است.',
})

# ── v1.2: audio track (dub) picker — Video Cutter + download quality picker ──
FA_STRINGS.update({
    'Audio track': 'ترک صدا',
    '{n} languages': '{n} زبان',
    'AI dub': 'دوبلهٔ هوش مصنوعی',
    'Dub': 'دوبله',
    'Original voice of the video': 'صدای اصلی خود ویدیو',
    'Dubbed in {l}': 'دوبله به {l}',
    'Generated by YouTube with an AI voice': 'ساختهٔ یوتیوب با صدای هوش مصنوعی',
    'Show fewer': 'نمایش کمتر',
    'Show all {n} languages': 'نمایش همهٔ {n} زبان',
    'This video is dubbed. Pick the voice your clip should carry — the preview switches to it right away.':
        'این ویدیو دوبله دارد. صدایی را که کلیپ باید داشته باشد انتخاب کن؛ پیش‌نمایش همان لحظه عوض می‌شود.',
})

# ── Niche Scan (was Snapshot Insights): rename + small-channel / outlier /
#    format-split readings ──
FA_STRINGS.update({
    'Shorts {s} · long-form {l} · {n} of {t} rows': 'شورتس {s} · ویدیوی بلند {l} · {n} از {t} ردیف',
    'OUTPERFORMED THEIR CHANNEL': 'فراتر از کانالِ خودش',
    "{h} videos got 3×+ their channel's usual views · {n} of {t} rows": '{h} ویدیو بیش از ۳ برابرِ بازدیدِ معمولِ کانالش گرفته · {n} از {t} ردیف',
    'no public channel averages': 'میانگینِ عمومیِ کانال در دسترس نیست',
    'SMALL CHANNELS WINNING': 'برد کانال\u200cهای کوچک',
    'of {k} videos from channels under 10K subs beat the median · {n} of {t} sized': 'از {k} ویدیوی کانال\u200cهای زیر ۱۰ هزار عضو، از میانه جلو زده\u200cاند · {n} از {t} ردیف',
    'no public subscriber counts': 'تعداد عضو عمومی نیست',
    'Channel average (outlier baseline)': 'میانگین کانال (مبنای ویدیوی استثنایی)',
    '{k} videos from channels under 10K subscribers beat the median — small channels can win here.': '{k} ویدیو از کانال\u200cهای زیر ۱۰ هزار عضو از میانه جلو زده\u200cاند؛ اینجا کانال کوچک هم شانس دارد.',
    'No channel under 10K subscribers made this list.': 'هیچ کانالِ زیر ۱۰ هزار عضوی به این فهرست نرسیده.',
    'Shorts and long-form behave very differently here — read them separately.': 'شورتس و ویدیوی بلند اینجا رفتار کاملاً متفاوتی دارند؛ جدا بخوانیدشان.',
    '{p}% of the videos with a declared language are in “{l}”.': '{p}٪ از ویدیوهایی که زبانشان مشخص است به «{l}» هستند.',
    'Under 10K subs': 'زیر ۱۰ هزار عضو',
    '10K–100K subs': '۱۰ تا ۱۰۰ هزار عضو',
    '100K–1M subs': '۱۰۰ هزار تا ۱ میلیون عضو',
    'Over 1M subs': 'بالای ۱ میلیون عضو',
})

# ── v1.1.3: rail sign-off (made with ♥ + donate) ──
FA_STRINGS.update({
    'Made with': 'ساخته‌شده با',
    'Donate': 'حمایت',
    'Support YouTube Hunter': 'حمایت از یوتیوب هانتر',
})

# ── v1.1.3: Niche Scan brief, unreadable / cut-short replies ──
FA_STRINGS.update({
    'The AI answered, but not in a shape we can lay out': 'هوش مصنوعی جواب داد، ولی نه به شکلی که بشه چیدش',
    'Usually a one-off. Running it again almost always comes back clean.': 'معمولاً اتفاقیه. یه بار دیگه اجرا کنی تقریباً همیشه درست برمی‌گرده.',
    'Try again': 'دوباره امتحان کن',
    'Show raw reply': 'نمایش پاسخ خام',
    'Hide raw reply': 'پنهان کردن پاسخ خام',
    'Copy raw reply': 'کپی پاسخ خام',
    "The AI's reply was cut short. Everything that arrived is below; the last sections may be missing.": 'پاسخ هوش مصنوعی نیمه‌کاره رسید. هرچه رسیده پایین هست؛ ممکن است بخش‌های آخر نباشند.',
    'Run again': 'اجرای دوباره',
    'Brief ready, but the reply was cut short — some sections may be missing.': 'بریف آماده است، ولی پاسخ نیمه‌کاره رسید؛ ممکن است چند بخش نباشد.',
})

# ── v3.41.6: Niche Scan brief — "Dossier" redesign ──
FA_STRINGS.update({
    'Needs Studio': 'نیازمند استودیو',
    'AI BRIEF': 'بریف هوش مصنوعی',
    'EVERY LINE CARRIES ONE OF THREE LABELS': 'هر جمله یکی از این سه برچسب را دارد',
    'HOW SURE THE BRIEF IS': 'بریف چقدر مطمئن است',
    'tap a label to focus it': 'روی یک برچسب بزن تا فقط همان را ببینی',
    'tap it again to show all': 'دوباره بزن تا همه نمایش داده شوند',
    'What the brief stands on': 'بریف روی چه چیزی بنا شده',
    'every statement keeps its label': 'هر جمله برچسب خودش را نگه می‌دارد',
})


# v3.42: Send to AI Ideas fix + browser bridge
FA_STRINGS.update({
    "Added to AI Ideas — it's ticked as a reference there.": "به ایده‌های هوش مصنوعی اضافه شد — آنجا به‌عنوان ویدیوی مرجع تیک خورده است.",
    "Already picked on AI Ideas.": "قبلاً در ایده‌های هوش مصنوعی انتخاب شده است.",
    "AI Ideas isn't ready yet — try again in a moment.": "ایده‌های هوش مصنوعی هنوز آماده نیست — چند لحظه دیگر دوباره امتحان کن.",
    "Picked on AI Ideas": "در ایده‌های هوش مصنوعی انتخاب شده",
    "{n} reference video(s) picked — sent from {src}.": "{n} ویدیوی مرجع انتخاب شد — ارسال‌شده از {src}.",
    "another page": "صفحه‌ای دیگر",
    "Couldn't read this video's formats — showing the standard options.": "کیفیت‌های این ویدیو خوانده نشد — گزینه‌های استاندارد نمایش داده می‌شود.",
})

# ── v3.43: pause / resume on the live card + browser-extension setup ──
FA_STRINGS.update({
    'Paused': 'توقف موقت',
    'Pausing…': 'در حال توقف موقت…',
    'Download paused.': 'دانلود موقتاً متوقف شد.',
    'Press ▶ to continue': 'برای ادامه ▶ را بزن',
    'Pause': 'توقف موقت',
    'Resume': 'ادامه',
    'Add the download button to YouTube': 'دکمه‌ی دانلود را به یوتیوب اضافه کن',
    'One time, about 30 seconds. After that every YouTube video gets a Hunter button: pick a quality and it downloads here.':
        'فقط یک بار، حدود ۳۰ ثانیه. بعد از آن زیر هر ویدیوی یوتیوب دکمه‌ی هانتر هست: کیفیت را انتخاب کن و همین‌جا دانلود می‌شود.',
    'Open the extensions page': 'صفحه‌ی افزونه‌ها را باز کن',
    'Opens {b} on {u}': '{b} را روی {u} باز می‌کند',
    'Open {b} extensions': 'باز کردن افزونه‌های {b}',
    "Couldn't start the browser. Type {u} in its address bar.": 'مرورگر باز نشد. {u} را در نوار آدرس آن بنویس.',
    'Turn on “Developer mode”': '«Developer mode» را روشن کن',
    'The switch in the top-right corner of that page.': 'کلیدی که گوشه‌ی بالا سمت راست همان صفحه است.',
    'Drag this folder onto that page': 'این پوشه را بکش و روی آن صفحه رها کن',
    'Or click “Load unpacked” there and press Ctrl+V in the folder box: the path is already copied.':
        'یا آنجا «Load unpacked» را بزن و در کادر پوشه Ctrl+V بزن؛ مسیر از قبل کپی شده است.',
    'Path copied': 'مسیر کپی شد',
    'Copy path': 'کپی مسیر',
    'Open folder': 'باز کردن پوشه',
    'Connected. Open any YouTube video, the Hunter button is next to Share.':
        'وصل شد. هر ویدیوی یوتیوب را باز کن، دکمه‌ی هانتر کنار Share است.',
    'Waiting for the extension…': 'در انتظار افزونه…',
    'Skip for now': 'فعلاً رد کن',
    'Browser extension': 'افزونه‌ی مرورگر',
    'Connected. Every YouTube video has a Hunter download button.': 'وصل است. هر ویدیوی یوتیوب دکمه‌ی دانلود هانتر دارد.',
    'Adds a Hunter download button to every YouTube video. One-time setup, about 30 seconds.':
        'یک دکمه‌ی دانلود هانتر به هر ویدیوی یوتیوب اضافه می‌کند. نصب یک‌باره، حدود ۳۰ ثانیه.',
    'Reinstall': 'نصب دوباره',
    'Set up': 'راه‌اندازی',
})

# ── v3.43b: browser-extension section in Settings + live numbers in the archive ──
FA_STRINGS.update({
    'API quota used up · numbers from {ago}': 'سهمیه‌ی API تمام شد · اعداد مربوط به {ago}',
    'Adds a Hunter download button to every YouTube video and Short. One-time setup, about a minute.':
        'یک دکمه‌ی دانلود هانتر به همه‌ی ویدیوها و شورت‌های یوتیوب اضافه می‌کند. نصب یک‌باره، حدود یک دقیقه.',
    "Click “Load unpacked” (the first new button), go to the folder below and press “Select Folder”. Select the folder itself, don't open a file inside it. Quicker: drag the folder card below onto the extensions page.":
        'روی «Load unpacked» (اولین دکمه‌ی جدید) بزن، به پوشه‌ی زیر برو و «Select Folder» را بزن. خود پوشه را انتخاب کن، نه فایلی داخل آن. راه سریع‌تر: کارت پوشه‌ی زیر را بکش و روی صفحه‌ی افزونه‌ها رها کن.',
    'Copy folder path': 'کپی مسیر پوشه',
    "Couldn't update · numbers from {ago}": 'به‌روزرسانی نشد · اعداد مربوط به {ago}',
    'Download button on YouTube': 'دکمه‌ی دانلود روی یوتیوب',
    'Hide the steps': 'بستن مراحل',
    'In the left sidebar of that page, near the bottom.': 'در منوی کناری سمت چپ همان صفحه، نزدیک پایین.',
    'Installed. Every YouTube video and Short has a Hunter download button.': 'نصب است. همه‌ی ویدیوها و شورت‌های یوتیوب دکمه‌ی دانلود هانتر دارند.',
    'Live · updated {ago}': 'زنده · به‌روزشده {ago}',
    'Load the extension folder': 'پوشه‌ی افزونه را اضافه کن',
    'One time, about a minute. You can also do it later from Settings → Browser extension.':
        'فقط یک بار، حدود یک دقیقه. بعداً هم از تنظیمات ← افزونه‌ی مرورگر می‌توانی انجامش بدهی.',
    'Open Settings → YouTube API': 'باز کردن تنظیمات ← YouTube API',
    'Open {b}': 'باز کردن {b}',
    "Press F5 on any YouTube tab that was already open. The Hunter button sits next to Like and Share; on Shorts it's at the top of the right-hand buttons.":
        'در هر تب یوتیوبی که از قبل باز بود F5 بزن. دکمه‌ی هانتر کنار Like و Share است؛ در شورت‌ها بالای دکمه‌های سمت راست.',
    'Refresh YouTube': 'یوتیوب را رفرش کن',
    'Reinstall or update the extension': 'نصب دوباره یا به‌روزرسانی افزونه',
    'Saved numbers · add a YouTube API key for live ones': 'اعداد ذخیره‌شده · برای اعداد زنده کلید YouTube API اضافه کن',
    'Show folder': 'نمایش پوشه',
    "The browser-extension folder isn't next to the app. Reinstall YouTube Hunter to get it back.":
        'پوشه‌ی browser-extension کنار برنامه نیست. یوتیوب هانتر را دوباره نصب کن.',
    'The switch at the top of that page: right corner (left corner if your browser is in Persian). New buttons appear under it.':
        'کلید بالای همان صفحه: گوشه‌ی راست (اگر مرورگرت فارسی است، گوشه‌ی چپ). بعد از روشن کردن، چند دکمه‌ی جدید زیرش ظاهر می‌شود.',
    'Tip: in the “Select Folder” window, paste the copied path into the bar at the top and press Enter.':
        'نکته: در پنجره‌ی «Select Folder» مسیر کپی‌شده را در نوار بالا Paste کن و Enter بزن.',
    'Unavailable': 'در دسترس نیست',
    'Updating live numbers…': 'در حال به‌روزرسانی اعداد زنده…',
    'Updating live numbers… {d}/{t}': 'در حال به‌روزرسانی اعداد زنده… {d}/{t}',
    'Views, likes and subscribers are re-read from YouTube when you open a section and every 5 minutes. Click to update now.':
        'بازدید، لایک و مشترک‌ها هر بار که بخشی را باز می‌کنی و هر ۵ دقیقه دوباره از یوتیوب خوانده می‌شوند. برای به‌روزرسانی فوری کلیک کن.',
    'Waiting for the extension… this turns green by itself after step 3.': 'در انتظار افزونه… بعد از مرحله‌ی ۳ خودش سبز می‌شود.',
    'YouTube API quota is used up, so these are the last saved numbers.': 'سهمیه‌ی YouTube API تمام شده؛ این‌ها آخرین اعداد ذخیره‌شده هستند.',
    'archived · numbers live': 'آرشیو · اعداد زنده',
    'archived · updating live numbers…': 'آرشیو · در حال به‌روزرسانی اعداد…',
    'drag me': 'بکش',
    'extension browser chrome youtube button': 'افزونه مرورگر کروم یوتیوب دکمه',
    'list cached {ago} · numbers live': 'لیست از کش {ago} · اعداد زنده',
    'when it was saved': 'زمان ذخیره',
    "{b} doesn't let other apps open this page, so the address is copied for you. In the {b} window: click the address bar, press Ctrl+V, then Enter.":
        '{b} اجازه نمی‌دهد برنامه‌ی دیگری این صفحه را باز کند، برای همین آدرس برایت کپی می‌شود. در پنجره‌ی {b}: روی نوار آدرس کلیک کن، Ctrl+V بزن و بعد Enter.',
    "{b} wasn't found. Open your browser yourself and paste the address.": '{b} پیدا نشد. مرورگرت را خودت باز کن و آدرس را Paste کن.',
    '{n} unavailable': '{n} در دسترس نیست',
})

# ── v3.43c: Cut on YouTube (browser extension bridge) ──
FA_STRINGS.update({
    'Three cuts are already running — wait for one to finish.': 'سه برش همین الان در حال اجراست — صبر کن یکی تمام شود.',
    'Bad segment times.': 'زمان‌های بازه نامعتبر است.',
})

# ── v3.46 / v3.47: cut output formats + audio-only cuts ──
FA_STRINGS.update({
    'No picture, just the sound': 'بدون تصویر، فقط صدا',
    'Output format': 'فرمت خروجی',
    "Couldn't cut the audio.": 'برش صدا انجام نشد.',
    'No playable audio stream was found.': 'هیچ جریان صوتی قابل پخشی پیدا نشد.',
    'Audio only: the selected audio track will be cut and saved without video.': 'فقط صدا: ترک صوتی انتخاب‌شده بدون تصویر برش و ذخیره می‌شود.',
    'Video cut includes audio. Choose MP4, MKV, or WEBM above.': 'برش ویدیو صدا را هم دارد. بالا MP4، MKV یا WEBM را انتخاب کن.',
})

# ── v3.49: AI Chat — brief analyser, batch YouTube links, conversational Scope ──
FA_STRINGS.update({
    'Analyse a brief': 'تحلیل بریف',
    'Add YouTube links': 'افزودن لینک‌های یوتیوب',
    'YouTube links': 'لینک‌های یوتیوب',
    'One video or a whole batch': 'یک ویدیو یا یک دسته‌ی کامل',
    'Paste one link, or many (one per line, or separated by spaces / commas)': 'یک لینک یا چند لینک بچسبان (هر خط یکی، یا با فاصله / کاما جدا)',
    '{n} video(s) found': '{n} ویدیو پیدا شد',
    'No YouTube link found yet': 'هنوز لینک یوتیوبی پیدا نشد',
    'Up to 50 at once. With a YouTube API key the exact stats and subscriber counts are fetched for the whole batch in one go (2 quota units total).': 'هر بار تا ۵۰ لینک. با کلید YouTube API، آمار دقیق و تعداد سابسکرایبر کل دسته یک‌جا گرفته می‌شود (در مجموع ۲ واحد سهمیه).',
    'Add {n} videos': 'افزودن {n} ویدیو',
    'Paste one or more YouTube video links.': 'یک یا چند لینک ویدیوی یوتیوب بچسبان.',
    'Only the first {n} links are added.': 'فقط {n} لینک اول اضافه می‌شود.',
    'Those videos are already in this conversation.': 'این ویدیوها از قبل در این گفتگو هستند.',
    'Fetching {n} video(s)…': 'در حال دریافت {n} ویدیو…',
    "{n} video(s) added · {f} couldn't be read (private or removed?).": '{n} ویدیو اضافه شد · {f} مورد خوانده نشد (خصوصی یا حذف‌شده؟).',
    '{n} video(s) added to the conversation.': '{n} ویدیو به گفتگو اضافه شد.',
    "Couldn't read those videos. Are they public?": 'این ویدیوها خوانده نشدند. عمومی هستند؟',
    'Saved Niche Scan briefs': 'بریف‌های ذخیره‌شده‌ی موضوع‌سنج',
    'No saved briefs yet. Run a Niche Scan and its brief shows up here, or paste one below.': 'هنوز بریفی ذخیره نشده. یک موضوع‌سنجی اجرا کن تا بریفش اینجا بیاید، یا پایین یکی بچسبان.',
    "Or paste a brief (a client's, a sponsor's, or your own plan)": 'یا یک بریف بچسبان (از مشتری، اسپانسر، یا برنامه‌ی خودت)',
    'Brief name (optional)': 'نام بریف (اختیاری)',
    'Goal, audience, the idea, deliverables, deadline… paste it as it is.': 'هدف، مخاطب، ایده، خروجی‌ها، ددلاین… همان‌طور که هست بچسبان.',
    'Scope checks every claim against the numbers it came from.': 'اسکوپ هر ادعا را با عددهایی که از آن آمده می‌سنجد.',
    'Add {n} briefs': 'افزودن {n} بریف',
    'Add brief': 'افزودن بریف',
    "Analyse this brief: what's strong, what's missing, and what should I make from it?": 'این بریف رو تحلیل کن: چی‌اش قویه، چی کم داره، و ازش چی بسازم؟',
    "Analyse these briefs: what's strong, what's missing, and what should I make from them?": 'این بریف‌ها رو تحلیل کن: چی‌شون قویه، چی کم دارن، و ازشون چی بسازم؟',
    "A Niche Scan brief or a client's brief: what's strong, what's missing.": 'بریف موضوع‌سنج یا بریف مشتری: نقاط قوت و کمبودها.',
    '{n} brief(s) added. Ask Scope to analyse them.': '{n} بریف اضافه شد. از اسکوپ بخواه تحلیلشان کند.',
    'Brief added. Ask Scope to analyse it.': 'بریف اضافه شد. از اسکوپ بخواه تحلیلش کند.',
    "Couldn't save the brief: {e}": 'بریف ذخیره نشد: {e}',
    'Reading the brief…': 'در حال خواندن بریف…',
    'Brief ready': 'بریف آماده است',
    'Brief': 'بریف',
    'Untitled brief': 'بریف بدون عنوان',
    'My brief': 'بریف من',
    'Written brief': 'بریف نوشته‌شده',
    'Research brief': 'بریف تحقیقی',
    'Numbers only': 'فقط اعداد',
    'Mark as connected': 'علامت‌گذاری به‌عنوان متصل',
    'Already installed and it still says waiting? Open or refresh any YouTube tab once; that wakes the extension up.': 'نصب کردی و هنوز «در انتظار» است؟ یک بار هر تب یوتیوب را باز یا رفرش کن؛ همین افزونه را بیدار می‌کند.',
})
