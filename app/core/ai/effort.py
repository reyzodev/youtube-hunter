"""app.core.ai.effort - YouTube Hunter.

"How hard should the AI think?" — one setting, five levels, translated into
whatever each wire shape actually understands.

    auto    send nothing extra; the provider's own default
    low     fast and cheap: the shortest answer that does the job
    medium  balanced
    high    reason carefully, be thorough
    max     the most the model offers

Two layers, so the setting means something on EVERY model:

  1. A short line added to the system instruction. Works everywhere, including
     plain chat models that have no reasoning switch at all.
  2. The provider's native reasoning knob, only where the model has one:
       OpenAI-shaped   reasoning models (o1/o3/o4/gpt-5/gpt-oss)  reasoning_effort
                       OpenRouter                               reasoning.effort
       Anthropic       Claude 3.7 / 4.x                         thinking.budget_tokens
       Google          Gemini 2.5                               thinkingConfig.thinkingBudget
                       Gemini 3                                 thinkingConfig.thinkingLevel

Native knobs are the part that can be wrong for a given router or model id, so
every caller that applies them also keeps a clean body and retries ONCE without
them when the server answers 400/422 (see `should_retry_plain`). A user who
picks "High" on a model that cannot reason therefore still gets an answer, not
an error.
"""

import re

EFFORT_LEVELS = ("auto", "low", "medium", "high", "max")
EFFORT_DEFAULT = "auto"

EFFORT_LABELS = {
    "auto": "Auto",
    "low": "Low",
    "medium": "Medium",
    "high": "High",
    "max": "Max",
}
EFFORT_HINTS = {
    "auto": "The model's own default.",
    "low": "Fastest and cheapest. Short, direct answers.",
    "medium": "Balanced speed and depth.",
    "high": "Thinks it through. Slower, more thorough.",
    "max": "Everything the model has. Slowest, deepest.",
}


def norm_effort(value):
    v = str(value or "").strip().lower()
    return v if v in EFFORT_LEVELS else EFFORT_DEFAULT


# ── layer 1: the instruction ───────────────────────────────────────────────
_SYSTEM_LINES = {
    "low": ("Response effort: LOW. Be efficient — give the shortest complete "
            "answer that fully does the job. No preamble."),
    "high": ("Response effort: HIGH. Think the problem through carefully before "
             "answering, check your reasoning against the data you were given, "
             "and be thorough and specific."),
    "max": ("Response effort: MAXIMUM. Reason step by step privately, weigh "
            "alternatives, verify every claim against the data you were given, "
            "and give the most complete and specific answer you can. Do not cut "
            "corners for length."),
}


def system_with_effort(system, effort):
    """`system` plus the effort line (or `system` unchanged for auto/medium)."""
    line = _SYSTEM_LINES.get(norm_effort(effort), "")
    if not line:
        return system
    return (system.rstrip() + "\n\n" + line) if system else line


# ── model families ─────────────────────────────────────────────────────────
def _base(model):
    return str(model or "").split("/")[-1].strip().lower()


def is_openai_reasoning(model):
    """OpenAI's reasoning families reject `temperature` and, on api.openai.com,
    want `max_completion_tokens`. Matched on the last id segment so a routed id
    ("openai/gpt-5") counts too."""
    b = _base(model)
    return b.startswith(("o1", "o3", "o4", "gpt-5", "gpt-oss"))


_CLAUDE_THINKING_RE = re.compile(r"claude-(?:3-7|opus-4|sonnet-4|haiku-4|4)")


def claude_can_think(model):
    return bool(_CLAUDE_THINKING_RE.search(_base(model)))


def gemini_thinking_kind(model):
    """"budget" for Gemini 2.5, "level" for Gemini 3, "" for anything else."""
    b = _base(model)
    if "gemini-3" in b:
        return "level"
    if "2.5" in b:
        return "budget"
    return ""


_OPENAI_EFFORT = {"low": "low", "medium": "medium", "high": "high", "max": "high"}
_CLAUDE_BUDGET = {"low": 1024, "medium": 4000, "high": 10000, "max": 24000}
_GEMINI_BUDGET = {"low": 512, "medium": 4096, "high": 12288, "max": 24576}


# ── layer 2: the native knobs ──────────────────────────────────────────────
def apply_openai(body, model, effort, host=""):
    """Mutates an OpenAI-shaped body. Returns True if a native knob was added
    (so the caller knows a plain retry is worth trying on a 400)."""
    e = norm_effort(effort)
    if e == "auto" or not is_openai_reasoning(model):
        return False
    if "openrouter" in str(host or "").lower():
        body["reasoning"] = {"effort": _OPENAI_EFFORT[e]}
    else:
        body["reasoning_effort"] = _OPENAI_EFFORT[e]
    return True


def apply_anthropic(body, model, effort):
    """Extended thinking. Thinking tokens come out of max_tokens, so the budget
    is ADDED on top of what the caller asked for, and temperature has to go
    (thinking only runs at the default)."""
    e = norm_effort(effort)
    if e == "auto" or not claude_can_think(model):
        return False
    budget = _CLAUDE_BUDGET[e]
    body["thinking"] = {"type": "enabled", "budget_tokens": budget}
    body["max_tokens"] = int(body.get("max_tokens") or 0) + budget
    body.pop("temperature", None)
    body.pop("top_p", None)
    return True


def apply_gemini(body, model, effort):
    e = norm_effort(effort)
    kind = gemini_thinking_kind(model)
    if e == "auto" or not kind:
        return False
    gc = body.setdefault("generationConfig", {})
    if kind == "level":
        gc["thinkingConfig"] = {"thinkingLevel": "low" if e == "low" else "high"}
    else:
        budget = _GEMINI_BUDGET[e]
        gc["thinkingConfig"] = {"thinkingBudget": budget}
        # Gemini counts thinking against maxOutputTokens: give it its own room.
        gc["maxOutputTokens"] = min(65536, int(gc.get("maxOutputTokens") or 0) + budget)
    return True


def should_retry_plain(http_code):
    """A 400/422 after adding a native knob most likely means "this model or
    router does not take that parameter" — worth one retry without it."""
    try:
        return int(http_code) in (400, 422)
    except (TypeError, ValueError):
        return False
