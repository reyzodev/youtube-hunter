"""app.core.monetization - Youtube Scrapper."""

import json
import re
import urllib.parse
import urllib.request

from app.core.net import _urlopen, configured_proxy

# ═════════════════════════════════════════════════════════════════════════
#  MONETIZATION SIGNAL DETECTION
#  ---------------------------------------------------------------------
#  The official YouTube Data API never exposes real monetization status,
#  so these signals (channel memberships, merch shelf, Super Thanks, and
#  creator-configured mid-roll ad breaks) are read directly off YouTube's
#  public web pages, the same way a logged-out visitor's browser would.
#  This is inherently best-effort: YouTube can change its page markup at
#  any time, so every result also carries a "confidence" label instead of
#  a flat yes/no.
# ═════════════════════════════════════════════════════════════════════════
_YT_UA_HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"),
    "Accept-Language": "en-US,en;q=0.9",
    # Without a consent cookie a chunk of the world gets served the EU consent
    # interstitial instead of the page, and every single signal below then
    # reads as "absent" — which is exactly how a checker ends up calling every
    # channel on earth "uncertain". These two cookies are what a browser has
    # after the visitor clicks through that screen once.
    "Cookie": "CONSENT=YES+cb; SOCS=CAI",
}


def fetch_youtube_html(url, timeout=12):
    """Best-effort fetch of a YouTube page's raw HTML. Returns str or None."""
    # &hl=en&gl=US pins the response to the English/US layout. The markers
    # below are literal strings from YouTube's own JSON ("Join", "Store"), and
    # those are localised — checking an Iranian or German visitor's copy of the
    # page for the English words silently found nothing.
    if "hl=" not in url:
        url += ("&" if "?" in url else "?") + "hl=en&gl=US"
    try:
        req = urllib.request.Request(url, headers=_YT_UA_HEADERS)
        # Through the configured proxy, like every other outbound request. Users
        # who reach YouTube only via a VPN/proxy were getting None from here and
        # therefore "uncertain" for every channel, while the API-backed pages on
        # the same screen worked — because those went through _urlopen and this
        # did not.
        with _urlopen(req, timeout, configured_proxy()) as resp:
            raw = resp.read()
        return raw.decode("utf-8", errors="ignore")
    except Exception:
        return None


def extract_balanced_json(text, marker):
    """Pull a `marker = { ... };` (or `marker": { ... }`) JSON blob out of raw
    HTML/JS by counting braces (regex alone breaks on braces inside strings).
    Returns a parsed dict, or None."""
    if not text:
        return None
    idx = text.find(marker)
    if idx == -1:
        return None
    brace_start = text.find("{", idx)
    if brace_start == -1:
        return None
    depth = 0
    in_str = False
    esc = False
    quote = ""
    i = brace_start
    n = len(text)
    while i < n:
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                in_str = False
        else:
            if ch in ("'", '"'):
                in_str = True
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[brace_start:i + 1])
                    except Exception:
                        return None
        i += 1
    return None


def _collect_ad_offsets(obj, found):
    """Recursively walk playerAds/adPlacements looking for offsetMs values."""
    if isinstance(obj, dict):
        if "offsetMs" in obj:
            try:
                found.add(int(obj["offsetMs"]))
            except Exception:
                pass
        for v in obj.values():
            _collect_ad_offsets(v, found)
    elif isinstance(obj, list):
        for v in obj:
            _collect_ad_offsets(v, found)


def check_channel_page_signals(channel_id):
    """Scrape the channel homepage for the two hard, YPP-only signals.

    WHAT CHANGED AND WHY. This used to look for "membershipOfferRenderer" and
    '"tabTitle":"Store"'. Neither string exists in YouTube's current channel
    markup, so both checks were dead code that always answered "no" — which
    is the real reason every channel came back Uncertain: the two strongest
    signals in the whole flow could never fire. What the page carries now is
    the channel's tab strip, and two of those tabs cannot exist unless the
    channel is in the Partner Program:

        "Join"   →  Channel Memberships are switched on
        "Store"  →  the merch / shopping shelf is switched on

    Both are checked against the tab titles specifically (rather than the raw
    page, where the words appear in unrelated places) so a video *titled*
    "Join my store" can't fool it.
    """
    html = fetch_youtube_html(f"https://www.youtube.com/channel/{channel_id}")
    if not html:
        return {"membership": False, "merch": False, "html_ok": False}
    tabs = set(re.findall(r'"title":"(Join|Store|Shop|Membership|Memberships)"', html))
    return {
        "membership": bool({"Join", "Membership", "Memberships"} & tabs)
                      or "membershipOfferRenderer" in html
                      or "sponsorButtonRenderer" in html,
        "merch": bool({"Store", "Shop"} & tabs)
                 or "merchShelfRenderer" in html,
        "html_ok": True,
    }


def check_video_monetization_signal(video_id, is_short):
    """Scrape one video's (or Short's) player response for ad + fan-funding
    signals.

    Three things are read, strongest first:

      ads          `adPlacements` / `playerAds` only appear in the player
                   response when YouTube is prepared to serve an ad against
                   that video, which it will not do on a video that isn't
                   monetised. Present = money; absent proves nothing, because
                   the logged-out player also skips ads for its own reasons
                   (this asymmetry is why it is scored as evidence FOR and
                   never as evidence AGAINST).
      super_thanks the fan-funding button, a Partner-Program-only feature.
      midroll      two or more creator-placed ad breaks — long-form only,
                   Shorts have no mid-rolls to place.
    """
    url = (f"https://www.youtube.com/shorts/{video_id}" if is_short
           else f"https://www.youtube.com/watch?v={video_id}")
    html = fetch_youtube_html(url)
    if not html:
        return {"super_thanks": False, "midroll": False, "ads": False, "ok": False}

    player = (extract_balanced_json(html, "var ytInitialPlayerResponse")
              or extract_balanced_json(html, "ytInitialPlayerResponse"))

    if player is not None:
        blob = json.dumps(player)
        super_thanks = ("creatorSupportButtonRenderer" in blob
                        or "superThanks" in blob.lower())
        ads = ("adPlacements" in player or "playerAds" in player
               or "adSlotRenderer" in blob)
        midroll = False
        if not is_short:
            offsets = set()
            for key in ("playerAds", "adPlacements"):
                if key in player:
                    _collect_ad_offsets(player[key], offsets)
            # "Multiple custom timestamps" = 2+ distinct configured breaks
            midroll = len([o for o in offsets if o > 0]) >= 2
        return {"super_thanks": super_thanks, "midroll": midroll,
                "ads": ads, "ok": True}

    # Fallback: JSON extraction failed (page layout changed) — do a raw
    # substring search so the check degrades gracefully instead of failing.
    return {
        "super_thanks": ("creatorSupportButtonRenderer" in html
                         or "superThanksConfig" in html),
        "midroll": False,
        "ads": ('"adPlacements"' in html or '"playerAds"' in html),
        "ok": True,
    }
