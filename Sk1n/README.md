# Sk1n

One setting + a respring re-skins SpringBoard in a prepackaged era:

| Skin id | Era | Icon catalog |
|---------|-----|--------------|
| `ios1` | iOS 1-6, skeuomorphic: glossy icons (strong top sheen), metallic dock shelf, black status bar, Helvetica-Bold labels | authentic iOS 6 set (zagnut531/iOS-6-Icons, extracted from real devices) + stronger runtime gloss on uncovered apps |
| `ios7` | iOS 7, flat (no gloss, bright solid colors, simple frosted dock) | Okapi flat pack (JustAnOkapi, Unlicense) + generated flat set |
| `glass27` | iOS 26/27 Liquid Glass (translucent layered icons, frosted Control Center, material blur) | the device's real icons, untouched — that artwork is this era's own look |
| `stock` | no skin (default) | untouched |

Bundle id `com.kolby.sk1n`. ObjC-only dylib, SpringBoard filter, rootless (Dopamine) and roothide packages.
Prefs live in Settings > Sk1n (PreferenceLoader).

## Visual accuracy notes

Chrome is tuned against real era photos and side-by-sides:
- iOS 1-6: Version Museum iPhone OS 1 galleries, Engadget 2007 UI shots, Ars Technica iOS 6 vs 7 comparisons. Gloss is a bright top-half sheen + inner hairline; dock is a metallic gradient shelf.
- iOS 7: flat icons with no dimensional chrome (the 2013 break from skeuomorphism).
- iOS 26/27: Apple Liquid Glass material (translucent, refractive icons and Control Center); no extra overlay is applied so the device's own art stays correct.

## Settings

- **Enable Sk1n** - master switch.
- **Active Skin** - stock / iOS 1-6 / iOS 7 / Liquid Glass.
- **Slide to Unlock** (`slideToUnlock`, off by default, *experimental*) - independent of the skin.
  - **Slider Style** (`sliderStyle`: auto / ios1 / ios7 / glass27) - pick the slider look separately from the skin; `auto` follows the active skin's `slider` config.
  - **Disable swipe-up gesture (risky)** (`slideToUnlockBlockSwipe`, off by default).
- **Apply & Respring** - saves and respawns SpringBoard (`sbreload`, falling back to `killall -9 SpringBoard`) from the jbroot.
- **Revert to Stock & Respring** - sets skin to `stock`, turns slider off, respring.

## Safety (fail closed)

- **Kill switch:** `touch /var/jb/var/mobile/Library/Sk1n/DISABLE` (rootless; jbroot-resolved on roothide, via `SPKKillSwitchEngaged`). Checked first in the constructor and again before the slider installs.
- **Crash-loop guard:** a `.loading` sentinel is written while loading and cleared 8 s after a successful load. If SpringBoard died in between, the next launch writes `DISABLE` and stands down. (Side effect: respringing again within 8 s of a launch also trips it - delete `DISABLE` to re-enable.)
- Every hook is plain ObjC runtime replacement, guarded: a missing class/selector installs nothing and is traced (`hook_missing_class` / `hook_missing_selector`). Hook bodies are `@try`-wrapped and fall back to the stock result.
- Invalid skins (bad plist, unsafe ids/paths, bad colours) are rejected and never applied.
- `SPKTrace` is synchronous + fsync'd: `<jbroot>/var/mobile/Library/Sk1n/status.log`.

## Skin format

```
layout/Library/Sk1n/Skins/<id>/
  Skin.plist
  Icons/<bundle id>.png        # 180px (@3x); also <id>@2x.png / @3x.png
```

User skins can also be dropped in `<jbroot>/var/mobile/Library/Sk1n/Skins/<id>/` (searched first).

`Skin.plist` keys: `id` (== directory name), `name`, `era` (`ios1|ios7|glass27`), `version`, `colors` (name -> `#RRGGBB[AA]`; `dockTop`, `dockBottom`, `tint`, `label`), `fonts`, `iconsDirectory`, `lockscreen`, `sounds`, and:

```
slider = { style: ios1|ios7|glass27, text, textColor, thumbColor, trackColor, shimmer: bool }
```

Classes: `Sk1nSkin` (loader + strict validator), `Sk1nSkinStore` (discovery). `tools/validate-skins.py` is the Python twin of the validator and runs in CI.

## Icon override engine

Hooks `-[SBIconImageView contentsImage]` and `-displayedImage` and resolves one image per bundle id, automatically (no pref):

1. **Authored skin artwork** - `<skin>/Icons/<bundle id>.png` (180px @3x; also @2x). The skin's own legacy-era icon files; **this always wins** - custom art is only ever consulted when the runtime has a file for the app.
2. **Real artwork** - `SPKRealIconForBundleID()` (SPKit; `+[UIImage _applicationIconImageForBundleIdentifier:format:scale:]`, format 2, the call device-verified through SwiftPeek's icon inventory). Era chrome is drawn over it only for iOS 1-6 (stronger classic gloss matching 2007-2012 photos); **iOS 7 and glass27 get no chrome** — their eras' artwork is already flat/modern. Covers every app the skin does not carry an icon for.
3. **Themer artwork** - `SPKThemeIconForBundleID()` (first SnowBoard/Anemone `IconBundles/<bundle id>[@3x|@2x|].png` hit), also chromed. Last resort.

The bundled `<skin>/Icons` sets are era catalogs: era-true packs (see
`tools/ICON_CATALOG.md` for sources and licences) first - authentic iOS 6 art
for `ios1` (extracted from real devices), the Unlicense'd Okapi flat pack for `ios7` - and the engine's own
generated set (`tools/sk1n-icons.py`) where the packs have no file. **Original Apple artwork is not generated here**: the
runtime renders the device's own icons (`SPKRealIconForBundleID`) for every
app; the one Apple-artwork set (`ios1`) is authentic era art redistributed
from the upstream pack under the terms noted in `tools/ICON_CATALOG.md`.

**Which of the two SpringBoard hooks actually reads on iOS 16/17 rootless is not verified from CI** - both are tried; the trace shows which installed. Folders, widgets and many modern icon paths may not be covered.

## Slide to unlock

`Sk1nSlideToUnlockView` is a complete UIKit control (no private API): ios1 glossy dark track / silver thumb / shimmering text; ios7 flat capsule; glass27 glass capsule track + glass thumb, travelling specular shimmer, thumb swells and springs while held (`UIGlassEffect` found at runtime on iOS 26+, `UIBlurEffect` material below). Respects Reduce Motion, VoiceOver adjustable.

The lock screen wiring (`Sk1nLockScreen`) hooks `CSCoverSheetViewController -viewDidAppear:`, adds the slider, hides `CSTeachableMomentsContainerView` (the "swipe up" hint) and unlocks through `-[SBLockScreenManager unlockUIFromSource:withOptions:]`. **None of that could be verified without a device**: the unlock call may only raise the passcode/Face ID UI, and the swipe-up suppression is a name-based heuristic over gesture recognisers (the log lists the class names it saw, for the next device cycle). That is why the feature is off by default and swipe suppression is a second, separate opt-in.

- **Badges and page dots** - per era, no extra setting: iOS 1-6 badges are the bright red pill with the raised white edge, iOS 7 badges are flat opaque red, glass27 badges are translucent glass capsules; page dots go solid dark for the legacy eras and take the skin tint for glass27. Badge and page-control classes are probed by name (`SBIconIconBadgeView` / `SBIconBadgeView` etc., `SBHomeScreenPageControl` / `SBPageControlView` etc.) - whatever exists installs, the trace records which.
- **Status bar (ios1)** - black background for the classic 2007 look (probed `UIStatusBar` / `SBStatusBar` / `_UIStatusBar`).
- **Icon labels (ios1)** - Helvetica-Bold 11pt with white text and subtle shadow (probed `SBIconLabelView` / `SBIconView`).

## Not done yet (honest list)

- `fonts` and `sounds` in Skin.plist are parsed/validated but not applied/played.
- Liquid Glass here is the blur/`UIGlassEffect` approach, not the Siri27 Metal `LGGlassRenderer` pipeline.
- Dock plate hook (`SBDockView -layoutSubviews`), badge, page-dot, status bar, and label hooks are style-only and **unverified on device** - a renamed private class costs the feature, not the home screen; the trace names what installed (or was absent). The glass27 dock tries a runtime-found `UIGlassEffect`, same approach as the slider, with the material blur as the floor.

## Build

macOS only (Theos + Xcode); see `.github/workflows/build-sk1n.yml`. `src/spkit` is a symlink to `../../SPKit` (Theos object paths), compiled with `-DSPK_CLASS_PREFIX=Sk1nSPK`; `sk1nprefs/shared` symlinks `../src` for the respring helper.
