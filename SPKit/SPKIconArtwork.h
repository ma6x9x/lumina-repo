#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Real app artwork

/// The app's own home-screen icon, rendered by UIKit itself — the same call
/// SpringBoard's compositor and every themer ends up reading on device:
///
///     +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]
///
/// with format 2 (home screen) at `UIScreen.mainScreen.scale`. The returned
/// image is pre-masked (squircle alpha) and pre-scaled; draw it as-is.
///
/// Private API, guarded: returns nil when the selector or the workspace is
/// absent, or the render throws. This is the technique SwiftPeek's icon
/// inventory device-verified on iPhone13,1 / iOS 17.3 before Sk1n adopted it —
/// do not reintroduce an SBIconModel read here (that is what made
/// SwiftPeek 0.2.x dangerous; see SwiftPeek/docs/DEPENDENCY_PLAN.md).
UIImage * _Nullable SPKRealIconForBundleID(NSString *bundleID);

#pragma mark - Themer artwork

/// SnowBoard / Anemone style bundled artwork: first hit of
/// `<theme root>/<theme>/IconBundles/<bundleID>[@3x|@2x|].png` across the
/// theme search paths (`<jbroot>`, then `/var/jb`, then the raw rootful
/// path — the same order a themer's runtime would see). nil when nothing
/// matches, or when the bundle id is empty or path-unsafe.
UIImage * _Nullable SPKThemeIconForBundleID(NSString *bundleID);

/// The search paths `SPKThemeIconForBundleID` consults, most likely first.
/// Exposed for diagnostics / recon (SwiftPeek's icon inventory records it).
NSArray<NSString *> *SPKIconThemeSearchPaths(void);

NS_ASSUME_NONNULL_END