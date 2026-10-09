#!/usr/bin/env python3
"""⌘F opens Find on Page, receives focus, and closes cleanly.

Build first (`./build.sh`), then `python3 Tests/find_bar.py`. It runs in
split_view.py's test world with its harness: started hidden, everything
removed afterwards.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

t = sv.T()
try:
    sv.setup()
    sv.launch()

    # 1. Single tab mode
    sv.page("<h1>Hello Search</h1><p>Search find bar test on page with Search keyword.</p>")
    time.sleep(1.5)

    state = sv.sp("state")
    t.ok("single: initially finding is False", state.get("finding") is False, state.get("finding"))

    # Press ⌘F
    sv.cmd({"do": "keyeq", "chars": "f", "code": 3})
    time.sleep(0.8)

    state = sv.sp("state")
    probe = sv.cmd({"do": "probe"})
    t.ok("single: ⌘F opens find bar (finding is True)", state.get("finding") is True, state.get("finding"))
    t.ok("single: find bar text field has keyboard focus", "TextField" in probe.get("responder", ""), probe.get("responder"))

    # Press Escape
    sv.cmd({"do": "press", "chars": "\x1b", "code": 53})
    time.sleep(0.8)

    state = sv.sp("state")
    probe = sv.cmd({"do": "probe"})
    t.ok("single: Escape closes find bar", state.get("finding") is False, state.get("finding"))
    t.ok("single: focus returns to page view", "PageView" in probe.get("responder", "") or "WK" in probe.get("responder", ""), probe.get("responder"))

    # 2. Split view mode
    sv.cmd({"do": "ui", "split": True})
    time.sleep(0.8)
    sv.page("<h1>Second Split Page</h1><p>Split view finding test.</p>")
    time.sleep(1.0)

    # Press ⌘F in split view
    sv.cmd({"do": "keyeq", "chars": "f", "code": 3})
    time.sleep(0.8)

    state = sv.sp("state")
    probe = sv.cmd({"do": "probe"})
    t.ok("split: ⌘F opens find bar", state.get("finding") is True, state.get("finding"))
    t.ok("split: find bar text field has keyboard focus", "TextField" in probe.get("responder", ""), probe.get("responder"))

    # Press Escape in split view
    sv.cmd({"do": "press", "chars": "\x1b", "code": 53})
    time.sleep(0.8)

    state = sv.sp("state")
    t.ok("split: Escape closes find bar", state.get("finding") is False, state.get("finding"))
finally:
    t.done()
    sv.finish()

sys.exit(1 if t.failed else 0)
