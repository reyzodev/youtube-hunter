"""app.core.gdrive - YouTube Hunter.

Google Drive for AI Chat, two ways in:

1. Paste a share link (no sign-in). Works for any file shared as "Anyone with
   the link": Drive files, Google Sheets (exported as CSV), Docs (as text) and
   Slides (as text). This is the zero-setup path and is always available.

2. Connect a Google account (OAuth, read-only) and browse "My Drive" from inside
   the app — private files included. Uses the standard installed-app loopback
   flow with PKCE: the browser opens Google's consent screen, Google redirects
   to a one-shot server on 127.0.0.1, and the refresh token is kept in the
   app config. It needs an OAuth client of type "Desktop app" from Google
   Cloud Console (APIs & Services → Credentials), with the Drive API enabled.
   Put the id/secret in the Drive dialog's Setup section once (or ship them in
   app/constants.py as GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET for a build).

Everything here is blocking and meant for worker threads.
"""

import base64
import hashlib
import http.server
import json
import os
import re
import secrets
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from app.config import load_app_config, save_app_config
from app.core.net import _urlopen, configured_proxy
from app.i18n import tr

SCOPE = "https://www.googleapis.com/auth/drive.readonly"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/drive/v3"

# Google-native types → what we export them as.
_EXPORTS = {
    "application/vnd.google-apps.spreadsheet": ("text/csv", ".csv"),
    "application/vnd.google-apps.document": ("text/plain", ".txt"),
    "application/vnd.google-apps.presentation": ("text/plain", ".txt"),
}
_EXT_FOR_MIME = {
    "text/csv": ".csv", "text/plain": ".txt", "application/json": ".json",
    "image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp",
    "image/gif": ".gif", "application/pdf": ".pdf",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "text/tab-separated-values": ".tsv", "text/markdown": ".md",
}
# What the in-app browser lists — the file types the chat can actually read.
_LIST_QUERY = (
    "trashed = false and ("
    "mimeType = 'application/vnd.google-apps.spreadsheet' or "
    "mimeType = 'application/vnd.google-apps.document' or "
    "mimeType = 'text/csv' or mimeType = 'text/plain' or "
    "mimeType = 'application/pdf' or mimeType contains 'image/' or "
    "mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' or "
    "mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' or "
    "mimeType = 'application/json' or mimeType = 'text/tab-separated-values')"
)


# ═════════════════════════════════════════════════════════════════════════
#  Links
# ═════════════════════════════════════════════════════════════════════════
_LINK_RES = (
    ("sheet", re.compile(r"docs\.google\.com/spreadsheets/d/([\w-]{10,})")),
    ("doc", re.compile(r"docs\.google\.com/document/d/([\w-]{10,})")),
    ("slides", re.compile(r"docs\.google\.com/presentation/d/([\w-]{10,})")),
    ("file", re.compile(r"drive\.google\.com/file/d/([\w-]{10,})")),
    ("file", re.compile(r"drive\.google\.com/(?:open|uc)\?(?:.*&)?id=([\w-]{10,})")),
    ("folder", re.compile(r"drive\.google\.com/drive/(?:u/\d+/)?folders/([\w-]{10,})")),
)


def parse_drive_link(text):
    """("sheet"|"doc"|"slides"|"file"|"folder", id, gid) or None."""
    text = (text or "").strip()
    for kind, rx in _LINK_RES:
        m = rx.search(text)
        if m:
            gid = ""
            g = re.search(r"[#&?]gid=(\d+)", text)
            if g:
                gid = g.group(1)
            return kind, m.group(1), gid
    return None


def is_drive_link(text):
    return parse_drive_link(text) is not None


def download_link(text, dest_dir):
    """Download a shared Drive link into dest_dir. Returns (path, name).
    Uses the connected account when there is one (private files work too),
    otherwise the public export/download endpoints."""
    parsed = parse_drive_link(text)
    if not parsed:
        raise ValueError(tr("That doesn't look like a Google Drive link."))
    kind, fid, gid = parsed
    if kind == "folder":
        raise ValueError(tr("That's a folder link — open the folder and share a single file instead, or connect your Google account to browse it."))
    if is_connected():
        try:
            return download_file(fid, dest_dir)
        except Exception:
            pass        # fall through to the public path
    if kind == "sheet":
        url = f"https://docs.google.com/spreadsheets/d/{fid}/export?format=csv"
        if gid:
            url += f"&gid={gid}"
    elif kind == "doc":
        url = f"https://docs.google.com/document/d/{fid}/export?format=txt"
    elif kind == "slides":
        url = f"https://docs.google.com/presentation/d/{fid}/export/txt"
    else:
        url = f"https://drive.google.com/uc?export=download&id={fid}"
    data, ctype, name = _get(url)
    if kind == "file" and ctype.startswith("text/html"):
        # The "can't scan this file for viruses" interstitial (big files), or a
        # private file's sign-in page.
        html = data[:200000].decode("utf-8", "replace")
        if "accounts.google.com" in html and "uc-download-link" not in html and "confirm" not in html:
            raise ValueError(_private_msg())
        m = re.search(r'name="uuid" value="([^"]+)"', html)
        url2 = f"https://drive.usercontent.google.com/download?id={fid}&export=download&confirm=t"
        if m:
            url2 += "&uuid=" + m.group(1)
        data, ctype, name = _get(url2)
        if ctype.startswith("text/html"):
            raise ValueError(_private_msg())
    if ctype.startswith("text/html") and kind != "file":
        raise ValueError(_private_msg())
    if not name:
        name = {"sheet": "Google Sheet.csv", "doc": "Google Doc.txt",
                "slides": "Google Slides.txt"}.get(kind, "Drive file")
    name = _ensure_ext(name, ctype)
    return _save(data, dest_dir, name), name


def _private_msg():
    return tr("Google Drive refused the download. Share the file as “Anyone with the link”, or connect your Google account.")


# ═════════════════════════════════════════════════════════════════════════
#  OAuth
# ═════════════════════════════════════════════════════════════════════════
def client_credentials():
    cfg = load_app_config()
    cid = (cfg.get("gdrive_client_id") or "").strip()
    sec = (cfg.get("gdrive_client_secret") or "").strip()
    if not cid:
        try:
            from app import constants
            cid = getattr(constants, "GDRIVE_CLIENT_ID", "") or ""
            sec = sec or getattr(constants, "GDRIVE_CLIENT_SECRET", "") or ""
        except Exception:
            pass
    return cid.strip(), sec.strip()


def save_client_credentials(cid, secret):
    cfg = load_app_config()
    cfg["gdrive_client_id"] = (cid or "").strip()
    cfg["gdrive_client_secret"] = (secret or "").strip()
    save_app_config(cfg)


def is_configured():
    return bool(client_credentials()[0])


def is_connected():
    return bool((load_app_config().get("gdrive_refresh_token") or "").strip())


def account_email():
    return (load_app_config().get("gdrive_email") or "").strip()


def disconnect():
    cfg = load_app_config()
    tok = cfg.pop("gdrive_refresh_token", None)
    cfg.pop("gdrive_email", None)
    save_app_config(cfg)
    _TOKEN_CACHE.clear()
    if tok:
        try:
            req = urllib.request.Request(
                "https://oauth2.googleapis.com/revoke",
                data=urllib.parse.urlencode({"token": tok}).encode(), method="POST")
            _urlopen(req, 10, configured_proxy()).close()
        except Exception:
            pass


def connect(open_url, should_stop=lambda: False, timeout=240):
    """Run the loopback consent flow. `open_url(url)` opens the system browser.
    Returns the connected account's email."""
    cid, secret = client_credentials()
    if not cid:
        raise RuntimeError(tr("Add a Google OAuth client ID first (Setup)."))
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    state = secrets.token_urlsafe(16)
    result = {}

    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):          # noqa: N802 — stdlib API
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            if q.get("state", [""])[0] == state:
                result["code"] = q.get("code", [""])[0]
                result["error"] = q.get("error", [""])[0]
            ok = bool(result.get("code"))
            body = ("<html><body style='font-family:sans-serif;background:#0b0b0e;color:#eee;"
                    "display:flex;align-items:center;justify-content:center;height:100vh'>"
                    f"<h2>{'YouTube Hunter is connected to Google Drive. You can close this tab.' if ok else 'Connection was cancelled.'}</h2>"
                    "</body></html>").encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), _Handler)
    srv.timeout = 0.5
    port = srv.server_address[1]
    redirect = f"http://127.0.0.1:{port}"
    url = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redirect, "response_type": "code",
        "scope": SCOPE + " openid email", "access_type": "offline", "prompt": "consent",
        "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
    })
    open_url(url)
    deadline = time.time() + timeout
    try:
        while not result and time.time() < deadline:
            if should_stop():
                raise RuntimeError(tr("Connection cancelled."))
            srv.handle_request()
    finally:
        srv.server_close()
    if not result.get("code"):
        raise RuntimeError(tr("Google sign-in was cancelled or timed out."))
    tok = _post_token({"code": result["code"], "client_id": cid, "client_secret": secret,
                       "redirect_uri": redirect, "grant_type": "authorization_code",
                       "code_verifier": verifier})
    refresh = tok.get("refresh_token")
    if not refresh:
        raise RuntimeError(tr("Google didn't return a refresh token. Remove YouTube Hunter from your Google account's third-party access and try again."))
    _TOKEN_CACHE["access"] = tok.get("access_token", "")
    _TOKEN_CACHE["exp"] = time.time() + int(tok.get("expires_in", 3000)) - 60
    email = ""
    try:
        about = _api_json("/about?fields=user(emailAddress,displayName)")
        email = (about.get("user") or {}).get("emailAddress", "")
    except Exception:
        pass
    cfg = load_app_config()
    cfg["gdrive_refresh_token"] = refresh
    cfg["gdrive_email"] = email
    save_app_config(cfg)
    return email


_TOKEN_CACHE = {}
_TOKEN_LOCK = threading.Lock()


def _access_token():
    with _TOKEN_LOCK:
        if _TOKEN_CACHE.get("access") and time.time() < _TOKEN_CACHE.get("exp", 0):
            return _TOKEN_CACHE["access"]
        cid, secret = client_credentials()
        refresh = (load_app_config().get("gdrive_refresh_token") or "").strip()
        if not (cid and refresh):
            raise RuntimeError(tr("Google Drive isn't connected."))
        tok = _post_token({"refresh_token": refresh, "client_id": cid,
                           "client_secret": secret, "grant_type": "refresh_token"})
        _TOKEN_CACHE["access"] = tok.get("access_token", "")
        _TOKEN_CACHE["exp"] = time.time() + int(tok.get("expires_in", 3000)) - 60
        return _TOKEN_CACHE["access"]


def _post_token(fields):
    req = urllib.request.Request(TOKEN_URL, data=urllib.parse.urlencode(fields).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"},
                                 method="POST")
    try:
        with _urlopen(req, 20, configured_proxy()) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode("utf-8")).get("error_description") or str(e)
        except Exception:
            msg = str(e)
        raise RuntimeError(tr("Google sign-in failed: {msg}").format(msg=msg)) from e


def _api_json(path):
    req = urllib.request.Request(API + path,
                                 headers={"Authorization": "Bearer " + _access_token()})
    with _urlopen(req, 25, configured_proxy()) as r:
        return json.loads(r.read().decode("utf-8"))


def list_files(search="", page_size=60):
    """Recent readable files in the connected Drive (newest first)."""
    q = _LIST_QUERY
    s = (search or "").strip().replace("\\", "").replace("'", "\\'")
    if s:
        q = f"name contains '{s}' and " + q
    params = urllib.parse.urlencode({
        "q": q, "pageSize": page_size, "orderBy": "modifiedTime desc",
        "fields": "files(id,name,mimeType,size,modifiedTime,iconLink,thumbnailLink)",
        "includeItemsFromAllDrives": "true", "supportsAllDrives": "true",
    })
    out = []
    for f in (_api_json("/files?" + params).get("files") or []):
        out.append({
            "id": f.get("id", ""), "name": f.get("name", ""),
            "mime": f.get("mimeType", ""), "size": int(f.get("size", 0) or 0),
            "modified": (f.get("modifiedTime") or "")[:10],
            "kind": _kind_for_mime(f.get("mimeType", "")),
        })
    return out


def download_file(fid, dest_dir):
    meta = _api_json(f"/files/{fid}?fields=id,name,mimeType,size&supportsAllDrives=true")
    mime = meta.get("mimeType", "")
    name = meta.get("name") or "Drive file"
    if mime in _EXPORTS:
        exp_mime, ext = _EXPORTS[mime]
        url = f"{API}/files/{fid}/export?" + urllib.parse.urlencode({"mimeType": exp_mime})
        if not name.lower().endswith(ext):
            name += ext
    else:
        url = f"{API}/files/{fid}?alt=media&supportsAllDrives=true"
        name = _ensure_ext(name, mime)
    data, _ctype, _n = _get(url, {"Authorization": "Bearer " + _access_token()})
    return _save(data, dest_dir, name), name


def _kind_for_mime(m):
    if m.startswith("image/"):
        return "image"
    if m in ("application/vnd.google-apps.spreadsheet", "text/csv",
             "text/tab-separated-values",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"):
        return "table"
    if m in ("application/pdf",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document"):
        return "doc"
    return "text"


# ── http helpers ─────────────────────────────────────────────────────────
def _get(url, headers=None, limit=40 * 1024 * 1024):
    req = urllib.request.Request(url, headers=dict(headers or {}))
    try:
        with _urlopen(req, 40, configured_proxy()) as r:
            data = r.read(limit + 1)
            ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            name = _filename_from(r.headers.get("Content-Disposition") or "")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403, 404):
            raise ValueError(_private_msg()) from e
        raise RuntimeError(tr("Google Drive error ({code}).").format(code=e.code)) from e
    except (socket.timeout, TimeoutError) as e:
        raise RuntimeError(tr("Google Drive took too long to answer.")) from e
    except urllib.error.URLError as e:
        raise RuntimeError(tr("Couldn't reach Google Drive: {reason}").format(reason=e.reason)) from e
    if len(data) > limit:
        raise ValueError(tr("That file is too large (40 MB max)."))
    return data, ctype, name


def _filename_from(cd):
    m = re.search(r"filename\*=UTF-8''([^;]+)", cd, re.I)
    if m:
        return urllib.parse.unquote(m.group(1)).strip('"')
    m = re.search(r'filename="?([^";]+)"?', cd, re.I)
    return m.group(1).strip() if m else ""


def _ensure_ext(name, ctype):
    if os.path.splitext(name)[1]:
        return name
    return name + _EXT_FOR_MIME.get(ctype, "")


def _save(data, dest_dir, name):
    os.makedirs(dest_dir, exist_ok=True)
    stem, ext = os.path.splitext(name)
    safe = "".join(ch for ch in stem if ch.isalnum() or ch in " -_()").strip() or "drive"
    path = os.path.join(dest_dir, f"{safe[:60]}-{secrets.token_hex(4)}{ext.lower()}")
    with open(path, "wb") as f:
        f.write(data)
    return path
