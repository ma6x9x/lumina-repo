# Sk1n

One setting + a respring re-skins SpringBoard in a prepackaged era:

| Skin id | Era | Icon catalog |
|---------|-----|--------------|
| `ios1` | iOS 1-6, skeuomorphic: glossy icons (strong top sheen), metallic dock shelf, black status bar, Helvetica-Bold labels | authentic iOS 6 set (zagnut531/iOS-6-Icons, extracted from real devices) + stronger runtime gloss on uncovered apps |
| `ios7` | iOS 7, flat (no gloss, bright solid colors, simple frosted dock) | Okapi flat pack (JustAnOkapi, Unlicense) + generated flat set |
| `glass27` | iOS 26/27 Liquid Glass (translucent layered icons, frosted Control Center, material blur) | **Solid Glass 27** (iVintageLover/Solid-Glass) when imported; otherwise the device's real icons |
| `stock` | no skin (default) | untouched |

Bundle id `com.kolby.sk1n`. ObjC-only dylib, SpringBoard filter, rootless (Dopamine) and roothide packages.
Prefs live in Settings > Sk1n (PreferenceLoader).

## Visual accuracy notes

Chrome is tuned against real era photos and side-by-sides:
- iOS 1-6: Version Museum iPhone OS 1 galleries, Engadget 2007 UI shots, Ars Technica iOS 6 vs 7 comparisons. Gloss is a bright top-half sheen + inner hairline; dock is a metallic gradient shelf.
- iOS 7: flat icons with no dimensional chrome (the 2013 break from skeuomorphism).
- iOS 26/27: Apple Liquid Glass material. Preferred authored set is **Solid Glass 27** from https://github.com/iVintageLover/Solid-Glass (see `tools/ICON_CATALOG.md` for extraction + import steps). Authored icons win over real device artwork.

## Settings

- **Enable Sk1n** - master switch.
- **Active Skin** - stock / iOS 1-6 / iOS 7 / Liquid Glass.
- **Slide to Unlock** (`slideToUnlock`, off by default, *experimental*) - enables a **classic right-swipe unlock** on the CoverSheet. Slide far enough to the right (or flick) and it calls `SBLockScreenManager unlockUIFromSource:withOptions:`.
  - **Slider Style** (`sliderStyle`: auto / ios1 / ios7 / glass27) - if set to anything other than `auto`, also installs the classic visual slider as a secondary control that uses the same unlock route.
- **Apply & Respring** - saves and respawns SpringBoard.
- **Revert to Stock & Respring** - sets skin to `stock`, turns the unlock feature off, respring.

## Safety (fail closed)

- **Kill switch:** `touch /var/jb/var/mobile/Library/Sk1n/DISABLE` (rootless; jbroot-resolved on roothide). Checked first in the constructor.
- **Crash-loop guard:** a `.loading` sentinel is written while loading and cleared 8 s after a successful load. If SpringBoard died in between, the next launch writes `DISABLE` and stands down.
- Every hook is plain ObjC runtime replacement, guarded. Hook bodies are `@try`-wrapped.
- Invalid skins are rejected and never applied.
- `SPKTrace` is synchronous + fsync'd: `<jbroot>/var/mobile/Library/Sk1n/status.log`.

## Skin format

```
layout/Library/Sk1n/Skins/<id>/
  Skin.plist
  Icons/<bundle id>.png
```

User skins can also be dropped in `<jbroot>/var/mobile/Library/Sk1n/Skins/<id>/` (searched first).

## Icon override engine

Hooks `-[SBIconImageView contentsImage]` and `-displayedImage`:

1. **Authored skin artwork** - `<skin>/Icons/<bundle id>.png` always wins.
2. **Real artwork** - `SPKRealIconForBundleID()`. iOS 1-6 gets stronger classic gloss; iOS 7 and glass27 stay untouched unless an authored icon exists.
3. **Themer artwork** - last resort.

See `tools/ICON_CATALOG.md` for sources and licences, including how to import Solid Glass 27.

## Unlock (classic right-swipe)

When **Slide to Unlock** is enabled, Sk1n installs a horizontal pan on `CSCoverSheetViewController`. Sliding roughly 40 % of the screen width to the right (or a strong rightward flick) calls the unlock method, matching the old iOS 1-6 behavior. The gesture allows simultaneous recognition so Face ID and the stock vertical dismiss still work. The classic visual slider is optional and only appears when a style is explicitly chosen; it uses the same unlock call.

On a device that has not yet authenticated, the unlock call may still surface the passcode or Face ID UI. That is expected.

## Not done yet

- `fonts` and `sounds` in Skin.plist are parsed but not applied.
- Liquid Glass here is the blur/`UIGlassEffect` approach, not the Siri27 Metal pipeline.
- Dock / badge / status-bar / label hooks are style-only and unverified on device.

## Build

macOS only (Theos + Xcode); see `.github/workflows/build-sk1n.yml`.
