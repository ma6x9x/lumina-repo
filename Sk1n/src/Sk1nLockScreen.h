#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// EXPERIMENTAL. Installs the slide-to-unlock UI on the CoverSheet.
///
/// What is verified: the slider view itself (Sk1nSlideToUnlockView) is plain
/// UIKit. What is NOT verified from CI: that CSCoverSheetViewController's
/// -viewDidAppear: is the right place on every iOS 16/17 build, that
/// -[SBLockScreenManager unlockUIFromSource:withOptions:] performs a real
/// unlock (it should on passcode-less/already-authenticated state; on a Face ID
/// device that has not authenticated it may only present the passcode UI),
/// and which gesture recognisers carry the stock swipe-up. Every step is
/// @try-wrapped, traced, and fails by leaving the stock lock screen alone.
///
/// Returns the number of hooks installed.
NSUInteger Sk1nLockScreenInstall(Sk1nEra style, NSDictionary *_Nullable sliderConfig, BOOL blockSwipe);

NS_ASSUME_NONNULL_END
