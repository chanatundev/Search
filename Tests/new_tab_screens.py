#!/usr/bin/env python3
"""Test for Multiple New Tab Screens and Multiple New Tab Tabs."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402


def get_screen():
    return sv.cmd({"do": "newTabScreen"})


def set_screen(screen):
    return sv.cmd({"do": "newTabScreen", "set": screen})


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()

        # Check default screen
        res = get_screen()
        t.ok("default new tab screen is minimal", res.get("screen") == "minimal", res)

        # Switch to bookmarks
        res = set_screen("bookmarks")
        time.sleep(0.3)
        t.ok("switched to bookmarks", res.get("ok") and res.get("screen") == "bookmarks", res)

        current = get_screen()
        t.ok("get_screen reports bookmarks", current.get("screen") == "bookmarks", current)

        # Switch to shortcuts
        res = set_screen("shortcuts")
        time.sleep(0.3)
        t.ok("switched to shortcuts", res.get("ok") and res.get("screen") == "shortcuts", res)

        current = get_screen()
        t.ok("get_screen reports shortcuts", current.get("screen") == "shortcuts", current)

        # Switch to focus
        res = set_screen("focus")
        time.sleep(0.3)
        t.ok("switched to focus", res.get("ok") and res.get("screen") == "focus", res)

        current = get_screen()
        t.ok("get_screen reports focus", current.get("screen") == "focus", current)

        # Switch back to minimal
        res = set_screen("minimal")
        time.sleep(0.3)
        t.ok("switched back to minimal", res.get("ok") and res.get("screen") == "minimal", res)

        current = get_screen()
        t.ok("get_screen reports minimal", current.get("screen") == "minimal", current)

        # Test multiple 'New Tab' tabs:
        # Initial state should have 1 tab (the default blank tab)
        st = sv.sp("state")
        t.ok("starts with 1 blank tab", len(st["tabs"]) == 1 and st["tabs"][0]["blank"], st["tabs"])

        # Press new tab three times
        sv.sp("newTab")
        time.sleep(0.2)
        sv.sp("newTab")
        time.sleep(0.2)
        sv.sp("newTab")
        time.sleep(0.2)

        st = sv.sp("state")
        blank_tabs = [x for x in st["tabs"] if x["blank"]]
        t.ok("pressing new tab three times created multiple blank tabs (total 4)", len(blank_tabs) == 4, len(blank_tabs))
        t.ok("all blank tabs have New Tab title", all(x["title"] == "" or x.get("label") == "New Tab" for x in blank_tabs), blank_tabs)
        t.ok("active tab is the latest new tab", st["activeID"] == st["tabs"][-1]["id"], (st["activeID"], st["tabs"]))

    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
