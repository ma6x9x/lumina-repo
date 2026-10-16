#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Finds skins on disk. Search order (first valid hit wins per id):
///   1. <jbroot>/var/mobile/Library/Sk1n/Skins   (user-installed)
///   2. <jbroot>/Library/Sk1n/Skins              (shipped with the package)
@interface Sk1nSkinStore : NSObject
+ (instancetype)shared;
@property (nonatomic, copy, readonly) NSArray<NSString *> *searchRoots;
- (nullable Sk1nSkin *)skinWithID:(NSString *)skinID;
- (NSArray<Sk1nSkin *> *)allSkins;
@end

NS_ASSUME_NONNULL_END
