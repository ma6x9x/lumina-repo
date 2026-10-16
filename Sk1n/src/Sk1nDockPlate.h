#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Era-styled backdrop for the dock, inserted by a guarded SBDockView hook.
@interface Sk1nDockPlate : UIView
- (instancetype)initWithSkin:(Sk1nSkin *)skin;
@end

/// Returns YES if the dock hook installed.
BOOL Sk1nDockPlateInstall(Sk1nSkin *skin);

NS_ASSUME_NONNULL_END
