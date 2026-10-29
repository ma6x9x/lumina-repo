# Sk1n icon catalog - sources and licences

Each bundled skin's `Icons/` directory is a merged catalog: era-true third
party packs first, plus the engine's own generated set
(`tools/sk1n-icons.py`) for bundle ids the packs do not cover. The packs are
imported with `tools/import-iconpack.py` (see that file for the per-pack
mapping tables). This file records where every imported icon came from and
under what terms it is redistributed.

For true 1:1 era fidelity (especially iOS 1-6), drop accurate packs into the
skin's Icons/ folder. Authored PNGs always win over runtime chrome. Reference
real photos from Version Museum iPhone OS 1 galleries, Engadget 2007 UI shots,
Ars Technica iOS 6 vs 7 comparisons, Basic Apple Guy's iOS Icon History, and
the 2007.mobile WebAssembly emulator for exact shapes, colors, and gloss.

## zagnut531/iOS-6-Icons → `ios1`

https://github.com/zagnut531/iOS-6-Icons — "Cropped icons" of the iPhone &
iPod touch set, mapped to bundle ids by `tools/import-iconpack.py`
(`APPLE_CROPPED`), upscaled 114px → 180px and alpha-masked to the home-screen
squircle. Extracted straight from real devices (iPad 4 / iPod touch 5).

**Licence: none present in the upstream repo.** Authentic iOS era artwork
(Apple's copyright) plus redditor-made icons for apps that did not exist in
the era. Redistributed here as era reference for a personal theming package.
If you are a rights holder and object, remove the
`layout/Library/Sk1n/Skins/ios1/Icons/` set shipped from this pack — the
skin still works: real artwork rendered from the device at runtime covers
every app without any of these files, and the refined runtime gloss now better
matches 2007-2012 photos.

To create your own 1:1 replicas: screenshot or export from 2007.mobile,
Version Museum, or a real device, then place as `<bundle>.png` (180px preferred).

## JustAnOkapi/Okapi-Icons-Bulk → `ios7`

https://github.com/JustAnOkapi/Okapi-Icons-Bulk — the `Okapi Icons.theme`
icon bundle set. **Licence: The Unlicense** (public domain). Nothing in this
set is Apple artwork. This is the preferred authored set for the iOS 7 skin
(flat, no gloss, bright solid colors matching the 2013 overhaul).

## iVintageLover/Solid-Glass → `glass27`

https://github.com/iVintageLover/Solid-Glass — Solid Glass 27 (and the
companion Solid Glass 26 package). These are the real iOS 26/27 Liquid Glass
icons backported for jailbroken devices. The latest release is on the
[releases page](https://github.com/iVintageLover/Solid-Glass/releases).

**How to import:**
```bash
# download the latest .deb (Solid Glass 27 Rootless or Rootful) from the releases page
mkdir -p /tmp/sk1n-catalog
dpkg-deb -x Solid.Glass.27.Rootless.deb /tmp/sk1n-catalog/Solid-Glass-extract
python3 tools/import-iconpack.py solidglass27
```

The importer targets the Light.theme IconBundles set (172+ icons including many third-party apps). Dark / Clear variants can be swapped by editing the theme_dir in PACKS["solidglass27"].

**Licence:** check the upstream repo / package. Redistributed here as era
reference for a personal theming package. Authored icons from this pack win
over real device artwork for the glass27 skin.

## glass27 (fallback)

If no Solid Glass icons are present, the skin falls back to the device's own
real icons (untouched). Once the pack is imported, the authored set is used.

## The generated set (every era)

`tools/sk1n-icons.py` draws the fallback set for the stock bundle ids in
`ios1` and `ios7` from scratch (PIL primitives) — original art, no Apple
artwork copied, traced or upscaled. These are the apps none of the packs
cover. The glass27 skin does not ship a generated set; it uses Solid Glass
27 when available.

## Creating custom 1:1 packs

1. Research exact era look (2007.mobile for iOS 1, Version Museum galleries, side-by-sides).
2. Export or recreate icons at 180px (or @2x/@3x variants).
3. Name them by bundle ID (e.g. `com.apple.mobilephone.png`).
4. Drop into `layout/Library/Sk1n/Skins/<era>/Icons/` or the user override path.
5. Respring. Authored files override everything.

Runtime gloss for ios1 is now tuned closer to real photos (brighter crown, soft falloff, subtle lower band).