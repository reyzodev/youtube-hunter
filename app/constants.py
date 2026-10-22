"""app.constants - Youtube Scrapper."""


# ═════════════════════════════════════════════════════════════════════════
#  APP VERSION
# ═════════════════════════════════════════════════════════════════════════
# Single source of truth: the sidebar footer shows it and the build stamps it
# onto the .exe. installer.iss carries its own copy (Inno Setup cannot read a
# Python constant) — keep the two in step when bumping.
APP_VERSION = "1.0.0"


# ═════════════════════════════════════════════════════════════════════════
#  IN-APP UPDATES (GitHub Releases)
# ═════════════════════════════════════════════════════════════════════════
# The app asks GitHub for the latest release of this repo. A release whose tag
# (e.g. v1.2.0) is newer than APP_VERSION and that carries the installer .exe
# shows the update button in the title bar. Set "auto_update": false in
# config.json to turn the check off.
UPDATE_REPO = "reyzodev/youtube-hunter"
UPDATE_ASSET_HINT = "YouTubeHunter-Setup"
UPDATE_CHECK_HOURS = 6


# ═════════════════════════════════════════════════════════════════════════
#  SUPPORT / DONATION PAGE
# ═════════════════════════════════════════════════════════════════════════
# The Donate pill in the sidebar opens this address inside the app (the
# Support window hosts a live web view).
#
# Set since v1.2: the pill shows again and the Support window loads this page.
# Blanking it hides the pill and keeps QtWebEngine from ever being initialised
# (~260 MB of resident memory the app does not spend unless there is a page).
#
# A per-install override still wins:
#   "donate_url": "https://your-page.example"
# in %APPDATA%\YoutubeScrapperCyber\config.json — no rebuild needed.
# Only http(s) is accepted; anything else is ignored.
DONATE_URL = "https://donofa.com/youtube_hunter"


# ═════════════════════════════════════════════════════════════════════════
#  GEMINI (Google AI) — used by the AI-powered analysis features
#  (Monetization insight, Idea Finder outlier analysis, Idea Analysis view)
# ═════════════════════════════════════════════════════════════════════════
# NOTE: no API keys are shipped inside the source code (security). Keys are
# entered once in Settings and persisted in the user's config file.
GEMINI_API_KEY_DEFAULT = ""
GEMINI_MODEL_DEFAULT = "gemini-2.5-flash"
GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


FORMAT_EXT = {"csv": "csv", "json": "jsonl", "xlsx": "xlsx", "sqlite": "db"}
FORMAT_KEYS = ["csv", "json", "xlsx", "sqlite"]
# 3 = "oldest" is NOT a YouTube search order — the Data API has no ascending
# date sort. It is served by walking the channel's uploads playlist to the end
# and reversing it (see DashboardVM._get_oldest_video_ids), which is why it only
# applies to a channel scrape.
SORT_MAP = {0: "date", 1: "viewCount", 2: "relevance", 3: "oldest"}
SORT_SUFFIX = {"date": "newest", "viewCount": "popular",
               "relevance": "relevant", "oldest": "oldest"}

# Google Drive for AI Chat (optional). A "Desktop app" OAuth client from Google
# Cloud Console can be shipped here for a build; users can also paste their own
# in the chat's Google Drive dialog. Empty = share-link import only.
GDRIVE_CLIENT_ID = ""
GDRIVE_CLIENT_SECRET = ""
