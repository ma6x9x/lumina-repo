#!/usr/bin/env python3
"""Import an era icon pack into a Sk1n skin's authored Icons/ directory.

Converts third-party icon packs (Anemone `Bundles/<bundle>/<Name>[@2x].png`,
SnowBoard `IconBundles/<bundle>[@2x|-large].png`, and flat
`<Name>.<ext>` folders with a name -> bundle id map) into Sk1n's
`<skin>/Icons/<bundle id>.png` layout. Era-appropriate post-processing:

- ios1-era sources are full-bleed squares (authentic iOS 1-6 art): masked
  to the home-screen proportion (22.4% corner radius) so the icon reads
  right even where SpringBoard does not apply its own mask.
- Any icon is upscaled to 180px (the @3x default the engine declares) so
  low-resolution era art (114px iOS 6 @2x) does not get scaled twice.

The pack's own files are never modified. Usage:

    pip install pillow
    python3 tools/import-iconpack.py PACKS_DIR            # all packs
    python3 tools/import-iconpack.py zagnut531            # one pack by key

Solid Glass 27 (glass27):
    # download the latest .deb from https://github.com/iVintageLover/Solid-Glass/releases
    # (Solid.Glass.27.Rootless.deb or Rootful)
    mkdir -p /tmp/sk1n-catalog
    dpkg-deb -x Solid.Glass.27.Rootless.deb /tmp/sk1n-catalog/Solid-Glass-extract
    python3 tools/import-iconpack.py solidglass27
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SKINS = ROOT / "layout/Library/Sk1n/Skins"

SIZE = 180

# ---- The packs. Each pack: source layout, target skin era, name map. ----
APPLE_CROPPED = {
    # filename stem -> bundle id (iPhone set, "Cropped icons")
    "AirPort Utility": "com.apple.AirPortUtility",
    "App Store": "com.apple.AppStore",
    "Apple Store": "com.apple.store.J2A",
    "Calculator": "com.apple.calculator",
    "Calendar": "com.apple.mobilecal",
    "Camera": "com.apple.camera",
    "Cards": "com.apple.Cards",
    "Clock": "com.apple.mobiletimer",
    "Compass": "com.apple.compass",
    "Contacts": "com.apple.Contacts",
    "FaceTime": "com.apple.facetime",
    "Find Friends": "com.apple.findmyfriends",
    "Find iPhone": "com.apple.mobileme.fmip1",
    "Game Center": "com.apple.gamecenter",
    "GarageBand": "com.apple.mobilegarageband",
    "Hold’em": "com.apple.texassholdem",
    "iBooks": "com.apple.iBooks",
    "iMovie": "com.apple.iMovie",
    "iTunes Movie Trailers": "com.apple.ITML",
    "iTunes Remote": "com.apple.Remote",
    "iTunes U": "com.apple.itunesu",
    "iTunes": "com.apple.mobilestore",
    "Keynote": "com.apple.Keynote",
    "Mail": "com.apple.mobilemail",
    "Maps": "com.apple.Maps",
    "Messages": "com.apple.MobileSMS",
    "Music": "com.apple.Music",
    "Newsstand": "com.apple.Newstand",
    "Nike+ iPod": "com.apple.nike",
    "Notes": "com.apple.mobilenotes",
    "Numbers": "com.apple.Numbers",
    "Pages": "com.apple.Pages",
    "Passbook": "com.apple.Passbook",
    "Phone": "com.apple.mobilephone",
    "Photos": "com.apple.mobileslideshow",
    "Podcasts": "com.apple.podcasts",
    "Reminders": "com.apple.reminders",
    "Remote": "com.apple.Remote",
    "Safari": "com.apple.mobilesafari",
    "Settings": "com.apple.Preferences",
    "Stocks": "com.apple.stocks",
    "Videos": "com.apple.videos",
    "Voice Memos": "com.apple.VoiceMemos",
    "Weather": "com.apple.weather",
    "Weather Celsius": "com.apple.weather",
}

def squircle_mask(size, radius=0.224):
    m = Image.new("L", (size, size), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size - 1, size - 1), int(size * radius), fill=255)
    return m

def to_era_png(img, era):
    """Normalise to a 180px RGBA icon for <skin>/Icons/<id>.png."""
    img = img.convert("RGBA")
    if img.size[0] != SIZE or img.size[1] != SIZE:
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    if era == "ios1" and img.size[0] > 0:
        # Authentic era art is full-bleed square; bake the mask so the icon
        # looks right regardless of what SBIconImageView does to it.
        img.putalpha(squircle_mask(SIZE))
    return img

def import_anemone_bundles(theme_dir, out_dir, era):
    """`Bundles/<bundle>/<Name>[@2x].png` — one directory per bundle id."""
    n = 0
    bundles = theme_dir / "Bundles"
    if not bundles.is_dir():
        return n
    for d in sorted(bundles.iterdir()):
        if not d.is_dir():
            continue
        best = None
        for suffix in ("@3x.png", "@2x.png", ".png"):
            cand = d / (d.name + suffix)
            if cand.is_file():
                best = cand
                break
        if not best:
            continue
        to_era_png(Image.open(best), era).save(out_dir / f"{d.name}.png", optimize=True)
        n += 1
    return n

def import_iconbundles(theme_dir, out_dir, era):
    """`IconBundles/<bundle>[-large|@2x|].png` — flat, suffix in the name."""
    n = 0
    bundles = theme_dir / "IconBundles"
    if not bundles.is_dir():
        return n
    for f in sorted(bundles.iterdir()):
        if not f.is_file() or f.suffix.lower() != ".png":
            continue
        stem = f.stem
        if stem.endswith("-large"):
            stem = stem[: -len("-large")]
        elif stem.endswith("@2x") or stem.endswith("@3x"):
            stem = stem[: -3]
        to_era_png(Image.open(f), era).save(out_dir / f"{stem}.png", optimize=True)
        n += 1
    return n

def import_flat_named(folder, out_dir, era, name_map):
    """`<Name>.<ext>` files resolved through a name -> bundle id map."""
    n = 0
    for f in sorted(folder.iterdir()):
        if not f.is_file() or f.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            continue
        bid = name_map.get(f.stem)
        if not bid:
            continue
        to_era_png(Image.open(f), era).save(out_dir / f"{bid}.png", optimize=True)
        n += 1
    return n

THIRD_PARTY = {
    # authentic third-party artwork from the iOS 6 era (upstream 3rd-party dir)
    "Facebook": "com.facebook.Facebook",
    "Facebook Messenger": "com.facebook.Messenger",
    "Instagram": "com.burbn.instagram",
    "Twitter": "com.atebits.Tweetie2",
    "Netflix iPhone": "com.netflix.Netflix",
    "Spotify iPhone": "com.spotify.Client",
    "WhatsApp": "net.whatsapp.WhatsApp",
    "Snapchat iPhone": "com.toyopagroup.picaboo",
    "YouTube iPhone": "com.google.ios.youtube",
    "Discord": "com.hammerandchisel.discord",
}

MODERN_RECREATIONS = {
    # redditor-made era-style icons for apps that did not exist in iOS 6
    # (credited in tools/ICON_CATALOG.md)
    "Fitness": "com.apple.Fitness",
    "Freeform": "com.apple.Freeform",
    "Clips": "com.apple.clips",
    "Apple Watch": "com.apple.Bridge",
    "Code Scanner": "com.apple.meshkit",
}

PACKS = {
    "zagnut531": {
        # https://github.com/zagnut531/iOS-6-Icons - authentic iOS 6 era art,
        # no licence in the repo (see tools/ICON_CATALOG.md); era artwork.
        "theme_dir": "iOS-6-Icons/iPhone & iPod touch/Cropped icons",
        "era": "ios1",
        "kind": "flat",
        "name_map": APPLE_CROPPED,
    },
    "zagnut531-3rd": {
        "theme_dir": "iOS-6-Icons/3rd-party icons",
        "era": "ios1",
        "kind": "flat",
        "name_map": THIRD_PARTY,
    },
    "zagnut531-modern": {
        "theme_dir": "iOS-6-Icons/Apple icons",
        "era": "ios1",
        "kind": "flat",
        "name_map": MODERN_RECREATIONS,
    },
    "okapi": {
        # https://github.com/JustAnOkapi/Okapi-Icons-Bulk - Unlicense;
        # solid flat icons, wide third-party bundle coverage.
        "theme_dir": "Okapi-Icons-Bulk/Okapi Icons/Okapi Icons.theme",
        "era": "ios7",
        "kind": "iconbundles",
    },
    "solidglass27": {
        # https://github.com/iVintageLover/Solid-Glass - Solid Glass 27
        # (iOS 26/27 Liquid Glass icons). Extract the .deb first:
        #   mkdir -p /tmp/sk1n-catalog
        #   dpkg-deb -x Solid.Glass.27.Rootless.deb /tmp/sk1n-catalog/Solid-Glass-extract
        # Light.theme is the preferred non-clear variant.
        "theme_dir": "Solid-Glass-extract/var/jb/Library/Themes/Light.theme",
        "era": "glass27",
        "kind": "iconbundles",
    },
}

def main():
    packs_root = Path("/tmp/sk1n-catalog")  # default catalog checkout location
    args = sys.argv[1:]
    if args and args[0] not in PACKS:  # [packs_root] pack...
        packs_root = Path(args[0]); args = args[1:]
    args = args or list(PACKS)
    for arg in args:
        if arg in PACKS:
            cfg = PACKS[arg]
        else:
            sys.exit(f"unknown pack {arg}; known: {', '.join(PACKS)}")
        out = SKINS / cfg["era"] / "Icons"
        out.mkdir(parents=True, exist_ok=True)
        src = packs_root / cfg["theme_dir"]
        if not src.is_dir():
            sys.exit(f"pack source not found: {src} — clone/extract the pack first")
        if cfg["kind"] == "iconbundles":
            n = import_iconbundles(src, out, cfg["era"])
        elif cfg["kind"] == "anemone":
            n = import_anemone_bundles(src, out, cfg["era"])
        else:
            n = import_flat_named(src, out, cfg["era"], cfg["name_map"])
        print(f"{arg}: {n} icons -> {cfg['era']}")

if __name__ == "__main__":
    main()
