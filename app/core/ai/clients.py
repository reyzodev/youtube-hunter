"""app.core.ai.clients - Youtube Scrapper."""

import json
import re
import socket
import urllib.parse

from app.constants import GEMINI_API_KEY_DEFAULT, GEMINI_ENDPOINT, GEMINI_MODEL_DEFAULT
from app.core.ai import effort as _effort
from app.core.net import (_dropped_connection_error, _read_timeout_error,
                          _urlopen, is_dropped_connection, request_with_retry)
from app.i18n import tr

class GeminiClient:
    """Minimal wrapper around the Gemini `generateContent` REST endpoint."""

    def __init__(self, api_key, model=None, proxy=None, base_url=None,
                 label=None):
        self.api_key = (api_key or GEMINI_API_KEY_DEFAULT).strip()
        self.proxy = (proxy or "").strip()
        self.model = (model or GEMINI_MODEL_DEFAULT).strip()
        # An alternative host that speaks the same Google Generative AI shape —
        # a proxy or a regional mirror. Empty means Google's own endpoint.
        self.base_url = (base_url or "").strip().rstrip("/")
        # What to call this provider in an error message. Passed in by AIClient
        # so a failure names the provider the user picked in Settings ("Google
        # Gemini", or a Custom router's own name when it speaks this shape)
        # rather than always saying "Gemini".
        self.label = (label or "").strip() or "Gemini"

    def endpoint(self):
        if not self.base_url:
            return GEMINI_ENDPOINT.format(model=self.model)
        return "%s/models/%s:generateContent" % (self.base_url, self.model)

    def generate(self, prompt, system_instruction=None, timeout=60, max_output_tokens=2048,
                 effort=None):
        if not self.api_key:
            raise RuntimeError(tr("Gemini API key is missing."))
        url = self.endpoint()

        def make_body(with_effort):
            body = {
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.8, "maxOutputTokens": max_output_tokens},
            }
            if system_instruction:
                body["systemInstruction"] = {"parts": [{"text": system_instruction}]}
            applied = _effort.apply_gemini(body, self.model, effort) if with_effort else False
            return body, applied

        def post(body):
            payload_bytes = json.dumps(body).encode("utf-8")

            def build():
                # Rebuilt per attempt: a Request's body cannot be re-sent once its
                # stream has been consumed.
                return urllib.request.Request(
                    url,
                    data=payload_bytes,
                    headers={"Content-Type": "application/json",
                             "x-goog-api-key": self.api_key},
                    method="POST",
                )
            return json.loads(
                request_with_retry(build, timeout, self.proxy,
                                   provider_label=self.label).decode("utf-8"))

        try:
            body, applied = make_body(True)
            try:
                payload = post(body)
            except urllib.error.HTTPError as e:
                # The thinking knob is the one part a model may not take
                # (gemini-2.0, a mirror that strips it): retry once without it.
                if not (applied and _effort.should_retry_plain(e.code)):
                    raise
                payload = post(make_body(False)[0])
        except urllib.error.HTTPError as e:
            try:
                err_body = json.loads(e.read().decode("utf-8"))
                msg = err_body.get("error", {}).get("message", str(e))
            except Exception:
                msg = str(e)
            raise RuntimeError(tr("{provider} API error ({code}): {msg}").format(
                provider=self.label, code=e.code, msg=msg)) from e
        except Exception as e:
            # Checked before URLError on purpose: a mid-request reset is an
            # OSError but NOT a URLError, so it used to escape every clause here
            # and surface as a bare "[WinError 10054] …".
            if is_dropped_connection(e):
                raise _dropped_connection_error(self.label) from e
            if isinstance(e, urllib.error.URLError):
                raise RuntimeError(tr("Network error contacting {provider}: {reason}").format(
                    provider=self.label, reason=e.reason)) from e
            raise

        candidates = payload.get("candidates") or []
        if not candidates:
            block_reason = payload.get("promptFeedback", {}).get("blockReason")
            if block_reason:
                raise RuntimeError(tr("Gemini declined to respond ({reason}).").format(reason=block_reason))
            raise RuntimeError(tr("Gemini returned an empty response."))
        parts = candidates[0].get("content", {}).get("parts", [])
        text = "".join(p.get("text", "") for p in parts if not p.get("thought")).strip()
        if not text:
            raise RuntimeError(tr("Gemini returned an empty response."))
        return text


AI_PROVIDERS = ["openai", "anthropic", "gemini", "custom"]
AI_PROVIDER_LABELS = {
    "openai":    "OpenAI",
    "anthropic": "Anthropic",
    "gemini":    "Google Gemini",
    # kept for reading configs saved before the picker was reworked
    "deepseek":  "DeepSeek",
    "claude":    "Anthropic",
    "custom":    "Custom (OpenAI-compatible / aggregator)",
}
AI_PROVIDER_DEFAULT_MODEL = {
    "openai":    "gpt-4o-mini",
    "anthropic": "claude-sonnet-4-5-20250929",
    "gemini":    GEMINI_MODEL_DEFAULT,
    "deepseek":  "deepseek-chat",
    "claude":    "claude-sonnet-4-5-20250929",
    "custom":    "",
}

# Anthropic publishes no unauthenticated model catalogue, so the Settings model
# picker is seeded with the ids this app knows rather than left empty. A user
# can always type an exact id instead.
ANTHROPIC_KNOWN_MODELS = (
    "claude-opus-4-1-20250805",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
)

# Per-provider connection defaults. For the built-in providers the user only
# ever pastes a key — host/path/model come from here so there's nothing else to
# configure — but every one of these is now overridable in Settings, because
# plenty of people reach these APIs through a same-shape proxy or mirror.
# "custom" is fully user-driven (empty host). These hosts are the current
# official REST bases (verified Aug 2026):
#   OpenAI     https://api.openai.com/v1        + /chat/completions
#   Anthropic  https://api.anthropic.com/v1     + /messages
#   Gemini     https://generativelanguage.googleapis.com/v1beta (own shape)
#   DeepSeek   https://api.deepseek.com/v1      + /chat/completions
AI_PROVIDER_DEFAULTS = {
    "openai":    {"base_url": "https://api.openai.com/v1",
                  "path": "/chat/completions"},
    "anthropic": {"base_url": "https://api.anthropic.com/v1",
                  "path": "/messages"},
    "claude":    {"base_url": "https://api.anthropic.com/v1",
                  "path": "/messages"},
    "gemini":    {"base_url": "https://generativelanguage.googleapis.com/v1beta",
                  "path": ""},
    "deepseek":  {"base_url": "https://api.deepseek.com/v1",
                  "path": "/chat/completions"},
    "custom":    {"base_url": "", "path": "/chat/completions"},
}
# Which providers are "built-in" (fixed host, key-only UX) vs the editable one.
AI_BUILTIN_PROVIDERS = ("openai", "anthropic", "gemini")

DEEPSEEK_ENDPOINT = "https://api.deepseek.com/v1/chat/completions"
CLAUDE_ENDPOINT = "https://api.anthropic.com/v1/messages"

# Which wire shape a Custom Provider speaks. "Custom" used to be a synonym for
# "OpenAI-compatible", which silently excluded routers that expose Anthropic's
# /v1/messages or Google's generateContent instead — so it is now an explicit
# choice, and every built-in provider derives its own default from here.
AI_API_MODES = ["openai_compatible", "anthropic_messages", "google_genai"]
AI_API_MODE_LABELS = {
    "openai_compatible":  "OpenAI API Compatible",
    "anthropic_messages": "Anthropic Messages",
    "google_genai":       "Google Generative AI",
}
# The shape each built-in provider actually speaks.
AI_PROVIDER_API_MODE = {
    "openai":    "openai_compatible",
    "anthropic": "anthropic_messages",
    "claude":    "anthropic_messages",
    "gemini":    "google_genai",
    "deepseek":  "openai_compatible",
    "custom":    "openai_compatible",
}


def api_mode_for(provider, api_mode=None):
    """Resolve the wire shape to use. An explicit `api_mode` wins (that is the
    Custom provider's dropdown); otherwise the provider's own shape is used, so
    configs saved before this setting existed keep behaving identically."""
    if api_mode in AI_API_MODES:
        return api_mode
    return AI_PROVIDER_API_MODE.get(
        (provider or "").strip().lower(), "openai_compatible")


def default_path_for(provider, api_mode=None):
    """The endpoint path a provider uses when the user has not set one.

    For the built-in providers this is just their shipped default. It matters
    for the CUSTOM provider: its path has to follow the wire shape the user
    picked, because "Custom" is not a synonym for "OpenAI-shaped" any more. A
    router set to Anthropic Messages must POST to /messages — sending an
    Anthropic body to /chat/completions is the kind of mismatch that returns a
    confusing 404 from the router rather than a clear error here.
    """
    mode = api_mode_for(provider, api_mode)
    if mode == "google_genai":
        return ""                      # the model id goes in the URL instead
    if mode == "anthropic_messages":
        return "/messages"
    return "/chat/completions"


def _parse_openai_style_payload(raw_text):
    """Parse a `/chat/completions` response body into the normal
    {"choices": [{"message": {"content": ...}}]} shape.

    Almost every provider returns one clean JSON object here — that's the
    fast path. Two other shapes reach this function and both have to work:

      * a few aggregators (9router among them) send the response as several
        raw JSON chunks back-to-back with no separator — effectively
        streaming even though "stream": false was sent — which makes a plain
        json.loads() fail with "Extra data" even though every individual
        chunk is itself valid JSON.
      * a request this app deliberately STREAMED (see the `stream` argument of
        _openai_style_chat) comes back as Server-Sent Events: `data: {…}`
        lines, blank lines between them, sometimes `event: …` labels, ending
        in `data: [DONE]`.

    So this walks the body one JSON value at a time, skipping any SSE framing
    line it meets, and stitches the text deltas back together instead of
    failing outright."""
    raw_text = (raw_text or "").strip()
    first_err = None
    try:
        return json.loads(raw_text)
    except json.JSONDecodeError as e:
        # `except ... as e` auto-unbinds `e` once this block ends, so it
        # must be copied to a plain variable to survive until the
        # `raise first_err` below.
        first_err = e

    decoder = json.JSONDecoder()
    pieces = []
    i, n = 0, len(raw_text)
    saw_any = False
    while i < n:
        while i < n and raw_text[i] in " \t\r\n":
            i += 1
        if raw_text[i:i + 5] == "data:":
            i += 5
            while i < n and raw_text[i] == " ":
                i += 1
            continue
        if raw_text[i:i + 6] == "[DONE]":
            i += 6
            continue
        if i >= n:
            break
        if raw_text[i] != "{":
            # An SSE label ("event: content_block_delta"), a keep-alive comment
            # (": ping") or any other non-JSON framing line. Skip the whole line
            # rather than giving up: the JSON chunks after it are the payload.
            nl = raw_text.find("\n", i)
            if nl == -1:
                break
            i = nl + 1
            continue
        try:
            chunk, end = decoder.raw_decode(raw_text, i)
        except json.JSONDecodeError:
            break
        i = end
        saw_any = True
        choice = (chunk.get("choices") or [{}])[0]
        piece = (choice.get("delta") or {}).get("content")
        if piece is None:
            piece = (choice.get("message") or {}).get("content")
        if piece:
            pieces.append(piece)

    if not saw_any or not pieces:
        raise first_err
    return {"choices": [{"message": {"content": "".join(pieces)}}]}


def _parse_anthropic_stream(raw_text):
    """Reassemble a streamed `/v1/messages` body into the normal
    {"content": [{"type": "text", "text": …}]} shape.

    Anthropic's stream is SSE with named events; the text lives in
    `content_block_delta` frames as `delta.text`. Only text deltas are
    collected — this app never asks for tool use — and a body that is already
    one plain JSON object is returned untouched, so the same function serves a
    streamed and a non-streamed reply."""
    raw_text = (raw_text or "").strip()
    try:
        payload = json.loads(raw_text)
        if isinstance(payload, dict):
            return payload
    except json.JSONDecodeError:
        pass

    decoder = json.JSONDecoder()
    pieces = []
    stop_reason = ""
    i, n = 0, len(raw_text)
    while i < n:
        while i < n and raw_text[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        if raw_text[i:i + 5] == "data:":
            # The frame's payload follows on the same line. Stepping past the
            # prefix (rather than skipping the line) is the whole point — this is
            # where the text lives.
            i += 5
            while i < n and raw_text[i] == " ":
                i += 1
            continue
        if raw_text[i] != "{":
            # An `event: …` label or a keep-alive comment. Skip the line.
            nl = raw_text.find("\n", i)
            if nl == -1:
                break
            i = nl + 1
            continue
        try:
            frame, end = decoder.raw_decode(raw_text, i)
        except json.JSONDecodeError:
            break
        i = end
        kind = frame.get("type")
        if kind == "content_block_delta":
            delta = frame.get("delta") or {}
            if delta.get("type") in (None, "text_delta") and delta.get("text"):
                pieces.append(delta["text"])
        elif kind == "content_block_start":
            block = frame.get("content_block") or {}
            if block.get("type") == "text" and block.get("text"):
                pieces.append(block["text"])
        elif kind == "message_delta":
            stop_reason = ((frame.get("delta") or {}).get("stop_reason")
                           or stop_reason)
    return {"content": [{"type": "text", "text": "".join(pieces)}],
            "stop_reason": stop_reason}


def _openai_style_chat(endpoint, api_key, model, prompt, system_instruction,
                        timeout, extra_headers=None, provider_label="AI",
                        proxy=None, max_tokens=2048, stream=False, effort=None):
    """Shared POST for every OpenAI-`/chat/completions`-shaped API: DeepSeek,
    and any Custom/aggregator endpoint (OpenRouter, Together, etc. all speak
    this same shape with just a different base URL + bearer key).

    `stream` asks the provider to send the reply as Server-Sent Events. It is
    not a UI feature — nothing here shows tokens as they arrive — it exists
    because a non-streamed request sends NOTHING until the whole generation is
    done, and an aggregator in front of the model routinely gives up on a
    silent connection long before a report-sized answer is finished (measured:
    the same prompt 403s at ~195s unstreamed and completes at ~294s streamed).
    Streaming keeps bytes crossing the wire, which also turns `timeout` from
    "the whole answer must finish inside N seconds" into "no gap longer than N
    seconds", which is the limit that was actually wanted.
    """
    if not (model or "").strip():
        raise RuntimeError(
            tr("{provider}: no model name is set. Aggregator/custom "
               "endpoints need an exact model id (e.g. "
               "\"openai/gpt-4o-mini\" on OpenRouter) — fill in the MODEL "
               "field before validating.").format(provider=provider_label))
    messages = []
    if system_instruction:
        messages.append({"role": "system", "content": system_instruction})
    messages.append({"role": "user", "content": prompt})
    # "stream" is always explicit, never left to the provider's default: at
    # least one aggregator (9router) streams chunked JSON back regardless of
    # what was asked — see _parse_openai_style_payload, which handles that and
    # a genuinely streamed reply through the same path.
    def make_body(with_effort):
        body = {"model": model, "messages": messages, "stream": bool(stream)}
        if _effort.is_openai_reasoning(model):
            # Reasoning models reject `temperature`, and api.openai.com wants
            # `max_completion_tokens` (reasoning tokens come out of it, so it
            # gets room). Routers keep the classic name.
            cap = max(int(max_tokens or 0), 8192)
            if "api.openai.com" in str(endpoint):
                body["max_completion_tokens"] = cap
            else:
                body["max_tokens"] = cap
        else:
            body["temperature"] = 0.8
            body["max_tokens"] = max_tokens
        applied = _effort.apply_openai(body, model, effort, endpoint) if with_effort else False
        return body, applied

    headers = {"Content-Type": "application/json",
               "Authorization": f"Bearer {api_key}"}
    if stream:
        headers["Accept"] = "text/event-stream"
    if extra_headers:
        headers.update(extra_headers)

    def post(body):
        payload_bytes = json.dumps(body).encode("utf-8")

        def build():
            # Rebuilt per attempt: a Request's body cannot be re-sent once consumed.
            return urllib.request.Request(
                endpoint, data=payload_bytes, headers=headers, method="POST")
        return request_with_retry(
            build, timeout, proxy, provider_label=provider_label).decode("utf-8")

    try:
        body, applied = make_body(True)
        try:
            raw_text = post(body)
        except urllib.error.HTTPError as e:
            # A router that does not forward `reasoning_effort` answers 400:
            # the effort setting must never be the reason a call fails.
            if not (applied and _effort.should_retry_plain(e.code)):
                raise
            raw_text = post(make_body(False)[0])
        payload = _parse_openai_style_payload(raw_text)
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = (err_body.get("error", {}) or {}).get("message", str(e))
        except Exception:
            msg = str(e)
        raise RuntimeError(
            tr("{provider} API error ({code}): {msg}").format(
                provider=provider_label, code=e.code, msg=msg)) from e
    except json.JSONDecodeError as e:
        raise RuntimeError(
            tr("{provider} sent back a response that isn't valid JSON — "
               "double-check the API Host and API Path are correct for "
               "this provider.").format(provider=provider_label)) from e
    except Exception as e:
        # Before the URLError check: a mid-request reset is an OSError but not a
        # URLError, so it would otherwise escape as a raw "[WinError 10054] …".
        if is_dropped_connection(e):
            raise _dropped_connection_error(provider_label) from e
        if isinstance(e, urllib.error.URLError):
            raise RuntimeError(
                tr("Network error contacting {provider}: {reason}").format(
                    provider=provider_label, reason=e.reason)) from e
        raise

    choices = payload.get("choices") or []
    if not choices:
        raise RuntimeError(tr("{provider} returned an empty response.").format(
            provider=provider_label))
    text = (choices[0].get("message", {}) or {}).get("content", "").strip()
    if not text:
        raise RuntimeError(tr("{provider} returned an empty response.").format(
            provider=provider_label))
    return text


# Endpoint suffixes a user may paste into API Path. Whatever precedes one of
# these is the API root, and the model list lives at {root}/models.
_ENDPOINT_SUFFIXES = ("/chat/completions", "/completions", "/responses",
                      "/messages", "/embeddings")


def _models_endpoint_candidates(host, path):
    """Every plausible `/models` URL for a Custom provider, best guess first.

    OpenAI-shaped APIs put the catalogue beside the chat endpoint
    (…/v1/chat/completions → …/v1/models), but people fill Host/Path in many
    ways: the version can sit in the host ("https://x.ai/v1") or in the path
    ("/v1/chat/completions"), the path may carry a trailing slash or a query,
    or it may be left blank. The old code only handled the exact
    "/chat/completions" ending and otherwise fell back to {host}/models, which
    on most routers is a 403/404 page, not the API."""
    host = (host or "").strip().rstrip("/")
    path = (path or "").strip().split("?", 1)[0].rstrip("/")
    if path and not path.startswith("/"):
        path = "/" + path
    root = path
    for suf in _ENDPOINT_SUFFIXES:
        if root.lower().endswith(suf):
            root = root[:-len(suf)]
            break
    else:
        # Already the list URL, or a bare root such as "/v1".
        if root.lower().endswith("/models"):
            root = root[:-len("/models")]
    out = []

    def add(u):
        if u not in out:
            out.append(u)

    add(f"{host}{root}/models")
    if not re.search(r"/v\d+[a-z]*$", host + root, re.I):
        add(f"{host}{root}/v1/models")
    add(f"{host}/models")
    if not re.search(r"/v\d+[a-z]*$", host, re.I):
        add(f"{host}/v1/models")
    return out


def _custom_models_endpoint(host, path):
    """Best-guess `/models` URL (kept for the legacy QWidgets build)."""
    return _models_endpoint_candidates(host, path)[0]


def _http_error_message(e):
    """A readable reason out of an HTTPError, whatever the body looks like:
    an OpenAI {"error": {"message"}}, a {"detail"} / {"message"} body, or an
    HTML block page (Cloudflare & co.), which is named as such."""
    body = ""
    try:
        body = e.read().decode("utf-8", "replace")
    except Exception:
        pass
    try:
        j = json.loads(body)
        err = j.get("error") if isinstance(j, dict) else None
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
        if isinstance(err, str) and err:
            return err
        for k in ("message", "detail", "msg"):
            if isinstance(j, dict) and j.get(k):
                return str(j[k])
    except Exception:
        pass
    low = body.lower()
    if "cloudflare" in low or "cf-ray" in low or "error 1010" in low or "<html" in low:
        return tr("the server returned a web page instead of the API "
                  "(a firewall / bot-protection block, or the Host/Path "
                  "points at the website rather than its API)")
    snippet = " ".join(body.split())[:160]
    return snippet or str(e)


def _openai_style_list_models(host, path, api_key, timeout, proxy=None,
                              anthropic=False):
    """GET the Custom Provider's model list (the "Fetch" button in Settings).

    Tries each candidate URL from _models_endpoint_candidates() until one
    answers with a model list. The key is sent both as a Bearer token and as
    x-api-key, because routers differ on which one they read (Anthropic-shaped
    ones want x-api-key + anthropic-version). Any of these failing with
    401/403/404/405 just means "not here", so the next URL is tried; only when
    all fail is an error raised, and that error tells the user they can still
    type the model id by hand."""
    headers = {"Authorization": f"Bearer {api_key}", "x-api-key": api_key}
    if anthropic:
        headers["anthropic-version"] = "2023-06-01"
    first_err = None
    first_code = None
    for endpoint in _models_endpoint_candidates(host, path):
        req = urllib.request.Request(endpoint, headers=dict(headers), method="GET")
        try:
            with _urlopen(req, timeout, proxy) as resp:
                raw = resp.read().decode("utf-8", "replace")
        except (socket.timeout, TimeoutError) as e:
            raise _read_timeout_error(tr("The API"), timeout) from e
        except urllib.error.HTTPError as e:
            msg = _http_error_message(e)
            # Report the most telling failure: an auth refusal (401/403) says
            # more than a 404 from a URL that simply isn't the API.
            if first_err is None or (e.code in (401, 403) and first_code not in (401, 403)):
                first_code, first_err = e.code, msg
            if e.code in (400, 401, 403, 404, 405, 410):
                continue
            raise RuntimeError(
                tr("Fetching the model list failed ({code}): {msg}").format(
                    code=e.code, msg=msg)) from e
        except urllib.error.URLError as e:
            raise RuntimeError(
                tr("Network error fetching models: {reason}").format(reason=e.reason)) from e
        except Exception as e:
            if is_dropped_connection(e):
                raise _dropped_connection_error(tr("The API"), generating=False) from e
            raise
        ids = _model_ids_from_payload(raw)
        if ids:
            return ids
        # 200 but not a model list (an HTML landing page, say): keep looking.
        if first_err is None:
            first_code, first_err = 200, tr("not a model list")

    if first_code in (401, 403):
        raise RuntimeError(
            tr("Fetching the model list failed ({code}): {msg}. Some providers "
               "don't let API keys list models — type the exact model id in the "
               "Model box instead; chat requests still work.").format(
                code=first_code, msg=first_err))
    raise RuntimeError(
        tr("Fetching the model list failed ({code}): {msg}").format(
            code=first_code or "?", msg=first_err or tr("no response")))


def _model_ids_from_payload(raw):
    try:
        payload = json.loads(raw)
    except Exception:
        return []
    items = None
    if isinstance(payload, dict):
        for k in ("data", "models", "result", "items"):
            if isinstance(payload.get(k), list):
                items = payload[k]
                break
    elif isinstance(payload, list):
        items = payload
    ids = []
    for it in (items or []):
        if isinstance(it, dict):
            model_id = it.get("id") or it.get("name") or it.get("model")
        else:
            model_id = it if isinstance(it, str) else None
        if model_id:
            model_id = str(model_id)
            if model_id.startswith("models/"):
                model_id = model_id[len("models/"):]
            ids.append(model_id)
    return sorted(set(ids))


def list_models(provider, api_key, base_url=None, path=None, timeout=20,
                proxy=None, api_mode=None):
    """The models a provider offers, for the "Fetch" button in Settings.

    Each wire shape publishes its catalogue differently, so this dispatches the
    same way generate() does rather than assuming OpenAI's convention:
      * openai_compatible  → GET {root}/models,        {"data": [{"id": …}]}
      * google_genai       → GET {base}/models?key=…,  {"models": [{"name": …}]}
      * anthropic_messages → no public list endpoint; the known model ids are
                             returned so the picker is still populated.
    """
    mode = api_mode_for(provider, api_mode)
    base = (base_url or AI_PROVIDER_DEFAULTS.get(
        (provider or "").strip().lower(), {}).get("base_url", "")).strip().rstrip("/")

    if mode == "google_genai":
        root = base or "https://generativelanguage.googleapis.com/v1beta"
        endpoint = "%s/models" % root
        req = urllib.request.Request(
            endpoint, headers={"x-goog-api-key": api_key}, method="GET")
        payload = _get_json(req, timeout, proxy)
        ids = []
        for item in (payload.get("models") or []):
            name = (item or {}).get("name") or ""
            # Google returns fully-qualified names ("models/gemini-2.5-flash");
            # the id is what every other part of the app stores.
            ids.append(name.split("/")[-1] if "/" in name else name)
        ids = [i for i in ids if i]
        if not ids:
            raise RuntimeError(tr("This API didn't return any models."))
        return sorted(set(ids))

    if mode == "anthropic_messages":
        # Anthropic (and most routers that speak its shape) do publish
        # GET {root}/models for a key. Try it; if the host doesn't offer one,
        # seed the picker with the ids this app knows rather than leave it empty.
        if base:
            try:
                return _openai_style_list_models(
                    base, path or "/messages", api_key, timeout, proxy=proxy,
                    anthropic=True)
            except Exception:
                pass
        return sorted(ANTHROPIC_KNOWN_MODELS)

    if not base:
        raise RuntimeError(tr("Enter an API Host first."))
    return _openai_style_list_models(base, path, api_key, timeout, proxy=proxy)


def _get_json(req, timeout, proxy):
    """GET + parse, with the same error messages the model fetch already used."""
    try:
        with _urlopen(req, timeout, proxy) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (socket.timeout, TimeoutError) as e:
        raise _read_timeout_error(tr("The API"), timeout) from e
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = (err_body.get("error", {}) or {}).get("message", str(e))
        except Exception:
            msg = str(e)
        raise RuntimeError(
            tr("Fetching the model list failed ({code}): {msg}").format(
                code=e.code, msg=msg)) from e
    except json.JSONDecodeError:
        raise RuntimeError(
            tr("The models endpoint didn't return valid JSON — double-check "
               "the API Host and API Path."))
    except Exception as e:
        # Not retried, unlike a chat call: this is a cheap GET the user can
        # simply press again, and the Settings page already surfaces the button.
        if is_dropped_connection(e):
            raise _dropped_connection_error(tr("The API"), generating=False) from e
        if isinstance(e, urllib.error.URLError):
            raise RuntimeError(
                tr("Network error fetching models: {reason}").format(
                    reason=e.reason)) from e
        raise


def _anthropic_style_chat(endpoint, api_key, model, prompt, system_instruction,
                          timeout, provider_label="Anthropic", proxy=None,
                          max_tokens=2048, stream=False, effort=None):
    """Shared POST for every Anthropic-`/v1/messages`-shaped API: Anthropic
    itself, and any Custom provider set to the "Anthropic Messages" mode (some
    routers expose that shape rather than OpenAI's).

    `stream` has the same purpose here as in _openai_style_chat: keep bytes
    moving on a long generation so nothing in the path decides the connection
    is idle and cuts it. See that docstring for the measurement."""
    if not (model or "").strip():
        raise RuntimeError(
            tr("{provider}: no model name is set. Aggregator/custom "
               "endpoints need an exact model id (e.g. "
               "\"openai/gpt-4o-mini\" on OpenRouter) — fill in the MODEL "
               "field before validating.").format(provider=provider_label))
    def make_body(with_effort):
        body = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if stream:
            body["stream"] = True
        if system_instruction:
            body["system"] = system_instruction
        applied = _effort.apply_anthropic(body, model, effort) if with_effort else False
        return body, applied

    def post(body):
        payload_bytes = json.dumps(body).encode("utf-8")

        def build():
            # Rebuilt per attempt: a Request's body cannot be re-sent once consumed.
            headers = {"Content-Type": "application/json",
                       "x-api-key": api_key,
                       "anthropic-version": "2023-06-01"}
            if stream:
                headers["Accept"] = "text/event-stream"
            return urllib.request.Request(
                endpoint, data=payload_bytes, headers=headers, method="POST")
        return _parse_anthropic_stream(
            request_with_retry(build, timeout, proxy,
                               provider_label=provider_label).decode("utf-8"))

    try:
        body, applied = make_body(True)
        try:
            payload = post(body)
        except urllib.error.HTTPError as e:
            # Extended thinking is model-specific; a router or an older Claude
            # that refuses it gets the same request without it.
            if not (applied and _effort.should_retry_plain(e.code)):
                raise
            payload = post(make_body(False)[0])
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = (err_body.get("error", {}) or {}).get("message", str(e))
        except Exception:
            msg = str(e)
        raise RuntimeError(tr("{provider} API error ({code}): {msg}").format(
            provider=provider_label, code=e.code, msg=msg)) from e
    except Exception as e:
        # Before the URLError check: a mid-request reset is an OSError but not a
        # URLError, so it would otherwise escape as a raw "[WinError 10054] …".
        if is_dropped_connection(e):
            raise _dropped_connection_error(provider_label) from e
        if isinstance(e, urllib.error.URLError):
            raise RuntimeError(tr("Network error contacting {provider}: {reason}").format(
                provider=provider_label, reason=e.reason)) from e
        raise
    parts = payload.get("content") or []
    text = "".join(p.get("text", "") for p in parts if p.get("type") == "text").strip()
    if not text:
        raise RuntimeError(tr("{provider} returned an empty response.").format(
            provider=provider_label))
    return text


class AIClient:
    """Routes AI calls to whichever provider is selected in Settings —
    Gemini, DeepSeek, Anthropic Claude, or a Custom endpoint. Every AI-powered
    feature in the app (Monetize insight, Idea Finder outlier analysis, Idea
    Analysis, AI Ideas) builds its client through here instead of hardcoding
    Gemini, so switching the provider in Settings changes all of them at once.

    `api_mode` decides which WIRE SHAPE a Custom provider speaks. "Custom" used
    to mean "OpenAI-compatible" and nothing else, which quietly excluded every
    router that exposes Anthropic's /v1/messages or Google's generateContent
    instead. Defaults are derived from the provider, so existing configs keep
    working untouched."""

    def __init__(self, provider, api_key, model=None, base_url=None, proxy=None,
                 path=None, custom_name=None, api_mode=None, effort=None):
        self.provider = (provider or "gemini").strip().lower()
        self.api_key = (api_key or "").strip()
        self.model = (model or AI_PROVIDER_DEFAULT_MODEL.get(self.provider, "")).strip()
        self.base_url = (base_url or "").strip().rstrip("/")
        self.proxy = (proxy or "").strip()
        # Custom Provider only: the endpoint path (default mirrors the old
        # hardcoded "/chat/completions") and the user's display name for it
        # (e.g. "9router"), used to make error messages legible instead of
        # a generic "Custom AI".
        self.path = ((path or "/chat/completions").strip()) or "/chat/completions"
        self.custom_name = (custom_name or "").strip()
        self.api_mode = api_mode_for(self.provider, api_mode)
        # How hard the model should think — see app.core.ai.effort. "auto"
        # sends nothing extra, which is exactly how every call behaved before.
        self.effort = _effort.norm_effort(effort)

    @property
    def label(self):
        """What to call this provider in an error message."""
        if self.provider == "custom":
            return self.custom_name or tr("Custom AI")
        return AI_PROVIDER_LABELS.get(self.provider, self.provider)

    def endpoint(self):
        """The full URL this client will POST to, host + path resolved.

        Exposed (rather than being buried inside generate()) because Settings
        validation and the tests both need to see where a config actually points
        without making a call."""
        base = self.base_url or AI_PROVIDER_DEFAULTS.get(
            self.provider, {}).get("base_url", "")
        base = base.rstrip("/")
        if self.api_mode == "google_genai":
            model = self.model or GEMINI_MODEL_DEFAULT
            if not base:
                return GEMINI_ENDPOINT.format(model=model)
            return "%s/models/%s:generateContent" % (base, model)
        # Everything else is host + path. The path is resolved from the WIRE
        # SHAPE when the user has not overridden it, so a Custom provider set to
        # Anthropic Messages posts to /messages rather than OpenAI's
        # /chat/completions (see default_path_for).
        path = self.path
        default_path = default_path_for(self.provider, self.api_mode)
        if not path or (path == "/chat/completions"
                        and default_path != "/chat/completions"):
            path = default_path
        if not path:
            path = AI_PROVIDER_DEFAULTS.get(self.provider, {}).get("path", "")
        if path and not path.startswith("/"):
            path = "/" + path
        return base + path

    # Above this output budget a call is treated as a LONG generation and is
    # streamed by default (see _openai_style_chat's `stream`). 3000 tokens is
    # comfortably above the small utility calls (validation, a one-line label)
    # and below every report/blueprint/brief call in the app, all of which ask
    # for 4000+ and are the ones that were dying at a router's duration cap.
    LONG_OUTPUT_TOKENS = 3000

    def generate(self, prompt, system_instruction=None, timeout=60,
                 max_output_tokens=2048, stream=None):
        """One completion, routed by wire shape.

        `stream` is a transport choice, not a UI one: None (the default) means
        "decide from the size of the ask", streaming anything above
        LONG_OUTPUT_TOKENS. Nothing displays partial text — the full reply is
        still reassembled before returning — but a streamed request keeps bytes
        crossing the wire, which is what stops an aggregator from 403-ing a
        long generation it has decided is a stalled connection. Pass True/False
        to force it.
        """
        mode = self.api_mode
        if stream is None:
            stream = int(max_output_tokens or 0) > self.LONG_OUTPUT_TOKENS
        effort = self.effort
        system_instruction = _effort.system_with_effort(system_instruction, effort)

        if mode == "google_genai":
            # Google's own endpoint has no such cap and this app talks to it
            # through a separate client, so `stream` doesn't apply here.
            client = GeminiClient(self.api_key, self.model, self.proxy,
                                  base_url=self.base_url, label=self.label)
            return client.generate(prompt, system_instruction, timeout,
                                   max_output_tokens, effort=effort)

        if not self.api_key:
            raise RuntimeError(
                tr("{provider} API key is missing.").format(provider=self.label))

        if self.provider == "custom" and not self.base_url:
            raise RuntimeError(tr("Custom AI base URL is missing."))

        if mode == "anthropic_messages":
            return _anthropic_style_chat(
                self.endpoint(), self.api_key,
                self.model or AI_PROVIDER_DEFAULT_MODEL.get("anthropic", ""),
                prompt, system_instruction, timeout,
                provider_label=self.label, proxy=self.proxy,
                max_tokens=max_output_tokens, stream=stream, effort=effort)

        if mode == "openai_compatible":
            model = self.model
            if not model and self.provider in AI_PROVIDER_DEFAULT_MODEL:
                model = AI_PROVIDER_DEFAULT_MODEL[self.provider]
            return _openai_style_chat(
                self.endpoint(), self.api_key, model, prompt,
                system_instruction, timeout, provider_label=self.label,
                proxy=self.proxy, max_tokens=max_output_tokens, stream=stream,
                effort=effort)

        raise RuntimeError(tr("Unknown AI provider: {p}").format(p=self.provider))
