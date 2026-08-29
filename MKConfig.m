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
    // v2.0.66.93: 此处原有一条【无条件 NSLog】(打 keys 数 / enabled / shape / color)。
    //   工程其余诊断早在 .73/.78 就全部 RDLog 化(编译期 no-op)、sDebugLog/sProbeLog 一并删除,
    //   唯独这条漏了 —— 而 reload 是热路径: 拖任一滑块都会经由 Darwin 通知触发一次,
    //   等于拖动过程中持续往 syslog 刷字符串格式化。诊断价值为零(线上取不到日志), 直接删除。
    //   若将来确需排查配置读取, 请用 Tweak.x 的 RDLog 宏, 不要在此恢复裸 NSLog。
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

// v2.0.30: 「保留小黄点」开关，默认开（保留运行中 TF/beta App 的小黄点）
- (BOOL)keepBetaDot {
    id v = _prefs[@"keepBetaDot"];
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return YES;
}

// v2.0.66.80: 位置模式，默认替换名称
- (MKLocationMode)locationMode {
    id v = _prefs[@"locationMode"];
    return v ? (MKLocationMode)[v integerValue] : MKLocationReplace;
}
// v2.0.66.80: 角标角落，默认左上
- (MKBadgeCorner)badgeCorner {
    id v = _prefs[@"badgeCorner"];
    if (!v) return MKBadgeCornerTopLeft;
    NSInteger c = [v integerValue];
    return (c >= 0 && c <= 3) ? (MKBadgeCorner)c : MKBadgeCornerTopLeft;
}
// v2.0.66.81: 角标粗细，默认 4，钳制 1-6，支持小数（drawRect 直接读 float）
- (CGFloat)badgeThickness {
    id v = _prefs[@"badgeThickness"];
    CGFloat t = v ? [v floatValue] : 4.0f;
    return (t < 1.0f) ? 1.0f : (t > 6.0f ? 6.0f : t);
}
// v2.0.66.81: 角标与图标距离，默认 0(内贴图标边角)，越大越向外离图标越远，钳制 0-12
- (CGFloat)badgeInset {
    id v = _prefs[@"badgeInset"];
    CGFloat i = v ? [v floatValue] : 0.0f;
    return (i < 0.0f) ? 0.0f : (i > 12.0f ? 12.0f : i);
}
// v2.0.66.91: 角标弧线长度比例。plist 存 60~100 的百分数(滑块直观)，此处换算为 0.60~1.00 小数。
// 默认 90 —— 用户实机对比 .90 的 100% 后要求「再短 10%」，故新默认即 90%。
// 下限 60: 60pt 图标上 60% ≈ 8pt 弧，再短就接近 .88「太短」的观感，不给踩坑空间。
- (CGFloat)badgeArcLength {
    id v = _prefs[@"badgeArcLength"];
    CGFloat p = v ? [v floatValue] : 90.0f;
    if (p < 60.0f) p = 60.0f; else if (p > 100.0f) p = 100.0f;
    return p / 100.0f;
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
