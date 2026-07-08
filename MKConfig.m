//
//  MKConfig.m
//

#import "MKConfig.h"

static NSString * const kPrefsDomain = @"com.mk.runningdotindicatorprefs";

@implementation MKConfig {
    NSDictionary *_prefs;
}

+ (instancetype)sharedConfig {
    static MKConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MKConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
    }
    return self;
}

- (void)reload {
    // 使用 CFPreferences API 而非直接读文件, 兼容 rootless/rootful 路径差异
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
    CFArrayRef keys = CFPreferencesCopyKeyList(
        (__bridge CFStringRef)kPrefsDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    if (keys) {
        NSDictionary *d = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
            keys,
            (__bridge CFStringRef)kPrefsDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost);
        CFRelease(keys);
        _prefs = d ?: @{};
    } else {
        _prefs = @{};
    }

    NSLog(@"[RunningDotIndicator] MKConfig reload, keys: %lu, enabled=%@, color=%@",
          (unsigned long)[_prefs count],
          _prefs[@"enabled"],
          _prefs[@"color"] ?: @"(default)");
}

#pragma mark - 读取字段(带默认值)

- (BOOL)enabled {
    id v = _prefs[@"enabled"];
    return v ? [v boolValue] : YES;
}

- (MKShape)shape {
    id v = _prefs[@"shape"];
    return v ? (MKShape)[v integerValue] : MKShapeCircle;
}

- (CGFloat)size {
    id v = _prefs[@"size"];
    CGFloat s = v ? [v floatValue] : 6.0f;
    return (s < 3.0f) ? 3.0f : (s > 14.0f ? 14.0f : s);
}

- (MKPosition)position {
    id v = _prefs[@"position"];
    return v ? (MKPosition)[v integerValue] : MKPositionLeft;
}

- (CGFloat)opacity {
    id v = _prefs[@"opacity"];
    CGFloat o = v ? [v floatValue] : 1.0f;
    return (o < 0.1f) ? 0.1f : (o > 1.0f ? 1.0f : o);
}

- (UIColor *)color {
    // 优先使用自定义十六进制颜色; 为空或非法时回退到预设颜色
    NSString *custom = _prefs[@"customColor"];
    if ([custom isKindOfClass:[NSString class]] && [custom length]) {
        UIColor *c = [[self class] colorFromHex:custom];
        // colorFromHex 对非法输入会返回 systemGreenColor, 此处视为"解析失败"
        // 只要能解析出非默认值就用自定义色
        return c;
    }
    NSString *hex = _prefs[@"color"];
    if (![hex length]) hex = @"#34C759";
    return [[self class] colorFromHex:hex];
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]] || ![hex length]) {
        return [UIColor systemGreenColor];
    }
    NSMutableString *s = [NSMutableString stringWithString:hex];
    [s replaceOccurrencesOfString:@"#" withString:@""
                           options:0 range:NSMakeRange(0, s.length)];
    // 去除可能的前缀 0x
    [s replaceOccurrencesOfString:@"0x" withString:@""
                           options:0 range:NSMakeRange(0, s.length)];
    NSString *clean = [s uppercaseString];

    // #RGB -> #RRGGBB
    if (clean.length == 3) {
        NSMutableString *expanded = [NSMutableString string];
        for (NSUInteger i = 0; i < clean.length; i++) {
            unichar c = [clean characterAtIndex:i];
            [expanded appendFormat:@"%C%C", c, c];
        }
        clean = expanded;
    }
    if (clean.length < 6) {
        return [UIColor systemGreenColor];
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&value]) {
        return [UIColor systemGreenColor];
    }

    CGFloat r = ((value >> 16) & 0xFF) / 255.0f;
    CGFloat g = ((value >> 8)  & 0xFF) / 255.0f;
    CGFloat b = ( value        & 0xFF) / 255.0f;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
}

@end
