#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Persist the active skin (CFPreferences, synchronised) - used by Apply and Revert.
void Sk1nSetActiveSkin(NSString *skinID);
/// Respring by spawning sbreload/killall from the jailbreak root. Runs from the
/// Settings process; does nothing in the tweak itself. Returns YES if a helper spawned.
BOOL Sk1nRespringNow(void);

NS_ASSUME_NONNULL_END
