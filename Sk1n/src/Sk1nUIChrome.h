#import <UIKit/UIKit.h>
#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Badge + page dot chrome for the active era. Every target class is probed
/// by name and every hook is guarded — on an iOS release that renamed any of
/// these, the feature silently does not install and the trace says so.
/// Returns the number of hooks that actually installed.
NSUInteger Sk1nBadgeChromeInstall(Sk1nSkin *skin);
NSUInteger Sk1nPageDotsInstall(Sk1nSkin *skin);

NS_ASSUME_NONNULL_END