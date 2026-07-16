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

    // v2.0.25: 固化「默认应为开」的缺省键（详见 _mk_materializeDefaultsIfNeeded）。
    [self _mk_materializeDefaultsIfNeeded];

    NSLog(@"[RunningDotIndicator] MKConfig reload, keys: %lu, enabled=%@, shape=%@, color=%@",
          (unsigned long)[_prefs count],
          _prefs[@"enabled"],
          _prefs[@"shape"],
          _prefs[@"color"] ?: @"(default)");
}

#pragma mark - 缺省键固化（防设置面板物化成 0）

// v2.0.25: 修复 rd_log(73) 实锤 bug ——
//   现象：用户从没手动拨过「文件夹图标」开关，但一打开系统「设置」App，
//         folderIndicators 就被翻成 0 且持续 ~66s，期间 off 路径(MKConfig getter 返回 0 →
//         Tweak.x FICON-ABORT reason=folderIndicators-off 真调 MKRemoveIndicatorForBid)
//         把所有文件夹圆点拆光。
//   根因：该键「键缺失→默认开(YES)」是 getter 的兜底假象，磁盘上从未写出过 1。
//         设置面板加载时偏好框架把缺省键物化写盘，落成了 0（而非 plist 的 <true/>），
//         于是 getter 老老实实返回 0。enabled 同理——一旦被物化成 0，整个插件会被关掉（更炸）。
//   修复：仅当键【确实不存在】时把默认值固化到磁盘(写入 + synchronize)。
//         · 键存在(用户主动设过 0) → 跳过，尊重用户选择，绝不覆盖。
//         · 键缺失(从未拨过) → 写出 1，设置面板打开前键已是 1，框架读到现有值不再物化成 0。
//   只固化「默认 YES」的关键开关；colorMode/shape/dotSize 等默认 0/低位本就安全，无需固化。
- (void)_mk_materializeDefaultsIfNeeded {
    static NSDictionary<NSString *, NSNumber *> *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            @"enabled":          @YES,
            @"folderIndicators": @YES,
        };
    });
    BOOL wrote = NO;
    for (NSString *key in defaults) {
        if (_prefs[key] != nil) continue;   // 用户已显式设过（含主动关 0）→ 不碰
        CFPreferencesSetValue(
            (__bridge CFStringRef)key,
            (__bridge CFPropertyListRef)defaults[key],
            (__bridge CFStringRef)kPrefsDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost);
        wrote = YES;
    }
    if (wrote) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
        if ([self debugLog]) {
            NSLog(@"[RunningDotIndicator] _mk_materializeDefaultsIfNeeded: 固化缺省开关键 → enabled=YES, folderIndicators=YES (仅缺省缺失时写入, 不覆盖用户主动设的 0)");
        }
    }
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
