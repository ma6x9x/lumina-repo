#import "Sk1nPrefs.h"
#import "SPKRuntime.h"

BOOL Sk1nPrefEnabled(void) { return SPKPrefBool(SK1N_DOMAIN, @"enabled", YES); }
BOOL Sk1nPrefSlideToUnlock(void) { return SPKPrefBool(SK1N_DOMAIN, @"slideToUnlock", NO); }
BOOL Sk1nPrefBlockSwipe(void) { return SPKPrefBool(SK1N_DOMAIN, @"slideToUnlockBlockSwipe", NO); }

static NSString *Sk1nPrefString(NSString *key, NSString *fallback) {
    id v = SPKPrefs(SK1N_DOMAIN)[key];
    if ([v isKindOfClass:NSString.class] && [(NSString *)v length] > 0) return v;
    return fallback;
}
NSString *Sk1nPrefActiveSkinID(void) { return Sk1nPrefString(@"activeSkin", @"stock"); }
NSString *Sk1nPrefSliderStyle(void) { return Sk1nPrefString(@"sliderStyle", @"auto"); }
