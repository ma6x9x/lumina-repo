#import "Sk1nUIChrome.h"
#import "Sk1nHook.h"
#import "SPKRuntime.h"
#import <objc/message.h>

// Era chrome for the two most visible home-screen UI bits outside icon art:
// icon badges and the page dots. All styles are drawn with plain
// UIKit/CoreAnimation on top of whatever the stock view already renders, so
// the fallback (nothing installed) is the stock look, never a crash.

static Sk1nSkin *gSkin;

// Badge view classes across the 13…17 range, most likely first. None of this
// is device-verified from CI — each candidate that exists installs its own
// hook, and the trace records which ones were seen.
static NSArray<NSString *> *Sk1nBadgeClassNames(void) {
    return @[@"SBIconIconBadgeView", @"SBIconBadgeView", @"SBIconBadge"];
}

// Page control classes across the range; iOS 16/17 rootless most likely
// first. Same posture as badges: probe, guard, trace.
static NSArray<NSString *> *Sk1nPageControlClassNames(void) {
    return @[@"SBHomeScreenPageControl", @"SBPageControlView", @"SBRootPageControl"];
}

#pragma mark - Badge styling

static void Sk1nStyleBadge(UIView *badge, Sk1nSkin *skin) {
    CALayer *layer = badge.layer;
    CGFloat h = MAX(1.0, badge.bounds.size.height);
    switch (skin.era) {
        case Sk1nEraIOS1: {
            // iOS 1-6: bright red pill with a raised look — deep red body and
            // a white edge highlight the way the old bubbles had.
            layer.cornerRadius = h / 2.0;
            layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
            layer.borderWidth = 1.5;
            layer.backgroundColor = [UIColor colorWithRed:0.88 green:0.11 blue:0.10 alpha:1].CGColor;
            break;
        }
        case Sk1nEraIOS7: {
            // iOS 7: a flat, opaque red capsule (modern badges are translucent).
            layer.cornerRadius = h / 2.0;
            layer.borderWidth = 0;
            layer.backgroundColor = [UIColor colorWithRed:1 green:0.24 blue:0.23 alpha:1].CGColor;
            break;
        }
        case Sk1nEraGlass27: {
            // Liquid glass: translucent capsule with a hairline pane edge and
            // the skin's tint as the text colour behind it.
            layer.cornerRadius = h / 2.0;
            layer.borderWidth = 0.75;
            layer.borderColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
            UIColor *bg = [UIColor colorWithWhite:0.15 alpha:0.55];
            layer.backgroundColor = bg.CGColor;
            break;
        }
    }
    // The badge label: white for the legacy eras, tint-tinted white for glass.
    for (UIView *sub in badge.subviews) {
        UILabel *label = nil;
        if ([sub isKindOfClass:UILabel.class]) label = (UILabel *)sub;
        else if ([sub respondsToSelector:@selector(textLabel)])
            label = ((id (*)(id, SEL))objc_msgSend)(sub, @selector(textLabel));
        if ([label isKindOfClass:UILabel.class]) {
            switch (skin.era) {
                case Sk1nEraIOS1:
                case Sk1nEraIOS7: label.textColor = UIColor.whiteColor; break;
                case Sk1nEraGlass27: label.textColor = [UIColor colorWithWhite:1 alpha:0.95]; break;
            }
        }
    }
}

#pragma mark - Page dot styling

static void Sk1nStylePageControl(UIView *pc, Sk1nSkin *skin) {
    UIColor *tint = [skin colorNamed:@"tint" fallback:[UIColor clearColor]];
    // Walk the dot subviews (image views / small views) and tint them. The
    // stock colour comes back untouched if this view is not what we think.
    for (UIView *sub in pc.subviews) {
        if (sub.bounds.size.width < 2 || sub.bounds.size.height > 30) continue;
        switch (skin.era) {
            case Sk1nEraIOS1:
            case Sk1nEraIOS7:
                // Legacy: dark, solid dots.
                sub.alpha = 1.0;
                sub.tintColor = [UIColor colorWithWhite:0.22 alpha:0.95];
                break;
            case Sk1nEraGlass27:
                sub.alpha = 0.9;
                sub.tintColor = tint ?: [UIColor colorWithWhite:1 alpha:0.8];
                break;
        }
    }
}

#pragma mark - Install

NSUInteger Sk1nBadgeChromeInstall(Sk1nSkin *skin) {
    gSkin = skin;
    NSUInteger n = 0;
    for (NSString *clsName in Sk1nBadgeClassNames()) {
        // Layout is when both the bounds and the subview tree are valid;
        // styling here re-applies on every relayout, so a SpringBoard that
        // resets the layer can never fully win.
        IMP orig = Sk1nHookNamed(clsName, @selector(layoutSubviews), ^id(IMP or_) {
            return ^void(UIView *self_) {
                ((void (*)(id, SEL))or_)(self_, @selector(layoutSubviews));
                @try { Sk1nStyleBadge(self_, gSkin); } @catch (__unused id ex) {}
            };
        });
        if (orig) n++;
    }
    return n;
}

NSUInteger Sk1nPageDotsInstall(Sk1nSkin *skin) {
    gSkin = skin;
    NSUInteger n = 0;
    for (NSString *clsName in Sk1nPageControlClassNames()) {
        IMP orig = Sk1nHookNamed(clsName, @selector(layoutSubviews), ^id(IMP or_) {
            return ^void(UIView *self_) {
                ((void (*)(id, SEL))or_)(self_, @selector(layoutSubviews));
                @try { Sk1nStylePageControl(self_, gSkin); } @catch (__unused id ex) {}
            };
        });
        if (orig) n++;
    }
    return n;
}