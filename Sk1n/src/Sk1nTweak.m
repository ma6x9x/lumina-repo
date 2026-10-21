// Sk1n - SpringBoard entry point. ObjC only (Swift in SpringBoard = Safe Mode).
//
// Order matters and every early return is a FAIL-CLOSED path that leaves stock
// iOS untouched: bundle check -> trace config -> kill switch -> master pref ->
// crash-loop guard -> skin load + validation -> hooks (each guarded).
#import <UIKit/UIKit.h>
#import "SPKRuntime.h"
#import "Sk1nPrefs.h"
#import "Sk1nSkinStore.h"
#import "Sk1nIconEngine.h"
#import "Sk1nDockPlate.h"
#import "Sk1nLockScreen.h"

static NSString *Sk1nSentinelPath(void) {
    return SPKRootedPath(@"/var/mobile/Library/Sk1n/.loading");
}
static NSString *Sk1nDisablePath(void) {
    return SPKRootedPath(@"/var/mobile/Library/Sk1n/DISABLE");
}

__attribute__((constructor))
static void Sk1nInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

        // Before anything that could crash: tracing must record the crash it explains.
        SPKTraceConfigure(SK1N_SUBDIR, SK1N_VERSION);
        SPKTrace(@"ctor_begin", @{@"version": SK1N_VERSION});

        if (SPKKillSwitchEngaged(SK1N_SUBDIR)) {
            SPKTrace(@"kill_switch", @{@"engaged": @"1"});
            return;
        }
        if (!Sk1nPrefEnabled()) { SPKTrace(@"disabled_by_pref", nil); return; }

        NSString *skinID = Sk1nPrefActiveSkinID();
        BOOL wantSlider = Sk1nPrefSlideToUnlock();
        if ([skinID isEqualToString:@"stock"] && !wantSlider) {
            SPKTrace(@"stock_nothing_to_do", nil);
            return;
        }

        // Crash-loop guard: if the previous launch never got to clear the sentinel,
        // SpringBoard died while we were loading. Engage the kill switch and stand down.
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *sentinel = Sk1nSentinelPath();
        [fm createDirectoryAtPath:[sentinel stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:nil];
        if ([fm fileExistsAtPath:sentinel]) {
            [@"crash-loop guard tripped\n" writeToFile:Sk1nDisablePath() atomically:YES
                                              encoding:NSUTF8StringEncoding error:nil];
            [fm removeItemAtPath:sentinel error:nil];
            SPKTrace(@"crashloop_guard_tripped", @{@"action": @"DISABLE written; remove it to re-enable"});
            return;
        }
        [@"1" writeToFile:sentinel atomically:YES encoding:NSUTF8StringEncoding error:nil];

        @try {
            Sk1nSkin *skin = nil;
            if (![skinID isEqualToString:@"stock"]) {
                skin = [Sk1nSkinStore.shared skinWithID:skinID];
                if (!skin) {
                    SPKTrace(@"skin_load_failed", @{@"id": skinID});
                } else {
                    SPKTrace(@"skin_loaded", @{@"id": skin.skinID, @"era": Sk1nEraName(skin.era) ?: @"?"});
                    NSUInteger icons = Sk1nIconEngineInstall(skin);
                    BOOL dock = Sk1nDockPlateInstall(skin);
                    SPKTrace(@"skin_applied", @{@"icon_hooks": @(icons).stringValue, @"dock_hook": dock ? @"1" : @"0", @"icon_flavor": Sk1nPrefIconFlavor()});
                }
            }

            if (wantSlider) {
                // Slider style is independent of the skin. "auto" follows the skin's
                // own slider config; an explicit style uses that era's built-in
                // look (with the skin's text/colour overrides if the skin has any).
                NSString *pick = Sk1nPrefSliderStyle();
                Sk1nEra era = Sk1nEraIOS1; BOOL haveEra = NO;
                NSDictionary *cfg = skin.slider;
                if ([pick isEqualToString:@"auto"]) {
                    if (skin) {
                        haveEra = Sk1nEraFromName(cfg[@"style"], &era);
                        if (!haveEra) { era = skin.era; haveEra = YES; }
                    } else {
                        era = Sk1nEraIOS1; haveEra = YES; cfg = nil; // stock skin + slider: classic
                    }
                } else {
                    haveEra = Sk1nEraFromName(pick, &era);
                    if (skin && haveEra) {
                        // Only reuse the skin's config if it targets the same era.
                        Sk1nEra cfgEra;
                        if (!(Sk1nEraFromName(cfg[@"style"], &cfgEra) && cfgEra == era)) cfg = nil;
                    } else cfg = nil;
                }
                if (haveEra) {
                    NSUInteger n = Sk1nLockScreenInstall(era, cfg, Sk1nPrefBlockSwipe());
                    SPKTrace(@"lockscreen_hooks", @{@"installed": @(n).stringValue, @"style": Sk1nEraName(era) ?: @"?"});
                }
            }
        } @catch (NSException *ex) {
            SPKTrace(@"ctor_exception", @{@"reason": ex.reason ?: @""});
        }

        // Survived load: clear the crash-loop sentinel after SpringBoard has had time to settle.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSFileManager.defaultManager removeItemAtPath:Sk1nSentinelPath() error:nil];
            SPKTrace(@"sentinel_cleared", nil);
        });
        SPKTrace(@"ctor_end", nil);
    }
}
