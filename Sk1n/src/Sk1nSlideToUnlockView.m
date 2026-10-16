#import "Sk1nSlideToUnlockView.h"

static const CGFloat kInset = 3.0;

@implementation Sk1nSlideToUnlockView {
    NSDictionary *_config;
    UIView *_track;
    UIView *_trackFill;           // gradient or effect host
    UILabel *_label;
    CAGradientLayer *_labelMask;
    CAGradientLayer *_trackGloss;
    CAGradientLayer *_glassShimmer;
    UIView *_thumb;
    CAGradientLayer *_thumbGrad;
    CAGradientLayer *_thumbGloss;
    CAShapeLayer *_arrow;
    UIVisualEffectView *_trackGlass;
    UIVisualEffectView *_thumbGlass;
    CGFloat _thumbX;
    BOOL _completed;
    BOOL _shimmer;
    UIPanGestureRecognizer *_pan;
}

+ (CGSize)preferredSizeForStyle:(Sk1nEra)style containerWidth:(CGFloat)w {
    CGFloat width = MIN(MAX(w - 64, 220), 340);
    return CGSizeMake(width, style == Sk1nEraIOS1 ? 56 : 60);
}

- (instancetype)initWithFrame:(CGRect)frame style:(Sk1nEra)style config:(NSDictionary *)config {
    if ((self = [super initWithFrame:frame])) {
        _style = style;
        _config = [config copy] ?: @{};
        _completionThreshold = 0.88;
        id sh = _config[@"shimmer"];
        _shimmer = sh ? [sh boolValue] : YES;
        if (UIAccessibilityIsReduceMotionEnabled()) _shimmer = NO;
        [self build];
    }
    return self;
}

- (UIColor *)cfgColor:(NSString *)key fallback:(UIColor *)fb {
    return Sk1nColorFromHex(_config[key]) ?: fb;
}

- (UIVisualEffect *)glassEffect {
    // iOS 26+: real UIGlassEffect, found at runtime so the dylib still builds
    // and loads against older SDKs. Below that: system material blur.
    Class g = NSClassFromString(@"UIGlassEffect");
    if (g) {
        @try {
            id eff = [[g alloc] init];
            if ([eff isKindOfClass:UIVisualEffect.class]) {
                @try { [eff setValue:@YES forKey:@"interactive"]; } @catch (__unused id ex) {}
                return eff;
            }
        } @catch (__unused id ex) {}
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
}

- (void)build {
    self.clipsToBounds = NO;
    _track = [[UIView alloc] init];
    _track.userInteractionEnabled = NO;
    _track.clipsToBounds = YES;
    [self addSubview:_track];

    _label = [[UILabel alloc] init];
    _label.text = _config[@"text"] ?: @"slide to unlock";
    _label.textAlignment = NSTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    _thumb = [[UIView alloc] init];
    [self addSubview:_thumb];

    switch (_style) {
        case Sk1nEraIOS1: {
            CAGradientLayer *g = [CAGradientLayer layer];
            g.colors = @[(id)[UIColor colorWithWhite:0.10 alpha:1].CGColor,
                         (id)[UIColor colorWithWhite:0.30 alpha:1].CGColor];
            [_track.layer addSublayer:g]; _trackFill = nil; _trackGloss = g;
            _track.layer.borderWidth = 1;
            _track.layer.borderColor = [self cfgColor:@"trackColor" fallback:[UIColor colorWithWhite:0.75 alpha:0.6]].CGColor;
            _label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightRegular];
            _label.textColor = [self cfgColor:@"textColor" fallback:UIColor.whiteColor];

            UIColor *tc = [self cfgColor:@"thumbColor" fallback:[UIColor colorWithWhite:0.86 alpha:1]];
            _thumbGrad = [CAGradientLayer layer];
            _thumbGrad.colors = @[(id)UIColor.whiteColor.CGColor, (id)tc.CGColor,
                                  (id)[UIColor colorWithWhite:0.55 alpha:1].CGColor];
            _thumbGrad.locations = @[@0, @0.5, @1];
            [_thumb.layer addSublayer:_thumbGrad];
            _thumbGloss = [CAGradientLayer layer];
            _thumbGloss.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.9].CGColor,
                                   (id)[UIColor colorWithWhite:1 alpha:0.15].CGColor];
            [_thumb.layer addSublayer:_thumbGloss];
            _thumb.layer.borderWidth = 0.5;
            _thumb.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:0.8].CGColor;
            _thumb.layer.shadowColor = UIColor.blackColor.CGColor;
            _thumb.layer.shadowOpacity = 0.5; _thumb.layer.shadowRadius = 2;
            _thumb.layer.shadowOffset = CGSizeMake(0, 1);
            break;
        }
        case Sk1nEraIOS7: {
            _track.backgroundColor = [self cfgColor:@"trackColor" fallback:[UIColor colorWithWhite:1 alpha:0.18]];
            _label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightLight];
            _label.textColor = [self cfgColor:@"textColor" fallback:UIColor.whiteColor];
            _thumb.backgroundColor = [self cfgColor:@"thumbColor" fallback:UIColor.whiteColor];
            break;
        }
        case Sk1nEraGlass27: {
            _trackGlass = [[UIVisualEffectView alloc] initWithEffect:[self glassEffect]];
            [_track addSubview:_trackGlass];
            _track.layer.borderWidth = 0.75;
            _track.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
            _glassShimmer = [CAGradientLayer layer];
            _glassShimmer.startPoint = CGPointMake(0, 0.5); _glassShimmer.endPoint = CGPointMake(1, 0.5);
            _glassShimmer.colors = @[(id)[UIColor colorWithWhite:1 alpha:0].CGColor,
                                     (id)[UIColor colorWithWhite:1 alpha:0.28].CGColor,
                                     (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
            _glassShimmer.locations = @[@(-0.4), @(-0.2), @0];
            [_track.layer addSublayer:_glassShimmer];
            _label.font = [UIFont systemFontOfSize:21 weight:UIFontWeightMedium];
            _label.textColor = [self cfgColor:@"textColor" fallback:[UIColor colorWithWhite:1 alpha:0.9]];

            _thumbGlass = [[UIVisualEffectView alloc] initWithEffect:[self glassEffect]];
            _thumbGlass.userInteractionEnabled = NO;
            [_thumb addSubview:_thumbGlass];
            _thumb.layer.borderWidth = 0.75;
            _thumb.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
            _thumb.clipsToBounds = YES;
            UIColor *tint = Sk1nColorFromHex(_config[@"thumbColor"]);
            if (tint) _thumb.backgroundColor = [tint colorWithAlphaComponent:0.25];
            break;
        }
    }

    // arrow glyph on the thumb
    _arrow = [CAShapeLayer layer];
    _arrow.fillColor = nil;
    _arrow.lineWidth = _style == Sk1nEraIOS1 ? 4 : 3;
    _arrow.lineCap = kCALineCapRound; _arrow.lineJoin = kCALineJoinRound;
    _arrow.strokeColor = (_style == Sk1nEraIOS1 ? [UIColor colorWithWhite:0.25 alpha:1]
                          : _style == Sk1nEraIOS7 ? [UIColor colorWithWhite:0.45 alpha:1]
                          : [UIColor colorWithWhite:1 alpha:0.95]).CGColor;
    [_thumb.layer addSublayer:_arrow];

    _labelMask = [CAGradientLayer layer];
    _labelMask.startPoint = CGPointMake(0, 0.5); _labelMask.endPoint = CGPointMake(1, 0.5);
    UIColor *dim = [UIColor colorWithWhite:1 alpha:_style == Sk1nEraIOS7 ? 0.55 : 0.35];
    _labelMask.colors = @[(id)dim.CGColor, (id)UIColor.whiteColor.CGColor, (id)dim.CGColor];
    _labelMask.locations = _shimmer ? @[@(-0.3), @(-0.15), @0] : @[@0, @0.5, @1];
    if (!_shimmer) _labelMask.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor];
    _label.layer.mask = _labelMask;

    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:_pan];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = _label.text;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    self.accessibilityHint = @"Swipe up or down to unlock";
}

- (CGFloat)thumbWidth { return _style == Sk1nEraIOS1 ? 76 : self.bounds.size.height - 2 * kInset + 14; }
- (CGFloat)maxX { return MAX(0, self.bounds.size.width - [self thumbWidth] - kInset * 2); }
- (CGFloat)progress { CGFloat m = [self maxX]; return m > 0 ? MIN(1, MAX(0, _thumbX / m)) : 0; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _track.frame = b;
    _track.layer.cornerRadius = _style == Sk1nEraIOS1 ? 10 : b.size.height / 2;
    _trackGloss.frame = _track.bounds; _trackGlass.frame = _track.bounds;
    _glassShimmer.frame = _track.bounds;

    CGFloat tw = [self thumbWidth], th = b.size.height - 2 * kInset;
    CGFloat cr = _style == Sk1nEraIOS1 ? 8 : th / 2;
    _thumb.transform = CGAffineTransformIdentity;
    _thumb.frame = CGRectMake(kInset + _thumbX, kInset, tw, th);
    _thumb.layer.cornerRadius = cr;
    _thumbGrad.frame = _thumb.bounds; _thumbGrad.cornerRadius = cr;
    _thumbGloss.frame = CGRectMake(0, 0, tw, th * 0.5);
    _thumbGloss.cornerRadius = cr;
    _thumbGlass.frame = _thumb.bounds;

    UIBezierPath *p = [UIBezierPath bezierPath];
    CGFloat cx = tw / 2, cy = th / 2;
    [p moveToPoint:CGPointMake(cx - 5, cy - 8)];
    [p addLineToPoint:CGPointMake(cx + 5, cy)];
    [p addLineToPoint:CGPointMake(cx - 5, cy + 8)];
    _arrow.path = p.CGPath;

    CGFloat lx = kInset + tw + 6;
    _label.frame = CGRectMake(lx, 0, b.size.width - lx - kInset - 8, b.size.height);
    _labelMask.frame = _label.bounds;
    [self applyProgress];
}

- (void)applyProgress {
    CGFloat p = self.progress;
    _label.alpha = MAX(0, 1 - p * 1.6);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startShimmer]; else [self stopShimmer];
}

- (void)startShimmer {
    if (!_shimmer) return;
    [self stopShimmer];
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"locations"];
    a.fromValue = @[@(-0.3), @(-0.15), @0];
    a.toValue = @[@1, @1.15, @1.3];
    a.duration = _style == Sk1nEraGlass27 ? 2.6 : 2.0;
    a.repeatCount = HUGE_VALF;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_labelMask addAnimation:a forKey:@"sk1n.shimmer"];
    if (_glassShimmer) {
        CABasicAnimation *b = [a copy];
        b.fromValue = @[@(-0.4), @(-0.2), @0];
        b.toValue = @[@1, @1.2, @1.4];
        b.duration = 3.2;
        [_glassShimmer addAnimation:b forKey:@"sk1n.glass"];
    }
}

- (void)stopShimmer {
    [_labelMask removeAnimationForKey:@"sk1n.shimmer"];
    [_glassShimmer removeAnimationForKey:@"sk1n.glass"];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (_completed) return;
    CGFloat maxX = [self maxX];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint loc = [g locationInView:self];
            if (loc.x > kInset + [self thumbWidth] + 24) { g.enabled = NO; g.enabled = YES; return; } // must grab the thumb
            if (_style == Sk1nEraGlass27) {
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8
                                    options:UIViewAnimationOptionAllowUserInteraction animations:^{
                    self->_thumb.transform = CGAffineTransformMakeScale(1.12, 1.12);
                } completion:nil];
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat x = _thumbX + [g translationInView:self].x;
            [g setTranslation:CGPointZero inView:self];
            _thumbX = MIN(MAX(0, x), maxX);
            _thumb.center = CGPointMake(kInset + _thumbX + _thumb.bounds.size.width / 2, _thumb.center.y);
            [self applyProgress];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (g.state == UIGestureRecognizerStateEnded && self.progress >= _completionThreshold) {
                [self complete];
            } else {
                [self springBack];
            }
            break;
        }
        default: break;
    }
}

- (void)complete {
    _completed = YES;
    _thumbX = [self maxX];
    [UIView animateWithDuration:0.12 animations:^{
        self->_thumb.center = CGPointMake(kInset + self->_thumbX + self->_thumb.bounds.size.width / 2, self->_thumb.center.y);
        self->_thumb.transform = CGAffineTransformIdentity;
        self->_label.alpha = 0;
    }];
    void (^cb)(void) = self.onUnlock;
    if (cb) cb();
}

- (void)springBack {
    _thumbX = 0;
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_thumb.center = CGPointMake(kInset + self->_thumb.bounds.size.width / 2, self->_thumb.center.y);
        self->_thumb.transform = CGAffineTransformIdentity;
        self->_label.alpha = 1;
    } completion:nil];
}

- (void)reset {
    _completed = NO;
    [self springBack];
}

// VoiceOver: increment/decrement unlocks.
- (void)accessibilityIncrement { if (!_completed) [self complete]; }
- (void)accessibilityDecrement { if (!_completed) [self complete]; }

@end
