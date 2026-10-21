"""app.config - Youtube Scrapper."""

import json
import os
import sys

def _get_config_path():
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support")
    else:
        base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    cfg_dir = os.path.join(base, "YoutubeScrapperCyber")
    try:
        os.makedirs(cfg_dir, exist_ok=True)
    except Exception:
        cfg_dir = os.path.expanduser("~")
    return os.path.join(cfg_dir, "config.json")


CONFIG_PATH = _get_config_path()
def load_app_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_app_config(data):
    """Write the config atomically: serialise into a unique temp file next to
    it, then os.replace() it over the real one. Opening config.json with "w"
    truncated it first, so a crash / kill / full disk mid-write left a broken
    file that load_app_config() then read as {} (every setting "lost")."""
    import tempfile
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(
            prefix=".config-", suffix=".tmp", dir=os.path.dirname(CONFIG_PATH))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.replace(tmp_path, CONFIG_PATH)
            tmp_path = None
        except PermissionError:
            # Windows: an AV scanner / another reader can briefly lock the
            # target; fall back to the old direct write rather than lose it
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass
    finally:
        if tmp_path:
            try:
                os.remove(tmp_path)
            except Exception:
                pass
