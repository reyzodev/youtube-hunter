// YouTube Hunter — content script (youtube.com).
//
// 1. Puts a YouTube Hunter button (the crown mark with its play triangle
//    turned into a download arrow) next to Like / Share on every watch page,
//    and on the Shorts action rail.
// 2. Clicking it opens a panel in the TOP-RIGHT corner of the tab: the
//    qualities this video really has (the desktop app's own probe), a size
//    ladder, and one Download button. The desktop app downloads in the
//    background — its window never has to come up — and the picked rung of the
//    ladder fills as the download progresses.
//    v3.44: the panel STAYS open after Download — the button itself turns
//    into the live progress capsule (percent, speed, size, time left, ⏸ / ▶).
//    Close the panel and the desktop app's live card takes over; nothing is
//    lost either way. The panel now wears the APP's theme, not YouTube's.
//
// 3. v3.43c — CUT. The same panel has a Cut tab: mark an In and an Out on the
//    video you're watching (drag the handles, type a timecode, or press [ / ]
//    at the playhead), pick a quality, and the desktop app cuts just that
//    segment — the full video is never downloaded. The marked range is also
//    painted onto YouTube's own progress bar, and dragging a handle scrubs the
//    real player, so you choose the cut by the frame you see.
//
// Everything is rendered inside shadow roots, so YouTube's CSS can't reach in
// and ours can't leak out.

(() => {
  "use strict";
  if (window.__ythLoaded) return;
  window.__ythLoaded = true;
  console.debug("[YouTube Hunter] content script loaded");

  const ASSET = (p) => chrome.runtime.getURL(p);
  // The panel's stylesheet, read once up front and inlined into the shadow
  // root (a <link> there loads async, so the panel would flash unstyled).
  let PANEL_CSS = "";
  fetch(ASSET("panel.css")).then((r) => r.text()).then((x) => { PANEL_CSS = x; }).catch(() => {});
  const STORE_KEY = "yth.lastQuality";

  // ── i18n ──────────────────────────────────────────────────────────────
  // The panel follows the APP's language (from /v1/ping); before the app has
  // answered, it follows the browser.
  const STR = {
    en: {
      button: "Hunter",
      buttonTip: "Download with YouTube Hunter",
      close: "Close",
      connecting: "Connecting to YouTube Hunter…",
      offTitle: "YouTube Hunter isn't running",
      offBody: "Start it and your download begins right here. It opens minimised, so you stay on YouTube.",
      offStart: "Start YouTube Hunter",
      offWaking: "Starting YouTube Hunter…",
      offWakeFail: "Still no answer. Open YouTube Hunter yourself, then try again.",
      retry: "Try again",
      reading: "Reading the formats this video really has…",
      standard: "Couldn't read this video's formats, so these are the standard options.",
      audio: "Audio",
      download: "Download",
      sending: "Sending to YouTube Hunter…",
      preparing: "Preparing…",
      left: "left",
      keepGoing: "Keeps going in YouTube Hunter if you close this.",
      done: "Saved",
      doneBody: "It's in your Downloads.",
      showFolder: "Show in folder",
      openApp: "Open YouTube Hunter",
      failed: "Download failed",
      stopped: "Stopped in YouTube Hunter",
      already: "Already downloading in YouTube Hunter",
      noVideo: "Open a video first.",
      shorts: "Short",
      unknownSize: "size on download",
      // v3.43c
      againQuality: "Pick another quality to save it too.",
      savedTag: "saved",
      // v3.45 — formats, dubs, ▶ Play
      play: "Play",
      playTip: "Open the saved file in your player",
      playFail: "Couldn't find that file. It may have been moved or deleted.",
      fmtVideo: "Video format",
      fmtAudio: "Audio format",
      audioTrack: "Audio track",
      trackOriginal: "Original",
      trackDub: "dubbed",
      trackAuto: "auto-dubbed",
      savedHere: "Already saved. Play it, or pick another quality / format.",
      audioCutNote: "Audio only: the selected track is cut without video.",
      audioOnly: "Audio only",
      audioOnlySub: "No picture, just the sound",
      video: "Video",
      parkedTag: "paused",
      videoCutNote: "Video cut keeps audio. Choose the output container above.",
      tabDownload: "Download",
      tabCut: "Cut",
      cutTip: "Cut a clip with YouTube Hunter",
      cutLabel: "Cut",
      markIn: "In",
      markOut: "Out",
      setIn: "In here",
      setOut: "Out here",
      preview: "Preview",
      stopPreview: "Stop",
      clipLen: "clip",
      quality: "Quality",
      cutBtn: "Cut clip",
      cutting: "Cutting…",
      cutSending: "Sending the cut to YouTube Hunter…",
      cutStop: "Stop",
      cutSaved: "Clip saved",
      cutSavedBody: "In your Videos folder and Video Cutter's Clips.",
      newCut: "New cut",
      openCutter: "Open Video Cutter",
      cutFailed: "Cut failed",
      cutStopped: "Cut stopped.",
      cutNeedsUpdate: "Update YouTube Hunter on your PC to cut from YouTube.",
      cutLost: "Lost track of this cut. It may still finish — check the Clips list in the app.",
      adShowing: "An ad is playing. The editor opens as soon as the video starts.",
      liveStream: "Live streams can't be cut while they're still live.",
      noPlayer: "Start the video so the editor can read its length.",
      keyframe: "Lossless cut: it lands on the nearest keyframe, usually within a second.",
      keysHint: "[ and ] mark In / Out at the playhead",
      // v3.44 — live download capsule
      dlDownloading: "Downloading",
      dlStarting: "Starting…",
      dlPausing: "Pausing…",
      dlPaused: "Paused",
      dlResuming: "Resuming…",
      dlFinishing: "Finishing up…",
      pause: "Pause",
      resume: "Resume",
      speed: "speed",
      ofTotal: "of {t}",
      sizeSoFar: "so far",
      etaWait: "estimating",
      pausedNote: "Paused. Resume here, or later from Downloads in YouTube Hunter.",
      // v3.48 — UX pass
      output: "Output",
      zoomClip: "Zoom to clip",
      zoomAll: "Whole video",
      cutKeep: "Keeps cutting in YouTube Hunter if you close this.",
    },
  };
  // English only: the panel does not switch language.
  const lang = "en";
  const t = (k) => (STR[lang] && STR[lang][k]) || STR.en[k] || k;

  // ── fonts (document-level, so the shadow roots can use them) ──────────
  (function loadFonts() {
    const faces = [
      ["YTH Hanken", "fonts/HankenGrotesk.ttf", { weight: "100 900" }],
      ["YTH Mono", "fonts/JetBrainsMono-Regular.ttf", { weight: "100 800" }],
      ["YTH Vazir", "fonts/Vazirmatn-Regular.ttf", { weight: "400" }],
      ["YTH Vazir", "fonts/Vazirmatn-Medium.ttf", { weight: "500" }],
      ["YTH Vazir", "fonts/Vazirmatn-SemiBold.ttf", { weight: "600" }],
      ["YTH Vazir", "fonts/Vazirmatn-Bold.ttf", { weight: "700" }],
    ];
    for (const [fam, file, desc] of faces) {
      try {
        const f = new FontFace(fam, `url("${ASSET(file)}")`, desc);
        document.fonts.add(f);
        f.load().catch(() => {});
      } catch (_) { /* fonts are a nicety */ }
    }
  })();

  // ── bridge (through the service worker) ───────────────────────────────
  function call(path, { method = "GET", body, timeout } = {}) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(
          { type: "yth-bridge", method, path, body, timeout },
          (res) => {
            if (chrome.runtime.lastError || !res) {
              resolve({ reachable: false, status: 0, data: null, error: "extension" });
            } else resolve(res);
          }
        );
      } catch (_) {
        // "Extension context invalidated" after the extension was reloaded
        resolve({ reachable: false, status: 0, data: null, error: "extension" });
      }
    });
  }

  // ── page helpers ──────────────────────────────────────────────────────
  function currentVideo() {
    const u = new URL(location.href);
    if (u.pathname === "/watch" && u.searchParams.get("v")) {
      return { id: u.searchParams.get("v"), short: false };
    }
    const m = u.pathname.match(/^\/shorts\/([A-Za-z0-9_-]{11})/);
    if (m) return { id: m[1], short: true };
    return null;
  }

  function pageMeta() {
    const pick = (sels) => {
      for (const s of sels) {
        const el = document.querySelector(s);
        const v = el && (el.textContent || "").trim();
        if (v) return v;
      }
      return "";
    };
    let title = pick([
      "ytd-watch-metadata h1 yt-formatted-string",
      "ytd-watch-metadata #title h1",
      "ytd-reel-video-renderer[is-active] h2",
      "ytd-reel-video-renderer[is-active] .ytShortsVideoTitleViewModelShortsVideoTitle",
    ]);
    if (!title) title = (document.title || "").replace(/\s*-\s*YouTube\s*$/, "");
    const channel = pick([
      "ytd-watch-metadata ytd-channel-name a",
      "ytd-watch-metadata #owner #channel-name a",
      "ytd-reel-video-renderer[is-active] .ytReelChannelBarViewModelChannelName a",
      "ytd-reel-video-renderer[is-active] ytd-channel-name a",
    ]);
    return { title, channel };
  }

  // YouTube marks its dark theme with a `dark` attribute on <html>.
  const isDark = () => document.documentElement.hasAttribute("dark");

  // ── the brand mark ────────────────────────────────────────────────────
  // Same geometry as app/ui/brand.py (738 × 812 design box). The play
  // triangle becomes a download arrow: the app's icon, "combined with download".
  let markSeq = 0;
  function markSVG(size, arrow = true) {
    const id = "m" + (++markSeq);
    const inner = arrow
      ? '<polygon points="352,338 386,338 386,418 424,418 369,486 314,418 352,418" fill="#fff"/>'
      : '<polygon points="324,351 427,422 324,493" fill="#fff"/>';
    return `<svg class="mark" width="${size}" height="${size}" viewBox="-37 0 812 812" aria-hidden="true">
      <defs>
        <linearGradient id="${id}c" x1="0" y1="0" x2="0" y2="812" gradientUnits="userSpaceOnUse">
          <stop offset="0" style="stop-color:var(--acc)"/><stop offset=".4" style="stop-color:var(--acc2)"/>
          <stop offset=".78" style="stop-color:var(--acc-deep)"/><stop offset="1" style="stop-color:var(--acc-deeper)"/>
        </linearGradient>
        <linearGradient id="${id}p" x1="0" y1="240" x2="0" y2="804" gradientUnits="userSpaceOnUse">
          <stop offset="0" style="stop-color:var(--acc)"/><stop offset=".45" style="stop-color:var(--acc2)"/>
          <stop offset="1" style="stop-color:var(--acc-deep)"/>
        </linearGradient>
      </defs>
      <polygon points="156,240 231,322 231,444 310,524 318,662 363,804 156,526" fill="url(#${id}p)"/>
      <polygon points="582,526 375,804 420,662 428,524 507,444 507,322 582,240" fill="url(#${id}p)"/>
      <polygon points="0,0 304,146 304,260 369,304 434,260 434,146 738,0 475,307 475,477 418,532 410,662 369,812 328,662 320,532 263,477 263,307" fill="url(#${id}c)"/>
      ${inner}
    </svg>`;
  }

  // scissors — two rings and two blades, drawn on the same 24 grid as the
  // app's remixicon set so it sits with the crown without looking borrowed.
  function scissorsSVG(size) {
    return `<svg class="sc" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="6" cy="17.5" r="3" fill="none" stroke="currentColor" stroke-width="2"/>
      <circle cx="6" cy="6.5" r="3" fill="none" stroke="currentColor" stroke-width="2"/>
      <path d="M8.4 15.6L20 5M8.4 8.4L20 19" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
    </svg>`;
  }

  // ── accent (follows the app's accent once it has answered) ────────────
  let accent = { a: "#FF1F44", b: "#CC0026" };
  // v3.44: the app's own theme (mode + palette, from /v1/ping). Remembered,
  // so the panel opens in the app's colours even before the app answers.
  const THEME_KEY = "yth.appTheme";
  let appTheme = null;
  try {
    chrome.storage.local.get(THEME_KEY).then((x) => {
      const v = x && x[THEME_KEY];
      if (v && v.mode && !appTheme) { appTheme = v; if (v.accent) accent = v.accent; Panel.retheme(); }
    }).catch(() => {});
  } catch (_) { /* storage is a nicety */ }
  function hexToRgb(h) {
    const m = String(h || "").replace("#", "").match(/^([0-9a-f]{6})$/i);
    if (!m) return [255, 31, 68];
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function shade(h, k) {
    const [r, g, b] = hexToRgb(h);
    return `rgb(${Math.round(r * k)},${Math.round(g * k)},${Math.round(b * k)})`;
  }
  function applyVars(el) {
    const [r, g, b] = hexToRgb(accent.a);
    el.style.setProperty("--acc", accent.a);
    el.style.setProperty("--acc2", accent.b);
    el.style.setProperty("--acc-deep", shade(accent.a, 0.38));
    el.style.setProperty("--acc-deeper", shade(accent.a, 0.19));
    el.style.setProperty("--acc-rgb", `${r},${g},${b}`);
  }

  // ── formatting ────────────────────────────────────────────────────────
  const bytes = (n) => {
    if (!n || n <= 0) return "";
    const u = ["B", "KB", "MB", "GB"];
    let v = n, i = 0;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
  };
  const clock = (s) => {
    s = Math.max(0, Math.round(s || 0));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0");
  };
  // timecode with tenths — what the cut editor shows and accepts
  const tc = (s) => {
    s = Math.max(0, Number(s) || 0);
    const whole = Math.floor(s), tenth = Math.floor((s - whole) * 10 + 1e-6);
    return clock(whole) + "." + tenth;
  };
  // "1:23.4", "01:02:03", "83", "83.5", Persian digits too → seconds (NaN if junk)
  const parseTc = (txt) => {
    const s = String(txt || "").trim()
      .replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)))
      .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
      .replace(/[٫,]/g, ".").replace(/[：]/g, ":");
    if (!/^\d+(?::\d{1,2}){0,2}(?:\.\d+)?$/.test(s)) return NaN;
    return s.split(":").reduce((acc, part) => acc * 60 + parseFloat(part), 0);
  };
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // ═════════════════════════════════════════════════════════════════════
  //  The in-page button
  // ═════════════════════════════════════════════════════════════════════
  const BTN_CSS = `
    :host { all: initial; display: inline-flex; align-items: center; }
    .pill {
      display: inline-flex; align-items: stretch; height: 36px; border-radius: 18px;
      background: var(--chip); overflow: hidden;
      font: 500 14px/36px Roboto, "YTH Vazir", Arial, sans-serif; color: var(--fg);
      -webkit-font-smoothing: antialiased;
    }
    button {
      all: unset; box-sizing: border-box; cursor: pointer;
      display: inline-flex; align-items: center; gap: 7px;
      height: 36px; padding: 0 13px 0 11px;
      color: inherit; white-space: nowrap;
      transition: background .15s ease;
    }
    .cut { padding: 0 12px 0 10px; position: relative; }
    .cut::before {
      content: ""; position: absolute; inset-inline-start: 0; top: 8px; bottom: 8px;
      width: 1px; background: var(--sep);
    }
    button:hover { background: var(--chip-hover); }
    button:active .mark, button:active .sc { transform: scale(.9); }
    button:focus-visible { outline: 2px solid var(--acc); outline-offset: -2px; border-radius: 18px; }
    button[aria-expanded="true"] { background: rgba(var(--acc-rgb), .16); color: var(--acc-text); }
    .mark { display: block; flex: none; filter: drop-shadow(0 1px 1.5px rgba(0,0,0,.25)); transition: transform .15s ease; }
    .sc { display: block; flex: none; transition: transform .15s ease; }
    button.dl:hover .mark { animation: nudge .5s cubic-bezier(.3,1.6,.5,1); }
    button.cut:hover .sc { animation: snip .45s cubic-bezier(.3,1.6,.5,1); }
    button.cut[aria-expanded="true"] .sc { color: var(--acc); }
    @keyframes nudge { 40% { transform: translateY(2px); } }
    @keyframes snip { 35% { transform: rotate(-14deg) scale(.92); } 70% { transform: rotate(4deg); } }
    :host([round]) .pill { flex-direction: column; height: auto; background: none; border-radius: 0; gap: 14px; overflow: visible; }
    :host([round]) button {
      flex-direction: column; gap: 4px; height: auto; padding: 0;
      font-size: 12px; line-height: 16px; background: none;
    }
    :host([round]) .cut::before { display: none; }
    :host([round]) .disc {
      width: 48px; height: 48px; border-radius: 50%; display: grid; place-items: center;
      background: var(--chip); transition: background .15s ease;
    }
    :host([round]) button:hover .disc { background: var(--chip-hover); }
    :host([round]) button[aria-expanded="true"] .disc { background: rgba(var(--acc-rgb), .22); }
    @media (prefers-reduced-motion: reduce) { .mark, .sc { animation: none !important; } }
  `;

  function themeButton(host) {
    const dark = isDark();
    host.style.setProperty("--fg", dark ? "#f1f1f1" : "#0f0f0f");
    host.style.setProperty("--chip", dark ? "rgba(255,255,255,.1)" : "rgba(0,0,0,.05)");
    host.style.setProperty("--chip-hover", dark ? "rgba(255,255,255,.2)" : "rgba(0,0,0,.1)");
    host.style.setProperty("--sep", dark ? "rgba(255,255,255,.18)" : "rgba(0,0,0,.14)");
    host.style.setProperty("--acc-text", dark ? "#fff" : "#0f0f0f");
    applyVars(host);
  }

  // One host, two halves: [ crown Hunter | scissors Cut ]. A single host keeps
  // the insertion logic below unchanged (one element to find / re-insert).
  function makeButton(round) {
    const host = document.createElement("yth-hunter-button");
    host.style.marginInlineStart = round ? "0" : "8px";
    if (round) {
      host.setAttribute("round", "");
      host.style.margin = "0 0 16px";
    }
    const root = host.attachShadow({ mode: "open" });
    root.innerHTML = `<style>${BTN_CSS}</style>
      <span class="pill">
        <button class="dl" type="button" data-mode="download" aria-haspopup="dialog" aria-expanded="false" title="${esc(t("buttonTip"))}">
          ${round ? `<span class="disc">${markSVG(26)}</span>` : markSVG(20)}
          <span class="lbl">${esc(t("button"))}</span>
        </button>
        <button class="cut" type="button" data-mode="cut" aria-haspopup="dialog" aria-expanded="false" title="${esc(t("cutTip"))}" aria-label="${esc(t("cutTip"))}">
          ${round ? `<span class="disc">${scissorsSVG(22)}</span><span class="lbl2">${esc(t("cutLabel"))}</span>` : scissorsSVG(18)}
        </button>
      </span>`;
    themeButton(host);
    root.querySelectorAll("button").forEach((b) => b.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      Panel.toggle(host, b.getAttribute("data-mode"));
    }));
    return host;
  }

  function relabelButtons() {
    document.querySelectorAll("yth-hunter-button").forEach((h) => {
      const r = h.shadowRoot;
      if (!r) return;
      const dl = r.querySelector("button.dl"), ct = r.querySelector("button.cut");
      if (dl) { dl.title = t("buttonTip"); r.querySelector(".lbl").textContent = t("button"); }
      if (ct) {
        ct.title = t("cutTip"); ct.setAttribute("aria-label", t("cutTip"));
        const l2 = r.querySelector(".lbl2"); if (l2) l2.textContent = t("cutLabel");
      }
      themeButton(h);
    });
  }

  // Where the button goes. YouTube re-renders these rows freely, so this runs
  // from a (debounced) MutationObserver and simply re-inserts when missing.
  const WATCH_TARGETS = [
    "ytd-watch-metadata #actions #top-level-buttons-computed",
    "ytd-watch-metadata #top-level-buttons-computed",
    "ytd-watch-metadata #actions-inner #menu",
    "ytd-watch-metadata #actions-inner",
    "ytd-watch-metadata #actions",
    "#above-the-fold #top-level-buttons-computed",
    "#top-level-buttons-computed",
  ];
  const SHORTS_TARGETS = [
    "ytd-reel-video-renderer[is-active] #actions",
    "ytd-reel-video-renderer[is-active] reel-action-bar-view-model",
    "ytd-shorts [is-active] #actions",
    "ytd-shorts reel-action-bar-view-model",
  ];

  // YouTube keeps hidden duplicates of these rows in the DOM (old layouts,
  // the miniplayer, inactive Shorts), so querySelector() often lands on an
  // invisible copy. Always pick the first match that is actually on screen.
  const isShown = (el) => !!el && el.isConnected && el.getClientRects().length > 0
    && getComputedStyle(el).visibility !== "hidden";
  // v3.48: rows that LOOK like the watch actions row but aren't. The open
  // playlist / Mix panel has its own #top-level-buttons-computed (in its
  // header menu), and the bare fallback selector used to land the button
  // there whenever the playlist was open. Never insert into these.
  const NOT_HERE = [
    "ytd-playlist-panel-renderer", "#playlist", "#secondary", "#related",
    "ytd-engagement-panel-section-list-renderer", "ytd-miniplayer",
    "ytd-menu-popup-renderer", "tp-yt-iron-dropdown", "ytd-comments",
  ].join(",");
  const badSpot = (el) => !!(el && el.closest && el.closest(NOT_HERE));
  function findVisible(selectors) {
    for (const sel of selectors) {
      for (const el of document.querySelectorAll(sel)) {
        if (isShown(el) && !badSpot(el)) return el;
      }
    }
    return null;
  }
  const ownsVisibleButton = (round) => [...document.querySelectorAll("yth-hunter-button")]
    .some((h) => h.hasAttribute("round") === round && isShown(h) && !badSpot(h));

  function ensureButton() {
    const vid = currentVideo();
    if (!vid) return;
    if (!vid.short) {
      const row = findVisible(WATCH_TARGETS);
      // already in the best row there is (or nothing better exists yet)
      const mine = [...document.querySelectorAll("yth-hunter-button:not([round])")]
        .find((h) => isShown(h) && !badSpot(h));
      if (mine && (!row || mine.parentNode === row)) return;
      if (!row) {
        // nowhere good yet: at least don't leave one sitting in the playlist
        document.querySelectorAll("yth-hunter-button:not([round])").forEach((x) => { if (badSpot(x)) x.remove(); });
        return;
      }
      const wasOpen = mine && Panel.anchoredTo(mine);
      document.querySelectorAll("yth-hunter-button:not([round])").forEach((x) => x.remove());
      const btn = makeButton(false);
      row.appendChild(btn);
      if (wasOpen) Panel.reanchor(btn);
      console.debug("[YouTube Hunter] button added to", row);
    } else {
      if (ownsVisibleButton(true)) return;
      const bar = findVisible(SHORTS_TARGETS);
      if (!bar) return;
      document.querySelectorAll("yth-hunter-button[round]").forEach((x) => x.remove());
      bar.insertBefore(makeButton(true), bar.firstChild);
      console.debug("[YouTube Hunter] shorts button added to", bar);
    }
  }

  let ensureTimer = 0;
  const scheduleEnsure = () => {
    if (ensureTimer) return;
    ensureTimer = setTimeout(() => { ensureTimer = 0; ensureButton(); }, 250);
  };
  new MutationObserver(scheduleEnsure).observe(document.documentElement, {
    childList: true, subtree: true,
  });
  // YouTube is a single-page app: a new video is a navigation event, not a load.
  window.addEventListener("yt-navigate-finish", () => {
    ensureButton();
    Panel.onNavigate();
  });
  // follow YouTube's own dark/light switch
  new MutationObserver(() => { relabelButtons(); Panel.retheme(); })
    .observe(document.documentElement, { attributes: true, attributeFilter: ["dark", "light"] });

  // ═════════════════════════════════════════════════════════════════════
  //  The corner panel
  // ═════════════════════════════════════════════════════════════════════
  const Panel = (() => {
    let host = null, root = null, anchorBtn = null;
    let mode = "download";           // which tab: download | cut
    let state = {
      phase: "idle",      // connecting | offline | waking | reading | pick | sending | running | done | error
      video: null, meta: null,
      rows: [], probed: true, format: null,
      key: null,
      live: null,          // running progress
      result: null,        // final status
      message: "",
      saved: [],           // v3.43c: row ids already saved for this video
      dlKey: null,         // the row id the running download was started with
      // v3.45: the in-app picker's choices, here too
      vf: null, af: null,  // video container / audio codec (null = app's saved pick)
      lang: "",            // audio track of a dubbed video ("" = original)
      tracks: [],          // [{key, name, native, nameFa, kind, code, rtl}]
      formats: null,       // {video: [{key,label,sub}], audio: [...]}
      refreshing: false,   // re-sizing the ladder for a new format / dub
      parked: null,        // v3.47: row id of a paused download while another row is picked
    };
    let pollTimer = 0, wakeTimer = 0, runToken = 0;
    // v3.44: phases in which the footer is the live progress capsule
    const LIVE = ["sending", "running", "pausing", "paused", "resuming"];
    const isLive = () => LIVE.includes(state.phase);
    let pauseApi = false;          // the app answers /v1/pause + /v1/resume
    let playApi = false;           // v3.45: the app answers /v1/play
    let fmtToken = 0;              // v3.45: latest format / dub re-read wins
    // v3.45: a row's identity is quality + format + dub ("720p@mkv~ar"); an
    // older app sends no id, and then the bare key is all there is.
    const rid = (r) => (r && (r.id || r.key)) || null;
    const curRow = () => state.rows.find((r) => rid(r) === state.key) || null;
    const baseKey = () => { const r = curRow(); return r ? r.key : null; };
    const isSaved = (r) => !!r && (state.saved.includes(rid(r)) || !!r.saved);
    let ctlAt = 0, ctlWant = "";   // last ⏸ / ▶ press (bridges the status gap)
    let shownPct = 0, pctRaf = 0;  // the number on the capsule eases, not jumps
    let speeds = [];               // recent speeds → the sparkline
    const speedsDl = () => speeds;
    let lastVideo = null;          // v3.48: the video rung to return to from "Audio only"

    function build() {
      host = document.createElement("yth-hunter-panel");
      host.style.cssText = "all: initial; position: fixed; z-index: 2147483000; top: 0; left: 0;";
      root = host.attachShadow({ mode: "open" });
      root.innerHTML = (PANEL_CSS ? `<style>${PANEL_CSS}</style>`
                                  : `<link rel="stylesheet" href="${ASSET("panel.css")}">`) + `
        <section class="panel" role="dialog" aria-modal="false" aria-label="YouTube Hunter" hidden>
          <header class="head">
            <span class="brand">${markSVG(22, false)}<span class="name">YouTube Hunter</span></span>
            <span class="link" title=""><i></i></span>
            <button class="x" type="button"></button>
          </header>
          <nav class="tabs" role="tablist">
            <span class="thumbx" aria-hidden="true"></span>
            <button type="button" role="tab" data-act="tab" data-mode="download"></button>
            <button type="button" role="tab" data-act="tab" data-mode="cut"></button>
          </nav>
          <div class="video"></div>
          <div class="body"></div>
          <footer class="foot"></footer>
        </section>`;
      document.documentElement.appendChild(host);
      root.querySelector(".x").addEventListener("click", () => close());
      // v3.48: the body scrolls under a fixed footer; fade the edge that has
      // more content behind it, so "there's more below" is visible
      root.querySelector(".body").addEventListener("scroll", shade, { passive: true });
      window.addEventListener("resize", shade, { passive: true });
      document.addEventListener("keydown", onGlobalKey, true);
      root.addEventListener("click", onClick);
      root.addEventListener("keydown", onDdKey);
      retheme();
    }

    function retheme() {
      if (!host) return;
      // v3.44: the APP's theme when known; YouTube's until the app answers
      const mode = appTheme && appTheme.mode ? appTheme.mode : (isDark() ? "dark" : "light");
      host.setAttribute("data-theme", mode === "light" ? "light" : "dark");
      host.setAttribute("data-lang", lang);
      const vars = (appTheme && appTheme.vars) || {};
      for (const k of THEME_VARS) {
        if (vars[k]) host.style.setProperty("--" + k, vars[k]);
        else host.style.removeProperty("--" + k);
      }
      applyVars(host);
      const sec = root.querySelector(".panel");
      sec.setAttribute("dir", lang === "fa" ? "rtl" : "ltr");
      sec.setAttribute("lang", lang);
      root.querySelector(".x").setAttribute("aria-label", t("close"));
      root.querySelector(".x").innerHTML =
        '<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
      const tabs = root.querySelectorAll(".tabs button");
      tabs[0].innerHTML = `<svg width="16" height="16" viewBox="0 0 18 18" aria-hidden="true"><path d="M9 2.5v9m0 0l-3.6-3.6M9 11.5l3.6-3.6M3 15h12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg><span>${esc(t("tabDownload"))}</span>`;
      tabs[1].innerHTML = `${scissorsSVG(16)}<span>${esc(t("tabCut"))}</span>`;
    }

    // the palette keys /v1/ping may send (see web_bridge._THEME_VARS)
    const THEME_VARS = ["bg", "raise", "well", "line", "line-soft", "text", "strong",
                        "muted", "dim", "track", "ok", "bad", "warn", "on-acc"];

    function shade() {
      if (!root) return;
      const b = root.querySelector(".body"), sec = root.querySelector(".panel");
      if (!b || !sec) return;
      const up = b.scrollTop > 2, down = b.scrollTop + b.clientHeight < b.scrollHeight - 2;
      sec.toggleAttribute("data-more-up", up);
      sec.toggleAttribute("data-more-down", down);
    }

    function isOpen() {
      return !!(host && !root.querySelector(".panel").hidden);
    }

    function setExpanded(v) {
      document.querySelectorAll("yth-hunter-button").forEach((h) => {
        const r = h.shadowRoot;
        if (!r) return;
        r.querySelectorAll("button[data-mode]").forEach((b) => {
          const on = v && h === anchorBtn && b.getAttribute("data-mode") === mode;
          b.setAttribute("aria-expanded", on ? "true" : "false");
        });
      });
    }

    function freshState(vid) {
      return { phase: "connecting", video: vid, meta: pageMeta(), rows: [], probed: true,
               format: null, key: null, live: null, result: null, message: "",
               saved: [], dlKey: null, vf: state.vf, af: state.af, lang: "",
               tracks: [], formats: null, refreshing: false, parked: null };
    }

    function open(btn, wantMode) {
      const vid = currentVideo();
      if (!host) build();
      anchorBtn = btn || anchorBtn || null;
      if (wantMode) setMode(wantMode, true);
      const sec = root.querySelector(".panel");
      const fresh = sec.hidden;
      sec.hidden = false;
      if (fresh) {
        sec.classList.remove("arrive");
        void sec.offsetWidth;
        sec.classList.add("arrive");
      }
      setExpanded(true);
      if (!vid) {
        state = Object.assign(state, { phase: "error", video: null, message: t("noVideo") });
        render();
        return;
      }
      const same = state.video && state.video.id === vid.id;
      if (!same) Cut.reset();
      if (!same || ["error", "offline", "idle", "waking"].includes(state.phase)) {
        const keep = same ? state.saved : [];
        state = freshState(vid);
        state.saved = keep;
        render();
        connect(true);
      } else {
        render();
        if (isLive()) poll();
        // the app's theme / accent may have changed since the last open
        call("/v1/ping", { timeout: 1500 }).then((p) => { if (p.reachable && p.data && p.data.ok) adopt(p.data); });
      }
      Cut.onShow();
      startBeat();
    }

    // v3.47: one steady heartbeat while the panel is open and the tab is on
    // screen, independent of the download / cut polls (which pause, park or
    // stop). The app hides its corner card for exactly these jobs and shows
    // it again ~4 s after the panel closes or the tab is left.
    let beatTimer = 0;
    function beat() {
      if (!isOpen() || document.visibilityState !== "visible" || !state.video) return;
      const job = Cut.job();
      call("/v1/watch", { method: "POST", timeout: 1500,
                          body: { v: state.video.id, jobs: job ? [job] : [] } });
    }
    function startBeat() {
      clearInterval(beatTimer);
      beat();
      beatTimer = setInterval(beat, 1000);
    }
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") beat();
      else if (isOpen()) release();
    });

    // v3.51: tell the app the panel stopped following this video / cut NOW, so
    // its corner card slides in at once instead of ~4 s later (or never, if a
    // late poll refreshed the watch).
    function release() {
      if (!state.video) return;
      const job = Cut.job();
      call("/v1/unwatch", { method: "POST", timeout: 1500,
                            body: { v: state.video.id, jobs: job ? [job] : [] } });
    }

    function close() {
      if (!host) return;
      const wasOpen = isOpen();
      clearInterval(beatTimer); beatTimer = 0;
      root.querySelector(".panel").hidden = true;
      setExpanded(false);
      clearTimeout(pollTimer); pollTimer = 0;
      clearInterval(wakeTimer); wakeTimer = 0;
      Cut.onHide();
      if (wasOpen) release();
      if (anchorBtn && anchorBtn.shadowRoot) {
        const b = anchorBtn.shadowRoot.querySelector(`button[data-mode="${mode}"]`);
        b && b.focus({ preventScroll: true });
      }
    }

    function toggle(btn, wantMode) {
      wantMode = wantMode || "download";
      if (isOpen() && (!btn || btn === anchorBtn) && wantMode === mode) close();
      else if (isOpen() && btn === anchorBtn) { setMode(wantMode); setExpanded(true); }
      else open(btn, wantMode);
    }

    function setMode(m, quiet) {
      m = m === "cut" ? "cut" : "download";
      if (m === mode && !quiet) return;
      mode = m;
      if (!root) return;
      const sec = root.querySelector(".panel");
      sec.setAttribute("data-mode", mode);
      root.querySelector(".tabs").setAttribute("data-mode", mode);
      root.querySelectorAll(".tabs button").forEach((b) => {
        const on = b.getAttribute("data-mode") === mode;
        b.setAttribute("aria-selected", on ? "true" : "false");
        b.tabIndex = on ? 0 : -1;
      });
      if (!quiet) {
        render();
        if (mode === "cut") Cut.onShow(); else Cut.onHide(true);
        setExpanded(true);
      }
    }

    function onNavigate() {
      const vid = currentVideo();
      if (!isOpen()) { Cut.onHide(); return; }
      if (!vid || !state.video || vid.id !== state.video.id) close();
    }

    // ── flow ────────────────────────────────────────────────────────────
    // autoWake: the panel was just opened by a click on the YouTube button.
    // If the app isn't running, start it right away (youtubehunter://) instead
    // of making the user press "Start" — retry / wake-poll calls pass false so
    // a failed launch never loops.
    async function connect(autoWake) {
      const token = ++runToken;
      const ping = await call("/v1/ping", { timeout: 1500 });
      if (token !== runToken) return;
      if (!ping.reachable || !ping.data || !ping.data.ok) {
        if (autoWake && ping.error !== "extension") { wake(); return; }
        state.phase = "offline";
        render();
        return;
      }
      adopt(ping.data);
      // a download for this video may already be going (panel reopened)
      const st = await call("/v1/status?v=" + encodeURIComponent(state.video.id));
      if (token !== runToken) return;
      const s = st.data || {};
      if (s.state === "running" || s.state === "starting") {
        state.phase = liveSubPhase(s);
        state.live = s;
        render();
        poll();
        // still read the ladder so the rung can show which quality is filling
      } else if (s.state === "stopped" && pauseApi) {
        // parked earlier (here, on the live card or the Downloads page)
        state.phase = "paused";
        state.live = s;
        render();
        poll();
      }
      readQualities(token);
    }

    function adopt(info) {
      if (info.lang && STR[info.lang] && info.lang !== lang) {
        lang = info.lang;
        relabelButtons();
        retheme();
      }
      if (info.accent && info.accent.a) {
        accent = { a: info.accent.a, b: info.accent.b || info.accent.a };
        relabelButtons();
        retheme();
      }
      pauseApi = !!info.pause;
      playApi = !!info.play;
      if (info.theme && info.theme.mode) {
        appTheme = { mode: info.theme.mode, vars: info.theme.vars || {} };
        try { chrome.storage.local.set({ [THEME_KEY]: Object.assign({ accent }, appTheme) }); } catch (_) {}
        retheme();
      }
    }

    // running / starting status → which live sub-phase the capsule shows
    function liveSubPhase(s) {
      if (s.cancelling && s.intent === "pause") return "pausing";
      if (s.cancelling && s.intent === "resume") return "resuming";
      if (/…$/.test(s.text || "") && !(s.done > 0) && ctlWant === "resume") return "resuming";
      return "running";
    }

    function qualitiesPath() {
      let p = "/v1/qualities?v=" + encodeURIComponent(state.video.id);
      if (state.vf) p += "&vf=" + encodeURIComponent(state.vf);
      if (state.af) p += "&af=" + encodeURIComponent(state.af);
      if (state.lang) p += "&lang=" + encodeURIComponent(state.lang);
      return p;
    }

    // the answer of /v1/qualities → state (shared by the first read and by
    // every format / dub change)
    function takeQualities(d, wantBase) {
      state.rows = (Array.isArray(d.rows) ? d.rows : []).filter((r) => r && r.key !== "best");
      state.probed = !!d.probed;
      state.format = d.format || null;
      if (d.format) { state.vf = d.format.video || state.vf; state.af = d.format.audio || state.af; }
      state.formats = d.formats || null;
      state.tracks = Array.isArray(d.tracks) ? d.tracks : [];
      state.lang = typeof d.lang === "string" ? d.lang : state.lang;
      // files already on disk (any session) count as saved
      for (const id of (Array.isArray(d.saved) ? d.saved : [])) if (!state.saved.includes(id)) state.saved.push(id);
      for (const r of state.rows) if (r.saved && !state.saved.includes(rid(r))) state.saved.push(rid(r));
      const byBase = wantBase && state.rows.find((r) => r.key === wantBase);
      if (byBase) state.key = rid(byBase);
    }

    async function readQualities(token) {
      if (!isLive()) { state.phase = "reading"; render(); }
      const q = await call(qualitiesPath(), { timeout: 90000 });
      if (token !== runToken) return;
      if (!q.reachable) {
        if (!isLive()) { state.phase = "offline"; render(); }
        return;
      }
      const d = q.data || {};
      // v3.43c: "Best available" never shows here — the real qualities are
      // listed, and "best" is just the top one of them. (Also filtered by the
      // app; this keeps an older app from bringing it back.)
      takeQualities(d, baseKey());
      if (!state.key || !state.rows.some((r) => rid(r) === state.key)) {
        let saved = null;
        try { saved = (await chrome.storage.local.get(STORE_KEY))[STORE_KEY]; } catch (_) {}
        const video = state.rows.filter((r) => !r.isAudio);
        const hit = saved && state.rows.find((r) => r.key === saved || rid(r) === saved);
        state.key = rid(hit || video[0] || state.rows[0]);
      }
      if (!isLive() && state.phase !== "done") state.phase = "pick";
      Cut.seedQuality();
      render();
    }

    // v3.45: a new video / audio format or audio track — re-size the ladder
    // (the app has the extraction cached, so this is quick) and keep the
    // same quality picked.
    async function refetch(patch) {
      if (!state.video || !canPick()) return;
      park();
      Object.assign(state, patch);
      const want = baseKey();
      const token = ++fmtToken, run = runToken;
      state.refreshing = true;
      if (state.phase === "done" || state.phase === "error") { state.phase = "pick"; state.message = ""; }
      render();
      const q = await call(qualitiesPath(), { timeout: 90000 });
      if (token !== fmtToken || run !== runToken || !state.video) return;
      state.refreshing = false;
      if (q.reachable && q.data && q.data.ok) {
        takeQualities(q.data, want);
        if (!state.rows.some((r) => rid(r) === state.key)) {
          const video = state.rows.filter((r) => !r.isAudio);
          state.key = rid(video[0] || state.rows[0]);
        }
      }
      render();
    }

    async function play(id) {
      const row = state.rows.find((r) => rid(r) === id) || curRow();
      if (!row || !state.video) return;
      if (!playApi) {          // an older app: the folder is the best it can do
        call("/v1/reveal", { method: "POST", body: { v: state.video.id } });
        return;
      }
      const r = await call("/v1/play", { method: "POST", body: { v: state.video.id, id: rid(row) } });
      if (r.reachable && r.data && !r.data.ok) {
        // gone from disk: forget it, so the row offers Download again
        state.saved = state.saved.filter((k) => k !== rid(row));
        row.saved = false;
        state.message = t("playFail");
        render();
      }
    }

    function wake() {
      // The installer registers youtubehunter:// → YouTube Hunter.exe. The
      // browser asks once ("Open YouTube Hunter?"); the app starts minimised.
      const a = document.createElement("a");
      a.href = "youtubehunter://wake";
      a.style.display = "none";
      document.body.appendChild(a);
      a.click();
      a.remove();
      state.phase = "waking";
      state.message = "";
      render();
      const started = Date.now();
      clearInterval(wakeTimer);
      wakeTimer = setInterval(async () => {
        const p = await call("/v1/ping", { timeout: 900 });
        if (p.reachable && p.data && p.data.ok) {
          clearInterval(wakeTimer); wakeTimer = 0;
          state.phase = "connecting";
          render();
          connect();
        } else if (Date.now() - started > 30000) {
          clearInterval(wakeTimer); wakeTimer = 0;
          state.phase = "offline";
          state.message = t("offWakeFail");
          render();
        }
      }, 1000);
    }

    async function startDownload() {
      const row = curRow();
      if (!row) return;
      try { await chrome.storage.local.set({ [STORE_KEY]: row.key }); } catch (_) {}
      state.phase = "sending";
      state.parked = null;
      state.dlKey = rid(row);
      state.result = null;
      state.live = { pct: 0, text: t("sending") };
      shownPct = 0; speeds = []; ctlWant = ""; ctlAt = 0;
      render();
      const meta = state.meta || pageMeta();
      const res = await call("/v1/download", {
        method: "POST",
        // inPage: this panel follows the download itself, so the desktop
        // live card stays away while it is open (and takes over on close)
        body: { v: state.video.id, key: row.key, title: meta.title, channel: meta.channel,
                inPage: true,
                // v3.45: the format + dub picked in this panel
                vf: state.vf || undefined, af: state.af || undefined, lang: state.lang || "" },
        timeout: 20000,
      });
      if (!res.reachable) { state.phase = "offline"; render(); return; }
      if (!res.data || !res.data.ok) {
        state.phase = "error";
        state.message = (res.data && res.data.error) || t("failed");
        render();
        return;
      }
      if (res.data.already) state.live = { pct: 0, text: t("already") };
      // v3.44: the panel stays open — the Download button has become the live
      // capsule. (It used to close here and hand over to the desktop card,
      // which then popped up over YouTube.) Closing the panel still hands
      // the download to the desktop card, so the user can choose.
      state.phase = "running";
      paintOrRender();
      poll();
    }

    // ⏸ / ▶ — the same pause the desktop live card does (the row parks with
    // its .part file; ▶ continues from there)
    async function control(want) {
      if (!pauseApi || !state.video) return;
      ctlWant = want; ctlAt = Date.now();
      state.phase = want === "pause" ? "pausing" : "resuming";
      if (want === "resume") { speeds = []; }
      paintOrRender();
      const r = await call("/v1/" + want, { method: "POST", body: { v: state.video.id }, timeout: 4000 });
      if (!r.reachable) { state.phase = "offline"; render(); return; }
      poll();
    }

    // live sub-phases repaint in place (no flicker); anything else re-renders
    function paintOrRender() {
      const dlc = root && root.querySelector(".dlc");
      if (dlc && isLive() && mode === "download") {
        root.querySelector(".panel").setAttribute("data-phase", state.phase);
        paintProgress();
      } else render();
    }

    function poll() {
      clearTimeout(pollTimer);
      const vid = state.video && state.video.id;
      if (!vid) return;
      let misses = 0;
      const tick = async () => {
        if (!isOpen() || !state.video || state.video.id !== vid) return;
        // watch=1 only while the tab is really on screen: that's what keeps
        // the desktop live card out of the way (and lets it back in when the
        // user looks elsewhere or closes the panel)
        const watch = document.visibilityState === "visible" ? "&watch=1" : "";
        const r = await call("/v1/status?v=" + encodeURIComponent(vid) + watch, { timeout: 4000 });
        if (!state.video || state.video.id !== vid) return;
        const s = (r && r.data) || {};
        const sinceCtl = Date.now() - ctlAt;
        let next = 800;
        if (!r.reachable) {
          if (++misses > 4) { state.phase = "offline"; render(); return; }
        } else if (s.state === "running" || s.state === "starting" || s.state === "none") {
          misses = 0;
          // "none" right after sending = the GUI thread hasn't registered it yet
          if (s.state !== "none") {
            state.live = s;
            if (s.speed > 0) { speeds.push(s.speed); if (speeds.length > 36) speeds.shift(); }
          }
          let ph = s.state === "none" ? state.phase : liveSubPhase(s);
          // ⏸ was just pressed and the app hasn't flagged it yet: hold "Pausing…"
          if (ctlWant === "pause" && sinceCtl < 2500 && ph === "running") ph = "pausing";
          if (ctlWant === "resume" && ph === "running" && (s.done > 0 || s.pct > (state.live.pct || 0))) ctlWant = "";
          if (!LIVE.includes(ph)) ph = "running";
          state.phase = ph;
          paintOrRender();
        } else if (s.state === "stopped" && pauseApi) {
          // ▶ was just pressed: the row still says stopped until it restarts
          if (ctlWant === "resume" && sinceCtl < 6000) {
            next = 500;
          } else {
            ctlWant = "";
            state.phase = "paused";
            state.live = Object.assign({}, state.live || {}, { pct: s.pct, speed: 0, eta: 0 });
            paintOrRender();
            next = 1200;              // a resume from the app shows up here too
          }
        } else if (s.state === "done") {
          state.phase = "done"; state.result = s; ctlWant = "";
          // v3.45: the app names the exact file it saved ("720p@mp4")
          const k = (s.id && state.rows.some((r) => rid(r) === s.id)) ? s.id : (state.dlKey || state.key);
          if (k && !state.saved.includes(k)) state.saved.push(k);
          state.key = k || state.key;
          render(); if (mode === "download") burst(); return;
        } else if (s.state === "error") {
          state.phase = "error"; state.message = s.error || t("failed"); render(); return;
        } else if (s.state === "stopped") {
          state.phase = "error"; state.message = t("stopped"); render(); return;
        }
        pollTimer = setTimeout(tick, next);
      };
      pollTimer = setTimeout(tick, 400);
    }

    // The download ladder is pickable again once a download has finished (or
    // failed): v3.43c — it used to stay locked on "Saved", so a second quality
    // of the same video needed a page reload.
    // v3.47: a PAUSED download no longer locks the ladder either: the user
    // can look at (and download) another quality / format while it waits.
    const canPick = () => state.phase === "pick" || state.phase === "done"
      || state.phase === "paused"
      || (state.phase === "error" && state.rows.length > 0);

    // paused -> picking something else: the paused job stays parked in the
    // app (its .part file is kept); picking its row again brings the ▶ back.
    function park() {
      if (state.phase !== "paused") return;
      state.parked = state.dlKey || state.key;
      clearTimeout(pollTimer); pollTimer = 0;
      state.phase = "pick";
      state.message = "";
    }
    function unpark(k) {
      if (!state.parked || k !== state.parked) return false;
      state.key = k;
      state.parked = null;
      state.phase = "paused";
      render();
      poll();
      return true;
    }

    // ── events ──────────────────────────────────────────────────────────
    function onClick(e) {
      const el = e.target.closest("[data-act]");
      // v3.49: a click anywhere outside an open dropdown closes it
      const inDd = e.target.closest && e.target.closest(".dd");
      if (!inDd) ddClose(false);
      if (!el) return;
      const act = el.getAttribute("data-act");
      if (act === "ddtoggle") {
        const dd = el.closest(".dd");
        if (dd.getAttribute("data-open") === "1") ddClose(true); else ddOpen(dd);
        return;
      }
      if (act === "ddpick") { pickTrack(el.getAttribute("data-val") || ""); return; }
      if (act === "tab") {
        setMode(el.getAttribute("data-mode"));
      } else if (act === "pick") {
        if (!canPick()) return;
        const k = el.getAttribute("data-key");
        if (unpark(k)) {
          const r0 = root.querySelector(`.rung[data-key="${CSS.escape(k)}"]`);
          r0 && r0.focus({ preventScroll: true });
          return;
        }
        if (state.phase === "paused" && k === state.key) return;
        park();
        if (state.phase !== "pick" || k !== state.key) {
          const was = curRow();
          if (was && !was.isAudio) lastVideo = was.key;
          state.key = k;
          state.phase = "pick";
          state.message = "";
          render();
          const r = root.querySelector(`.rung[data-key="${CSS.escape(k)}"]`);
          r && r.focus({ preventScroll: true });
        }
      } else if (act === "download") startDownload();
      else if (act === "play") play(el.getAttribute("data-key") || state.key);
      else if (act === "vf" || act === "af") {
        const v = el.getAttribute("data-val");
        if (!v || !canPick()) return;
        // v3.48: an audio format means "audio only"; a video format means a
        // video rung (the last one picked, else the top one)
        const cur = curRow();
        let switched = false;
        if (act === "af" && cur && !cur.isAudio) {
          const a = state.rows.find((r) => r.isAudio);
          if (a) { lastVideo = cur.key; park(); state.key = rid(a); switched = true; }
        } else if (act === "vf" && cur && cur.isAudio) {
          const vr = state.rows.find((r) => !r.isAudio && r.key === lastVideo) || state.rows.find((r) => !r.isAudio);
          if (vr) { park(); state.key = rid(vr); switched = true; }
        }
        if (v !== state[act]) refetch({ [act]: v });
        else if (switched) { state.phase = "pick"; state.message = ""; render(); }
      }
      else if (act === "pause" || act === "resume") control(act);
      else if (act === "wake") wake();
      else if (act === "retry") {
        state.phase = "connecting"; state.message = ""; render(); connect();
      } else if (act === "reveal") {
        call("/v1/reveal", { method: "POST", body: { v: state.video.id, id: state.key || undefined } });
      } else if (act === "app") {
        call("/v1/show", { method: "POST", body: { page: 8 } });
      } else Cut.onAct(act, el);
    }

    function onGlobalKey(e) {
      if (!isOpen()) return;
      if (ddOpenEl()) {
        if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); ddClose(true); }
        return;                       // arrows belong to the open list
      }
      if (e.key === "Escape") {
        const path = e.composedPath ? e.composedPath() : [];
        // Esc inside a timecode field only leaves the field
        if (path.some((n) => n && n.classList && n.classList.contains("tcin"))) return;
        close();
        return;
      }
      if (mode === "cut") Cut.onKey(e);
    }

    // keyboard: arrows move through the ladder like a radio group
    function onLadderKey(e) {
      if (!canPick()) return;
      const keys = state.rows.map(rid);
      let i = keys.indexOf(state.key);
      if (e.key === "ArrowDown" || e.key === "ArrowRight") i = Math.min(keys.length - 1, i + 1);
      else if (e.key === "ArrowUp" || e.key === "ArrowLeft") i = Math.max(0, i - 1);
      else if (e.key === "Enter") {
        if (state.phase === "pick") { if (isSaved(curRow())) play(state.key); else startDownload(); }
        return;
      }
      else return;
      e.preventDefault();
      if (unpark(keys[i])) { const r1 = root.querySelector(`.rung[data-key="${CSS.escape(keys[i])}"]`); r1 && r1.focus(); return; }
      park();
      state.key = keys[i];
      state.phase = "pick";
      render();
      const r = root.querySelector(`.rung[data-key="${CSS.escape(state.key)}"]`);
      r && r.focus();
    }

    // ── rendering ───────────────────────────────────────────────────────
    const ready = () => !["connecting", "offline", "waking"].includes(state.phase)
      && !(state.phase === "error" && !state.video);

    function render() {
      if (!host) return;
      retheme();
      const sec = root.querySelector(".panel");
      sec.setAttribute("data-phase", state.phase);
      sec.toggleAttribute("data-live", isLive());
      sec.setAttribute("data-mode", mode);
      root.querySelector(".tabs").setAttribute("data-mode", mode);
      root.querySelectorAll(".tabs button").forEach((b) => {
        const on = b.getAttribute("data-mode") === mode;
        b.setAttribute("aria-selected", on ? "true" : "false");
        b.tabIndex = on ? 0 : -1;
      });
      const link = root.querySelector(".link");
      const live = !["offline", "waking", "connecting"].includes(state.phase);
      link.classList.toggle("on", live);
      link.title = live ? "YouTube Hunter" : t("offTitle");

      // video strip
      const v = state.video;
      const vEl = root.querySelector(".video");
      if (v) {
        const meta = state.meta || {};
        vEl.hidden = false;
        vEl.innerHTML = `
          <span class="thumb${v.short ? " short" : ""}"><img alt="" src="https://i.ytimg.com/vi/${esc(v.id)}/mqdefault.jpg" onerror="this.remove()">${(() => { const d = Cut.dur(); return d > 0 && d !== Infinity ? `<span class="tdur">${esc(clock(d))}</span>` : ""; })()}</span>
          <span class="vt">
            <b>${esc(meta.title || "")}</b>
            <small>${v.short ? `<em>${esc(t("shorts"))}</em>` : ""}${esc(meta.channel || "")}</small>
          </span>`;
      } else vEl.hidden = true;

      const body = root.querySelector(".body"), foot = root.querySelector(".foot");
      if (mode === "cut" && ready() && state.phase !== "reading") {
        body.innerHTML = Cut.bodyHTML();
        foot.innerHTML = Cut.footHTML();
        Cut.bind(body);
        Cut.paint();
        shade();
        return;
      }
      if (mode === "cut" && state.phase === "reading") {
        body.innerHTML = Cut.skeletonHTML();
        foot.innerHTML = "";
        shade();
        return;
      }
      body.innerHTML = bodyHTML();
      foot.innerHTML = footHTML();
      const ladder = root.querySelector(".ladder");
      if (ladder) ladder.addEventListener("keydown", onLadderKey);
      paintProgress();
      shade();
    }

    function bodyHTML() {
      switch (state.phase) {
        case "connecting":
          return `<p class="quiet"><span class="spin"></span>${esc(t("connecting"))}</p>`;
        case "offline":
          return `<div class="off">
              <b>${esc(t("offTitle"))}</b>
              <p>${esc(state.message || t("offBody"))}</p>
            </div>`;
        case "waking":
          return `<p class="quiet"><span class="spin"></span>${esc(t("offWaking"))}</p>`;
        case "reading":
          return `<div class="ladder ghost" aria-busy="true">
              ${[88, 64, 40, 22].map((w, i) => `<div class="rung skel" style="--d:${i * 90}ms"><span class="bar"><i style="width:${w}%"></i></span></div>`).join("")}
            </div><p class="note">${esc(t("reading"))}</p>`;
        case "error":
          return (state.rows.length && state.video ? ladderHTML() : "")
            + `<div class="off err"><b>${esc(t("failed"))}</b><p>${esc(state.message)}</p></div>`;
        default:
          return ladderHTML();
      }
    }

    // v3.45: one row of format chips (MP4 · MKV · WEBM / MP3 · M4A · …)
    // v3.48: a segmented control; the row that doesn't apply to the picked
    // rung is dimmed (picking one of its formats switches to that kind)
    function fmtChipsHTML(act, list, cur, label) {
      if (!Array.isArray(list) || list.length < 2) return "";
      const dis = !canPick() || state.refreshing;
      const row = curRow();
      const off = row && (act === "af" ? !row.isAudio : !!row.isAudio);
      return `<div class="fmts${off ? " dim" : ""}" role="radiogroup" aria-label="${esc(label)}">
          <span class="fl">${esc(label)}</span>
          <span class="seg">${list.map((f) => `<button type="button" class="fchip${f.key === cur ? " on" : ""}" role="radio"
              aria-checked="${f.key === cur}" data-act="${act}" data-val="${esc(f.key)}"
              title="${esc(f.sub || "")}"${dis ? " disabled" : ""}>${esc(f.label || String(f.key).toUpperCase())}</button>`).join("")}</span>
        </div>`;
    }

    // v3.45: the audio track of a dubbed video (original + dubs)
    // v3.49: a designed dropdown instead of the native <select>, whose open
    // list is drawn by the OS (white/blue Windows menu on a dark panel). Each
    // row: language code chip · name + native name · Original / Dub badge.
    const trackName = (x) => (lang === "fa" ? (x.nameFa || x.name) : x.name) || x.code || "?";
    const trackNative = (x) => (x.native && x.native !== trackName(x) ? x.native : "");
    const trackKind = (x) => x.kind === "original" ? ["orig", t("trackOriginal")]
                           : x.kind === "auto" ? ["auto", t("trackAuto")] : ["dub", t("trackDub")];
    const trackCode = (x) => (String(x.code || x.key || "").split(/[-_]/)[0].toUpperCase().slice(0, 3)) || "♪";
    function trackInner(x) {
      const [k, kl] = trackKind(x);
      const nat = trackNative(x);
      return `<span class="ddcode">${esc(trackCode(x))}</span>
        <span class="ddtx"><b>${esc(trackName(x))}</b>${nat ? `<small>${esc(nat)}</small>` : ""}</span>
        <span class="ddk k-${k}">${esc(kl)}</span>`;
    }
    const ICON_CHEV = '<svg class="ddchev" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    const ICON_TICK = '<svg class="ddtick" width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M3 7.4l2.6 2.6L11 4.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';

    function trackHTML() {
      const tr = state.tracks || [];
      if (tr.length < 2) return "";
      const dis = !canPick() || state.refreshing;
      const curKey = state.lang || "";
      const cur = tr.find((x) => (x.key || "") === curKey) || tr.find((x) => x.kind === "original") || tr[0];
      return `<div class="trk">
          <span class="fl"><svg width="15" height="15" viewBox="0 0 18 18" aria-hidden="true"><path d="M3 10v-1a6 6 0 0 1 12 0v1M3 10h2.2v5H4a1 1 0 0 1-1-1zm12 0h-2.2v5H14a1 1 0 0 0 1-1z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>${esc(t("audioTrack"))}</span>
          <div class="dd" data-open="0">
            <button type="button" class="ddbtn" data-act="ddtoggle" aria-haspopup="listbox" aria-expanded="false"
                aria-label="${esc(t("audioTrack"))}: ${esc(trackName(cur))}"${dis ? " disabled" : ""}>${trackInner(cur)}${ICON_CHEV}</button>
            <div class="ddm" role="listbox" aria-label="${esc(t("audioTrack"))}">
              ${tr.map((x) => {
                const on = (x.key || "") === (cur.key || "");
                return `<button type="button" class="ddo${on ? " on" : ""}" role="option" aria-selected="${on}"
                    data-act="ddpick" data-val="${esc(x.key || "")}">${trackInner(x)}${ICON_TICK}</button>`;
              }).join("")}
            </div>
          </div>
        </div>`;
    }

    // ── dropdown behaviour (shared by the Download and Cut tabs) ──
    function ddOpenEl() { return root && root.querySelector('.dd[data-open="1"]'); }
    function ddClose(focusBtn) {
      const dd = ddOpenEl();
      if (!dd) return false;
      dd.setAttribute("data-open", "0");
      dd.classList.remove("up");
      const b = dd.querySelector(".ddbtn");
      if (b) { b.setAttribute("aria-expanded", "false"); if (focusBtn) b.focus({ preventScroll: true }); }
      return true;
    }
    function ddOpen(dd) {
      ddClose(false);
      const btn = dd.querySelector(".ddbtn"), menu = dd.querySelector(".ddm");
      if (!btn || btn.disabled) return;
      // open upward when the panel body has no room below the trigger
      const body = root.querySelector(".body");
      const br = body ? body.getBoundingClientRect() : { top: 0, bottom: innerHeight };
      const tr = btn.getBoundingClientRect();
      const mh = Math.min(menu.scrollHeight || 0, 260);
      dd.classList.toggle("up", tr.bottom + mh + 10 > br.bottom && tr.top - mh - 10 > br.top);
      dd.setAttribute("data-open", "1");
      btn.setAttribute("aria-expanded", "true");
      const on = menu.querySelector(".ddo.on") || menu.querySelector(".ddo");
      if (on) { on.focus({ preventScroll: true }); on.scrollIntoView({ block: "nearest" }); }
    }
    function pickTrack(v) {
      ddClose(false);
      if ((v || "") === (state.lang || "")) return;
      if (canPick()) refetch({ lang: v || "" });
      else { state.lang = v || ""; render(); }
    }
    function onDdKey(e) {
      const path = e.composedPath ? e.composedPath() : [];
      const dd = path.find((n) => n && n.classList && n.classList.contains("dd"));
      if (!dd) return;
      const open = dd.getAttribute("data-open") === "1";
      const opts = [...dd.querySelectorAll(".ddo")];
      const i = opts.indexOf(root.activeElement);
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault(); e.stopPropagation();
        if (!open) { ddOpen(dd); return; }
        const n = e.key === "ArrowDown" ? Math.min(opts.length - 1, i + 1) : Math.max(0, i - 1);
        opts[n] && opts[n].focus({ preventScroll: true });
        opts[n] && opts[n].scrollIntoView({ block: "nearest" });
      } else if (e.key === "Home" || e.key === "End") {
        if (!open) return;
        e.preventDefault();
        const o = e.key === "Home" ? opts[0] : opts[opts.length - 1];
        o && o.focus({ preventScroll: true });
      } else if (e.key === "Tab" && open) {
        ddClose(false);
      }
    }

    function ladderHTML() {
      const rows = state.rows;
      if (!rows.length) return `<p class="quiet"><span class="spin"></span>${esc(t("reading"))}</p>`;
      const max = Math.max(1, ...rows.map((r) => r.sizeBytes || 0));
      const locked = !canPick();
      const F = state.formats || {};
      let html = trackHTML();
      html += `<div class="ladder${state.refreshing ? " busy" : ""}" role="radiogroup" aria-label="${esc(t("download"))}"${state.refreshing ? ' aria-busy="true"' : ""}>`;
      let audioHead = false;
      if (rows.some((r) => !r.isAudio) && rows.some((r) => r.isAudio)) {
        html += `<div class="split first" aria-hidden="true">${esc(t("video"))}</div>`;
      }
      for (const r of rows) {
        if (r.isAudio && !audioHead) {
          audioHead = true;
          html += fmtChipsHTML("vf", F.video, state.vf, t("fmtVideo"));
          html += `<div class="split" aria-hidden="true">${esc(t("audio"))}</div>`;
        }
        const id = rid(r);
        const on = id === state.key;
        const got = isSaved(r);
        const w = r.sizeBytes ? Math.max(5, Math.round((r.sizeBytes / max) * 100)) : 0;
        html += `<div class="rung${on ? " on" : ""}${r.isAudio ? " audio" : ""}${got ? " got" : ""}" role="radio"
            tabindex="${on ? 0 : -1}" aria-checked="${on}" aria-disabled="${locked}"
            data-act="pick" data-key="${esc(id)}">
            <span class="dot"></span>
            <span class="q${/^\d{3,4}p$/.test(r.label) ? " res" : ""}">${esc(r.label)}</span>
            <span class="sub">${got ? `<span class="tag">✓ ${esc(t("savedTag"))}</span>` : ""}${state.parked && id === state.parked ? `<span class="tag park">⏸ ${esc(t("parkedTag"))}</span>` : ""}${esc(r.sub || "")}</span>
            <span class="sz${r.sizeBytes ? "" : " none"}">${r.sizeText ? (r.sizeExact ? "" : "≈ ") + esc(r.sizeText) : esc(t("unknownSize"))}</span>
            <span class="bar"><i style="width:${w}%"></i><u class="fill"></u></span>
          </div>`;
      }
      // the audio format sits UNDER "Audio only", like the video format under the video rows
      html += audioHead ? fmtChipsHTML("af", F.audio, state.af, t("fmtAudio"))
                        : fmtChipsHTML("vf", F.video, state.vf, t("fmtVideo"));
      html += "</div>";
      if (!state.probed) html += `<p class="note">${esc(t("standard"))}</p>`;
      if (state.message && state.phase === "pick") html += `<p class="note warn">${esc(state.message)}</p>`;
      else if (state.phase === "pick" && isSaved(curRow())) html += `<p class="note again">${esc(t("savedHere"))}</p>`;
      if (state.phase === "done") html += `<p class="note again">${esc(t("againQuality"))}</p>`;
      return html;
    }

    // "720p · MKV · AR" — what the button / capsule pill says
    function pillText(row) {
      if (!row) return "";
      const fmt = row.container || (state.format ? (row.isAudio ? state.format.audio : state.format.video) : "");
      const dub = state.lang ? " · " + String(state.lang).split("-")[0].toUpperCase() : "";
      return row.label + (fmt ? " · " + String(fmt).toUpperCase() : "") + dub;
    }

    const ICON_PLAY_BIG = '<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M5.5 3.6v10.8a.8.8 0 0 0 1.2.7l8.6-5.4a.8.8 0 0 0 0-1.4L6.7 2.9a.8.8 0 0 0-1.2.7z" fill="currentColor"/></svg>';

    function footHTML() {
      const row = curRow();
      switch (state.phase) {
        case "offline":
          return `<button class="primary" type="button" data-act="wake">${markSVG(18)}<span>${esc(t("offStart"))}</span></button>
                  <button class="ghost" type="button" data-act="retry">${esc(t("retry"))}</button>`;
        case "pick": {
          const busy = state.refreshing ? " disabled" : "";
          // v3.45: this exact quality / format / dub is already on disk → ▶ Play
          if (row && isSaved(row)) {
            return `<button class="primary play" type="button" data-act="play" data-key="${esc(rid(row))}" title="${esc(t("playTip"))}"${busy}>
                ${ICON_PLAY_BIG}<span>${esc(t("play"))}</span>
                <span class="pill">${esc(pillText(row))}</span>
              </button>
              <button class="ghost" type="button" data-act="reveal"><span>${esc(t("showFolder"))}</span></button>`;
          }
          return `<button class="primary" type="button" data-act="download"${row && !state.refreshing ? "" : " disabled"}>
              <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M9 2.5v9m0 0l-3.6-3.6M9 11.5l3.6-3.6M3 15h12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
              <span>${esc(t("download"))}</span>
              <span class="pill">${esc(pillText(row))}</span>
            </button>`;
        }
        case "sending":
        case "running":
        case "pausing":
        case "paused":
        case "resuming":
          return capsuleHTML(row);
        case "done": {
          const s = state.result || {};
          return `<div class="done">
              <span class="tick"><svg width="22" height="22" viewBox="0 0 22 22" aria-hidden="true"><path d="M5 11.5l4 4 8-9" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
              <span><b>${esc(t("done"))}${s.size ? " · " + esc(bytes(s.size)) : ""}</b><small>${esc(t("doneBody"))}</small></span>
            </div>
            <div class="row2">
              <button class="primary play" type="button" data-act="play" data-key="${esc(state.key || "")}" title="${esc(t("playTip"))}">${ICON_PLAY_BIG}<span>${esc(t("play"))}</span></button>
              <button class="ghost" type="button" data-act="reveal"><span>${esc(t("showFolder"))}</span></button>
            </div>`;
        }
        case "error":
          return `<button class="primary" type="button" data-act="retry"><span>${esc(t("retry"))}</span></button>
                  <button class="ghost" type="button" data-act="app">${esc(t("openApp"))}</button>`;
        default:
          return "";
      }
    }

    // ── v3.44: the live capsule ─────────────────────────────────────────
    // The Download button morphs into this: same place, same size, so the
    // click visibly "becomes" the download. A fill runs behind the percent,
    // ⏸ / ▶ sits where the format pill was, and three quiet numbers sit
    // underneath (speed with its own sparkline, size, time left).
    const ICON_PAUSE = '<svg class="ip" width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><rect x="4" y="3.5" width="3.4" height="11" rx="1.2" fill="currentColor"/><rect x="10.6" y="3.5" width="3.4" height="11" rx="1.2" fill="currentColor"/></svg>';
    const ICON_PLAY = '<svg class="ir" width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M5.5 3.6v10.8a.8.8 0 0 0 1.2.7l8.6-5.4a.8.8 0 0 0 0-1.4L6.7 2.9a.8.8 0 0 0-1.2.7z" fill="currentColor"/></svg>';

    function capsuleHTML(row) {
      const s = state.live || {};
      const pct = Math.max(0, Math.min(100, Number(s.pct) || 0));
      const q = pillText(row);
      return `<div class="dlc" data-st="${esc(state.phase)}">
          <div class="cap" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${pct}" aria-label="${esc(t("dlDownloading"))}">
            <span class="capfill" style="--p:${pct / 100}"><i></i></span>
            <span class="capnum"><b>${Math.round(shownPct)}</b><small>%</small></span>
            <span class="capmeta"><b class="capst"></b><small class="capq">${esc(q)}</small></span>
            ${pauseApi ? `<button class="capbtn" type="button" data-act="pause">${ICON_PAUSE}${ICON_PLAY}<span class="capspin"></span></button>` : ""}
          </div>
          <div class="stats">
            <span class="st"><b class="vsp">—</b><small>${esc(t("speed"))}</small><svg class="spark" viewBox="0 0 60 16" preserveAspectRatio="none" aria-hidden="true"><path d=""/></svg></span>
            <span class="st"><b class="vsz">—</b><small class="vtot">${esc(t("sizeSoFar"))}</small></span>
            <span class="st"><b class="veta">—</b><small>${esc(t("left"))}</small></span>
          </div>
          <p class="keep">${esc(t("keepGoing"))}</p>
        </div>`;
    }

    function sparkPath(arr) {
      const speeds = arr || speedsDl();
      if (speeds.length < 2) return "";
      const max = Math.max(...speeds) || 1;
      const n = speeds.length - 1;
      return speeds.map((v, i) => `${i ? "L" : "M"}${(i / n * 60).toFixed(1)},${(15 - v / max * 13).toFixed(1)}`).join("");
    }

    function easePct(target) {
      cancelAnimationFrame(pctRaf);
      const el = root && root.querySelector(".capnum b");
      if (!el) { shownPct = target; return; }
      const from = shownPct, t0 = performance.now(), dur = 700;
      const step = (now) => {
        const k = Math.min(1, (now - t0) / dur);
        shownPct = from + (target - from) * (1 - Math.pow(1 - k, 3));
        el.textContent = String(Math.round(shownPct));
        if (k < 1) pctRaf = requestAnimationFrame(step);
      };
      pctRaf = requestAnimationFrame(step);
    }

    // Progress is painted in place (no re-render), so the capsule and the
    // filling rung animate smoothly instead of being rebuilt every 800 ms.
    function paintProgress() {
      if (!root || mode !== "download" || !isLive()) return;
      const s = state.live || {};
      const pct = Math.max(0, Math.min(100, Number(s.pct) || 0));
      const ph = state.phase;
      const dlc = root.querySelector(".dlc");
      if (dlc) {
        const post = !!s.post;
        const indeterminate = ph === "sending" || ph === "resuming"
          || post || (ph === "running" && !(s.done > 0) && pct <= 0);
        dlc.setAttribute("data-st", ph);
        dlc.toggleAttribute("data-ind", indeterminate);
        const cap = dlc.querySelector(".cap");
        cap.setAttribute("aria-valuenow", String(pct));
        dlc.querySelector(".capfill").style.setProperty("--p", String(pct / 100));
        easePct(pct);
        const label = ph === "sending" ? t("sending")
          : ph === "pausing" ? t("dlPausing")
          : ph === "paused" ? t("dlPaused")
          : ph === "resuming" ? t("dlResuming")
          : post ? t("dlFinishing")
          : indeterminate ? t("dlStarting")
          : t("dlDownloading");
        dlc.querySelector(".capst").textContent = label;
        cap.setAttribute("aria-label", label);
        const btn = dlc.querySelector(".capbtn");
        if (btn) {
          const playing = ph !== "paused";
          btn.setAttribute("data-act", playing ? "pause" : "resume");
          btn.setAttribute("aria-label", playing ? t("pause") : t("resume"));
          btn.title = playing ? t("pause") : t("resume");
          btn.disabled = ph === "sending" || ph === "pausing" || ph === "resuming"
            || (ph === "running" && (post || s.canPause === false));
        }
        const live = ph === "running" && !post;
        dlc.querySelector(".vsp").textContent = live && s.speed > 0 ? bytes(s.speed) + "/s" : "—";
        dlc.querySelector(".vsz").textContent = s.done > 0 ? bytes(s.done) : (pct > 0 ? pct + "%" : "—");
        dlc.querySelector(".vtot").textContent = s.total > 0 ? t("ofTotal").replace("{t}", bytes(s.total)) : t("sizeSoFar");
        dlc.querySelector(".veta").textContent = live && s.eta > 0 ? clock(s.eta)
          : (live && !indeterminate ? t("etaWait") : "—");
        dlc.querySelector(".veta").classList.toggle("soft", !(live && s.eta > 0));
        dlc.querySelector(".spark path").setAttribute("d", live ? sparkPath() : "");
        dlc.querySelector(".keep").textContent = ph === "paused" ? t("pausedNote") : t("keepGoing");
      }
      const fill = root.querySelector(".rung.on .fill");
      if (fill) fill.style.width = pct + "%";
      root.querySelector(".panel").style.setProperty("--pct", pct / 100);
    }

    // the finish: the filled rung flashes once, a ring pulses off the tick
    function burst() {
      const sec = root && root.querySelector(".panel");
      if (!sec) return;
      sec.classList.remove("landed");
      void sec.offsetWidth;
      sec.classList.add("landed");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  v3.43c — the Cut tab
    // ═══════════════════════════════════════════════════════════════════
    //
    // Logic borrowed from a film editor's source monitor: two marks (In /
    // Out), a marked range on the timeline, mark keys, and the frame under
    // the handle is the one you're choosing. Nothing here keeps its own copy
    // of the video — the YouTube player IS the monitor: dragging a handle
    // seeks it, Preview plays exactly the range, and the range is painted
    // onto YouTube's own progress bar.
    const Cut = (() => {
      const MIN_LEN = 0.5;
      let c = null;                  // per-video cut state
      let raf = 0, drag = null, band = null, cutPoll = 0;
      let cutRate = { t0: 0, t: 0, w: 0, spd: 0 }, cutSpeeds = [], cutSpeedAt = 0;   // v3.49
      // v3.48: the ruler is a ZOOMED window around the clip (a 30 s clip on a
      // 40 min video used to be two handles on top of each other). A thin
      // overview strip under it keeps the whole video in sight.
      let view = null, zoomAll = false, tickKey = "";

      function reset() {
        stopPreview();
        removeBand();
        clearTimeout(cutPoll); cutPoll = 0;
        view = null; zoomAll = false; tickKey = "";
        c = { start: null, end: null, cap: null, format: "mp4", audioOnly: false,
              vfmt: "mp4", afmt: "mp3",
              phase: "edit", job: null, live: null, result: null, message: "", previewing: false };
      }
      reset();

      // ── the player ────────────────────────────────────────────────────
      function player() {
        const cands = [
          "#movie_player video.html5-main-video",
          "ytd-reel-video-renderer[is-active] video",
          "#shorts-player video",
          ".html5-video-player video",
        ];
        for (const sel of cands) {
          for (const v of document.querySelectorAll(sel)) {
            if (isShown(v)) return v;
          }
        }
        return null;
      }
      const shell = (v) => v && v.closest(".html5-video-player");
      const adShowing = (v) => {
        const p = shell(v);
        return !!(p && (p.classList.contains("ad-showing") || p.classList.contains("ad-interrupting")));
      };
      function duration() {
        const v = player();
        if (!v || adShowing(v)) return 0;
        const d = v.duration;
        return Number.isFinite(d) && d > 0 ? d : (d === Infinity ? Infinity : 0);
      }
      const now = () => { const v = player(); return v && !adShowing(v) ? v.currentTime || 0 : 0; };
      function seek(t) {
        const v = player();
        if (!v || adShowing(v)) return;
        try {
          if (drag && typeof v.fastSeek === "function") v.fastSeek(t);
          else v.currentTime = t;
        } catch (_) { /* a seek is a nicety while dragging */ }
      }

      // ── range ─────────────────────────────────────────────────────────
      function seedRange() {
        const d = duration();
        if (!(d > 0) || d === Infinity) return false;
        if (c.start == null || c.end == null || c.end > d + 0.05) {
          const len = Math.min(30, d);
          let s = Math.min(now(), Math.max(0, d - len));
          s = Math.floor(s * 10) / 10;
          c.start = s;
          c.end = Math.min(d, Math.round((s + len) * 10) / 10);
        }
        return true;
      }
      function setRange(s, e, moved) {
        const d = duration() || c.end || 0;
        s = Math.max(0, Math.min(s, d));
        e = Math.max(0, Math.min(e, d));
        if (moved === "in" && e - s < MIN_LEN) s = Math.max(0, e - MIN_LEN);
        if (moved === "out" && e - s < MIN_LEN) e = Math.min(d, s + MIN_LEN);
        if (e - s < MIN_LEN) { if (moved === "in") e = Math.min(d, s + MIN_LEN); else s = Math.max(0, e - MIN_LEN); }
        c.start = Math.round(s * 10) / 10;
        c.end = Math.round(e * 10) / 10;
        paint();
      }

      function win() {
        const d = duration();
        if (!(d > 0) || d === Infinity) return { a: 0, b: 1 };
        return view || { a: 0, b: d };
      }
      function fitView() {
        const d = duration();
        if (!(d > 0) || d === Infinity || c.start == null) { view = null; return; }
        if (zoomAll) { view = { a: 0, b: d }; return; }
        const len = c.end - c.start;
        const pad = Math.max(len * 0.6, 3);
        let a = c.start - pad, b = c.end + pad;
        const minSpan = Math.min(d, 12);
        if (b - a < minSpan) { const m = (a + b) / 2; a = m - minSpan / 2; b = m + minSpan / 2; }
        if (a < 0) { b -= a; a = 0; }
        if (b > d) { a -= b - d; b = d; }
        a = Math.max(0, a);
        if (b - a > d * 0.7) { a = 0; b = d; }
        view = { a, b };
      }
      // refit only when the clip is cramped, clipped or hugging an edge, so
      // the ruler doesn't jump under the user's hand for small moves
      function maybeRefit() {
        if (c.start == null) return;
        if (!view) { fitView(); return; }
        const v = win(), sp = v.b - v.a;
        const tight = (c.end - c.start) / sp < 0.14;
        const edge = c.start < v.a + sp * 0.05 && v.a > 0.01 || c.end > v.b - sp * 0.05 && v.b < duration() - 0.01;
        const out = c.start < v.a - 0.01 || c.end > v.b + 0.01;
        if (out || edge || (tight && !zoomAll) || (!zoomAll && (c.end - c.start) / sp > 0.85 && sp < duration())) fitView();
      }
      const isZoomed = () => { const d = duration(), v = win(); return d > 0 && (v.a > 0.01 || v.b < d - 0.01); };
      const pos = (x) => { const v = win(); return (x - v.a) / Math.max(1e-6, v.b - v.a) * 100; };

      // ── qualities: the download probe's video rungs, scaled to the clip ─
      function cutRows() {
        return state.rows.filter((r) => !r.isAudio && /^(2160|1440|1080|720|480|360)p$/.test(r.key));
      }
      function seedQuality() {
        const rows = cutRows();
        if (c.cap && rows.some((r) => r.key === c.cap)) return;
        // the download's pick if it's a video tier, else the best ≤ 1080p
        // (the Cutter page's own default), else the top one
        const dl = rows.find((r) => r.key === baseKey());
        const le1080 = rows.find((r) => parseInt(r.key, 10) <= 1080);
        c.cap = (dl || le1080 || rows[0] || {}).key || null;
      }
      // "720p · MKV" / "Audio only · MP3" (+ the dub)
      function cutPill() {
        const dub = state.lang ? " · " + String(state.lang).split("-")[0].toUpperCase() : "";
        if (c.audioOnly) return t("audioOnly") + " · " + String(c.afmt || "mp3").toUpperCase() + dub;
        const r = cutRows().find((x) => x.key === c.cap);
        return (r ? r.label + " · " : "") + String(c.vfmt || "mp4").toUpperCase() + dub;
      }
      function estimate(r) {
        const d = duration();
        if (!r || !r.sizeBytes || !(d > 0) || d === Infinity || c.start == null) return "";
        return "≈ " + bytes(r.sizeBytes * ((c.end - c.start) / d));
      }

      // ── preview: play exactly the range, once ───────────────────────────
      function startPreview() {
        const v = player();
        if (!v || c.start == null) return;
        c.previewing = true;
        try { v.currentTime = c.start; v.play(); } catch (_) {}
        loop();
        paint();
      }
      function stopPreview(pause) {
        if (!c || !c.previewing) return;
        c.previewing = false;
        if (pause) { const v = player(); try { v && v.pause(); } catch (_) {} }
        paint();
      }

      // ── YouTube's own progress bar carries the range ────────────────────
      function ensureBand() {
        const v = player();
        const bar = shell(v) && shell(v).querySelector(".ytp-progress-bar");
        if (!bar) { removeBand(); return null; }
        if (band && band.isConnected && band.parentNode === bar) return band;
        removeBand();
        band = document.createElement("yth-cut-band");
        band.setAttribute("aria-hidden", "true");
        band.style.cssText = "position:absolute;top:0;bottom:0;z-index:40;pointer-events:none;"
          + "border-radius:2px;box-sizing:border-box;transition:opacity .2s ease;";
        bar.appendChild(band);
        return band;
      }
      function removeBand() {
        if (band) { band.remove(); band = null; }
        document.querySelectorAll("yth-cut-band").forEach((b) => b.remove());
      }
      function paintBand() {
        const d = duration();
        if (mode !== "cut" || !isOpen() || !(d > 0) || d === Infinity || c.start == null) { removeBand(); return; }
        const b = ensureBand();
        if (!b) return;
        const [r, g, bl] = hexToRgb(accent.a);
        b.style.left = (c.start / d * 100) + "%";
        b.style.width = Math.max(0.3, (c.end - c.start) / d * 100) + "%";
        b.style.background = `rgba(${r},${g},${bl},.55)`;
        b.style.boxShadow = `inset 2px 0 0 #fff, inset -2px 0 0 #fff, 0 0 10px rgba(${r},${g},${bl},.7)`;
      }

      // ── the frame loop: playhead, preview stop, ad / length changes ─────
      let lastD = -1, lastAd = null;
      function loop() {
        cancelAnimationFrame(raf);
        const step = () => {
          raf = 0;
          if (!isOpen() || mode !== "cut") return;
          const v = player();
          const d = duration(), ad = adShowing(v);
          if (d !== lastD || ad !== lastAd) {
            const was = lastD;
            lastD = d; lastAd = ad;
            if (was !== -1 && c.phase === "edit") { render(); loop(); return; }
          }
          if (c.previewing && v && v.currentTime >= c.end - 0.04) {
            try { v.pause(); } catch (_) {}
            c.previewing = false;
            paint();
          }
          paintHead();
          raf = requestAnimationFrame(step);
        };
        raf = requestAnimationFrame(step);
      }

      function onShow() {
        if (mode !== "cut" || !isOpen()) return;
        lastD = -1;
        loop();
        if (c.phase === "running" || c.phase === "sending") pollCut();
      }
      function onHide(keepPoll) {
        cancelAnimationFrame(raf); raf = 0;
        stopPreview();
        removeBand();
        if (!keepPoll) { clearTimeout(cutPoll); cutPoll = 0; }
      }

      // ── markup ─────────────────────────────────────────────────────────
      function skeletonHTML() {
        return `<div class="cut ghost" aria-busy="true">
            <div class="tcbar"><span class="skl w40"></span><span class="skl w20"></span><span class="skl w40"></span></div>
            <div class="scrub skel"><i></i></div>
            <div class="qgrid">${[0, 1, 2].map((i) => `<span class="skl qchip" style="--d:${i * 90}ms"></span>`).join("")}</div>
          </div><p class="note">${esc(t("reading"))}</p>`;
      }

      function bodyHTML() {
        if (!state.video) return `<div class="off err"><b>${esc(t("cutFailed"))}</b><p>${esc(t("noVideo"))}</p></div>`;
        const v = player();
        if (adShowing(v)) return notice("ad", t("adShowing"));
        const d = duration();
        if (d === Infinity) return notice("live", t("liveStream"));
        if (!(d > 0) || !seedRange()) return notice("wait", t("noPlayer"));
        seedQuality();
        const locked = c.phase !== "edit" && c.phase !== "error";
        const rows = cutRows();
        if (!view) fitView();
        const ticks = tickMarks(win());
        tickKey = win().a + ":" + win().b;
        return `<div class="cut${locked ? " locked" : ""}" data-cphase="${c.phase}">
            <div class="tcbar">
              <label class="tcf in">
                <small>${esc(t("markIn"))}</small>
                <input class="tcin" data-mark="in" inputmode="decimal" spellcheck="false" autocomplete="off" ${locked ? "disabled" : ""} aria-label="${esc(t("markIn"))}">
              </label>
              <span class="len"><b></b><small>${esc(t("clipLen"))}</small></span>
              <label class="tcf out">
                <small>${esc(t("markOut"))}</small>
                <input class="tcin" data-mark="out" inputmode="decimal" spellcheck="false" autocomplete="off" ${locked ? "disabled" : ""} aria-label="${esc(t("markOut"))}">
              </label>
            </div>
            <div class="scrub" dir="ltr">
              <div class="rail">${ticks}</div>
              <div class="dim l"></div><div class="dim r"></div>
              <div class="sel"><u class="cfill"></u></div>
              <span class="h hin" role="slider" tabindex="${locked ? -1 : 0}" data-mark="in" aria-label="${esc(t("markIn"))}" aria-valuemin="0" aria-valuemax="${Math.round(d)}"><i></i></span>
              <span class="h hout" role="slider" tabindex="${locked ? -1 : 0}" data-mark="out" aria-label="${esc(t("markOut"))}" aria-valuemin="0" aria-valuemax="${Math.round(d)}"><i></i></span>
              <span class="ph"></span>
              <span class="hover-t"></span>
            </div>
            <div class="scale" dir="ltr"><span class="sa"></span>
              <button class="zoom" type="button" data-act="zoom"></button>
              <span class="sb"></span></div>
            <div class="mini" dir="ltr" aria-hidden="true"><i class="mwin"></i><i class="msel"></i><i class="mph"></i></div>
            <div class="tools">
              <button class="tool" type="button" data-act="setin" ${locked ? "disabled" : ""}>
                <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 2.5v11M5 2.5h3M5 13.5h3M14 8H8.5m0 0l2.2-2.2M8.5 8l2.2 2.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>${esc(t("setIn"))}</span><kbd>[</kbd></button>
              <button class="tool pv" type="button" data-act="preview" ${locked ? "disabled" : ""}>
                <svg class="pi" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 3.2v9.6L12.6 8z" fill="currentColor"/></svg>
                <svg class="si" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><rect x="4" y="4" width="8" height="8" rx="1.5" fill="currentColor"/></svg>
                <span></span></button>
              <button class="tool" type="button" data-act="setout" ${locked ? "disabled" : ""}>
                <kbd>]</kbd><span>${esc(t("setOut"))}</span>
                <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M11 2.5v11M11 2.5H8M11 13.5H8M2 8h5.5m0 0L5.3 5.8M7.5 8l-2.2 2.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
            </div>
            <div class="split cq">${esc(t("output"))}</div>
            <div class="outseg seg" role="radiogroup" aria-label="${esc(t("output"))}">
              <button type="button" class="fchip${c.audioOnly ? "" : " on"}" role="radio" aria-checked="${!c.audioOnly}" data-act="cutvideo" ${locked ? "disabled" : ""}>
                <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="3.5" width="9" height="9" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10.5 7l4-2.2v6.4l-4-2.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>
                <span>${esc(t("video"))}</span></button>
              <button type="button" class="fchip${c.audioOnly ? " on" : ""}" role="radio" aria-checked="${c.audioOnly}" data-act="cutaudio" ${locked ? "disabled" : ""}>
                <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 12.2V3.5l7-1.5v8.7" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><circle cx="4.3" cy="12.2" r="1.9" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="11.3" cy="10.7" r="1.9" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>
                <span>${esc(t("audioOnly"))}</span><small class="csz aud"></small></button>
            </div>
            ${c.audioOnly ? `
            <div class="cutfmts" role="radiogroup" aria-label="${esc(t("fmtAudio"))}">
              <span class="fl">${esc(t("fmtAudio"))}</span>
              <span class="seg">${(state.formats && state.formats.audio || [{key:"mp3",label:"MP3"},{key:"m4a",label:"M4A"},{key:"opus",label:"OPUS"},{key:"wav",label:"WAV"},{key:"flac",label:"FLAC"}]).map((f) => `<button type="button" class="fchip${c.afmt === f.key ? " on" : ""}" role="radio" aria-checked="${c.afmt === f.key}" data-act="cutaudiofmt" data-val="${esc(f.key)}" ${locked ? "disabled" : ""}>${esc(f.label)}</button>`).join("")}</span>
            </div>` : `
            <div class="qgrid" role="radiogroup" aria-label="${esc(t("quality"))}">
              ${rows.map((r) => {
                const on = r.key === c.cap;
                return `<button type="button" class="qchip${on ? " on" : ""}" role="radio" aria-checked="${on}" data-act="cap" data-key="${esc(r.key)}" ${locked ? "disabled" : ""}>
                    <b>${esc(r.label)}</b><small class="csz" data-key="${esc(r.key)}"></small>
                  </button>`;
              }).join("") || `<p class="note">${esc(t("standard"))}</p>`}
            </div>
            <div class="cutfmts" role="radiogroup" aria-label="${esc(t("fmtVideo"))}">
              <span class="fl">${esc(t("fmtVideo"))}</span>
              <span class="seg">${(state.formats && state.formats.video || [{key:"mp4",label:"MP4"},{key:"mkv",label:"MKV"},{key:"webm",label:"WEBM"}]).map((f) => `<button type="button" class="fchip${c.vfmt === f.key ? " on" : ""}" role="radio" aria-checked="${c.vfmt === f.key}" data-act="cutfmt" data-val="${esc(f.key)}" ${locked ? "disabled" : ""}>${esc(f.label)}</button>`).join("")}</span>
            </div>`}
            ${trackHTML()}
            <p class="note kf"><svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 7.2v4M8 4.9v.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg><span>${esc(c.audioOnly ? t("audioCutNote") : t("keyframe"))}</span></p>
            ${c.phase === "error" ? `<div class="off err"><b>${esc(t("cutFailed"))}</b><p>${esc(c.message)}</p></div>` : ""}
          </div>`;
      }

      function notice(kind, text) {
        const icon = kind === "ad"
          ? '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 15l2-6 2 6M8.7 13h2.6M14.5 9v6h1.3a2.5 2.5 0 000-6z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>'
          : kind === "live"
          ? '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="2.6" fill="currentColor"/><path d="M7.8 7.8a6 6 0 000 8.4M16.2 7.8a6 6 0 010 8.4M5 5a10 10 0 000 14M19 5a10 10 0 010 14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>'
          : '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13L18.5 12z" fill="currentColor"/></svg>';
        return `<div class="cnotice ${kind}"><span class="ci">${icon}</span><p>${esc(text)}</p></div>`;
      }

      // minor ticks every "nice" step, a taller one every 5th — a ruler,
      // so the rail reads as time rather than as a slider
      function tickMarks(v) {
        const sp = Math.max(1e-6, v.b - v.a);
        const steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600];
        const step = steps.find((x) => sp / x <= 60) || 3600;
        let out = "";
        for (let x = Math.ceil((v.a + 1e-6) / step) * step; x < v.b; x += step) {
          const maj = Math.round(x / step) % 5 === 0;
          out += `<i class="${maj ? "maj" : ""}" style="left:${((x - v.a) / sp * 100).toFixed(3)}%"></i>`;
        }
        return out;
      }

      function footHTML() {
        if (!state.video || adShowing(player()) || !(duration() > 0) || duration() === Infinity) return "";
        const scissors = scissorsSVG(18);
        switch (c.phase) {
          case "edit":
          case "error":
            return `<button class="primary cutgo" type="button" data-act="cut"${c.start == null ? " disabled" : ""}>
                ${scissors}<span>${esc(t("cutBtn"))}</span>
                <span class="pill"><span class="pq">${esc(cutPill())}</span> · <span class="pl"></span></span>
              </button>`;
          case "sending":
          case "running":
            // v3.48: the same live capsule as Download, ■ on the end
            return `<div class="dlc cutdlc" data-st="${c.phase}" data-ind>
                <div class="cap" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" aria-label="${esc(t("cutting"))}">
                  <span class="capfill" style="--p:0"><i></i></span>
                  <span class="capnum"><b>0</b><small>%</small></span>
                  <span class="capmeta"><b class="capst">${esc(c.phase === "sending" ? t("cutSending") : t("cutting"))}</b><small class="capq">${esc(cutPill())} · ${esc(tc(c.end - c.start))}</small></span>
                  <button class="capbtn" type="button" data-act="cutstop" title="${esc(t("cutStop"))}" aria-label="${esc(t("cutStop"))}"><svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><rect x="3.5" y="3.5" width="9" height="9" rx="2" fill="currentColor"/></svg><span class="capspin"></span></button>
                </div>
                <div class="stats">
                  <span class="st"><b class="vsp">—</b><small>${esc(t("speed"))}</small><svg class="spark" viewBox="0 0 60 16" preserveAspectRatio="none" aria-hidden="true"><path d=""/></svg></span>
                  <span class="st"><b class="vsz">—</b><small class="vtot">${esc(t("sizeSoFar"))}</small></span>
                  <span class="st"><b class="veta soft">—</b><small>${esc(t("left"))}</small></span>
                </div>
                <p class="keep">${esc(t("cutKeep"))}</p>
              </div>`;
          case "done": {
            const r = c.result || {};
            return `<div class="done">
                <span class="tick">${scissorsSVG(20)}</span>
                <span class="dn"><b>${esc(t("cutSaved"))}${r.size ? " · " + esc(bytes(r.size)) : ""}</b><small>${esc(r.name || t("cutSavedBody"))}</small></span>
              </div>
              <div class="row2">
                <button class="primary" type="button" data-act="cutreveal"><span>${esc(t("showFolder"))}</span></button>
                <button class="ghost" type="button" data-act="cutnew">${esc(t("newCut"))}</button>
              </div>
              <button class="link2" type="button" data-act="cutapp">${esc(t("openCutter"))}</button>`;
          }
          default:
            return "";
        }
      }

      // ── in-place paint (no re-render while dragging) ────────────────────
      function paint() {
        paintBand();
        if (!root || mode !== "cut") return;
        const box = root.querySelector(".cut");
        if (!box || c.start == null) return;
        const d = duration() || c.end || 1;
        if (!drag && (!view || c.start < win().a - 0.01 || c.end > win().b + 0.01)) fitView();
        const q = (sel) => box.querySelector(sel);
        const v = win();
        const k = v.a + ":" + v.b;
        if (k !== tickKey) { tickKey = k; q(".rail").innerHTML = tickMarks(v); }
        const cl = (x) => Math.max(0, Math.min(100, x));
        const a = cl(pos(c.start)), b = cl(pos(c.end));
        q(".sel").style.left = a + "%";
        q(".sel").style.width = (b - a) + "%";
        q(".dim.l").style.width = a + "%";
        q(".dim.r").style.left = b + "%";
        q(".hin").style.left = a + "%";
        q(".hout").style.left = b + "%";
        q(".hin").style.visibility = c.start < v.a - 0.01 ? "hidden" : "";
        q(".hout").style.visibility = c.end > v.b + 0.01 ? "hidden" : "";
        // scale + zoom switch + overview strip
        const zoomed = isZoomed();
        q(".scale .sa").textContent = clock(v.a);
        q(".scale .sb").textContent = clock(v.b);
        const zb = q(".scale .zoom");
        if (zb) {
          const canZoom = zoomAll || zoomed;
          zb.hidden = !canZoom;
          zb.textContent = zoomed ? t("zoomAll") : t("zoomClip");
          zb.disabled = c.phase !== "edit" && c.phase !== "error";
        }
        box.toggleAttribute("data-zoomed", zoomed);
        const mini = q(".mini");
        if (mini) {
          mini.querySelector(".mwin").style.left = (v.a / d * 100) + "%";
          mini.querySelector(".mwin").style.width = ((v.b - v.a) / d * 100) + "%";
          mini.querySelector(".msel").style.left = (c.start / d * 100) + "%";
          mini.querySelector(".msel").style.width = Math.max(0.4, (c.end - c.start) / d * 100) + "%";
        }
        q(".hin").setAttribute("aria-valuenow", c.start.toFixed(1));
        q(".hin").setAttribute("aria-valuetext", tc(c.start));
        q(".hout").setAttribute("aria-valuenow", c.end.toFixed(1));
        q(".hout").setAttribute("aria-valuetext", tc(c.end));
        const ins = box.querySelectorAll(".tcin");
        for (const el of ins) {
          if (root.activeElement === el) continue;      // don't fight the typist
          el.value = tc(el.getAttribute("data-mark") === "in" ? c.start : c.end);
        }
        q(".len b").textContent = tc(c.end - c.start);
        box.querySelectorAll(".csz").forEach((el) => {
          if (el.classList.contains("aud")) {
            const a = state.rows.find((x) => x.isAudio);
            el.textContent = estimate(a);
            return;
          }
          const r = state.rows.find((x) => x.key === el.getAttribute("data-key"));
          el.textContent = estimate(r);
        });
        const pv = q(".pv");
        if (pv) {
          pv.classList.toggle("playing", !!c.previewing);
          pv.querySelector("span").textContent = c.previewing ? t("stopPreview") : t("preview");
        }
        const pl = root.querySelector(".cutgo .pl");
        if (pl) pl.textContent = tc(c.end - c.start);
        const ps = root.querySelector(".cutgo .pq");
        if (ps) ps.textContent = cutPill();
        paintHead();
        paintCutProgress();
      }

      function paintHead() {
        if (!root) return;
        const ph = root.querySelector(".cut .ph");
        if (!ph) return;
        const d = duration();
        if (!(d > 0) || d === Infinity) return;
        const p = pos(now());
        ph.style.left = Math.max(0, Math.min(100, p)) + "%";
        ph.style.opacity = p < -0.5 || p > 100.5 ? "0" : "";
        const mp = root.querySelector(".cut .mini .mph");
        if (mp) mp.style.left = (now() / d * 100) + "%";
      }

      function paintCutProgress() {
        if (!root || (c.phase !== "running" && c.phase !== "sending")) return;
        const s = c.live || {};
        const pct = Math.max(0, Math.min(100, Number(s.pct) || 0));
        const dlc = root.querySelector(".cutdlc");
        if (dlc) {
          dlc.setAttribute("data-st", c.phase);
          dlc.toggleAttribute("data-ind", c.phase === "sending" || pct <= 0);
          dlc.querySelector(".cap").setAttribute("aria-valuenow", String(pct));
          dlc.querySelector(".capfill").style.setProperty("--p", String(pct / 100));
          dlc.querySelector(".capnum b").textContent = String(pct);
          dlc.querySelector(".capst").textContent =
            s.text || (c.phase === "sending" ? t("cutSending") : t("cutting"));
          const sb = dlc.querySelector(".capbtn");
          if (sb) sb.disabled = c.phase === "sending";
          // v3.49: speed · size · time left, exactly like the Download capsule.
          // The app sends them since 1.1.2; an older app only sends pct +
          // written, so the same numbers are derived here from the polls.
          const now = performance.now();
          const w = Number(s.written) || 0;
          let spd = Number(s.speed) || 0, tot = Number(s.total) || 0, eta = Number(s.eta) || 0;
          if (!cutRate.t0 && w > 0) cutRate = { t0: now, t: now, w, spd: 0 };
          if (cutRate.t0 && now - cutRate.t >= 450) {
            const inst = Math.max(0, (w - cutRate.w) / ((now - cutRate.t) / 1000));
            cutRate.spd = cutRate.spd > 0 ? cutRate.spd * 0.65 + inst * 0.35 : inst;
            cutRate.t = now; cutRate.w = w;
          }
          if (!("speed" in s)) {
            spd = cutRate.spd;
            if (pct >= 3 && w > 0) tot = Math.round(w * 100 / pct);
            const el = cutRate.t0 ? (now - cutRate.t0) / 1000 : 0;
            if (pct >= 2 && pct < 100 && el > 1.5) eta = el * (100 - pct) / pct;
          }
          if (spd > 0 && (!cutSpeeds.length || now - cutSpeedAt > 500)) {
            cutSpeeds.push(spd); cutSpeedAt = now;
            if (cutSpeeds.length > 24) cutSpeeds.shift();
          }
          const live = c.phase === "running" && pct > 0;
          dlc.querySelector(".vsp").textContent = live && spd > 0 ? bytes(spd) + "/s" : "—";
          dlc.querySelector(".vsz").textContent = w > 0 ? bytes(w) : (pct > 0 ? pct + "%" : "—");
          dlc.querySelector(".vtot").textContent = tot > w && tot > 0 ? t("ofTotal").replace("{t}", "~" + bytes(tot)) : t("sizeSoFar");
          const ve = dlc.querySelector(".veta");
          ve.textContent = live && eta > 0 ? clock(eta) : (c.phase === "running" ? t("etaWait") : "—");
          ve.classList.toggle("soft", !(live && eta > 0));
          dlc.querySelector(".spark path").setAttribute("d", live ? sparkPath(cutSpeeds) : "");
        }
        const f = root.querySelector(".cut .cfill");
        if (f) f.style.width = pct + "%";
      }

      // ── input ─────────────────────────────────────────────────────────
      function bind(body) {
        const box = body.querySelector(".cut");
        if (!box) return;
        const scrub = box.querySelector(".scrub");
        const mini = box.querySelector(".mini");
        if (mini) mini.addEventListener("pointerdown", onMini);
        scrub.addEventListener("pointerdown", onDown);
        scrub.addEventListener("pointermove", onHover);
        scrub.addEventListener("pointerleave", () => scrub.classList.remove("hovering"));
        box.querySelectorAll(".h").forEach((h) => h.addEventListener("keydown", onHandleKey));
        box.querySelectorAll(".tcin").forEach((el) => {
          el.addEventListener("change", () => commitTc(el));
          el.addEventListener("keydown", (e) => {
            e.stopPropagation();                 // YouTube shortcuts stay out
            if (e.key === "Enter") { e.preventDefault(); commitTc(el); el.blur(); }
            else if (e.key === "Escape") { e.preventDefault(); el.value = ""; el.blur(); paint(); }
            else if (e.key === "ArrowUp" || e.key === "ArrowDown") {
              e.preventDefault();
              nudge(el.getAttribute("data-mark"), (e.key === "ArrowUp" ? 1 : -1) * (e.shiftKey ? 1 : 0.1));
              el.value = tc(el.getAttribute("data-mark") === "in" ? c.start : c.end);
            }
          });
          el.addEventListener("keyup", (e) => e.stopPropagation());
          el.addEventListener("keypress", (e) => e.stopPropagation());
          el.addEventListener("blur", () => paint());
        });
      }

      function commitTc(el) {
        const v = parseTc(el.value);
        if (Number.isNaN(v)) { paint(); return; }
        const m = el.getAttribute("data-mark");
        if (m === "in") setRange(v, c.end, "in"); else setRange(c.start, v, "out");
        maybeRefit(); paint();
        seek(m === "in" ? c.start : c.end);
      }

      function nudge(m, dt) {
        if (c.phase !== "edit" && c.phase !== "error") return;
        if (m === "in") { setRange(c.start + dt, c.end, "in"); seek(c.start); }
        else { setRange(c.start, c.end + dt, "out"); seek(c.end); }
      }

      function onHandleKey(e) {
        const m = e.currentTarget.getAttribute("data-mark");
        const big = e.shiftKey ? 1 : 0.1;
        if (e.key === "ArrowLeft" || e.key === "ArrowDown") nudge(m, -big);
        else if (e.key === "ArrowRight" || e.key === "ArrowUp") nudge(m, big);
        else if (e.key === "PageDown") nudge(m, -5);
        else if (e.key === "PageUp") nudge(m, 5);
        else return;
        e.preventDefault();
        e.stopPropagation();
      }

      const timeAt = (scrub, x) => {
        const r = scrub.getBoundingClientRect();
        const v = win();
        return v.a + Math.max(0, Math.min(1, (x - r.left) / Math.max(1, r.width))) * (v.b - v.a);
      };

      // the overview strip: press / drag to slide the zoom window there
      function onMini(e) {
        if (e.button !== 0) return;
        const mini = e.currentTarget;
        const d = duration();
        if (!(d > 0) || d === Infinity) return;
        e.preventDefault();
        mini.setPointerCapture(e.pointerId);
        const go = (x) => {
          const r = mini.getBoundingClientRect();
          const tt = Math.max(0, Math.min(1, (x - r.left) / Math.max(1, r.width))) * d;
          const v = win(), sp = v.b - v.a;
          let a = Math.max(0, Math.min(d - sp, tt - sp / 2));
          view = { a, b: a + sp };
          drag = drag || { kind: "pan" };
          paint();
        };
        go(e.clientX);
        const mv = (ev) => go(ev.clientX);
        const up = () => {
          mini.removeEventListener("pointermove", mv);
          mini.removeEventListener("pointerup", up);
          mini.removeEventListener("pointercancel", up);
          drag = null;
        };
        mini.addEventListener("pointermove", mv);
        mini.addEventListener("pointerup", up);
        mini.addEventListener("pointercancel", up);
      }

      function onDown(e) {
        if (c.phase !== "edit" && c.phase !== "error") return;
        if (e.button !== 0) return;
        const scrub = e.currentTarget;
        const t0 = timeAt(scrub, e.clientX);
        const h = e.target.closest(".h");
        let kind = h ? h.getAttribute("data-mark") : null;
        if (!kind && e.target.closest(".sel")) kind = "move";
        if (!kind) kind = "seek";
        stopPreview(true);
        const v = player();
        if (kind !== "seek" && v && !v.paused) { try { v.pause(); } catch (_) {} }
        drag = { kind, scrub, off: t0 - c.start, len: c.end - c.start, id: e.pointerId };
        scrub.setPointerCapture(e.pointerId);
        scrub.classList.add("dragging");
        scrub.setAttribute("data-drag", kind);
        e.preventDefault();
        moveTo(e.clientX);
        const up = () => {
          scrub.removeEventListener("pointermove", mv);
          scrub.removeEventListener("pointerup", up);
          scrub.removeEventListener("pointercancel", up);
          scrub.classList.remove("dragging");
          scrub.removeAttribute("data-drag");
          const k = drag && drag.kind;
          drag = null;
          if (k !== "seek") { maybeRefit(); paint(); }
          // land on the exact frame (fastSeek snaps to keyframes)
          if (k === "in" || k === "move") seek(c.start);
          else if (k === "out") seek(c.end);
          if (k !== "seek") {
            const focusH = scrub.querySelector(k === "out" ? ".hout" : ".hin");
            focusH && focusH.focus({ preventScroll: true });
          }
        };
        const mv = (ev) => { if (drag && ev.pointerId === drag.id) moveTo(ev.clientX); };
        scrub.addEventListener("pointermove", mv);
        scrub.addEventListener("pointerup", up);
        scrub.addEventListener("pointercancel", up);
      }

      function moveTo(x) {
        if (!drag) return;
        const tt = timeAt(drag.scrub, x);
        const d = duration();
        if (drag.kind === "in") { setRange(Math.min(tt, c.end - MIN_LEN), c.end, "in"); seek(c.start); }
        else if (drag.kind === "out") { setRange(c.start, Math.max(tt, c.start + MIN_LEN), "out"); seek(c.end); }
        else if (drag.kind === "move") {
          let s = Math.max(0, Math.min(d - drag.len, tt - drag.off));
          c.start = Math.round(s * 10) / 10;
          c.end = Math.round((s + drag.len) * 10) / 10;
          paint();
          seek(c.start);
        } else { seek(tt); paintHead(); }
        showHoverT(drag.scrub, x);
      }

      function onHover(e) {
        if (drag) return;
        showHoverT(e.currentTarget, e.clientX);
      }
      function showHoverT(scrub, x) {
        const r = scrub.getBoundingClientRect();
        const ht = scrub.querySelector(".hover-t");
        if (!ht) return;
        const tt = timeAt(scrub, x);
        ht.textContent = tc(drag && drag.kind === "in" ? c.start : drag && drag.kind === "out" ? c.end : tt);
        const px = Math.max(22, Math.min(r.width - 22, x - r.left));
        ht.style.left = px + "px";
        scrub.classList.add("hovering");
      }

      function onKey(e) {
        if (c.phase !== "edit" && c.phase !== "error") return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const path = e.composedPath ? e.composedPath() : [];
        const typing = path.some((n) => n && (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName || "")));
        if (typing) return;
        if (e.key === "[" || e.key === "]") {
          e.preventDefault();
          e.stopPropagation();
          if (e.key === "[") onAct("setin"); else onAct("setout");
        }
      }

      // ── actions ─────────────────────────────────────────────────────────
      function onAct(act, el) {
        if (act === "setin") {
          if (c.start == null) return;
          const p = now();
          if (p >= c.end - MIN_LEN) setRange(p, Math.min(duration(), p + Math.max(MIN_LEN, c.end - c.start)), "in");
          else setRange(p, c.end, "in");
          maybeRefit(); paint();
          flash("in");
        } else if (act === "setout") {
          if (c.start == null) return;
          const p = now();
          if (p <= c.start + MIN_LEN) setRange(Math.max(0, p - Math.max(MIN_LEN, c.end - c.start)), p, "out");
          else setRange(c.start, p, "out");
          maybeRefit(); paint();
          flash("out");
        } else if (act === "zoom") {
          zoomAll = isZoomed();
          fitView();
          paint();
        } else if (act === "cutvideo") {
          if (c.phase !== "edit" && c.phase !== "error") return;
          c.audioOnly = false;
          c.format = c.vfmt;
          if (c.phase === "error") c.phase = "edit";
          render();
        } else if (act === "preview") {
          if (c.previewing) stopPreview(true); else startPreview();
        } else if (act === "cutfmt" || act === "cutaudiofmt" || act === "cutaudio") {
          if (c.phase !== "edit" && c.phase !== "error") return;
          c.audioOnly = act !== "cutfmt";
          const v = el.getAttribute("data-val");
          if (act === "cutfmt" && v) c.vfmt = v;
          if (act === "cutaudiofmt" && v) c.afmt = v;
          c.format = c.audioOnly ? c.afmt : c.vfmt;
          if (c.phase === "error") c.phase = "edit";
          render();
        } else if (act === "cap") {
          if (c.phase !== "edit" && c.phase !== "error") return;
          c.cap = el.getAttribute("data-key");
          c.audioOnly = false;
          c.format = c.vfmt;
          if (c.phase === "error") c.phase = "edit";
          render();
          const b = root.querySelector(`.qchip[data-key="${CSS.escape(c.cap)}"]`);
          b && b.focus({ preventScroll: true });
        } else if (act === "cut") startCut();
        else if (act === "cutstop") {
          if (c.job) call("/v1/cut/cancel", { method: "POST", body: { job: c.job } });
        } else if (act === "cutreveal") {
          if (c.job) call("/v1/cut/reveal", { method: "POST", body: { job: c.job } });
        } else if (act === "cutnew") {
          c.phase = "edit"; c.job = null; c.result = null; c.live = null; c.message = "";
          render();
        } else if (act === "cutapp") {
          call("/v1/show", { method: "POST", body: { page: 12 } });
        }
      }

      function flash(which) {
        const el = root && root.querySelector(which === "in" ? ".cut .tcf.in" : ".cut .tcf.out");
        if (!el) return;
        el.classList.remove("flash");
        void el.offsetWidth;
        el.classList.add("flash");
      }

      async function startCut() {
        if (c.start == null || !c.cap) return;
        stopPreview(true);
        const meta = state.meta || pageMeta();
        c.phase = "sending";
        c.live = { pct: 0 };
        cutRate = { t0: 0, t: 0, w: 0, spd: 0 }; cutSpeeds = []; cutSpeedAt = 0;
        c.message = "";
        render();
        const res = await call("/v1/cut", {
          method: "POST",
          body: { v: state.video.id, cap: parseInt(c.cap, 10) || 0, start: c.start, end: c.end,
                  title: meta.title, channel: meta.channel,
                  format: c.audioOnly ? c.afmt : c.vfmt, audioOnly: !!c.audioOnly, lang: state.lang || "" },
          timeout: 15000,
        });
        if (!res.reachable) { state.phase = "offline"; c.phase = "edit"; render(); return; }
        if (!res.data || !res.data.ok || !res.data.job) {
          c.phase = "error";
          c.message = res.status === 404 ? t("cutNeedsUpdate")
                    : (res.data && res.data.error) || t("cutFailed");
          render();
          return;
        }
        c.job = res.data.job;
        c.phase = "running";
        render();
        pollCut();
      }

      function pollCut() {
        clearTimeout(cutPoll);
        const job = c.job, vid = state.video && state.video.id;
        if (!job) return;
        // v3.51: only an explicit state:"error" from the app is a failed cut.
        // Anything else that isn't a clean answer (empty body, 5xx, a 404 while
        // the app is busy, an unknown state) is a hiccup in the status poll —
        // the cut itself keeps running in the app — so keep asking instead of
        // painting "Cut failed" over a cut that is still going.
        let misses = 0, bad = 0;
        const tick = async () => {
          if (!isOpen() || c.job !== job || !state.video || state.video.id !== vid) return;
          // watch=1 only while this tab is on screen (same rule as the download
          // poll): it is what keeps the app's corner card away, so sending it
          // from a hidden tab kept the card hidden after the user had left.
          const watch = document.visibilityState === "visible" ? "&watch=1" : "";
          const r = await call("/v1/cut/status?job=" + encodeURIComponent(job) + watch, { timeout: 6000 });
          if (c.job !== job) return;
          const s = (r && r.data) || {};
          if (!r.reachable) {
            if (++misses > 8) { state.phase = "offline"; render(); return; }
          } else if (s.state === "starting" || s.state === "running") {
            misses = 0; bad = 0;
            c.live = s;
            if (mode === "cut") paintCutProgress();
          } else if (s.state === "done") {
            c.phase = "done"; c.result = s; render();
            if (mode === "cut") burst();
            return;
          } else if (s.state === "stopped") {
            c.phase = "error"; c.message = t("cutStopped"); render(); return;
          } else if (s.state === "error") {
            c.phase = "error"; c.message = s.error || t("cutFailed"); render(); return;
          } else {
            misses = 0;
            // 404 = the app no longer knows this job (it was restarted);
            // anything else is a transient bad reply. Either way, retry first.
            if (++bad > (r.status === 404 ? 5 : 15)) {
              c.phase = "error";
              c.message = r.status === 404 ? t("cutLost")
                        : (s.error || t("cutFailed")) + (r.status ? " (" + r.status + ")" : "");
              render();
              return;
            }
          }
          cutPoll = setTimeout(tick, 600);
        };
        cutPoll = setTimeout(tick, 350);
      }

      const job = () => (c && (c.phase === "running" || c.phase === "sending") ? c.job : null);
      return { reset, seedQuality, onShow, onHide, bodyHTML, footHTML, skeletonHTML,
               bind, paint, onAct, onKey, job, dur: () => (c ? duration() : 0) };
    })();

    // v3.48: the button moved (YouTube re-rendered the row): keep the open
    // panel tied to the new one so the button stays lit and Esc refocuses it
    const anchoredTo = (h) => !!h && h === anchorBtn && isOpen();
    function reanchor(h) { anchorBtn = h; setExpanded(true); }

    return { toggle, open, close, onNavigate, retheme, anchoredTo, reanchor };
  })();

  // first paint
  ensureButton();
  // v3.43: installation hand-off. The desktop setup dialog closes as soon
  // as a content script proves the unpacked extension is alive. This is a
  // harmless local ping when the app is not running and does not touch YouTube.
  call("/v1/ping", { timeout: 1200 });
})();
