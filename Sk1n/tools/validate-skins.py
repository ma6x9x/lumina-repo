#!/usr/bin/env python3
"""Validate every Skin.plist - the Python twin of +[Sk1nSkin validationErrorsForPlist:].

Keep the two in sync. Used by CI so a malformed skin fails the build instead of
silently failing closed on a phone.

    python3 tools/validate-skins.py [skins-dir]
"""
import plistlib, re, sys
from pathlib import Path

ERAS = {"ios1", "ios7", "glass27"}
HEX = re.compile(r"^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")

def safe(s):
    return isinstance(s, str) and 0 < len(s) <= 64 and "/" not in s and ".." not in s and not s.startswith(".")

def validate(plist, dirname):
    if not isinstance(plist, dict):
        return ["Skin.plist is not a dictionary"]
    e = []
    sid = plist.get("id")
    if not safe(sid): e.append("id missing or unsafe")
    elif sid != dirname: e.append("id does not match directory name")
    if not isinstance(plist.get("name"), str) or not plist["name"]: e.append("name missing")
    if plist.get("era") not in ERAS: e.append("era must be ios1 | ios7 | glass27")
    colors = plist.get("colors")
    if not isinstance(colors, dict): e.append("colors missing")
    else:
        for k, v in colors.items():
            if not (isinstance(v, str) and HEX.match(v)): e.append(f"colors.{k} is not #RRGGBB[AA]")
    if "fonts" in plist and not isinstance(plist["fonts"], dict): e.append("fonts must be a dictionary")
    if "iconsDirectory" in plist and not safe(plist["iconsDirectory"]): e.append("iconsDirectory unsafe")
    if "lockscreen" in plist and not isinstance(plist["lockscreen"], dict): e.append("lockscreen must be a dictionary")
    sl = plist.get("slider")
    if sl is None: e.append("slider config missing")
    elif not isinstance(sl, dict): e.append("slider must be a dictionary")
    else:
        if "style" in sl and sl["style"] not in ERAS: e.append("slider.style must be ios1 | ios7 | glass27")
        if not isinstance(sl.get("text"), str): e.append("slider.text missing")
        for k in ("textColor", "thumbColor", "trackColor"):
            if k in sl and not (isinstance(sl[k], str) and HEX.match(sl[k])): e.append(f"slider.{k} is not #RRGGBB[AA]")
    snd = plist.get("sounds")
    if snd is not None:
        if not isinstance(snd, dict): e.append("sounds must be a dictionary")
        else:
            for k, v in snd.items():
                if not safe(v): e.append(f"sounds.{k} unsafe file name")
    return e

def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "layout/Library/Sk1n/Skins")
    bad = 0; n = 0
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        n += 1
        f = d / "Skin.plist"
        try:
            errs = validate(plistlib.loads(f.read_bytes()), d.name)
        except Exception as ex:
            errs = [f"unreadable: {ex}"]
        icons = d / "Icons"
        # An icon catalog is OPTIONAL: a skin may ship no artwork at all
        # (glass27) and get the device's own real artwork at runtime. When
        # the directory exists it must actually hold PNGs — an empty Icons/
        # is more likely a broken import than a statement.
        if icons.is_dir() and not any(icons.glob("*.png")): errs.append("Icons/ has no PNGs")
        print(("FAIL " if errs else "ok   ") + d.name + ("" if not errs else ": " + "; ".join(errs)))
        bad += bool(errs)
    if n == 0: print("no skins found"); return 1
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
