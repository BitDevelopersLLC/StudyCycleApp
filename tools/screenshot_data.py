#!/usr/bin/env python3
"""Put realistic sample data into Study Cycle for the store screenshots.

Usage:
    python tools/screenshot_data.py android <scene> [--adb PATH]
    python tools/screenshot_data.py ios <scene>

Scenes: focus, break, idle (progress, settings and about use "idle"), and alert: idle with a
5-minute custom focus block, so a real "Focus done" alert arrives 5 minutes after you tap Start.

Android needs a DEBUG build on the emulator (`flutter run` or `flutter install --debug`), because
the data is written with `adb shell run-as`. iOS edits the app's preferences file in the booted
Simulator (first written 2026-11-12 on Windows; check the first iOS run shows the data). Both stop
the app first; open it again afterwards.

The data is made up: a student who has studied most days for the last two weeks. It never leaves
the test device, and it is the same on both platforms so the screenshots match.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from xml.sax.saxutils import quoteattr, escape

APP_ID = "app.studycycle"
FOCUS_MIN = 90
BREAK_MIN = 20

#: Cycles finished on each earlier day, newest first (yesterday, the day before, ...).
#: Every day has at least one cycle, so the streak runs back 13 days plus today.
PAST_CYCLES = [3, 2, 4, 1, 2, 3, 2, 1, 2, 3, 1, 2, 2]
#: Days before the streak, so "All time" is a little bigger than the last two weeks.
OLDER_CYCLES = {16: 2, 17: 3, 19: 1, 20: 2, 23: 2, 24: 1}


def history(today: date, cycles_today: int, extra_minutes_today: int) -> dict[str, list[int]]:
    """Day totals in the app's format: {"yyyy-mm-dd": [focusSeconds, cycles]}."""
    days: dict[str, list[int]] = {}

    def add(day: date, cycles: int, extra: int = 0) -> None:
        days[day.isoformat()] = [(cycles * FOCUS_MIN + extra) * 60, cycles]

    add(today, cycles_today, extra_minutes_today)
    for back, cycles in enumerate(PAST_CYCLES, start=1):
        # A few days include a shorter, unfinished block on top of the full cycles.
        add(today - timedelta(days=back), cycles, 25 if back % 3 == 0 else 0)
    for back, cycles in OLDER_CYCLES.items():
        add(today - timedelta(days=back), cycles)
    return days


def timer(scene: str, now: datetime) -> dict[str, object] | None:
    """The saved timer for a scene, or None for idle."""
    def ms(d: datetime) -> int:
        return int(d.timestamp() * 1000)

    if scene == "focus":
        # Cycle 2, 1:12:34 left.
        ends = now + timedelta(hours=1, minutes=12, seconds=40)
        return {"status": "running", "phase": "focus", "cycles": 1,
                "lengthMs": FOCUS_MIN * 60_000, "endsAtMs": ms(ends), "remainingMs": 0, "autoStarts": 0}
    if scene == "break":
        # The break after cycle 2, 14:52 left.
        ends = now + timedelta(minutes=14, seconds=58)
        return {"status": "running", "phase": "rest", "cycles": 2,
                "lengthMs": BREAK_MIN * 60_000, "endsAtMs": ms(ends), "remainingMs": 0, "autoStarts": 0}
    return None


def values(scene: str, today: date, now: datetime) -> dict[str, object]:
    """Every preference key (without the platform prefix) and its value."""
    cycles_today = {"focus": 1, "break": 2, "idle": 2, "alert": 2}[scene]
    prefs: dict[str, object] = {
        "history.v1": json.dumps(history(today, cycles_today, 0), separators=(",", ":")),
        "plan.preset": "custom" if scene == "alert" else "ultradian",
        "plan.focusMinutes": 5 if scene == "alert" else FOCUS_MIN,
        "plan.breakMinutes": BREAK_MIN,
        "settings.autoStartFocus": False,
        "settings.keepScreenOn": True,
    }
    state = timer(scene, now)
    if state is not None:
        prefs["timer.v1"] = json.dumps(state, separators=(",", ":"))
    return prefs


def android(scene: str, adb: str) -> None:
    run = lambda *a: subprocess.run([adb, *a], check=True, capture_output=True, text=True).stdout
    today = date.fromisoformat(run("shell", "date", "+%F").strip())
    run("shell", "am", "force-stop", APP_ID)
    lines = ["<?xml version='1.0' encoding='utf-8' standalone='yes' ?>", "<map>"]
    for key, value in values(scene, today, datetime.now(timezone.utc)).items():
        name = quoteattr(f"flutter.{key}")
        if isinstance(value, bool):
            lines.append(f"    <boolean name={name} value=\"{str(value).lower()}\" />")
        elif isinstance(value, int):
            lines.append(f"    <long name={name} value=\"{value}\" />")
        else:
            lines.append(f"    <string name={name}>{escape(str(value))}</string>")
    lines.append("</map>")
    with tempfile.TemporaryDirectory() as tmp:
        local = Path(tmp) / "prefs.xml"
        local.write_text("\n".join(lines) + "\n", encoding="utf-8")
        run("push", str(local), "/data/local/tmp/studycycle-prefs.xml")
    target = "shared_prefs/FlutterSharedPreferences.xml"
    run("shell", f"run-as {APP_ID} mkdir -p shared_prefs && "
                 f"run-as {APP_ID} cp /data/local/tmp/studycycle-prefs.xml {target}")
    run("shell", "rm", "/data/local/tmp/studycycle-prefs.xml")
    print(f"android: wrote the {scene} scene for {today}")


def ios(scene: str) -> None:
    """Writes the app's preferences file in the booted Simulator (the app must be installed).

    shared_preferences keeps its values in NSUserDefaults with the "flutter." prefix, which is the
    plist at Library/Preferences/<bundle id>.plist inside the app's data container.
    """
    import plistlib

    def simctl(*a: str) -> str:
        return subprocess.run(["xcrun", "simctl", *a], check=True, capture_output=True, text=True).stdout

    subprocess.run(["xcrun", "simctl", "terminate", "booted", APP_ID], check=False, capture_output=True)
    container = Path(simctl("get_app_container", "booted", APP_ID, "data").strip())
    plist = container / "Library" / "Preferences" / f"{APP_ID}.plist"
    current: dict[str, object] = {}
    if plist.exists():
        current = plistlib.loads(plist.read_bytes())
    # Keep anything unrelated (such as alerts.asked), replace the app's data keys.
    for key in [k for k in current if k.startswith("flutter.") and k != "flutter.alerts.asked"]:
        del current[key]
    today = date.today()
    for key, value in values(scene, today, datetime.now(timezone.utc)).items():
        current[f"flutter.{key}"] = value
    plist.parent.mkdir(parents=True, exist_ok=True)
    plist.write_bytes(plistlib.dumps(current, fmt=plistlib.FMT_BINARY))
    # The Simulator's preferences daemon caches values; make it reread the file.
    subprocess.run(["xcrun", "simctl", "spawn", "booted", "killall", "-HUP", "cfprefsd"],
                   check=False, capture_output=True)
    print(f"ios: wrote the {scene} scene for {today} to {plist}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("platform", choices=["android", "ios"])
    parser.add_argument("scene", choices=["focus", "break", "idle", "alert"])
    parser.add_argument("--adb", default="adb", help="path to adb (Android only)")
    args = parser.parse_args()
    if args.platform == "android":
        android(args.scene, args.adb)
    else:
        ios(args.scene)


if __name__ == "__main__":
    main()
