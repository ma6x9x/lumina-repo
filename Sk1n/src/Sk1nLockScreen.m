#import "Sk1nLockScreen.h"
#import "Sk1nHook.h"
#import "Sk1nSlideToUnlockView.h"
#import "SPKRuntime.h"
#import "Sk1nPrefs.h"
#import <objc/message.h>

static const NSInteger kSliderTag = 0x5E1D;
static Sk1nEra gStyle;
static NSDictionary *gConfig;
static BOOL gBlockSwipe;

static BOOL Sk1nAttemptUnlock(void) {
    @try {
        Class c = NSClassFromString(@"SBLockScreenManager");
        id mgr = [c respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance)) : nil;
        SEL sel = NSSelectorFromString(@"unlockUIFromSource:withOptions:");
        if (mgr && [mgr respondsToSelector:sel]) {
            SPKTrace(@"unlock_begin", @{@"route": @"unlockUIFromSource:withOptions:"});
            ((void (*)(id, SEL, int, id))objc_msgSend)(mgr, sel, 0, nil);
            SPKTrace(@"unlock_result", @{@"route": @"unlockUIFromSource:withOptions:", @"called": @"1"});
            return YES;
        }
        SPKTrace(@"unlock_result", @{@"route": @"none", @"called": @"0"});
    } @catch (NSException *ex) {
        SPKTrace(@"unlock_exception", @{@"reason": ex.reason ?: @""});
    }
    return NO;
}

static void Sk1nHideHint(UIView *root) {
    // "Swipe up to unlock" hint lives in CSTeachableMomentsContainerView (by name; best effort).
    Class hint = NSClassFromString(@"CSTeachableMomentsContainerView");
    if (!hint) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:hint]) { v.hidden = YES; continue; }
        [stack addObjectsFromArray:v.subviews];
    }
}

static void Sk1nDisableSwipeGestures(UIView *root) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    NSMutableArray *names = [NSMutableArray array];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (v.tag == kSliderTag) continue;
        for (UIGestureRecognizer *g in v.gestureRecognizers) {
            NSString *n = NSStringFromClass(g.class);
            [names addObject:n];
            if ([n rangeOfString:@"Dismiss" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [n rangeOfString:@"Unlock" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                g.enabled = NO;
                SPKTrace(@"swipe_gesture_disabled", @{@"class": n});
            }
        }
        [stack addObjectsFromArray:v.subviews];
    }
    // Discovery data for the next device cycle: which recognisers exist at all.
    SPKTrace(@"coversheet_gestures", @{@"classes": [names componentsJoinedByString:@","]});
}

static void Sk1nInstallSlider(UIViewController *vc) {
    if (SPKKillSwitchEngaged(SK1N_SUBDIR)) return;
    UIView *root = vc.view;
    if (!root || [root viewWithTag:kSliderTag]) return;
    SPKTrace(@"slider_install_begin", nil);
    CGSize sz = [Sk1nSlideToUnlockView preferredSizeForStyle:gStyle containerWidth:root.bounds.size.width];
    Sk1nSlideToUnlockView *s = [[Sk1nSlideToUnlockView alloc]
        initWithFrame:CGRectMake((root.bounds.size.width - sz.width) / 2,
                                 root.bounds.size.height - sz.height - 96, sz.width, sz.height)
                style:gStyle config:gConfig];
    s.tag = kSliderTag;
    s.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin |
                         UIViewAutoresizingFlexibleRightMargin;
    __weak Sk1nSlideToUnlockView *weak = s;
    s.onUnlock = ^{
        if (!Sk1nAttemptUnlock()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [weak reset]; });
        } else {
            // Re-arm for the next lock.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [weak reset]; });
        }
    };
    [root addSubview:s];
    Sk1nHideHint(root);
    if (gBlockSwipe) Sk1nDisableSwipeGestures(root);
    SPKTrace(@"slider_install_result", @{@"style": Sk1nEraName(gStyle) ?: @"?"});
}

NSUInteger Sk1nLockScreenInstall(Sk1nEra style, NSDictionary *cfg, BOOL blockSwipe) {
    gStyle = style; gConfig = [cfg copy]; gBlockSwipe = blockSwipe;
    NSUInteger n = 0;
    SEL sel = @selector(viewDidAppear:);
    IMP orig = Sk1nHookNamed(@"CSCoverSheetViewController", sel, ^id(IMP orig) {
        return ^void(UIViewController *self_, BOOL animated) {
            ((void (*)(id, SEL, BOOL))orig)(self_, sel, animated);
            @try {
                Sk1nInstallSlider(self_);
            } @catch (NSException *ex) {
                SPKTrace(@"slider_install_exception", @{@"reason": ex.reason ?: @""});
            }
        };
    });
    if (orig) n++;
    return n;
}
