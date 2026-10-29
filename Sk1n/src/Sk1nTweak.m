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
#import "Sk1nUIChrome.h"
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

        SPKTraceConfigure(SK1N_SUBDIR, SK1N_VERSION);
        SPKTrace(@"ctor_begin", @{@"version": SK1N_VERSION});

        if (SPKKillSwitchEngaged(SK1N_SUBDIR)) {
            SPKTrace(@"kill_switch", @{@"engaged": @"1"});
            return;
        }
        if (!Sk1nPrefEnabled()) { SPKTrace(@"disabled_by_pref", nil); return; }

        NSString *skinID = Sk1nPrefActiveSkinID();
        BOOL wantUnlock = Sk1nPrefSlideToUnlock();
        if ([skinID isEqualToString:@"stock"] && !wantUnlock) {
            SPKTrace(@"stock_nothing_to_do", nil);
            return;
        }

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
                    NSUInteger badges = 0, dots = 0, status = 0, labels = 0;
                    @try {
                        badges = Sk1nBadgeChromeInstall(skin);
                        dots = Sk1nPageDotsInstall(skin);
                        status = Sk1nStatusBarInstall(skin);
                        labels = Sk1nLabelChromeInstall(skin);
                    } @catch (__unused id ex) {}
                    SPKTrace(@"skin_applied", @{@"icon_hooks": @(icons).stringValue, @"dock_hook": dock ? @"1" : @"0",
                                                @"badge_hooks": @(badges).stringValue, @"pagedots_hooks": @(dots).stringValue,
                                                @"status_hooks": @(status).stringValue, @"label_hooks": @(labels).stringValue});
                }
            }

            if (wantUnlock) {
                // Swipe-up is always the working path when the feature is on.
                // Classic slider is only added when the user explicitly picks a style
                // other than "auto" (or when the skin itself requests one).
                NSString *pick = Sk1nPrefSliderStyle();
                Sk1nEra era = Sk1nEraIOS1; BOOL haveEra = NO;
                NSDictionary *cfg = skin.slider;
                BOOL wantClassic = NO;

                if ([pick isEqualToString:@"auto"]) {
                    if (skin && cfg) {
                        haveEra = Sk1nEraFromName(cfg[@"style"], &era);
                        wantClassic = haveEra; // skin asked for a visual slider
                    }
                } else {
                    haveEra = Sk1nEraFromName(pick, &era);
                    wantClassic = haveEra;
                    if (skin && haveEra) {
                        Sk1nEra cfgEra;
                        if (!(Sk1nEraFromName(cfg[@"style"], &cfgEra) && cfgEra == era)) cfg = nil;
                    } else cfg = nil;
                }

                NSUInteger n = Sk1nLockScreenInstall(haveEra ? era : Sk1nEraIOS1, cfg, wantClassic);
                SPKTrace(@"lockscreen_hooks", @{@"installed": @(n).stringValue,
                                                @"swipe_up": @"1",
                                                @"classic_slider": wantClassic ? @"1" : @"0"});
            }
        } @catch (NSException *ex) {
            SPKTrace(@"ctor_exception", @{@"reason": ex.reason ?: @""});
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSFileManager.defaultManager removeItemAtPath:Sk1nSentinelPath() error:nil];
            SPKTrace(@"sentinel_cleared", nil);
        });
        SPKTrace(@"ctor_end", nil);
    }
}