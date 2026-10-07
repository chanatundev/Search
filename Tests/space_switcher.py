#!/usr/bin/env python3
"""Test for Control + ` space switcher and cycling."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402


def space_switcher():
    return sv.cmd({"do": "spaceSwitcher"})


def main():
    t = sv.T()
    try:
        sv.setup(); sv.launch()
        # Create spaces: Space 1 is default, add Space 2 and Space 3
        res = sv.cmd({"do": "space", "action": "new", "name": "Work"}); time.sleep(0.4)
        res = sv.cmd({"do": "space", "action": "new", "name": "Play"}); time.sleep(0.4)

        # Check spaces
        spaces_info = sv.cmd({"do": "space"})
        spaces = spaces_info["spaces"]
        print("Spaces:", [s["name"] for s in spaces])
        t.ok("at least 3 spaces created", len(spaces) >= 3, spaces)

        # Switch to first space (index 1)
        sv.cmd({"do": "space", "action": "go", "index": 1}); time.sleep(0.4)
        s0 = space_switcher()
        current_id = s0["active"]

        # Press Control + ` (key code 50, characters "`", mods ["ctrl"])
        sv.cmd({"do": "press", "code": 50, "chars": "`", "mods": ["ctrl"]}); time.sleep(0.8)
        s = space_switcher()
        t.ok("Control + ` opens space switcher", s["visible"] and len(s["candidates"]) >= 3, s)
        t.ok("selected space is next space", s["selected"] != current_id and s["selected"] == s["candidates"][1], s)
        t.ok("its cards have frames", len(s["cards"]) >= 3 and s["panel"][2] > 0, s["cards"])

        # Press ` again while holding Control
        sv.cmd({"do": "press", "code": 50, "chars": "`", "mods": ["ctrl"]}); time.sleep(0.6)
        s2 = space_switcher()
        t.ok("cycling forward selects space 3", s2["selected"] == s2["candidates"][2], s2)

        # Press Shift + ` while holding Control to cycle backward
        sv.cmd({"do": "press", "code": 50, "chars": "`", "mods": ["ctrl", "shift"]}); time.sleep(0.6)
        s3 = space_switcher()
        t.ok("Shift + Control + ` cycles backwards to space 2", s3["selected"] == s3["candidates"][1], s3)

        # Release control: test commit via flags event or card click
        # First test card click
        target_card = s["candidates"][2]
        x, y, w, h = s["cards"][target_card]
        sv.sp("mouse", points=[[x + w / 2, y + h / 2], [x + w / 2, y + h / 2]]); time.sleep(0.6)
        s_after_click = space_switcher()
        t.ok("clicking card commits space switch", s_after_click["active"] == target_card and not s_after_click["visible"], s_after_click)

        # Open switcher again
        sv.cmd({"do": "press", "code": 50, "chars": "`", "mods": ["ctrl"]}); time.sleep(0.8)
        s4 = space_switcher()
        t.ok("space switcher opened again", s4["visible"], s4)

        # Release Control by sending flagsChanged with empty mods
        sv.cmd({"do": "flags", "mods": []}); time.sleep(0.6)
        s5 = space_switcher()
        t.ok("releasing Control commits and closes switcher", not s5["visible"], s5)

        # Test Escape puts switcher away without switching
        cur = space_switcher()["active"]
        sv.cmd({"do": "press", "code": 50, "chars": "`", "mods": ["ctrl"]}); time.sleep(0.8)
        t.ok("switcher open before esc", space_switcher()["visible"])
        sv.cmd({"do": "press", "code": 53, "chars": "\x1b", "mods": []}); time.sleep(0.6)
        s_esc = space_switcher()
        t.ok("Escape dismisses switcher without switching", not s_esc["visible"] and s_esc["active"] == cur, s_esc)

    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
