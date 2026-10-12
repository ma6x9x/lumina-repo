#!/usr/bin/env python3
"""Rebuild the Lumina Repo APT index without dpkg-scanpackages.

macOS host fallback for scripts/update-apt-repo.sh: rebuilds Packages,
Packages.{gz,bz2,xz}, and Release from every .deb in dist/ (same fields
dpkg-scanpackages emits: control fields + Filename/Size/MD5sum/SHA1/SHA256).

Usage: python3 scripts/apt_reindex.py   (run from repo root)
"""
import bz2
import email.utils
import glob
import gzip
import hashlib
import lzma
import os
import subprocess
import sys

DIST = "dist"
INDEX_FILES = ["Packages", "Packages.gz", "Packages.bz2", "Packages.xz"]


def deb_control_fields(path):
    """Extract the ./control fields from a .deb (ar + control.tar.{gz,zst,xz})."""
    member = subprocess.run(["ar", "t", path], check=True,
                            capture_output=True, text=True).stdout.split()
    ctrl_member = next(m for m in member if m.startswith("control.tar"))
    raw = subprocess.run(["ar", "p", path, ctrl_member], check=True,
                         capture_output=True).stdout
    import io, tarfile
    with tarfile.open(fileobj=io.BytesIO(raw)) as tf:
        for name in ("./control", "control"):
            try:
                data = tf.extractfile(name).read()
                break
            except (KeyError, AttributeError):
                continue
        else:
            raise RuntimeError(f"no control member in {path}")
    fields = {}
    for line in data.decode("utf-8", "replace").splitlines():
        if not line.strip():
            break
        if ":" in line and not line.startswith((" ", "\t")):
            k, _, v = line.partition(":")
            fields[k.strip()] = v.strip()
    return fields


def stanza(path):
    fields = deb_control_fields(path)
    data = open(path, "rb").read()
    h_md5 = hashlib.md5(data).hexdigest()
    h_sha1 = hashlib.sha1(data).hexdigest()
    h_sha256 = hashlib.sha256(data).hexdigest()
    out = []
    for k in ("Package", "Version", "Architecture", "Maintainer",
              "Installed-Size", "Depends", "Conflicts", "Replaces",
              "Provides", "Section", "Description", "Author", "Name"):
        if k in fields:
            out.append(f"{k}: {fields[k]}")
    out.append(f"Filename: {path}")
    out.append(f"Size: {len(data)}")
    out.append(f"MD5sum: {h_md5}")
    out.append(f"SHA1: {h_sha1}")
    out.append(f"SHA256: {h_sha256}")
    return "\n".join(out) + "\n"


def main():
    debs = sorted(glob.glob(os.path.join(DIST, "*.deb")))
    if not debs:
        sys.exit(f"no .deb files in {DIST}/")
    text = "\n".join(stanza(p) for p in debs)
    data = text.encode("utf-8")
    open("Packages", "wb").write(data)
    open("Packages.gz", "wb").write(gzip.compress(data, 9, mtime=0))
    open("Packages.bz2", "wb").write(bz2.compress(data, 9))
    open("Packages.xz", "wb").write(
        lzma.compress(data, format=lzma.FORMAT_XZ, preset=9 | lzma.PRESET_EXTREME))

    def entry(f):
        d = open(f, "rb").read()
        return f" {hashlib.md5(d).hexdigest()} {len(d)} {f}"

    with open("Release", "w") as fh:
        fh.write("Origin: Lumina Repo\n")
        fh.write("Label: Lumina Repo\n")
        fh.write("Suite: stable\n")
        fh.write("Version: 1.0\n")
        fh.write("Codename: lumina\n")
        fh.write("Architectures: iphoneos-arm64 iphoneos-arm64e\n")
        fh.write("Components: main\n")
        fh.write("Description: Lumina Repo - tweaks by ma6x9x (rootless + roothide)\n")
        fh.write(f"Date: {email.utils.formatdate(localtime=True)}\n")
        fh.write("MD5Sum:\n")
        for f in INDEX_FILES:
            fh.write(entry(f) + "\n")
        fh.write("SHA256:\n")
        for f in INDEX_FILES:
            d = open(f, "rb").read()
            fh.write(f" {hashlib.sha256(d).hexdigest()} {len(d)} {f}\n")

    print(f"indexed {len(debs)} debs:")
    for p in debs:
        print(" ", p)
    print("\nstanzas:")
    for line in text.splitlines():
        if line.startswith(("Package:", "Version:", "Filename:")):
            print(" ", line)


if __name__ == "__main__":
    main()