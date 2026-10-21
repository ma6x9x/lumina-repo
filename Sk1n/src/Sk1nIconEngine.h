#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Icon override engine. Default flavour renders UIKit's own artwork for the
/// bundle (SPKRealIconForBundleID) re-chromed for the skin's era; the skin's
/// authored Icons/<bundleID>.png set is the optional "art" flavour. Returns
/// nil when no relevant image is available -> stock icon is kept.
UIImage *_Nullable Sk1nIconForBundleID(Sk1nSkin *skin, NSString *bundleID);

/// Hooks SpringBoard's icon image lookup. Every hook is guarded and traced;
/// returns the number of hooks that actually installed (0 = nothing changed).
NSUInteger Sk1nIconEngineInstall(Sk1nSkin *skin);

/// Drop the cache and current skin reference. The hooks installed by
/// Sk1nIconEngineInstall keep running until SpringBoard itself reloads, so
/// call this only on reload/respring paths, never mid-layout.
void Sk1nIconEngineUnload(void);

NS_ASSUME_NONNULL_END
