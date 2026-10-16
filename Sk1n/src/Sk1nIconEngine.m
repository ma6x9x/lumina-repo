#import "Sk1nIconEngine.h"
#import "Sk1nHook.h"
#import "SPKRuntime.h"
#import <objc/message.h>

static Sk1nSkin *gSkin;
static NSCache<NSString *, UIImage *> *gCache;

UIImage *Sk1nIconForBundleID(Sk1nSkin *skin, NSString *bundleID) {
    if (!skin || bundleID.length == 0 || [bundleID containsString:@"/"] || [bundleID containsString:@".."]) return nil;
    if (!gCache) gCache = [[NSCache alloc] init];
    NSString *key = [skin.skinID stringByAppendingFormat:@"|%@", bundleID];
    UIImage *hit = [gCache objectForKey:key];
    if (hit) return hit;
    NSString *base = [skin.iconsDirectory stringByAppendingPathComponent:bundleID];
    NSString *path = nil;
    CGFloat scale = UIScreen.mainScreen.scale;
    NSArray *cands = scale >= 3 ? @[@"@3x.png", @"@2x.png", @".png"] : @[@"@2x.png", @".png"];
    for (NSString *suffix in cands) {
        NSString *p = [base stringByAppendingString:suffix];
        if ([NSFileManager.defaultManager fileExistsAtPath:p]) { path = p; break; }
    }
    if (!path) return nil;
    UIImage *raw = [UIImage imageWithContentsOfFile:path];
    if (!raw || raw.size.width < 1) return nil;
    // Plain "<id>.png" is authored at 180px (@3x); declare the true scale so the
    // image does not render 3x too large.
    CGFloat s = [path hasSuffix:@"@3x.png"] ? 3 : [path hasSuffix:@"@2x.png"] ? 2 : 3;
    UIImage *img = raw.CGImage ? [UIImage imageWithCGImage:raw.CGImage scale:s orientation:UIImageOrientationUp] : raw;
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
