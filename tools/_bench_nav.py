"""Headless navigation benchmark (temporary).

    YH_BENCH=idle,first,repeat,pageidle,audit
    YH_BENCH_PAGES=5,10
    python tools/_bench_nav.py

Holds the background warm-up, then times page builds/switches, idle frames +
process CPU, and (optionally) per-page idle and a hidden-page unload audit.
"""
import os
import sys
import time
import json
import traceback

sys.path.insert(0, os.getcwd())
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_LOGGING_RULES", "qt.qml.binding.removal.info=false")

import main_qml
from PySide6.QtCore import QTimer, Qt, QObject
from PySide6.QtGui import QGuiApplication

captured = {}
results = {"first": {}, "repeat": {}, "idle": [], "pageidle": [], "pages": [],
           "stalls": [], "audit": [], "sync": {}}

for _name, _target, _attr in (("geo", "app.qml_backend.vm.geo_vm", "checkStartup"),
                              ("upd", "app.qml_backend.vm.update_vm", "start")):
    try:
        _m = __import__(_target, fromlist=["x"])
        _cls = getattr(_m, "GeoVM" if _name == "geo" else "UpdateVM")
        setattr(_cls, _attr, (lambda self: None) if _name == "geo"
                else (lambda self, first_delay_ms=6000: None))
    except Exception:
        pass
try:
    main_qml.WebBridge.start = lambda self: None
except Exception:
    pass

OrigApp = main_qml.AppController


class BenchApp(OrigApp):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        captured["app"] = self


main_qml.AppController = BenchApp

OrigExt = main_qml.ExtensionSetupVM


class BenchExt(OrigExt):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self._offered = True
        captured["ext"] = self


main_qml.ExtensionSetupVM = BenchExt

OrigEngine = main_qml.QQmlApplicationEngine


class BenchEngine(OrigEngine):
    def load(self, url):
        r = super().load(url)
        captured["engine"] = self
        QTimer.singleShot(650, _start)
        return r


main_qml.QQmlApplicationEngine = BenchEngine

PAGE_NAMES = {0: "Dashboard", 1: "Logs", 2: "History", 3: "Monetize", 4: "Niche",
              5: "Archive", 6: "Ideas", 7: "ContentLab", 8: "Downloads", 9: "Usage",
              10: "Settings", 11: "Insights", 12: "Cutter", 13: "AIChat"}

PHASES = [p.strip() for p in os.environ.get("YH_BENCH", "idle,first,repeat,pageidle").split(",") if p.strip()]
PAGES = [int(p) for p in os.environ.get("YH_BENCH_PAGES", "").split(",") if p.strip() != ""]


class Bench:
    def __init__(self, win, app):
        self.win = win
        self.app = app
        self.stack = win.findChild(QObject, "pageStack")
        self.warm = win.findChild(QObject, "warmTimer")
        self.heart = win.findChild(QObject, "heartBeat")
        self._goto_t = 0.0
        self.stalls = []
        self.last_tick = time.perf_counter()
        self.watch = QTimer()
        self.watch.setInterval(5)
        self.watch.setTimerType(Qt.PreciseTimer)
        self.watch.timeout.connect(self._tick)
        self.watch.start()
        self.frames = 0
        win.frameSwapped.connect(self._frame, Qt.DirectConnection)
        self._phase = ""
        self._poll = None
        for i in range(self.stack.property("count")):
            results["pages"].append({"i": i, "name": PAGE_NAMES.get(i, str(i))})

    def _frame(self):
        self.frames += 1

    def _tick(self):
        now = time.perf_counter()
        delta = (now - self.last_tick) * 1000.0
        self.last_tick = now
        if delta > 35.0:
            self.stalls.append({
                "phase": self._phase,
                "ms": round(delta, 1),
                "since_goto": round((now - self._goto_t) * 1000.0, 1) if self._goto_t else None,
            })
            if len(self.stalls) > 800:
                self.stalls = self.stalls[-800:]

    def _set_phase(self, phase):
        self._phase = phase
        self._goto_t = time.perf_counter()

    def later(self, ms, fn):
        QTimer.singleShot(ms, fn)

    def close_deno(self):
        dialog = self.win.findChild(QObject, "denoDialog")
        if dialog is not None and dialog.property("opened"):
            dialog.setProperty("visible", False)

    def stop_warm(self):
        if self.warm is not None:
            self.warm.setProperty("running", False)
            self.warm.setProperty("interval", 3600000)

    def goto_and_time(self, i, tag, done, timeout=8000):
        self._set_phase(f"{tag}:{i}")
        t0 = time.perf_counter()
        self.app.goto(i)
        sync_ms = (time.perf_counter() - t0) * 1000.0
        start = time.perf_counter()
        bucket = results.setdefault(tag, {})

        def poll():
            if int(self.stack.property("currentIndex")) == i:
                ms = (time.perf_counter() - start) * 1000.0
                self._poll.stop()
                bucket[i] = round(ms, 1)
                results["sync"][i] = round(sync_ms, 1)
                done(ms)
                return
            if (time.perf_counter() - start) * 1000.0 > timeout:
                self._poll.stop()
                bucket[i] = -1
                results["sync"][i] = round(sync_ms, 1)
                done(-1)
                return

        self._poll = QTimer()
        self._poll.setInterval(2)
        self._poll.setTimerType(Qt.PreciseTimer)
        self._poll.timeout.connect(poll)
        self._poll.start(2)

    def measure_idle(self, label, ms, done, bucket="idle"):
        self._set_phase("idle:" + label)
        f0 = self.frames
        c0 = time.process_time()
        t0 = time.perf_counter()

        def fin():
            frames = self.frames - f0
            cpu = (time.process_time() - c0) * 1000.0
            wall = (time.perf_counter() - t0) * 1000.0
            hb = self.heart
            item = {"label": label, "frames": frames,
                    "fps": round(frames / (wall / 1000.0), 1) if wall else 0,
                    "cpu_ms": round(cpu, 1), "wall_ms": round(wall, 1),
                    "beating": hb.property("beating") if hb else None,
                    "loops": hb.property("beatLoops") if hb else None}
            results[bucket].append(item)
            print(f"[bench] idle {label:32s} frames={frames:3d} cpu={item['cpu_ms']:6.1f}ms"
                  f" beating={item['beating']} loops={item['loops']}", flush=True)
            done()

        self.later(ms, fin)

    def deactivate(self, i):
        try:
            self.stack.childItems()[i].setProperty("active", False)
        except Exception:
            pass


bench = None


def _start():
    global bench
    try:
        win = captured["engine"].rootObjects()[0]
        bench = Bench(win, captured["app"])
        bench.stop_warm()
        QTimer.singleShot(180000, lambda: finish("hard-timeout"))
        print("[bench] up; heart:", bench.heart is not None,
              "loaders:", len(bench.stack.childItems()), flush=True)
        bench.later(500, bench.close_deno)
        if "inspect" in PHASES:
            bench.later(300, run_inspect)
        elif "settings" in PHASES:
            bench.later(300, run_settings)
        else:
            bench.goto_and_time(1, "boot", lambda ms: bench.later(500, run_idle))
    except Exception:
        traceback.print_exc()
        QGuiApplication.instance().quit()


def run_idle():
    if "idle" not in PHASES:
        return run_first()
    hb = bench.heart

    def set_racing(on):
        if hb is not None:
            hb.setProperty("racing", on)

    def rest2():
        set_racing(False)
        bench.later(300, lambda: bench.measure_idle(
            "beat_rest_2", 1000, lambda: bench.later(200, run_first)))

    def racing():
        set_racing(True)
        bench.later(300, lambda: bench.measure_idle("beat_racing", 1000, rest2))

    def rest1():
        bench.measure_idle("beat_rest_1", 1000, racing)

    # let the startup intros/skeletons finish first: their fades also paint
    bench.later(3500, rest1)


FIRST_ORDER = PAGES or [2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 5]


def run_first():
    if "first" not in PHASES:
        return run_repeat()

    def step(k=0):
        if k >= len(FIRST_ORDER):
            return run_repeat()
        i = FIRST_ORDER[k]

        def done(ms):
            print(f"[bench] first {i:2d} {PAGE_NAMES[i]:11s} {ms:8.1f} ms", flush=True)
            bench.later(200, lambda: step(k + 1))

        bench.goto_and_time(i, "first", done)

    step()


REPEAT_ORDER = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 4, 8, 10, 12, 13, 0]


def run_repeat():
    if "repeat" not in PHASES:
        return run_pageidle()

    def step(k=0):
        if k >= len(REPEAT_ORDER):
            return run_pageidle()
        i = REPEAT_ORDER[k]

        def done(ms):
            print(f"[bench] repeat {i:2d} {PAGE_NAMES[i]:11s} {ms:8.1f} ms", flush=True)
            bench.later(100, lambda: step(k + 1))

        bench.goto_and_time(i, "repeat", done)

    step()


def run_settings():
    """Time the shell-first Settings page, then prove the queued jump lands."""
    t0 = time.perf_counter()
    bench.app.goto(10)
    st = {"ready": None, "loaded": None, "jump_at": None, "check_at": None}

    def poll():
        el = (time.perf_counter() - t0) * 1000
        if bench.stack.property("currentIndex") != 10:
            if el > 8000:
                tm.stop(); finish()
            return
        win = bench.win
        wrapper = bench.stack.childItems()[10].property("item")
        page = wrapper.property("page") if wrapper is not None else None
        loader = win.findChild(QObject, "settingsSections")
        item = loader.property("item") if loader else None
        if st["ready"] is None:
            st["ready"] = el
            # exactly what the rail does while the cards are still building
            st["jump_at"] = el
            if page is not None:
                from PySide6.QtQml import QQmlExpression, QQmlContext
                ctx = QQmlContext(captured["engine"].rootContext())
                expr = QQmlExpression(ctx, page, "jumpTo(5, true)")
                if expr.hasError():
                    print("[settings] expr error:", expr.error().toString(), flush=True)
                else:
                    expr.evaluate()
                print("[settings] queued jump pending:", page.property("_pendingJump"), flush=True)
        if st["loaded"] is None and item is not None:
            st["loaded"] = el
            secs = []
            for i in range(7):
                sec = win.findChild(QObject, "settingsSection%d" % i)
                secs.append(None if sec is None else round(sec.property("height") or 0, 1))
            print(f"[settings] ready={st['ready']:.0f}ms loaded={el:.0f}ms "
                  f"(+{el - st['ready']:.0f}) heights={secs}", flush=True)
            st["check_at"] = el + 400
        if st["check_at"] is not None and el >= st["check_at"]:
            print(f"[settings] activeSection={page.property('activeSection')} "
                  f"pending={page.property('_pendingJump')}", flush=True)
            tm.stop(); finish()

    tm = QTimer()
    tm.setInterval(20)
    tm.timeout.connect(poll)
    tm.start()


def run_inspect():
    t0 = time.perf_counter()
    bench.app.goto(5)
    state = {}

    def deck_obj():
        return bench.win.findChild(QObject, "archiveDeck")

    def card_info():
        deck = deck_obj()
        if not deck or deck.property("item") is None:
            return "no deck item"
        item = deck.property("item")
        cells = item.childItems()
        card = cells[0].childItems()[0] if cells and cells[0].childItems() else None
        ch = round(card.property("implicitHeight"), 1) if card else None
        return (f"deck w={deck.property('width')} h={deck.property('height')}"
                f" cells={len(cells)} card_h={ch}")

    def after_open():
        arch = captured["engine"].rootContext().contextProperty("Archive")
        print(f"[inspect] isDetail={arch.property('isDetail')}"
              f" rows={len(arch.property('rows') or [])}", flush=True)
        print("[inspect] opened", card_info(), flush=True)
        groups = arch.property("groups") or []
        gid = groups[1].get("id") if len(groups) > 1 else None
        if gid is not None:
            t = time.perf_counter(); arch.closeDetail()
            print(f"[inspect] closeDetail {(time.perf_counter()-t)*1000:.1f}ms", flush=True)
            t = time.perf_counter(); arch.openGroup(gid)
            print(f"[inspect] reopen warm {(time.perf_counter()-t)*1000:.1f}ms", flush=True)
            t = time.perf_counter(); arch.closeDetail()
            print(f"[inspect] closeDetail2 {(time.perf_counter()-t)*1000:.1f}ms", flush=True)
        finish()

    def open_group():
        tm.stop()
        arch = captured["engine"].rootContext().contextProperty("Archive")
        groups = arch.property("groups") or []
        print("[inspect] before open", card_info(), f"groups={len(groups)}", flush=True)
        if groups:
            gid = groups[0].get("id")
            t = time.perf_counter()
            arch.openGroup(gid)
            print(f"[inspect] openGroup sync {(time.perf_counter()-t)*1000:.1f}ms", flush=True)
        bench.later(900, after_open)

    def poll():
        el = (time.perf_counter() - t0) * 1000
        idx = bench.stack.property("currentIndex")
        deck = deck_obj()
        loaded = bool(deck and deck.property("item") is not None)
        cur = (idx, loaded)
        if state.get("cur") != cur:
            state["cur"] = cur
            print(f"[inspect] {el:7.0f}ms currentIndex={idx} deckLoaded={loaded}", flush=True)
        if el > int(os.environ.get("YH_OPEN_AT", "5000")):
            open_group()

    tm = QTimer()
    tm.setInterval(30)
    tm.timeout.connect(poll)
    tm.start()


def run_pageidle():
    if "pageidle" not in PHASES:
        return run_audit()
    order = PAGES or [1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0]

    def step(k=0):
        if k >= len(order):
            return run_audit()
        i = order[k]

        def ready(ms):
            bench.measure_idle(f"page{i}_{PAGE_NAMES[i]}", 800, lambda: step(k + 1),
                               bucket="pageidle")

        bench.goto_and_time(i, "pageidlego", ready)

    step()


def run_audit():
    if "audit" not in PHASES:
        return finish()

    def measure(label, done):
        def fin():
            frames = bench.frames - f0
            cpu = (time.process_time() - c0) * 1000.0
            item = {"label": label, "frames": frames, "cpu_ms": round(cpu, 1),
                    "wall_ms": round((time.perf_counter() - t0) * 1000, 1)}
            results["audit"].append(item)
            print(f"[bench] audit {label:44s} frames={frames:3d} cpu={item['cpu_ms']:6.1f}ms",
                  flush=True)
            done()

        f0 = bench.frames
        c0 = time.process_time()
        t0 = time.perf_counter()
        bench.later(700, fin)

    ids = [13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 0]

    def step(k=0):
        if k >= len(ids) + 1:
            return finish()
        if k > 0:
            bench.deactivate(ids[k - 1])
        label = "all_built" if k == 0 else f"unload_{ids[k-1]}_{PAGE_NAMES[ids[k-1]]}"

        def done():
            bench.later(60, lambda: step(k + 1))

        measure(label, done)

    bench.goto_and_time(1, "auditgo", lambda ms: bench.later(250, step))


def finish(reason=""):
    results["stalls"] = bench.stalls if bench else []
    out = os.path.join(os.environ.get("TEMP", "/tmp"), "bench_nav_results.json")
    try:
        with open(out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=1)
        print("[bench] wrote", out, flush=True)
    except Exception:
        traceback.print_exc()
    print("[bench] RESULTS", json.dumps({k: v for k, v in results.items() if k != "stalls"}),
          flush=True)
    if result_stalls := results.get("stalls"):
        print("[bench] top stalls",
              sorted(result_stalls, key=lambda s: -s["ms"])[:15], flush=True)
    print("[bench] done", reason, flush=True)
    QGuiApplication.instance().quit()


try:
    main_qml.main()
except SystemExit:
    pass
except Exception:
    traceback.print_exc()
