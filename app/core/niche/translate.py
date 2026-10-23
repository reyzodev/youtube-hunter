"""app.core.niche.translate - YouTube Hunter.

Keyword translation for the Niche Finder's Country picker.

The app is English, so people type English keywords. "king" + France found
almost nothing, and that is correct behaviour: French YouTube titles say
"roi", and the Country filter (audience.market_fit) only keeps French titles.
So when a non-English market is picked, the keyword is translated into that
market's main language before it is sent to YouTube.

Rules (kept deliberately simple so nobody has to think about them):
  * Only for markets where English is not a main language (France, Germany,
    Turkey, Iran ... yes; US, UK, India, Canada, Philippines ... no).
  * A keyword already typed in the market's language comes back unchanged
    (the translator detects the source language).
  * Each comma-separated keyword is translated on its own.
  * Backends, in order: Google Translate's public endpoint (no key, ~100 ms),
    then the AI provider configured in Settings, then give up and search the
    keyword as typed. A failed translation never fails the search.
  * Results are memoised for the session: the same keyword + market costs
    one request, ever.
"""

import json
import re
import threading
import urllib.parse
import urllib.request

from app.core.niche import audience as _aud

# audience language code -> the code Google Translate wants
_GT_CODES = {"zh-hans": "zh-CN", "zh-hant": "zh-TW", "he": "iw", "tl": "tl",
             "no": "no", "ku": "ku"}

_MEMO = {}
_MEMO_LOCK = threading.Lock()
_MEMO_MAX = 500


def target_language(region):
    """The language a keyword should be translated into for `region`, or ''
    when no translation is wanted (no region, or English is spoken there)."""
    langs = _aud.country_languages(region)
    if not langs or "en" in langs:
        return ""
    return langs[0]


def _google(text, target, proxy, timeout=6):
    from app.core.net import _urlopen
    url = ("https://translate.googleapis.com/translate_a/single?client=gtx"
           "&sl=auto&tl=" + urllib.parse.quote(_GT_CODES.get(target, target))
           + "&dt=t&q=" + urllib.parse.quote(text))
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with _urlopen(req, timeout, proxy=proxy or None) as resp:
        data = json.loads(resp.read().decode("utf-8", "replace"))
    out = "".join((seg[0] or "") for seg in (data[0] or []) if seg)
    src = data[2] if len(data) > 2 and isinstance(data[2], str) else ""
    return out.strip(), _aud.norm_lang(src)


def _ai(text, target):
    from app.core.ai import profiles
    client = profiles.make_client()
    if not getattr(client, "api_key", ""):
        return ""
    lang = _aud.language_name(target) or target
    prompt = ("Translate this YouTube search keyword into %s, exactly as a "
              "native %s-speaking viewer would type it into YouTube search. "
              "Keep brand names, game titles and people's names as they are. "
              "If it is already %s, return it unchanged. Reply with the "
              "keyword only, no quotes, no explanation.\n\nKeyword: %s"
              % (lang, lang, lang, text))
    out = client.generate(prompt, timeout=20, max_output_tokens=60) or ""
    out = out.strip().splitlines()[0] if out.strip() else ""
    return out.strip().strip('"“”«»\'').strip()


def _clean(s, original):
    s = re.sub(r"\s+", " ", s or "").strip()
    # a translator that answers with a sentence is not a keyword
    if not s or len(s) > max(60, len(original) * 4):
        return ""
    return s


def translate_keyword(text, target, proxy=""):
    """(translated, backend) — backend is 'google' | 'ai' | 'same' | ''.
    'same' = already in the target language; '' = could not translate (the
    original is returned). Never raises."""
    text = (text or "").strip()
    if not text or not target:
        return text, ""
    key = (text.casefold(), target)
    with _MEMO_LOCK:
        if key in _MEMO:
            return _MEMO[key]
    result = (text, "")
    try:
        out, src = _google(text, target, proxy)
        out = _clean(out, text)
        if src and _aud._family(src) == _aud._family(target):
            result = (text, "same")
        elif out:
            result = (out, "same" if out.casefold() == text.casefold() else "google")
    except Exception:
        try:
            out = _clean(_ai(text, target), text)
            if out:
                result = (out, "same" if out.casefold() == text.casefold() else "ai")
        except Exception:
            pass
    if result[1]:                     # only remember answers, not failures
        with _MEMO_LOCK:
            if len(_MEMO) >= _MEMO_MAX:
                _MEMO.clear()
            _MEMO[key] = result
    return result


def translate_queries(queries, region, proxy=""):
    """Translate every keyword for `region`. Returns (new_queries, pairs) where
    pairs is [(original, translated)] for the ones that actually changed."""
    target = target_language(region)
    if not target:
        return list(queries), []
    out, pairs = [], []
    for q in queries:
        t, how = translate_keyword(q, target, proxy)
        out.append(t)
        if how in ("google", "ai") and t != q:
            pairs.append((q, t))
    # two keywords can translate to the same thing
    return list(dict.fromkeys(out)), pairs
