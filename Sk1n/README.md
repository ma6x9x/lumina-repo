# Sk1n

One setting + a respring re-skins SpringBoard in a prepackaged era:

| Skin id | Era |
|---------|-----|
| `ios1` | iOS 1-6, skeuomorphic: glossy icons, glossy dock shelf |
| `ios7` | iOS 7, flat |
| `glass27` | iOS 26/27 Liquid Glass (UIGlassEffect on iOS 26+, material blur below) |
| `stock` | no skin (default) |

Bundle id `com.kolby.sk1n`. ObjC-only dylib, SpringBoard filter, rootless (Dopamine) and roothide packages.
Prefs live in Settings > Sk1n (PreferenceLoader).

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

Hooks `-[SBIconImageView contentsImage]` and `-displayedImage` and swaps in `<skin>/Icons/<bundleID>.png` when present. **Which of the two SpringBoard actually reads on iOS 16/17 rootless is not verified from CI** - both are tried; the trace shows which installed. Folders, widgets and many modern icon paths may not be covered.

`tools/sk1n-icons.py` (needs Pillow) generates **original** placeholder icons for 24 stock bundle ids per era, drawn from scratch with PIL geometric primitives. **Original Apple artwork is not redistributed**, copied or traced; replace the placeholders with your own art.

## Slide to unlock

`Sk1nSlideToUnlockView` is a complete UIKit control (no private API): ios1 glossy dark track / silver thumb / shimmering text; ios7 flat capsule; glass27 glass capsule track + glass thumb, travelling specular shimmer, thumb swells and springs while held (`UIGlassEffect` found at runtime on iOS 26+, `UIBlurEffect` material below). Respects Reduce Motion, VoiceOver adjustable.

The lock screen wiring (`Sk1nLockScreen`) hooks `CSCoverSheetViewController -viewDidAppear:`, adds the slider, hides `CSTeachableMomentsContainerView` (the "swipe up" hint) and unlocks through `-[SBLockScreenManager unlockUIFromSource:withOptions:]`. **None of that could be verified without a device**: the unlock call may only raise the passcode/Face ID UI, and the swipe-up suppression is a name-based heuristic over gesture recognisers (the log lists the class names it saw, for the next device cycle). That is why the feature is off by default and swipe suppression is a second, separate opt-in.

## Not done yet (honest list)

- `fonts` and `sounds` in Skin.plist are parsed/validated but not applied/played.
- Liquid Glass here is the blur/`UIGlassEffect` approach, not the Siri27 Metal `LGGlassRenderer` pipeline.
- Dock plate hook (`SBDockView -layoutSubviews`) unverified on device.

## Build

macOS only (Theos + Xcode); see `.github/workflows/build-sk1n.yml`. `src/spkit` is a symlink to `../../SPKit` (Theos object paths), compiled with `-DSPK_CLASS_PREFIX=Sk1nSPK`; `sk1nprefs/shared` symlinks `../src` for the respring helper.
