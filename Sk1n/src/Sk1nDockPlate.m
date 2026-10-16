#import "Sk1nDockPlate.h"
#import "Sk1nHook.h"
#import "SPKRuntime.h"
#import <objc/message.h>

static const NSInteger kPlateTag = 0x5E1F;
static Sk1nSkin *gDockSkin;

@implementation Sk1nDockPlate {
    CAGradientLayer *_grad;
    CAGradientLayer *_gloss;
    UIVisualEffectView *_blur;
}

- (instancetype)initWithSkin:(Sk1nSkin *)skin {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.tag = kPlateTag;
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIColor *top = [skin colorNamed:@"dockTop" fallback:[UIColor colorWithWhite:0.2 alpha:0.9]];
        UIColor *bot = [skin colorNamed:@"dockBottom" fallback:[UIColor colorWithWhite:0.05 alpha:0.9]];
        switch (skin.era) {
            case Sk1nEraIOS1: {
                // Glossy "shelf": dark gradient plus a hard-edged highlight on the upper half.
                _grad = [CAGradientLayer layer];
                _grad.colors = @[(id)top.CGColor, (id)bot.CGColor];
                [self.layer addSublayer:_grad];
                _gloss = [CAGradientLayer layer];
                _gloss.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.28].CGColor,
                                  (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor];
                _gloss.locations = @[@0, @1];
                [self.layer addSublayer:_gloss];
                break;
            }
            case Sk1nEraIOS7: {
                self.backgroundColor = top; // flat, single colour, no gradient
                break;
            }
            case Sk1nEraGlass27: {
                UIBlurEffect *eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
                _blur = [[UIVisualEffectView alloc] initWithEffect:eff];
                _blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self addSubview:_blur];
                self.layer.borderWidth = 0.75;
                self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
                self.layer.cornerRadius = 30;
                self.clipsToBounds = YES;
                break;
            }
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _grad.frame = self.bounds;
    _gloss.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height * 0.5);
    _blur.frame = self.bounds;
}
@end

BOOL Sk1nDockPlateInstall(Sk1nSkin *skin) {
    gDockSkin = skin;
    SEL sel = @selector(layoutSubviews);
    IMP orig = Sk1nHookNamed(@"SBDockView", sel, ^id(IMP orig) {
        return ^void(UIView *self_) {
            ((void (*)(id, SEL))orig)(self_, sel);
            @try {
                UIView *plate = [self_ viewWithTag:kPlateTag];
                if (!plate) {
                    plate = [[Sk1nDockPlate alloc] initWithSkin:gDockSkin];
                    UIView *stockBG = nil;
                    if ([self_ respondsToSelector:NSSelectorFromString(@"backgroundView")])
                        stockBG = ((id (*)(id, SEL))objc_msgSend)(self_, NSSelectorFromString(@"backgroundView"));
                    if ([stockBG isKindOfClass:UIView.class] && stockBG.superview == self_) {
                        stockBG.hidden = YES;
                        [self_ insertSubview:plate aboveSubview:stockBG];
                    } else {
                        [self_ insertSubview:plate atIndex:0];
                    }
                }
                plate.frame = self_.bounds;
            } @catch (__unused id ex) {}
        };
    });
    return orig != NULL;
}
