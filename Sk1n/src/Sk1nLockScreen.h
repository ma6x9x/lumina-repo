#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// EXPERIMENTAL. Wires a working swipe-up unlock on the CoverSheet.
///
/// Primary path: a vertical pan recognizer installed on CSCoverSheetViewController
/// that calls -[SBLockScreenManager unlockUIFromSource:withOptions:] once the
/// user has swiped up far enough (or with enough velocity). This is the path
/// that should actually unlock the device.
///
/// Optional classic slider: only installed when the caller passes a non-nil
/// style and wants the visual control. The swipe-up gesture is independent.
///
/// What is verified: the gesture and the unlock call itself. What is NOT
/// verified from CI: that the unlock selector performs a full unlock on every
/// Face ID / passcode state, or that CSCoverSheetViewController is the exact
/// host on every iOS 16/17 build. Every step is @try-wrapped and fails by
/// leaving the stock lock screen alone.
///
/// Returns the number of hooks installed.
NSUInteger Sk1nLockScreenInstall(Sk1nEra style, NSDictionary *_Nullable sliderConfig, BOOL installClassicSlider);

NS_ASSUME_NONNULL_END