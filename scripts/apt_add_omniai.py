#!/usr/bin/env python3
"""Add OmniAI 1.0.0 entries to Packages and refresh compressed indexes + Release."""
import bz2, gzip, hashlib, io, lzma
from datetime import datetime, timezone

OMNIAI = """Package: com.kolby.omniai
Version: 1.0.0
Architecture: iphoneos-arm64
Maintainer: kolbymaxx
Installed-Size: 560
Depends: mobilesubstrate, preferenceloader, firmware (>= 16.0)
Conflicts: com.kolby.grokagent
Replaces: com.kolby.grokagent
Provides: com.kolby.grokagent
Filename: dist/com.kolby.omniai_1.0.0_iphoneos-arm64.deb
Size: 76032
MD5sum: e40355b23d804bbf4001f278ff1dd59d
SHA1: cf33945fc4de63b55fb306fa60ca1fd7379fa8ec
SHA256: 750a86c84f6ec8214544ad58e56330e0335444fc761ca0f9e2256357ce24e377
Section: Tweaks
Description: System-wide AI for iOS 16–18 — text selection + on-screen awareness with Grok, Claude, and Gemini web login.
Author: kolbymaxx
Name: OmniAI

Package: com.kolby.omniai
Version: 1.0.0
Architecture: iphoneos-arm64e
Maintainer: kolbymaxx
Installed-Size: 560
Depends: mobilesubstrate, preferenceloader, firmware (>= 16.0)
Conflicts: com.kolby.grokagent
Replaces: com.kolby.grokagent
Provides: com.kolby.grokagent
Filename: dist/com.kolby.omniai_1.0.0_iphoneos-arm64e.deb
Size: 76342
MD5sum: f779619b4b610892f461ba0e863b4aa3
SHA1: 6c7581b291af59e410ad66f93a452bf4a8aa77d5
SHA256: c53c9449452807e486ae7a054a1a3261619a279aa0e0ff533f4d5945041c29b8
Section: Tweaks
Description: System-wide AI for iOS 16–18 — text selection + on-screen awareness with Grok, Claude, and Gemini web login.
Author: kolbymaxx
Name: OmniAI
"""

def main():
    pkg = open("Packages").read()
    if "com.kolby.omniai" not in pkg:
        needle = "Package: com.kolby.rhcompat"
        idx = pkg.find(needle)
        if idx < 0:
            raise SystemExit("com.kolby.rhcompat not found in Packages")
        pkg = pkg[:idx] + OMNIAI.strip() + "\n\n" + pkg[idx:]
        open("Packages", "w").write(pkg if pkg.endswith("\n") else pkg + "\n")
    raw = open("Packages", "rb").read()
    bio = io.BytesIO()
    with gzip.GzipFile(fileobj=bio, mode="wb", mtime=0) as g:
        g.write(raw)
    gz = bio.getvalue()
    open("Packages.gz", "wb").write(gz)
    bz = bz2.compress(raw)
    open("Packages.bz2", "wb").write(bz)
    xz = lzma.compress(raw)
    open("Packages.xz", "wb").write(xz)
    date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    def h(data):
        return hashlib.md5(data).hexdigest(), hashlib.sha256(data).hexdigest(), len(data)
    files = [("Packages", raw), ("Packages.gz", gz), ("Packages.bz2", bz), ("Packages.xz", xz)]
    lines = [
        "Origin: KDotz Repo",
        "Label: KDotz Repo",
        "Suite: stable",
        "Version: 1.0",
        "Codename: kdotz",
        "Architectures: iphoneos-arm64 iphoneos-arm64e",
        "Components: main",
        "Description: KDotz Repo — tweaks by Kolby (rootless + roothide)",
        f"Date: {date}",
    ]
    md5s, shas = [], []
    for name, data in files:
        m, s, n = h(data)
        md5s.append(f" {m} {n} {name}")
        shas.append(f" {s} {n} {name}")
    open("Release", "w").write(
        "\n".join(lines) + "\nMD5Sum:\n" + "\n".join(md5s) + "\nSHA256:\n" + "\n".join(shas) + "\n"
    )
    text = raw.decode()
    checks = [
        ("com.kolby.siri27", "1.40.6"),
        ("com.music27.tweak", "1.1.11"),
        ("com.kolby.cc27", "1.0.8"),
        ("com.kolby.rhcompat", "1.0.2"),
        ("com.kolby.omniai", "1.0.0"),
    ]
    for name, ver in checks:
        if f"Package: {name}" not in text or f"Version: {ver}" not in text:
            raise SystemExit(f"missing {name} {ver}")
    print("APT index refreshed with OmniAI 1.0.0; latest package versions verified")

if __name__ == "__main__":
    main()
