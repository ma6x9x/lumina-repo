#import "SPIconPeek.h"
#import "SPRenderPeek.h"
#import "SPPrefs.h"
#import "SPKIconArtwork.h"
#import <objc/runtime.h>
#import <objc/message.h>

// -----------------------------------------------------------------------------
// SwiftPeek M4 — icon inventory (read-only, SpringBoard, opt-in)
// -----------------------------------------------------------------------------

BOOL SPIconPeekAvailable(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:@"com.apple.springboard"]) return NO;
    if (!SPPrefBool(@"enabled", NO)) return NO;
    if (!SPPrefBool(@"targetSpringBoard", NO)) return NO;
    return SPPrefBool(@"iconInventory", NO);
}

NSArray<NSString *> *SPIconThemeSearchPaths(void) {
    // Delegates to SPKit: Sk1n's icon engine resolves the same paths, so the
    // two tweaks cannot drift apart on where a themer's art lives.
    return SPKIconThemeSearchPaths();
}

/// SnowBoard / Anemone bundled artwork: `<theme>/IconBundles/<bundleid>.png`
/// (and the @2x/@3x variants), first hit wins, same as the runtime order a
/// themer would see. The search paths come from SPKit; only the inventory's
/// need for a path (not a decoded image) keeps this walk local.
static NSString *SPThemeOverridePathForBundle(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;

    for (NSString *root in SPIconThemeSearchPaths()) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        NSArray *themes = [fm contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *theme in themes) {
            NSString *bundlesDir = [[root stringByAppendingPathComponent:theme]
                                    stringByAppendingPathComponent:@"IconBundles"];
            for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png"]) {
                NSString *candidate = [bundlesDir stringByAppendingPathComponent:
                                       [bundleID stringByAppendingString:suffix]];
                if ([fm fileExistsAtPath:candidate]) return candidate;
            }
        }
    }
    return nil;
}

/// `+[UIImage _applicationIconImageForBundleIdentifier:format:scale:]` — the
/// device-verified extraction, now in SPKit (`SPKRealIconForBundleID`, format
/// 2, home-screen size, guarded typed cast). Sk1n's icon engine renders the
/// same call, so inventory and tweak see the same artwork.
static UIImage *SPIconImageForBundle(NSString *bundleID) {
    return SPKRealIconForBundleID(bundleID);
}

/// Installed applications via LSApplicationWorkspace. Read-only, and it does not
/// go anywhere near SBIconModel — which is what made 0.2.x dangerous.
static NSArray *SPInstalledApplicationProxies(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return @[];
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultSel]) return @[];

    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
    if (!workspace) return @[];

    SEL allSel = NSSelectorFromString(@"allInstalledApplications");
    if (![workspace respondsToSelector:allSel]) return @[];
    id result = ((id (*)(id, SEL))objc_msgSend)(workspace, allSel);
    return [result isKindOfClass:[NSArray class]] ? result : @[];
}

static NSString *SPProxyStringValue(id proxy, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!sel || ![proxy respondsToSelector:sel]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(proxy, sel);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/// Apple's own daemons and hidden system bundles are noise for a themer.
///
/// The first device inventory (iPhone13,1 / 17.3) returned 201 entries of which
/// 106 shared one identical near-white signature: AXRemoteViewService,
/// AskPermissionUI, CTCarrierSpaceAuth and a long tail of other UI-service
/// bundles. They have no icon, so UIKit hands back a generic placeholder, and
/// checking `applicationType == "Hidden"` alone does not catch them — they are
/// typed "System" and marked hidden through `appTags` instead.
static BOOL SPProxyIsUserVisible(id proxy) {
    NSString *type = SPProxyStringValue(proxy, @"applicationType") ?: @"";
    if ([type isEqualToString:@"Hidden"]) return NO;

    NSString *bundleID = SPProxyStringValue(proxy, @"applicationIdentifier") ?: @"";
    if (bundleID.length == 0) return NO;
    if ([bundleID hasPrefix:@"com.apple.datadetectors"]) return NO;
    if ([bundleID hasPrefix:@"com.apple.webapp"]) return NO;

    // The tag SpringBoard itself uses to keep a bundle off the Home Screen.
    SEL tagsSel = NSSelectorFromString(@"appTags");
    if ([proxy respondsToSelector:tagsSel]) {
        id tags = ((id (*)(id, SEL))objc_msgSend)(proxy, tagsSel);
        if ([tags isKindOfClass:[NSArray class]]) {
            for (id tag in (NSArray *)tags) {
                if (![tag isKindOfClass:[NSString class]]) continue;
                if ([tag caseInsensitiveCompare:@"hidden"] == NSOrderedSame) return NO;
                if ([tag caseInsensitiveCompare:@"SBInternalAppTag"] == NSOrderedSame) return NO;
            }
        }
    }

    // Bundles that still slip through with a placeholder icon are dropped
    // host-side by the signature check in tools/swiftpeek/icons.py, which is
    // the backstop for firmwares that tag things differently.
    return YES;
}

NSArray<NSDictionary *> *SPIconInventory(NSInteger maxIcons) {
    if (maxIcons <= 0) maxIcons = 200;
    NSMutableArray *out = [NSMutableArray array];

    @try {
        NSArray *proxies = SPInstalledApplicationProxies();
        for (id proxy in proxies) {
            if ((NSInteger)out.count >= maxIcons) break;
            @try {
                if (!SPProxyIsUserVisible(proxy)) continue;
                NSString *bundleID = SPProxyStringValue(proxy, @"applicationIdentifier");
                if (bundleID.length == 0) continue;

                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"bundle_id"] = bundleID;
                NSString *name = SPProxyStringValue(proxy, @"localizedName");
                if (name.length) entry[@"display_name"] = name;
                NSString *type = SPProxyStringValue(proxy, @"applicationType");
                if (type.length) entry[@"app_type"] = type;

                UIImage *icon = SPIconImageForBundle(bundleID);
                NSDictionary *sig = SPRenderSignatureForImage(icon);
                if (sig) entry[@"icon_signature"] = sig;

                NSString *override = SPThemeOverridePathForBundle(bundleID);
                if (override) {
                    entry[@"theme_override"] = override;
                    UIImage *themed = [UIImage imageWithContentsOfFile:override];
                    NSDictionary *themedSig = SPRenderSignatureForImage(themed);
                    if (themedSig) entry[@"theme_signature"] = themedSig;
                }

                [out addObject:entry];
            } @catch (__unused id e) {
                // One unreadable bundle must not end the sweep.
            }
        }
    } @catch (__unused id e) {
        return [out copy];
    }

    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(NSString *)a[@"bundle_id"] compare:(NSString *)b[@"bundle_id"]];
    }];
    return [out copy];
}
