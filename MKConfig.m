//
//  MKConfig.m
//  RunningDotIndicator
//
//  v1.4.8: 简化配置 — 圆点/横条两种形状，固定替换名字位置
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

    NSLog(@"[RunningDotIndicator] MKConfig reload, keys: %lu, enabled=%@, shape=%@, color=%@",
          (unsigned long)[_prefs count],
          _prefs[@"enabled"],
          _prefs[@"shape"],
          _prefs[@"color"] ?: @"(default)");
}

#pragma mark - 读取字段(带默认值)

- (BOOL)enabled {
    id v = _prefs[@"enabled"];
    return v ? [v boolValue] : YES;
}

- (MKColorMode)colorMode {
    id v = _prefs[@"colorMode"];
    return v ? (MKColorMode)[v integerValue] : MKColorModeFixed;
}

- (MKShape)shape {
    id v = _prefs[@"shape"];
    return v ? (MKShape)[v integerValue] : MKShapeDot;
}

- (CGFloat)dotSize {
    id v = _prefs[@"dotSize"];
    CGFloat s = v ? [v floatValue] : 6.0f;
    return (s < 3.0f) ? 3.0f : (s > 12.0f ? 12.0f : s);
}

- (CGFloat)barWidth {
    id v = _prefs[@"barWidth"];
    CGFloat w = v ? [v floatValue] : 24.0f;
    return (w < 12.0f) ? 12.0f : (w > 48.0f ? 48.0f : w);
}

- (CGFloat)barHeight {
    id v = _prefs[@"barHeight"];
    CGFloat h = v ? [v floatValue] : 4.0f;
    return (h < 2.0f) ? 2.0f : (h > 8.0f ? 8.0f : h);
}

- (CGFloat)opacity {
    id v = _prefs[@"opacity"];
    CGFloat o = v ? [v floatValue] : 1.0f;
    return (o < 0.1f) ? 0.1f : (o > 1.0f ? 1.0f : o);
}

- (BOOL)debugLog {
    // v1.6.29: 设置页「调试日志」开关优先；回退到文件开关 /var/mobile/Documents/rd_debug（历史兼容）
    // 二者 OR：任一为真即输出详细排障日志。文件开关为临时兼容手段，稳定后将随调试开关一起移除。
    id v = _prefs[@"debugLog"];
    if (v) return [v boolValue];
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Documents/rd_debug"];
}

- (UIColor *)color {
    NSString *custom = _prefs[@"customColor"];
    if ([custom isKindOfClass:[NSString class]] && [custom length]) {
        UIColor *c = [[self class] colorFromHex:custom];
        return c;
    }
    NSString *hex = _prefs[@"color"];
    if (![hex length]) hex = @"#34C759";
    return [[self class] colorFromHex:hex];
}

// v1.6.75: 桌面文件夹指示器总开关，默认开（保留原行为：文件夹内显示）
- (BOOL)folderIndicators {
    id v = _prefs[@"folderIndicators"];
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return YES;
}

// v1.6.75: 文件夹内显示方式，默认 0=排序靠前
- (NSInteger)folderIndicatorMode {
    id v = _prefs[@"folderIndicatorMode"];
    if ([v isKindOfClass:[NSNumber class]]) return [v integerValue];
    return 0;
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]] || ![hex length]) {
        return [UIColor systemGreenColor];
    }
    NSMutableString *s = [NSMutableString stringWithString:hex];
    [s replaceOccurrencesOfString:@"#" withString:@""
                           options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"0x" withString:@""
                           options:0 range:NSMakeRange(0, s.length)];
    NSString *clean = [s uppercaseString];

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
