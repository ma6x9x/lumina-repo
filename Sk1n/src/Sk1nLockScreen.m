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

#pragma mark - Classic right-swipe unlock

@interface Sk1nRightSwipeHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *host;
@end

@implementation Sk1nRightSwipeHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Let Face ID / vertical dismiss continue to work; we only claim the horizontal right swipe.
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateEnded &&
        pan.state != UIGestureRecognizerStateCancelled &&
        pan.state != UIGestureRecognizerStateFailed) return;

    CGPoint vel = [pan velocityInView:pan.view];
    CGPoint trans = [pan translationInView:pan.view];
    CGFloat width = pan.view.bounds.size.width;
    if (width < 1) return;

    // Rightward = positive x. Classic slide-to-unlock threshold.
    BOOL farEnough   = trans.x > width * 0.40;
    BOOL fastEnough  = vel.x   > 450;
    BOOL mostlyHorizontal = fabs(trans.y) < fabs(trans.x) * 1.3;

    if ((farEnough || fastEnough) && mostlyHorizontal && trans.x > 0) {
        SPKTrace(@"swipe_right_unlock", @{@"transX": @(trans.x).stringValue, @"velX": @(vel.x).stringValue});
        Sk1nAttemptUnlock();
    }
}

@end

static Sk1nRightSwipeHandler *gRightSwipeHandler;

static void Sk1nInstallRightSwipe(UIViewController *vc) {
    UIView *root = vc.view;
    if (!root) return;

    for (UIGestureRecognizer *g in root.gestureRecognizers) {
        if (g.tag == kSwipeTag) return;
    }

    if (!gRightSwipeHandler) gRightSwipeHandler = [Sk1nRightSwipeHandler new];
    gRightSwipeHandler.host = root;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gRightSwipeHandler action:@selector(handlePan:)];
    pan.delegate = gRightSwipeHandler;
    pan.maximumNumberOfTouches = 1;
    pan.tag = kSwipeTag;
    [root addGestureRecognizer:pan];

    SPKTrace(@"swipe_right_installed", nil);
}

#pragma mark - Optional classic visual slider

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
        Sk1nInstallRightSwipe(vc);
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
