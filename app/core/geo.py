"""app.core.geo - YouTube Hunter.

"Where does YouTube think this machine is?" — the public IP and its country,
looked up over the SAME network route each part of the app really uses.

Why this exists
---------------
YouTube and Google's APIs are filtered in Iran (and a few other countries).
From an Iranian IP every scrape, Niche search, download and transcript fails —
but it fails late and vaguely (a 403, a timeout, an empty result), so a new
user blames the app. Checking the country once, up front, turns that into one
clear sentence: "your IP is in Iran, turn the VPN on".

Two routes, because the app has two network stacks
---------------------------------------------------
  * "api"  — the YouTube Data API (Scraper, Niche Finder). googleapiclient talks
             through httplib2, which only honours the HTTP(S)_PROXY environment
             variables. It ignores the Windows system proxy AND the proxy typed
             into Settings. So a v2ray client in "system proxy" mode fixes the
             browser but NOT the scraper — only TUN / system-wide mode does.
  * "web"  — downloads, transcripts, AI calls, oEmbed. These go through the
             proxy set in Settings when there is one, otherwise urllib's
             normal OS-detected proxy (registry on Windows).

When both routes resolve to the same proxy settings, one lookup serves both.

v3.41.5: YouTube itself is probed too
-------------------------------------
A country list can't catch everything: an IP YouTube has blocked (a burnt
VPN exit, a datacenter range) or a filtered network outside the list looks
"fine" by country. So every check also asks YouTube directly, over the same
route, for its `generate_204` endpoints. Only a real HTTP 204 counts as
"reachable": a filter page, a DNS hijack (TLS fails), a redirect or a timeout
does not. A real 403 / 429 from YouTube means "YouTube refuses this IP".

Never raises. A lookup that cannot reach any geo service returns ok=False and
callers treat that as "unknown" — the app must never block a user because a
geo service was down.
"""

import json
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

# Countries where YouTube itself is blocked at the network level, so nothing
# the app does can work from an IP there. Iran is the case this was built
# for; the others share the exact same failure. Edit here to change the list.
RESTRICTED_COUNTRIES = {
    "IR": "Iran",
    "CN": "China",
    "KP": "North Korea",
    "TM": "Turkmenistan",
}

# Display names for the codes users actually see (their own country and the
# usual VPN exits). Anything else falls back to the name the geo service
# returned, then to the bare code.
_EN_NAMES = {
    "IR": "Iran", "CN": "China", "KP": "North Korea", "TM": "Turkmenistan",
    "DE": "Germany", "NL": "Netherlands", "US": "United States",
    "GB": "United Kingdom", "FR": "France", "TR": "Türkiye", "AE": "UAE",
    "FI": "Finland", "SE": "Sweden", "CA": "Canada", "RU": "Russia",
    "AM": "Armenia", "GE": "Georgia", "AZ": "Azerbaijan", "IQ": "Iraq",
    "QA": "Qatar", "OM": "Oman", "IN": "India", "JP": "Japan",
    "SG": "Singapore", "HK": "Hong Kong SAR", "CH": "Switzerland",
    "AT": "Austria", "IT": "Italy", "ES": "Spain", "PL": "Poland",
    "RO": "Romania", "LT": "Lithuania", "LV": "Latvia", "EE": "Estonia",
    "UA": "Ukraine", "KZ": "Kazakhstan", "AU": "Australia",
    "BG": "Bulgaria", "CZ": "Czechia", "NO": "Norway", "DK": "Denmark",
    "BE": "Belgium", "LU": "Luxembourg", "IE": "Ireland", "PT": "Portugal",
    "GR": "Greece", "CY": "Cyprus", "SA": "Saudi Arabia", "BH": "Bahrain",
    "KW": "Kuwait", "PK": "Pakistan", "AF": "Afghanistan",
    "KR": "South Korea", "TW": "Taiwan, China", "MY": "Malaysia",
    "TH": "Thailand", "VN": "Vietnam", "BR": "Brazil", "MX": "Mexico",
    "AR": "Argentina", "HU": "Hungary", "RS": "Serbia", "MD": "Moldova",
    "IL": "Israel",
}

_TIMEOUT = 4.0          # per endpoint
_DEADLINE = 7.0         # whole lookup, all endpoints raced in parallel
_IP_RE = re.compile(r"^[0-9a-fA-F:.]{3,45}$")


def country_label(code, name="", lang="en"):
    """A display name for an ISO code. `lang` is kept for call-site
    compatibility; the interface is English only."""
    code = (code or "").upper()
    return _EN_NAMES.get(code) or (name or "").strip() or code


def is_restricted(code):
    return (code or "").upper() in RESTRICTED_COUNTRIES


# ── one parser per geo service ─────────────────────────────────────────────
def _p_cloudflare(body):
    kv = {}
    for line in body.splitlines():
        k, _sep, v = line.partition("=")
        if _sep:
            kv[k.strip()] = v.strip()
    loc = kv.get("loc", "")
    if loc in ("", "XX", "T1"):         # XX = unknown, T1 = Tor
        return None
    return kv.get("ip", ""), loc, ""


def _p_ipwho(body):
    j = json.loads(body)
    if j.get("success") is False:
        return None
    return j.get("ip", ""), j.get("country_code", ""), j.get("country", "")


def _p_country_is(body):
    j = json.loads(body)
    return j.get("ip", ""), j.get("country", ""), ""


def _p_geojs(body):
    j = json.loads(body)
    return j.get("ip", ""), j.get("country", ""), j.get("name", "")


def _p_ip_api(body):
    j = json.loads(body)
    if j.get("status") != "success":
        return None
    return j.get("query", ""), j.get("countryCode", ""), j.get("country", "")


# Raced in parallel; the first one that answers wins. Cloudflare first in the
# list because it is the fastest and the least likely to be filtered itself.
_ENDPOINTS = (
    ("https://www.cloudflare.com/cdn-cgi/trace", _p_cloudflare, "cloudflare"),
    ("https://1.1.1.1/cdn-cgi/trace", _p_cloudflare, "cloudflare"),
    ("https://ipwho.is/", _p_ipwho, "ipwho.is"),
    ("https://api.country.is/", _p_country_is, "country.is"),
    ("https://get.geojs.io/v1/ip/country.json", _p_geojs, "geojs"),
    ("http://ip-api.com/json/?fields=status,country,countryCode,query", _p_ip_api, "ip-api"),
)


# ── routes ────────────────────────────────────────────────────────────────
def _configured_proxy():
    try:
        from app.core.net import configured_proxy
        return configured_proxy()
    except Exception:
        return ""


def route_proxies(route):
    """The proxy map a route really uses (see the module docstring)."""
    if route == "api":
        try:
            return dict(urllib.request.getproxies_environment())
        except Exception:
            return {}
    proxy = _configured_proxy()
    if proxy:
        return {"http": proxy, "https": proxy}
    try:
        return dict(urllib.request.getproxies())
    except Exception:
        return {}


def _same_route():
    a, w = route_proxies("api"), route_proxies("web")
    return (a.get("https") or a.get("http") or "") == (w.get("https") or w.get("http") or "")


def _fetch(url, parser, proxies):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler(proxies))
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) YouTubeHunter",
        "Accept": "application/json, text/plain, */*"})
    with opener.open(req, timeout=_TIMEOUT) as resp:
        body = resp.read(65536).decode("utf-8", "replace")
    got = parser(body)
    if not got:
        return None
    ip, code, name = got
    code = (code or "").strip().upper()
    if len(code) != 2 or not code.isalpha():
        return None
    ip = (ip or "").strip()
    if ip and not _IP_RE.match(ip):
        ip = ""
    return ip, code, (name or "").strip()


def lookup(route="web"):
    """{"ok", "ip", "code", "name", "restricted", "source"} for one route."""
    proxies = route_proxies(route)
    out = {"ok": False, "ip": "", "code": "", "name": "", "restricted": False,
           "source": "", "proxied": bool(proxies.get("https") or proxies.get("http"))}
    pool = ThreadPoolExecutor(max_workers=len(_ENDPOINTS), thread_name_prefix="geo")
    try:
        futs = {pool.submit(_fetch, u, p, proxies): src for u, p, src in _ENDPOINTS}
        try:
            for fut in as_completed(futs, timeout=_DEADLINE):
                try:
                    got = fut.result()
                except Exception:
                    continue
                if got:
                    ip, code, name = got
                    out.update(ok=True, ip=ip, code=code, name=name,
                               restricted=is_restricted(code), source=futs[fut])
                    break
        except Exception:       # the deadline passed — "unknown", never blocking
            pass
    finally:
        pool.shutdown(wait=False, cancel_futures=True)
    return out


# ── YouTube reachability (v3.41.5) ─────────────────────────────────────────
# Tiny, cache-free endpoints that answer an EMPTY 204 when YouTube really
# answered. Raced in parallel; one real 204 is enough.
_YT_ENDPOINTS = (
    "https://www.youtube.com/generate_204",
    "https://i.ytimg.com/generate_204",
    "https://youtubei.googleapis.com/generate_204",
    "https://m.youtube.com/generate_204",
)
_YT_TIMEOUT = 5.0
_YT_DEADLINE = 7.0


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """A filter usually answers with a redirect to its block page: never
    follow it, a redirect is NOT YouTube answering."""
    def redirect_request(self, *a, **k):
        return None


def _yt_fetch(url, proxies):
    """("ok", ms) | ("refused", code) | ("fail", reason)."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler(proxies),
                                         _NoRedirect())
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36",
        "Cache-Control": "no-cache"})
    t0 = time.monotonic()
    try:
        with opener.open(req, timeout=_YT_TIMEOUT) as resp:
            code = resp.status
            body = resp.read(512)
    except urllib.error.HTTPError as e:
        # A real HTTPS answer from YouTube that says no (bot / IP block).
        if e.code in (403, 429):
            return "refused", e.code
        return "fail", "http %s" % e.code
    except Exception as e:     # noqa: BLE001 — DNS, TLS, timeout, reset
        return "fail", type(e).__name__
    if code == 204 and not body:
        return "ok", int((time.monotonic() - t0) * 1000)
    return "fail", "http %s" % code


def probe_youtube(route="web"):
    """{"reachable", "refused", "ms", "detail"} — does YouTube answer here?"""
    proxies = route_proxies(route)
    out = {"reachable": False, "refused": False, "ms": 0, "detail": ""}
    pool = ThreadPoolExecutor(max_workers=len(_YT_ENDPOINTS), thread_name_prefix="ytping")
    fails = []
    try:
        futs = [pool.submit(_yt_fetch, u, proxies) for u in _YT_ENDPOINTS]
        try:
            for fut in as_completed(futs, timeout=_YT_DEADLINE):
                try:
                    kind, val = fut.result()
                except Exception:      # noqa: BLE001
                    continue
                if kind == "ok":
                    out.update(reachable=True, refused=False, ms=val, detail="")
                    break
                if kind == "refused":
                    out["refused"] = True
                fails.append(str(val))
        except Exception:      # deadline
            fails.append("timeout")
    finally:
        pool.shutdown(wait=False, cancel_futures=True)
    if not out["reachable"]:
        out["detail"] = ", ".join(fails[:4])
    return out


def _check_one(route):
    with ThreadPoolExecutor(max_workers=2) as ex:
        fg, fy = ex.submit(lookup, route), ex.submit(probe_youtube, route)
        r = fg.result()
        try:
            yt = fy.result()
        except Exception:      # noqa: BLE001
            yt = {"reachable": False, "refused": False, "ms": 0, "detail": "error"}
    r = dict(r)
    r["yt"] = yt
    r["yt_ok"] = bool(yt.get("reachable"))
    # YouTube answering proves the internet works even if every geo service
    # was filtered or slow.
    r["online"] = bool(r.get("ok")) or r["yt_ok"]
    return r


def check_routes():
    """Both routes. {"api": {...}, "web": {...}, "same_route": bool, "at": t}

    Each route dict also carries "yt" (probe_youtube), "yt_ok" and "online"."""
    same = _same_route()
    if same:
        r = _check_one("web")
        api, web = dict(r), dict(r)
    else:
        with ThreadPoolExecutor(max_workers=2) as ex:
            fa, fw = ex.submit(_check_one, "api"), ex.submit(_check_one, "web")
            api, web = fa.result(), fw.result()
    return {"api": api, "web": web, "same_route": same, "at": time.time()}
