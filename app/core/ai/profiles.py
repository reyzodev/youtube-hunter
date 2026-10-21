"""app.core.ai.profiles - YouTube Hunter.

AI providers as a LIST of saved profiles, plus "which one does what".

Why this exists
---------------
The old config kept ONE flat set of connection fields (ai_base_url, ai_path,
ai_model, ai_api_mode …) shared by every provider. Switching the picker from a
Custom router to Gemini blanked those fields, so the router's API host was gone
the moment anyone looked at another provider — and it was only ever written to
disk on Save, so leaving the app lost it too. It also meant exactly one custom
endpoint, ever.

Now every provider is its own profile and keeps its own fields forever:

    cfg["ai_profiles"] = [
      {"id": "gemini", "kind": "gemini", "name": "Gemini", "api_key": "…",
       "model": "", "base_url": "", "path": "", "api_mode": "", "models": []},
      {"id": "c-3f9a1b", "kind": "custom", "name": "9router", "api_key": "…",
       "base_url": "https://…/v1", "path": "/chat/completions",
       "api_mode": "openai_compatible", "model": "gpt-5", "models": [...]},
      …
    ]
    cfg["ai_active_profile"] = "c-3f9a1b"          # the default for everything
    cfg["ai_routes"] = {                             # optional per-feature picks
      "ideas":   {"profile": "gemini", "model": "", "effort": "high"},
      "chat":    {"profile": "",       "model": "", "effort": "auto"},
      "reports": {"profile": "",       "model": "", "effort": "auto"},
    }

A route's empty "profile" means "use the active profile"; an empty "model"
means "use that profile's model". The three built-in profiles (OpenAI,
Anthropic, Gemini) always exist; custom ones can be added without limit.

The flat legacy keys (ai_provider, ai_api_key, ai_model …) are still WRITTEN,
mirroring the active profile, so the legacy QWidgets build and anything that
still reads them keeps working. They are only READ once, to migrate a config
written before profiles existed.
"""

import uuid

from app.core.ai.clients import (AI_API_MODES, AI_PROVIDER_DEFAULT_MODEL,
                                 AIClient, api_mode_for)
from app.core.ai.effort import EFFORT_DEFAULT, norm_effort

BUILTIN_KINDS = ("openai", "anthropic", "gemini")
BUILTIN_NAMES = {"openai": "OpenAI", "anthropic": "Anthropic", "gemini": "Gemini"}

# Features that can be pointed at their own provider / model / effort.
FEATURES = ("ideas", "chat", "reports")

# The routes Settings edits. "chat" is owned by the AI Chat composer (it picks
# its own provider / model / effort there), and "reports" is retired with the
# Reports feature — Settings must never overwrite either from a stale copy.
SETTINGS_FEATURES = ("ideas",)

_FIELDS = ("id", "kind", "name", "api_key", "model", "base_url", "path",
           "api_mode", "models", "picked")


def _clean_profile(p):
    if not isinstance(p, dict):
        return None
    kind = str(p.get("kind") or "custom").strip().lower()
    if kind not in BUILTIN_KINDS:
        kind = "custom"
    pid = str(p.get("id") or "").strip() or (kind if kind != "custom" else new_profile_id())
    mode = str(p.get("api_mode") or "").strip()
    if mode not in AI_API_MODES:
        mode = ""
    models = [str(m) for m in (p.get("models") or []) if str(m).strip()]
    model = str(p.get("model") or "").strip()
    # v3.16-p3: `models` is the FETCHED catalogue; `picked` is the short list
    # the user actually added to this provider — the only models AI Chat (and
    # the routing panel) offer. A config from before this field existed
    # starts with just the model it already had.
    raw_picked = p.get("picked")
    if raw_picked is None:
        picked = [model] if model else []
    else:
        picked = [str(m).strip() for m in (raw_picked or []) if str(m).strip()]
    # invariant: the provider's own model is always one of its picked models
    if model and model not in picked:
        picked.insert(0, model)
    out = {
        "id": pid,
        "kind": kind,
        "name": str(p.get("name") or "").strip()
                or BUILTIN_NAMES.get(kind, "Custom"),
        "api_key": str(p.get("api_key") or "").strip(),
        "model": model,
        "base_url": str(p.get("base_url") or "").strip(),
        "path": str(p.get("path") or "").strip(),
        "api_mode": mode,
        "models": list(dict.fromkeys(models))[:400],
        "picked": list(dict.fromkeys(picked))[:100],
    }
    if raw_picked is None:
        out["_legacy_picked"] = True     # load_state folds pinned route models in
    return out


def allowed_models(profile):
    """The models a feature may pin on this profile: what the user added, or
    just the profile's own model when nothing was added."""
    picked = list(profile.get("picked") or [])
    if picked:
        return picked
    eff = effective_model(profile)
    return [eff] if eff else []


def _route_model_ok(state, route):
    """False when a route pins a model its profile no longer offers."""
    m = (route.get("model") or "").strip()
    if not m:
        return True
    prof = find(state, route.get("profile") or "") or find(state, state["active"])
    return prof is None or m in allowed_models(prof)


def new_profile_id():
    return "c-" + uuid.uuid4().hex[:6]


def builtin_profile(kind):
    return _clean_profile({"id": kind, "kind": kind, "name": BUILTIN_NAMES[kind]})


def blank_custom(name="", api_mode="openai_compatible"):
    return _clean_profile({"id": new_profile_id(), "kind": "custom", "name": name,
                           "api_mode": api_mode, "path": ""})


def _default_routes():
    return {f: {"profile": "", "model": "", "effort": EFFORT_DEFAULT} for f in FEATURES}


def _clean_routes(raw):
    out = _default_routes()
    if isinstance(raw, dict):
        for f in FEATURES:
            r = raw.get(f)
            if isinstance(r, dict):
                out[f] = {"profile": str(r.get("profile") or "").strip(),
                          "model": str(r.get("model") or "").strip(),
                          "effort": norm_effort(r.get("effort"))}
    return out


def _migrate_flat(cfg):
    """Profiles for a config written before profiles existed."""
    keys = dict(cfg.get("ai_provider_keys") or {})
    provider = (cfg.get("ai_provider") or "openai").strip().lower()
    if provider in ("claude",):
        provider = "anthropic"
    legacy_key = (cfg.get("ai_api_key") or "").strip()
    profiles = [builtin_profile(k) for k in BUILTIN_KINDS]
    for p in profiles:
        p["api_key"] = (keys.get(p["kind"]) or "").strip()
        if p["kind"] == "anthropic" and not p["api_key"]:
            p["api_key"] = (keys.get("claude") or "").strip()
    active = provider if provider in BUILTIN_KINDS else ""

    flat = {
        "model": (cfg.get("ai_model") or "").strip(),
        "base_url": (cfg.get("ai_base_url") or "").strip(),
        "path": (cfg.get("ai_path") or "").strip(),
        "api_mode": (cfg.get("ai_api_mode") or "").strip(),
    }
    if flat["path"] == "/chat/completions":
        flat["path"] = ""          # the shape's default; keep it implicit

    if provider in BUILTIN_KINDS:
        p = next(x for x in profiles if x["kind"] == provider)
        p.update({k: v for k, v in flat.items() if v})
        if legacy_key and not p["api_key"]:
            p["api_key"] = legacy_key
        # A previously-saved custom router survives as its own profile when its
        # host is still on record (it usually is not — that was the bug).
        if cfg.get("ai_custom_name") and (keys.get("custom") or cfg.get("ai_custom_models")):
            c = blank_custom(cfg.get("ai_custom_name"))
            c["api_key"] = (keys.get("custom") or "").strip()
            c["models"] = [m for m in (cfg.get("ai_custom_models") or []) if m]
            c["model"] = (cfg.get("ai_custom_selected_model") or "").strip()
            profiles.append(_clean_profile(c))
    else:
        # "custom", or a retired name (deepseek): the flat fields ARE the router.
        c = blank_custom(cfg.get("ai_custom_name") or
                         ("DeepSeek" if provider == "deepseek" else ""))
        c.update({k: v for k, v in flat.items() if v})
        if provider == "deepseek" and not c["base_url"]:
            c["base_url"] = "https://api.deepseek.com/v1"
        c["api_mode"] = c["api_mode"] or api_mode_for(provider)
        c["api_key"] = (keys.get(provider) or legacy_key or "").strip()
        c["models"] = [m for m in (cfg.get("ai_custom_models") or []) if m]
        if not c["model"]:
            c["model"] = (cfg.get("ai_custom_selected_model") or "").strip()
        c = _clean_profile(c)
        profiles.append(c)
        active = c["id"]
    return profiles, active or "gemini"


def load_state(cfg):
    """{"profiles": [...], "active": id, "routes": {...}, "proxy": str}"""
    cfg = cfg or {}
    raw = cfg.get("ai_profiles")
    if isinstance(raw, list) and raw:
        profiles = [p for p in (_clean_profile(x) for x in raw) if p]
        # de-dupe ids, then make sure every built-in is present
        seen, uniq = set(), []
        for p in profiles:
            if p["id"] in seen:
                p["id"] = new_profile_id()
            seen.add(p["id"])
            uniq.append(p)
        profiles = uniq
        for k in BUILTIN_KINDS:
            if not any(p["kind"] == k and p["id"] == k for p in profiles):
                profiles.insert(BUILTIN_KINDS.index(k), builtin_profile(k))
        active = str(cfg.get("ai_active_profile") or "").strip()
    else:
        profiles, active = _migrate_flat(cfg)
    if not any(p["id"] == active for p in profiles):
        active = "gemini"
    state = {"profiles": profiles, "active": active,
             "routes": _clean_routes(cfg.get("ai_routes")),
             "proxy": (cfg.get("ai_proxy") or "").strip()}
    # A config from before `picked` existed: a model a feature was already
    # pinned to (e.g. the chat composer's pick) stays on that profile's list,
    # so upgrading never silently changes which model answers.
    for r in state["routes"].values():
        m = (r.get("model") or "").strip()
        if not m:
            continue
        prof = find(state, r.get("profile") or "") or find(state, active)
        if prof and prof.get("_legacy_picked") and m not in prof["picked"]:
            prof["picked"].append(m)
    for p in profiles:
        p.pop("_legacy_picked", None)
    return state


def find(state, pid):
    for p in state["profiles"]:
        if p["id"] == pid:
            return p
    return None


def provider_of(profile):
    """The AIClient `provider` a profile maps to."""
    return profile["kind"] if profile["kind"] in BUILTIN_KINDS else "custom"


def effective_model(profile, override=""):
    return (override or profile.get("model") or
            AI_PROVIDER_DEFAULT_MODEL.get(provider_of(profile), "") or "").strip()


def write_state(cfg, state):
    """Put `state` into `cfg` (in place) — profiles, routes AND the legacy flat
    mirror of the active profile. Returns cfg."""
    cfg["ai_profiles"] = [{k: p.get(k) for k in _FIELDS} for p in state["profiles"]]
    cfg["ai_active_profile"] = state["active"]
    cfg["ai_routes"] = state["routes"]
    cfg["ai_proxy"] = state.get("proxy", "")
    act = find(state, state["active"]) or state["profiles"][0]
    prov = provider_of(act)
    keys = dict(cfg.get("ai_provider_keys") or {})
    for p in state["profiles"]:
        if p["kind"] in BUILTIN_KINDS:
            keys[p["kind"]] = p["api_key"]
    if prov == "custom":
        keys["custom"] = act["api_key"]
    cfg.update({
        "ai_provider": prov,
        "ai_api_key": act["api_key"],
        "ai_provider_keys": keys,
        "ai_model": effective_model(act),
        "ai_base_url": act["base_url"],
        "ai_path": act["path"] or "/chat/completions",
        "ai_api_mode": act["api_mode"],
        "ai_custom_name": act["name"] if prov == "custom" else cfg.get("ai_custom_name", ""),
    })
    return cfg


def resolve(feature=None, cfg=None):
    """Everything a feature needs to build its client, as a flat dict:
    provider, api_key, model, base_url, path, proxy, custom_name, api_mode,
    effort, profile_id, profile_name."""
    if cfg is None:
        from app.config import load_app_config
        cfg = load_app_config()
    state = load_state(cfg)
    route = state["routes"].get(feature or "", {}) if feature else {}
    prof = find(state, route.get("profile") or "") or find(state, state["active"]) \
        or state["profiles"][0]
    prov = provider_of(prof)
    # a pinned model the user has since removed from the provider → its own
    r_model = route.get("model", "") if (route and _route_model_ok(state, route)) else ""
    return {
        "provider": prov,
        "api_key": prof["api_key"],
        "model": effective_model(prof, r_model),
        "base_url": prof["base_url"],
        "path": prof["path"] or "/chat/completions",
        "proxy": state["proxy"],
        "custom_name": prof["name"] if prov == "custom" else "",
        "api_mode": prof["api_mode"],
        "effort": norm_effort(route.get("effort")),
        "profile_id": prof["id"],
        "profile_name": prof["name"],
    }


def client_from(r):
    """AIClient from a resolve() dict."""
    return AIClient(r["provider"], r["api_key"], r["model"], r["base_url"],
                    r["proxy"], path=r["path"], custom_name=r["custom_name"] or None,
                    api_mode=r["api_mode"] or None, effort=r.get("effort"))


def make_client(feature=None, cfg=None):
    return client_from(resolve(feature, cfg))


def is_ready(r):
    """Configured enough to try a call."""
    if r["provider"] == "custom":
        # a self-hosted gateway may need no key; a host is the minimum
        return bool(r["base_url"].strip())
    return bool(r["api_key"].strip())


def merge_foreign_routes(state, cfg):
    """Before Settings writes its in-memory `state`, take every route it does
    NOT own (see SETTINGS_FEATURES) from what is on disk, so a pick made in
    the AI Chat is never clobbered. A route pointing at a profile that no
    longer exists falls back to the default. Mutates and returns `state`."""
    try:
        disk = load_state(cfg)["routes"]
    except Exception:          # noqa: BLE001
        return state
    ids = {p["id"] for p in state["profiles"]}
    for f in FEATURES:
        if f in SETTINGS_FEATURES:
            continue
        if f == "reports":
            # retired from the UI: whatever is left of it follows the default
            state["routes"][f] = {"profile": "", "model": "", "effort": EFFORT_DEFAULT}
            continue
        r = dict(disk.get(f) or {})
        if r.get("profile") and r["profile"] not in ids:
            r["profile"], r["model"] = "", ""
        if not _route_model_ok(state, r):
            r["model"] = ""        # that model was removed from its provider
        state["routes"][f] = {"profile": r.get("profile", ""),
                              "model": r.get("model", ""),
                              "effort": norm_effort(r.get("effort"))}
    return state


def set_route_target(feature, profile_id, model="", cfg=None):
    """Point one feature at a profile AND one of its models in a single write
    (the AI Chat's model list uses this). Returns the new route dict."""
    from app.config import load_app_config, save_app_config
    if feature not in FEATURES:
        return None
    cfg = load_app_config() if cfg is None else cfg
    state = load_state(cfg)
    pid = str(profile_id or "").strip()
    if pid and not find(state, pid):
        pid = ""
    state["routes"][feature]["profile"] = pid
    state["routes"][feature]["model"] = str(model or "").strip() if pid else ""
    write_state(cfg, state)
    save_app_config(cfg)
    return state["routes"][feature]


def update_route(feature, field, value, cfg=None):
    """Write one route field straight to disk (the chat's effort chip uses
    this). Returns the new route dict."""
    from app.config import load_app_config, save_app_config
    if feature not in FEATURES or field not in ("profile", "model", "effort"):
        return None
    cfg = load_app_config() if cfg is None else cfg
    state = load_state(cfg)
    value = str(value or "").strip()
    if field == "effort":
        value = norm_effort(value)
    state["routes"][feature][field] = value
    if field == "profile":
        state["routes"][feature]["model"] = ""
    write_state(cfg, state)
    save_app_config(cfg)
    return state["routes"][feature]
