#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, Sk1nEra) {
    Sk1nEraIOS1 = 0,    // iOS 1-6, skeuomorphic
    Sk1nEraIOS7,        // flat
    Sk1nEraGlass27,     // Liquid Glass
};

/// "#RRGGBB" or "#RRGGBBAA" -> UIColor. nil on anything malformed.
UIColor *_Nullable Sk1nColorFromHex(NSString *_Nullable hex);
NSString *_Nullable Sk1nEraName(Sk1nEra era);
BOOL Sk1nEraFromName(NSString *_Nullable name, Sk1nEra *_Nullable out);

/// A theme bundle: <Skins>/<id>/Skin.plist + Icons/ + optional assets.
/// Validation is strict; an invalid skin is never applied (fail closed).
@interface Sk1nSkin : NSObject
@property (nonatomic, copy, readonly) NSString *skinID;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) Sk1nEra era;
@property (nonatomic, copy, readonly) NSString *directory;
@property (nonatomic, copy, readonly) NSDictionary *colors;   // name -> hex string
@property (nonatomic, copy, readonly) NSDictionary *fonts;    // name -> font spec (parsed, not yet applied)
@property (nonatomic, copy, readonly) NSString *iconsDirectory; // absolute
@property (nonatomic, copy, readonly) NSDictionary *lockscreen;
@property (nonatomic, copy, readonly) NSDictionary *slider;   // per-skin slider config
@property (nonatomic, copy, readonly) NSDictionary *sounds;   // name -> file (parsed, not yet played)

/// nil + *errors filled when the bundle is invalid.
+ (nullable instancetype)skinAtDirectory:(NSString *)dir errors:(NSArray<NSString *> *_Nullable *_Nullable)errors;
/// Pure validation of a decoded Skin.plist (also used by tools/validate-skins.py's twin).
+ (NSArray<NSString *> *)validationErrorsForPlist:(NSDictionary *)plist directoryName:(NSString *)dirName;

- (UIColor *)colorNamed:(NSString *)name fallback:(UIColor *)fallback;
@end

NS_ASSUME_NONNULL_END
