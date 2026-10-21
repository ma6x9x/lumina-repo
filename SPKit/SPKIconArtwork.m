#import "SPKIconArtwork.h"
#import "SPKRuntime.h"
#import <objc/message.h>

// -----------------------------------------------------------------------------
// SPKit — real app artwork + themer artwork lookup.
//
// Extracted from SwiftPeek's SPIconPeek (the device-verified parts) so Sk1n's
// icon engine and SwiftPeek's inventory share one implementation instead of
// drifting apart. Read-only everywhere: no SBIconModel, no icon mutation.
// -----------------------------------------------------------------------------

static CGFloat SPKScreenScale(void) {
    CGFloat s = UIScreen.mainScreen.scale;
    return s > 0 ? s : 2;
}

UIImage *SPKRealIconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    static SEL sel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    });
    if (!sel || ![UIImage respondsToSelector:sel]) return nil;

    UIImage *(*send)(id, SEL, id, int, CGFloat) =
        (UIImage *(*)(id, SEL, id, int, CGFloat))objc_msgSend;
    @try {
        return send([UIImage class], sel, bundleID, 2, SPKScreenScale());
    } @catch (__unused id e) {
        return nil;
    }
}

NSArray<NSString *> *SPKIconThemeSearchPaths(void) {
    NSString *jb = SPKJailbreakRoot() ?: @"";
    NSArray *rel = @[
        @"/Library/Themes",
        @"/Library/Application Support/SnowBoard/Themes",
    ];
    NSMutableOrderedSet *out = [NSMutableOrderedSet set];
    for (NSString *r in rel) {
        if (jb.length) [out addObject:[jb stringByAppendingString:r]];
        [out addObject:[@"/var/jb" stringByAppendingString:r]];
        [out addObject:r];
    }
    return [out array];
}

UIImage *SPKThemeIconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0 ||
        [bundleID containsString:@"/"] || [bundleID containsString:@".."]) return nil;

    static NSDictionary<NSString *, NSString *> *suffixForScale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        suffixForScale = @{ @"3": @"@3x.png", @"2": @"@2x.png", @"1": @".png" };
    });
    NSString *exact = suffixForScale[@(SPKScreenScale()).stringValue] ?: @".png";
    // Exact match first, then degrade: same order a themer would see.
    NSArray *suffixes = [exact isEqualToString:@".png"]
        ? @[@".png"]
        : @[ exact, @".png" ];

    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in SPKIconThemeSearchPaths()) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        for (NSString *theme in [fm contentsOfDirectoryAtPath:root error:NULL]) {
            NSString *bundlesDir = [[root stringByAppendingPathComponent:theme]
                                    stringByAppendingPathComponent:@"IconBundles"];
            for (NSString *suffix in suffixes) {
                NSString *candidate = [bundlesDir stringByAppendingPathComponent:
                                       [bundleID stringByAppendingString:suffix]];
                BOOL exists = NO;
                if ([fm fileExistsAtPath:candidate isDirectory:&exists] && !exists) {
                    UIImage *img = [UIImage imageWithContentsOfFile:candidate];
                    if (img && img.size.width >= 1) return img;
                }
            }
        }
    }
    return nil;
}