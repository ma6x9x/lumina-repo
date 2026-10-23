#import "Sk1nIconEngine.h"
#import "Sk1nHook.h"
#import "Sk1nSkin.h"
#import "SPKIconArtwork.h"
#import "SPKRuntime.h"
#import <objc/message.h>

// Icon resolution is automatic, not a pref:
//
//   1. authored  <skin>/Icons/<bundle id>.png — the skin's own (legacy-era)
//                artwork, used whenever the skin ships an icon file;
//   2. real      UIKit's own render of the app's real icon (SPKRealIconForBundleID)
//                — covers every app the skin does not carry art for; iOS 1-6
//                gets a subtle gloss, iOS 7 and glass27 artwork untouched
//                (that art is already the era's own look);
//   3. themed    SnowBoard/Anemone IconBundles artwork as a last resort.
//
// Custom artwork is only ever consulted when the runtime has no file for the
// app — the engine never draws its own icons.
// The bundled `<skin>/Icons` set is the legacy flavour of each era.

static Sk1nSkin *gSkin;
static NSCache<NSString *, UIImage *> *gCache;

#pragma mark - Authored skin artwork

static NSString *Sk1nSafeBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    if ([bundleID containsString:@"/"] || [bundleID containsString:@".."]) return nil;
    return bundleID;
}

/// `<skin>/Icons/<bundleID>[@3x|@2x|].png`, matching the screen scale.
static UIImage *Sk1nAuthoredIcon(Sk1nSkin *skin, NSString *bundleID) {
    bundleID = Sk1nSafeBundleID(bundleID);
    if (!skin || !bundleID) return nil;
    NSString *base = [skin.iconsDirectory stringByAppendingPathComponent:bundleID];
    NSFileManager *fm = NSFileManager.defaultManager;
    CGFloat scale = UIScreen.mainScreen.scale;
    NSArray *cands =
        scale >= 3 ? @[@"@3x.png", @"@2x.png", @".png"] :
        scale >= 2 ? @[@"@2x.png", @".png"] :
        @[@".png"];
    for (NSString *suffix in cands) {
        NSString *path = [base stringByAppendingString:suffix];
        if (![fm fileExistsAtPath:path]) continue;
        UIImage *raw = [UIImage imageWithContentsOfFile:path];
        if (!raw || raw.size.width < 1) return nil;
        // Plain "<id>.png" is authored at 180px (@3x); declare the true scale
        // so the image does not render 3x too large.
        CGFloat s = [path hasSuffix:@"@3x.png"] ? 3 : [path hasSuffix:@"@2x.png"] ? 2 : 3;
        return raw.CGImage
            ? [UIImage imageWithCGImage:raw.CGImage scale:s orientation:UIImageOrientationUp]
            : raw;
    }
    return nil;
}

#pragma mark - Era chrome

/// A home-screen icon mask (22.4% corner radius, the iOS 13+ proportion)
/// inset by `inset` device pixels. Caller owns the path (release when done).
static CGPathRef Sk1nSquirclePath(CGSize size, CGFloat inset) {
    CGRect rect = CGRectInset(CGRectMake(0, 0, size.width, size.height), inset, inset);
    CGFloat r = rect.size.width * 0.224;
    return CGPathCreateWithRoundedRect(rect, r, r, NULL);
}

/// Renders at the icon's device-pixel size in a scale-1 bitmap (so the
/// fetched icon's scale is not applied twice), then tags the result back
/// with the icon's scale. Returns `base` unchanged if the render fails.
static UIImage *Sk1nRenderChrome(UIImage *base, void (^draw)(CGRect px, CGContextRef cg))
{
    CGSize pxSize = CGSizeMake(base.size.width * base.scale, base.size.height * base.scale);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r =
        [[UIGraphicsImageRenderer alloc] initWithSize:pxSize format:fmt];
    UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef cg = ctx.CGContext;
        CGContextSetInterpolationQuality(cg, kCGInterpolationHigh);
        draw(CGRectMake(0, 0, pxSize.width, pxSize.height), cg);
    }];
    if (!out || out.size.width < 1) return base;
    return out.CGImage
        ? [UIImage imageWithCGImage:out.CGImage scale:base.scale orientation:UIImageOrientationUp]
        : base;
}

/// iOS 1-6 chrome over the real artwork: the base is clipped to the era's
/// squircle, a white sheen falls across the top half, and a hairline
/// highlight runs the inner edge — a lit glass tile, no shipped artwork.
static UIImage *Sk1nChromeIOS1(UIImage *base) {
    return Sk1nRenderChrome(base, ^(CGRect px, CGContextRef cg) {
        CGPathRef clip = Sk1nSquirclePath(px.size, 0);
        CGContextAddPath(cg, clip);
        CGPathRelease(clip);
        CGContextClip(cg);
        [base drawInRect:px];

        // Sheen: white gradient, strongest at the crown, gone by 58%.
        CGContextSaveGState(cg);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[] = { 1.0, 1.0, 1.0, 0.22,  1.0, 1.0, 1.0, 0.12,  1.0, 1.0, 1.0, 0.0 };
        CGFloat locs[]  = { 0.0, 0.30, 0.45 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
        if (g) {
            CGContextDrawLinearGradient(cg, g,
                CGPointMake(CGRectGetMidX(px), 0),
                CGPointMake(CGRectGetMidX(px), CGRectGetMinY(px) + 0.58 * px.size.height), 0);
            CGGradientRelease(g);
        }
        CGColorSpaceRelease(cs);
        CGContextRestoreGState(cg);

        // Hairline highlight along the inner edge, the way the old tiles had.
        CGContextSaveGState(cg);
        CGPathRef inner = Sk1nSquirclePath(px.size, 2);
        CGContextAddPath(cg, inner);
        CGPathRelease(inner);
        CGContextSetStrokeColorWithColor(cg, [UIColor colorWithWhite:1 alpha:0.14].CGColor);
        CGContextSetLineWidth(cg, 2.0);
        CGContextStrokePath(cg);
        CGContextRestoreGState(cg);
    });
}

/// iOS 7 chrome: none. iOS 7 was flat and the real artwork already is.
static UIImage *Sk1nChromeIOS7(UIImage *base) {
    return base;
}

static UIImage *Sk1nChromedIcon(UIImage *base, Sk1nEra era) {
    if (!base) return nil;
    @try {
        switch (era) {
            case Sk1nEraIOS1:    return Sk1nChromeIOS1(base);
            case Sk1nEraIOS7:    return Sk1nChromeIOS7(base);
            case Sk1nEraGlass27: return base;  // real artwork is this era's own look - no chrome
        }
    } @catch (__unused id ex) {}
    return base;
}

#pragma mark - Runtime artwork for a bundle id

static UIImage *Sk1nRuntimeIcon(Sk1nSkin *skin, NSString *bundleID) {
    UIImage *real = SPKRealIconForBundleID(bundleID);
    UIImage *chromed = Sk1nChromedIcon(real, skin.era);
    if (chromed) return chromed;
    // No real artwork (sideloaded stubs, hidden bundles) — fall back to a
    // themer theme's IconBundles or the skin's own authored set.
    UIImage *themed = SPKThemeIconForBundleID(bundleID);
    if (themed) return Sk1nChromedIcon(themed, skin.era);
    return Sk1nAuthoredIcon(skin, bundleID);
}

UIImage *Sk1nIconForBundleID(Sk1nSkin *skin, NSString *bundleID) {
    bundleID = Sk1nSafeBundleID(bundleID);
    if (!skin || !bundleID) return nil;
    if (!gCache) gCache = [[NSCache alloc] init];
    NSString *key = [skin.skinID stringByAppendingString:bundleID];
    UIImage *hit = [gCache objectForKey:key];
    if (hit) return hit;

    // A skin-authored icon file always wins; real artwork only covers apps
    // the skin does not carry an icon for.
    UIImage *img = Sk1nAuthoredIcon(skin, bundleID);
    if (!img) img = Sk1nRuntimeIcon(skin, bundleID);
    if (!img) return nil;
    [gCache setObject:img forKey:key];
    return img;
}

// Bundle id for an SBIconImageView, via runtime only (private headers absent).
static NSString *Sk1nBundleIDForIconView(id view) {
    @try {
        if (![view respondsToSelector:@selector(icon)]) return nil;
        id icon = ((id (*)(id, SEL))objc_msgSend)(view, @selector(icon));
        if (!icon) return nil;
        for (NSString *selName in @[@"applicationBundleID", @"leafIdentifier"]) {
            SEL sel = NSSelectorFromString(selName);
            if ([icon respondsToSelector:sel]) {
                id v = ((id (*)(id, SEL))objc_msgSend)(icon, sel);
                if ([v isKindOfClass:NSString.class] && [v length]) return v;
            }
        }
    } @catch (__unused id ex) {}
    return nil;
}

NSUInteger Sk1nIconEngineInstall(Sk1nSkin *skin) {
    gSkin = skin;
    gCache = [[NSCache alloc] init];
    NSUInteger n = 0;

    // iOS 16/17 rootless: SBIconImageView (SpringBoardHome) still exposes
    // -contentsImage and -displayedImage; both are tried and the result traced,
    // because which one the compositor reads has NOT been verified on device
    // from CI. Anything missing simply does not install.
    for (NSString *selName in @[@"contentsImage", @"displayedImage"]) {
        SEL sel = NSSelectorFromString(selName);
        IMP orig = Sk1nHookNamed(@"SBIconImageView", sel, ^id(IMP orig) {
            return ^UIImage *(id self_) {
                UIImage *stock = ((UIImage *(*)(id, SEL))orig)(self_, sel);
                @try {
                    NSString *bid = Sk1nBundleIDForIconView(self_);
                    if (bid) {
                        UIImage *o = Sk1nIconForBundleID(gSkin, bid);
                        if (o) return o;
                    }
                } @catch (__unused id ex) {}
                return stock;
            };
        });
        if (orig) n++;
    }
    return n;
}

void Sk1nIconEngineUnload(void) {
    gSkin = nil;
    gCache = nil;
}