#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// EXPERIMENTAL. Wires a classic right-swipe unlock on the CoverSheet.
///
/// Primary path: a horizontal pan recognizer that unlocks once the user has
/// slid far enough to the right (or with enough rightward velocity), matching
/// the old iOS 1-6 slide-to-unlock. Calls
/// -[SBLockScreenManager unlockUIFromSource:withOptions:].
///
/// Optional classic visual slider is still available when the caller requests it;
/// both paths use the same unlock method.
///
/// What is verified: the gesture and the unlock call. What is NOT verified from
/// CI: that the unlock selector performs a full unlock on every Face ID /
/// passcode state, or that CSCoverSheetViewController is the exact host on
/// every iOS 16/17 build. Every step is @try-wrapped and fails by leaving the
/// stock lock screen alone.
///
/// Returns the number of hooks installed.
NSUInteger Sk1nLockScreenInstall(Sk1nEra style, NSDictionary *_Nullable sliderConfig, BOOL installClassicSlider);

NS_ASSUME_NONNULL_END