#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Snowboard-style icon override. Looks up <skin>/Icons/<bundleID>.png (and @2x/@3x).
/// Returns nil when the skin has no icon for that bundle -> stock icon is kept.
UIImage *_Nullable Sk1nIconForBundleID(Sk1nSkin *skin, NSString *bundleID);

/// Hooks SpringBoard's icon image lookup. Every hook is guarded and traced;
/// returns the number of hooks that actually installed (0 = nothing changed).
NSUInteger Sk1nIconEngineInstall(Sk1nSkin *skin);

NS_ASSUME_NONNULL_END
