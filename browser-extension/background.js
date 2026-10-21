// YouTube Hunter — background service worker.
//
// The ONLY place that talks to the desktop app. Content scripts run with
// youtube.com's origin, and the app's local bridge deliberately refuses any
// web origin; requests made from here carry the extension's own
// chrome-extension:// origin, which the bridge accepts. See
// app/qml_backend/web_bridge.py in the app for the other half.

const BRIDGE = "http://127.0.0.1:47391";
// v1.1.3: identifies the caller as the extension. Chrome sends no Origin
// header on a plain GET from a service worker to a host it has permission
// for, so the app could not tell us apart from its own probe and its setup
// guide stayed on "Waiting for the extension" forever.
const CLIENT = "ext/" + ((chrome.runtime.getManifest && chrome.runtime.getManifest().version) || "1");

async function bridge({ method = "GET", path, body, timeout = 8000 }) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeout);
  try {
    const res = await fetch(BRIDGE + path, {
      method,
      headers: Object.assign(
        { "X-YTH-Bridge": "1", "X-YTH-Client": CLIENT },
        body ? { "Content-Type": "application/json" } : {}
      ),
      body: body ? JSON.stringify(body) : undefined,
      signal: ctl.signal,
      cache: "no-store",
    });
    let data = null;
    try { data = await res.json(); } catch (_) { data = null; }
    return { reachable: true, status: res.status, data };
  } catch (err) {
    // connection refused / timeout = the app isn't running (or is busy)
    return { reachable: false, status: 0, data: null,
             error: err && err.name === "AbortError" ? "timeout" : "offline" };
  } finally {
    clearTimeout(timer);
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (!msg || msg.type !== "yth-bridge") return false;
  bridge(msg).then(reply);
  return true; // keep the channel open for the async reply
});

// v3.43: tell the desktop app "I'm installed" the moment Chrome loads the
// extension (Load unpacked / drag-and-drop / update), so its setup guide
// turns green without the user having to open YouTube first.
chrome.runtime.onInstalled.addListener(() => {
  bridge({ path: "/v1/ping", timeout: 2000 });
});
chrome.runtime.onStartup.addListener(() => {
  bridge({ path: "/v1/ping", timeout: 2000 });
});

// v1.1.3: also say hello every time the service worker wakes up (Chrome
// starts it for any message, a YouTube tab, an update…). onInstalled fires
// once; if the app was closed at that moment the ping was lost and the
// guide waited until the next browser restart.
bridge({ path: "/v1/ping", timeout: 2000 });
