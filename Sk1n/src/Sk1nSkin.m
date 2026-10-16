#import "Sk1nSkin.h"

UIColor *Sk1nColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:NSString.class]) return nil;
    NSString *h = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
    if (h.length != 6 && h.length != 8) return nil;
    unsigned long long v = 0;
    NSScanner *sc = [NSScanner scannerWithString:h];
    if (![sc scanHexLongLong:&v] || !sc.isAtEnd) return nil;
    CGFloat r, g, b, a = 1;
    if (h.length == 8) {
        r = ((v >> 24) & 0xFF) / 255.0; g = ((v >> 16) & 0xFF) / 255.0;
        b = ((v >> 8) & 0xFF) / 255.0;  a = (v & 0xFF) / 255.0;
    } else {
        r = ((v >> 16) & 0xFF) / 255.0; g = ((v >> 8) & 0xFF) / 255.0; b = (v & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

NSString *Sk1nEraName(Sk1nEra era) {
    switch (era) {
        case Sk1nEraIOS1: return @"ios1";
        case Sk1nEraIOS7: return @"ios7";
        case Sk1nEraGlass27: return @"glass27";
    }
    return nil;
}

BOOL Sk1nEraFromName(NSString *name, Sk1nEra *out) {
    if (![name isKindOfClass:NSString.class]) return NO;
    NSDictionary *map = @{@"ios1": @(Sk1nEraIOS1), @"ios7": @(Sk1nEraIOS7), @"glass27": @(Sk1nEraGlass27)};
    NSNumber *n = map[name];
    if (!n) return NO;
    if (out) *out = (Sk1nEra)n.integerValue;
    return YES;
}

static BOOL Sk1nSafeComponent(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0 || s.length > 64) return NO;
    if ([s containsString:@"/"] || [s containsString:@".."] || [s hasPrefix:@"."]) return NO;
    return YES;
}

@implementation Sk1nSkin

+ (NSArray<NSString *> *)validationErrorsForPlist:(NSDictionary *)plist directoryName:(NSString *)dirName {
    NSMutableArray *e = [NSMutableArray array];
    if (![plist isKindOfClass:NSDictionary.class]) return @[@"Skin.plist is not a dictionary"];
    NSString *sid = plist[@"id"];
    if (!Sk1nSafeComponent(sid)) [e addObject:@"id missing or unsafe"];
    else if (![sid isEqualToString:dirName]) [e addObject:@"id does not match directory name"];
    if (![plist[@"name"] isKindOfClass:NSString.class] || [plist[@"name"] length] == 0) [e addObject:@"name missing"];
    if (!Sk1nEraFromName(plist[@"era"], NULL)) [e addObject:@"era must be ios1 | ios7 | glass27"];

    id colors = plist[@"colors"];
    if (![colors isKindOfClass:NSDictionary.class]) [e addObject:@"colors missing"];
    else for (NSString *k in colors) if (!Sk1nColorFromHex(colors[k])) [e addObject:[NSString stringWithFormat:@"colors.%@ is not #RRGGBB[AA]", k]];

    id fonts = plist[@"fonts"];
    if (fonts && ![fonts isKindOfClass:NSDictionary.class]) [e addObject:@"fonts must be a dictionary"];

    id icons = plist[@"iconsDirectory"];
    if (icons && !Sk1nSafeComponent(icons)) [e addObject:@"iconsDirectory unsafe"];

    id ls = plist[@"lockscreen"];
    if (ls && ![ls isKindOfClass:NSDictionary.class]) [e addObject:@"lockscreen must be a dictionary"];

    id sl = plist[@"slider"];
    if (!sl) [e addObject:@"slider config missing"];
    else if (![sl isKindOfClass:NSDictionary.class]) [e addObject:@"slider must be a dictionary"];
    else {
        id st = sl[@"style"];
        if (st && !Sk1nEraFromName(st, NULL)) [e addObject:@"slider.style must be ios1 | ios7 | glass27"];
        if (!sl[@"text"] || ![sl[@"text"] isKindOfClass:NSString.class]) [e addObject:@"slider.text missing"];
        for (NSString *k in @[@"textColor", @"thumbColor", @"trackColor"]) {
            id v = sl[k];
            if (v && !Sk1nColorFromHex(v)) [e addObject:[NSString stringWithFormat:@"slider.%@ is not #RRGGBB[AA]", k]];
        }
    }

    id snd = plist[@"sounds"];
    if (snd) {
        if (![snd isKindOfClass:NSDictionary.class]) [e addObject:@"sounds must be a dictionary"];
        else for (NSString *k in snd) if (!Sk1nSafeComponent(snd[k])) [e addObject:[NSString stringWithFormat:@"sounds.%@ unsafe file name", k]];
    }
    return e;
}

+ (instancetype)skinAtDirectory:(NSString *)dir errors:(NSArray<NSString *> **)errors {
    NSString *plistPath = [dir stringByAppendingPathComponent:@"Skin.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *errs = plist ? [self validationErrorsForPlist:plist directoryName:dir.lastPathComponent]
                          : @[@"Skin.plist missing or unreadable"];
    if (errs.count) { if (errors) *errors = errs; return nil; }

    Sk1nSkin *s = [[Sk1nSkin alloc] init];
    s->_skinID = [plist[@"id"] copy];
    s->_name = [plist[@"name"] copy];
    Sk1nEra era = Sk1nEraIOS1; Sk1nEraFromName(plist[@"era"], &era);
    s->_era = era;
    s->_directory = [dir copy];
    s->_colors = [plist[@"colors"] copy] ?: @{};
    s->_fonts = [plist[@"fonts"] copy] ?: @{};
    s->_iconsDirectory = [dir stringByAppendingPathComponent:plist[@"iconsDirectory"] ?: @"Icons"];
    s->_lockscreen = [plist[@"lockscreen"] copy] ?: @{};
    s->_slider = [plist[@"slider"] copy] ?: @{};
    s->_sounds = [plist[@"sounds"] copy] ?: @{};
    return s;
}

- (UIColor *)colorNamed:(NSString *)name fallback:(UIColor *)fallback {
    return Sk1nColorFromHex(self.colors[name]) ?: fallback;
}
@end
