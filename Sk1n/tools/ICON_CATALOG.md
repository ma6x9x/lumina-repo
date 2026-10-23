# Sk1n icon catalog - sources and licences

Each bundled skin's `Icons/` directory is a merged catalog: era-true third
party packs first, plus the engine's own generated set
(`tools/sk1n-icons.py`) for bundle ids the packs do not cover. The packs are
imported with `tools/import-iconpack.py` (see that file for the per-pack
mapping tables). This file records where every imported icon came from and
under what terms it is redistributed.

## zagnut531/iOS-6-Icons → `ios1`

https://github.com/zagnut531/iOS-6-Icons — "Cropped icons" of the iPhone &
iPod touch set, 45 icons mapped to bundle ids by
`tools/import-iconpack.py` (`APPLE_CROPPED`), upscaled 114px → 180px and
alpha-masked to the home-screen squircle.

Imported sets: the 45 stock-app icons from `iPhone & iPod touch/Cropped icons`,
10 era third-party app icons (`Facebook`, `Instagram`, `Twitter`, `Netflix`,
`Spotify`, `WhatsApp`, `Snapchat`, `YouTube`, `Discord`, `Messenger`) and 4
era-styled recreations for apps that did not exist in the era (`Fitness`,
`Freeform`, `Clips`, Apple Watch remote view, Code Scanner).

**Credit:** per the upstream README, credit u/Ape2002huh for the
Colgate/Apple Support/Apple Music for Artists/Clips/Vision Pro/Magnifier/
Freeform icons and u/kdfjkw4 for the Music Classical icon; the rest of the
pack is the author's own extraction.

**Licence: none present in the upstream repo.** These are authentic iOS era
artwork — Apple's copyright and Apple's app icons, extracted by the upstream
author from a jailbroken iPod touch 5 to document/restore the iOS 6 era, plus
redditor-made icons for apps that did not exist in the iOS 6 era (noted as
such by upstream) and third-party app artwork from that era. They are
redistributed here as era reference for a personal theming package, not as
Apple assets. If you are a rights holder and object, remove the
`layout/Library/Sk1n/Skins/ios1/Icons/` set shipped from this pack - the
skin still works: real artwork, rendered from the device at runtime
(`SPKRealIconForBundleID`), covers every app without any of these files.

## JustAnOkapi/Okapi-Icons-Bulk → `ios7`

https://github.com/JustAnOkapi/Okapi-Icons-Bulk - the `Okapi Icons.theme`
icon bundle set, 39 icons, `IconBundles/<bundle>-large.png` →
`<bundle>.png`. **Licence: The Unlicense** (public domain) - see
`layouts` attribution upstream; nothing in this set is Apple artwork.

## glass27

Ships no artwork. The device's own real icons, rendered at runtime and not
chromed — modern home-screen art is already the Liquid Glass era's look, and
overlaying a pane on it was what made the runtime-generated icons read messy.

## The generated set (every era)

`tools/sk1n-icons.py` draws the fallback set for the stock bundle ids in
`ios1` and `ios7` from scratch (PIL primitives) - original art, no Apple
artwork copied, traced or upscaled. These are the apps none of the packs
cover. The `glass27` skin ships no generated set (see above).