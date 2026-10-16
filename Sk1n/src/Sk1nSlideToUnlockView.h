#import <UIKit/UIKit.h>
#import "Sk1nSkin.h"

NS_ASSUME_NONNULL_BEGIN

/// Slide-to-unlock control, skinnable per era. Pure UIKit, no private API, so it
/// is fully exercised by CI-compilable code; only the *lock screen wiring*
/// (Sk1nLockScreen) is unverified on device.
///
///  ios1    classic glossy dark track, silver glossy thumb, shimmering text
///  ios7    flat capsule track and thumb, subtle shimmer
///  glass27 glass capsule track + glass thumb (UIGlassEffect on iOS 26+, system
///          material blur below), travelling specular shimmer, interactive feel
///          (thumb swells and springs while held)
@interface Sk1nSlideToUnlockView : UIView

/// `config` is the Skin.plist `slider` dictionary (text, textColor, thumbColor,
/// trackColor, shimmer). Unknown/missing keys fall back to era defaults.
- (instancetype)initWithFrame:(CGRect)frame style:(Sk1nEra)style config:(nullable NSDictionary *)config;

@property (nonatomic, readonly) Sk1nEra style;
@property (nonatomic, copy, nullable) void (^onUnlock)(void);
/// 0...1, updated live while dragging.
@property (nonatomic, readonly) CGFloat progress;
/// Fraction of the track the thumb must pass to count as unlocked.
@property (nonatomic) CGFloat completionThreshold; // default 0.88
/// Spring the thumb back to the start and re-arm.
- (void)reset;
/// Recommended size for a given era at a given container width.
+ (CGSize)preferredSizeForStyle:(Sk1nEra)style containerWidth:(CGFloat)w;

@end

NS_ASSUME_NONNULL_END
