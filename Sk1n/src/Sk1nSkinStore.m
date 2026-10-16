#import "Sk1nSkinStore.h"
#import "SPKRuntime.h"

@implementation Sk1nSkinStore

+ (instancetype)shared {
    static Sk1nSkinStore *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[Sk1nSkinStore alloc] init]; });
    return s;
}

- (NSArray<NSString *> *)searchRoots {
    return @[SPKRootedPath(@"/var/mobile/Library/Sk1n/Skins"), SPKRootedPath(@"/Library/Sk1n/Skins")];
}

- (Sk1nSkin *)skinWithID:(NSString *)skinID {
    if (skinID.length == 0 || [skinID containsString:@"/"] || [skinID containsString:@".."]) return nil;
    for (NSString *root in self.searchRoots) {
        NSString *dir = [root stringByAppendingPathComponent:skinID];
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSArray *errs = nil;
        Sk1nSkin *s = [Sk1nSkin skinAtDirectory:dir errors:&errs];
        if (s) return s;
        SPKTrace(@"skin_invalid", @{@"id": skinID, @"dir": dir, @"errors": [errs componentsJoinedByString:@"; "] ?: @""});
    }
    return nil;
}

- (NSArray<Sk1nSkin *> *)allSkins {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *root in self.searchRoots) {
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]) {
            if ([seen containsObject:name]) continue;
            Sk1nSkin *s = [self skinWithID:name];
            if (s) { [out addObject:s]; [seen addObject:name]; }
        }
    }
    return out;
}
@end
