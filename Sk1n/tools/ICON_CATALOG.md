# Sk1n icon catalog - sources and licences

Each bundled skin's `Icons/` directory is a merged catalog: era-true third
party packs first, plus the engine's own generated set
(`tools/sk1n-icons.py`) for bundle ids the packs do not cover. The packs are
imported with `tools/import-iconpack.py` (see that file for the per-pack
mapping tables). This file records where every imported icon came from and
under what terms it is redistributed.

## zagnut531/iOS-6-Icons → `ios1`

https://github.com/zagnut531/iOS-6-Icons — "Cropped icons" of the iPhone &
iPod touch set, mapped to bundle ids by `tools/import-iconpack.py`
(`APPLE_CROPPED`), upscaled 114px → 180px and alpha-masked to the home-screen
squircle.

**Licence: none present in the upstream repo.** Authentic iOS era artwork
(Apple's copyright) plus redditor-made icons for apps that did not exist in
the era. Redistributed here as era reference for a personal theming package.
If you are a rights holder and object, remove the
`layout/Library/Sk1n/Skins/ios1/Icons/` set shipped from this pack — the
skin still works: real artwork rendered from the device at runtime covers
every app without any of these files.

## JustAnOkapi/Okapi-Icons-Bulk → `ios7`

https://github.com/JustAnOkapi/Okapi-Icons-Bulk — the `Okapi Icons.theme`
icon bundle set. **Licence: The Unlicense** (public domain). Nothing in this
set is Apple artwork. This is the preferred authored set for the iOS 7 skin.

## glass27

Ships no artwork. The device's own real icons, rendered at runtime and not
chromed — modern home-screen art is already the Liquid Glass era's look.

## The generated set (every era)

`tools/sk1n-icons.py` draws the fallback set for the stock bundle ids in
`ios1` and `ios7` from scratch (PIL primitives) — original art, no Apple
artwork copied, traced or upscaled. These are the apps none of the packs
cover.

**iOS 7 generation (updated):** pure flat solid fills with cleaner geometric
glyphs sized and weighted to match real 2013 iOS 7 reference sheets. No
gradients, no gloss. The Okapi pack still wins when it has a file; the
generator only fills the gaps.

The `glass27` skin ships no generated set (see above).
