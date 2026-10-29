#import "Sk1nLockScreen.h"
#import "Sk1nHook.h"
#import "Sk1nSlideToUnlockView.h"
#import "SPKRuntime.h"
#import "Sk1nPrefs.h"
#import <objc/message.h>

static const NSInteger kSliderTag = 0x5E1D;
static const NSInteger kSwipeTag  = 0x5E1E;
static Sk1nEra gStyle;
static NSDictionary *gConfig;
static BOOL gInstallClassic;

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
    Class hint = NSClassFromString(@"CSTeachableMomentsContainerView");
    if (!hint) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:hint]) { v.hidden = YES; continue; }
        [stack addObjectsFromArray:v.subviews];
    }
}

#pragma mark - Working swipe-up

@interface Sk1nSwipeUpHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *host;
@end

@implementation Sk1nSwipeUpHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES; // coexist with stock dismiss / Face ID gestures
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;

    CGPoint vel = [pan velocityInView:pan.view];
    CGPoint trans = [pan translationInView:pan.view];

    // Upward = negative y. Require either a decent distance or a flick.
    BOOL farEnough   = trans.y < -80;
    BOOL fastEnough  = vel.y   < -400;
    BOOL mostlyVertical = fabs(trans.x) < fabs(trans.y) * 1.4;

    if ((farEnough || fastEnough) && mostlyVertical) {
        SPKTrace(@"swipe_up_unlock", @{@"transY": @(trans.y).stringValue, @"velY": @(vel.y).stringValue});
        Sk1nAttemptUnlock();
    }
}

@end

static Sk1nSwipeUpHandler *gSwipeHandler;

static void Sk1nInstallSwipeUp(UIViewController *vc) {
    UIView *root = vc.view;
    if (!root) return;

    // Avoid double-install
    for (UIGestureRecognizer *g in root.gestureRecognizers) {
        if (g.tag == kSwipeTag) return;
    }

    if (!gSwipeHandler) gSwipeHandler = [Sk1nSwipeUpHandler new];
    gSwipeHandler.host = root;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gSwipeHandler action:@selector(handlePan:)];
    pan.delegate = gSwipeHandler;
    pan.maximumNumberOfTouches = 1;
    pan.tag = kSwipeTag;
    [root addGestureRecognizer:pan];

    SPKTrace(@"swipe_up_installed", nil);
}

#pragma mark - Optional classic slider

static void Sk1nInstallClassicSlider(UIViewController *vc) {
    if (!gInstallClassic) return;
    UIView *root = vc.view;
    if (!root || [root viewWithTag:kSliderTag]) return;

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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [weak reset]; });
        }
    };
    [root addSubview:s];
    Sk1nHideHint(root);
    SPKTrace(@"classic_slider_installed", @{@"style": Sk1nEraName(gStyle) ?: @"?"});
}

#pragma mark - Install

static void Sk1nOnCoverSheetAppear(UIViewController *vc) {
    if (SPKKillSwitchEngaged(SK1N_SUBDIR)) return;
    @try {
        Sk1nInstallSwipeUp(vc);
        Sk1nInstallClassicSlider(vc);
    } @catch (NSException *ex) {
        SPKTrace(@"lockscreen_install_exception", @{@"reason": ex.reason ?: @""});
    }
}

NSUInteger Sk1nLockScreenInstall(Sk1nEra style, NSDictionary *cfg, BOOL installClassicSlider) {
    gStyle = style;
    gConfig = [cfg copy];
    gInstallClassic = installClassicSlider;

    NSUInteger n = 0;
    SEL sel = @selector(viewDidAppear:);
    IMP orig = Sk1nHookNamed(@"CSCoverSheetViewController", sel, ^id(IMP orig) {
        return ^void(UIViewController *self_, BOOL animated) {
            ((void (*)(id, SEL, BOOL))orig)(self_, sel, animated);
            Sk1nOnCoverSheetAppear(self_);
        };
    });
    if (orig) n++;
    return n;
}
