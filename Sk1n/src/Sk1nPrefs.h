#import <Foundation/Foundation.h>

#define SK1N_DOMAIN @"com.kolby.sk1n"
#define SK1N_SUBDIR @"Sk1n"   // <jbroot>/var/mobile/Library/Sk1n/{DISABLE,status.log}
#define SK1N_VERSION @"0.2.0"

NS_ASSUME_NONNULL_BEGIN

/// Master switch (default YES). Kill switch is checked separately.
BOOL Sk1nPrefEnabled(void);
/// "stock" (default), "ios1", "ios7", "glass27", or any installed skin id.
NSString *Sk1nPrefActiveSkinID(void);
/// Off by default: replaces swipe-up-to-unlock with a slider.
BOOL Sk1nPrefSlideToUnlock(void);
/// "auto" (match skin) | "ios1" | "ios7" | "glass27".
NSString *Sk1nPrefSliderStyle(void);
/// Off by default, riskier: also disables the stock dismiss gestures.
BOOL Sk1nPrefBlockSwipe(void);

NS_ASSUME_NONNULL_END
