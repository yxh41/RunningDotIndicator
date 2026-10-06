//
//  MKRootListController.m
//  设置页主控制器 —— 在原生 PSListController 外层做 2026 Liquid-Glass 视觉包装
//  所有 Root.plist 控件(开关/形状/滑块/颜色/不透明度)保持原样，仅做视觉美化
//

#import "MKRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <math.h>

// v2.0.66.86: PSTableCell / PSControlTableCell 的两个私有访问器。
// ⚠️ 必须用【类别声明】而不是 -performSelector: —— ARC 下 performSelector 会触发
//    -Warc-performSelector-leaks, 而 CI 开了 -Werror → 直接编译失败。
@interface NSObject (MKPSCellPrivate)
- (id)control;      // PSControlTableCell: UISwitch / UISegmentedControl / UISlider
- (id)specifier;    // PSTableCell: 该行对应的 PSSpecifier
@end

// 偏好设置域名(与 Tweak 读取的文件一致)
static NSString * const kPrefsDomain = @"com.mk.runningdotindicatorprefs";
// 每次值变化时广播的 Darwin 通知名
static NSString * const kReloadNotification = @"com.mk.runningdotindicator.reload";
// v2.0.66.93: 「注销 SpringBoard」通知 —— 设置 App 无权杀 SpringBoard,
// 只能发通知, 由注入在 SpringBoard 内的 dylib(MKRespringCallback) 自行 exit(0)。
static NSString * const kRespringNotification = @"com.mk.runningdotindicator.respring";

// v2.0.66.93: 「恢复默认设置」要清空的全部偏好键。
// 清空(而非写回默认值)的理由: 读取侧(MKConfig 各 getter / readPreferenceValue)在键缺失时
// 一律回落到默认值, 且 plist 的 <default> 与 MKConfig 里的默认值逐项一致 —— 删键即真正的
// 「出厂状态」, 也避免将来改默认值时这里成为一份必须同步维护的重复清单。
// ⚠️ 新增偏好项时必须把 key 加进本数组, 否则「恢复默认」会漏掉它。
static NSArray *MKAllPrefKeys(void) {
    static NSArray *keys = nil;
    if (!keys) keys = @[ @"enabled", @"shape", @"dotSize", @"barWidth", @"barHeight",
                         @"colorMode", @"color", @"customColor",
                         @"folderIndicators", @"keepBetaDot", @"opacity",
                         @"locationMode", @"locationModeHome", @"locationModeDock", @"locationModeFolder",
                         @"badgeCorner", @"badgeThickness",
                         @"badgeArcLength", @"badgeInset",
                         @"underlineWidthRatio", @"underlineThickness", @"underlineGap" ];
    return keys;
}

// ── 2026 玻璃风格常量 ──
static const CGFloat kHeroHeight = 150.0f;
static const CGFloat kHeroPad    = 24.0f;
static const CGFloat kCardRadius = 16.0f;
static const CGFloat kCardAlpha  = 0.62f; // 卡片半透明 → 透出毛玻璃背景

// 头图模拟图标尺寸（更精致，与真实桌面图标比例一致）
static const CGFloat kIconSize   = 52.0f;
static const CGFloat kIconRadius = 12.0f;
static const CGFloat kGlyphSize  = 32.0f;
static const CGFloat kGlyphRadius = 8.0f;
static const CGFloat kIconTopY   = 34.0f;
static const CGFloat kLabelAreaH = 14.0f; // 图标下方名称区域典型高度

@interface MKRootListController ()
@property (nonatomic, strong) UIView   *heroView;        // 顶部玻璃头图
@property (nonatomic, strong) UIView   *previewIcon;     // 头图里的模拟 App 图标
@property (nonatomic, strong) UIView   *previewGlyph;    // 图标内白色 glyph
@property (nonatomic, strong) UIView   *previewIndicator;// 实时预览指示点/横条
@property (nonatomic, strong) UILabel  *previewName;     // v2.0.66.84: 角标模式下显示的图标名称
@property (nonatomic, strong) CAShapeLayer *previewBadge;// v2.0.66.84: 角标模式实时预览弧线
@property (nonatomic, strong) UILabel  *previewTitle;    // 头图标题行
@property (nonatomic, strong) UILabel  *previewCaption;   // 头图副标题
@property (nonatomic, assign) BOOL      heroAnimated;     // 入场动画只播一次
// v2.0.66.117: 滑块行的实际行高缓存(indexPath → 78)。见 -tableView:heightForRowAtIndexPath:
@property (nonatomic, strong) NSMutableDictionary *rowHeights;
@end

@implementation MKRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        // v2.0.66.117: 规格重载(切换模式/恢复默认后 reloadSpecifiers)时清掉行高缓存,
        //   避免旧的 indexPath→78 落到结构变了的行上。
        [self.rowHeights removeAllObjects];
        // v2.0.66.117: 给滑块行打 height 标记。
        //   PSListController 自己实现了 -tableView:heightForRowAtIndexPath:, 会【完全忽略】
        //   tableView.rowHeight(.116 就是栽在这: 行仍是 44pt, 而滑块被写在 y=44 处 → 整条被裁掉)。
        //   若它读 specifier 的 height 属性, 这里就能一步到位(首帧即 78, 无跳变);
        //   若不读, 下面 -tableView:heightForRowAtIndexPath: 的缓存兜底仍会把高度抬起来。
        for (id obj in _specifiers) {
            if (![obj isKindOfClass:[PSSpecifier class]]) continue;
            PSSpecifier *spec = (PSSpecifier *)obj;
            NSString *cls = [spec propertyForKey:@"cell"] ?: @"";
            if ([cls rangeOfString:@"Slider"].location != NSNotFound) {
                [spec setProperty:[NSNumber numberWithFloat:78.0f] forKey:@"height"];
            }
        }
    }
    return _specifiers;
}

// v2.0.66.117: 逐行行高 —— 只把滑块行抬到 78pt, 其余行保持系统默认。
// 🔴 绝不能再写 `tableView.rowHeight = 78`: 那是【全局】的, 会把开关/下拉/按钮/分组行
//    一起撑成 78pt; 而且 PSListController 若实现了本回调, rowHeight 会被无视。
// 判定顺序: 先看首帧是否已知该行是滑块(缓存) → 否则问 super(它可能已读 height 属性返 78)。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat base = 44.0f;
    @try {
        if ([[self superclass] instancesRespondToSelector:_cmd]) {
            base = [super tableView:tableView heightForRowAtIndexPath:indexPath];
        } else if (tableView.rowHeight > 0.0f) {
            base = tableView.rowHeight;
        }
    } @catch (NSException *e) {
        base = (tableView.rowHeight > 0.0f) ? tableView.rowHeight : 44.0f;
    }
    if (base <= 0.0f) base = 44.0f;
    NSNumber *h = [self.rowHeights objectForKey:indexPath];
    // v2.0.66.117: 滑块行取 78(缓存命中时) —— 缓存由 willDisplayCell 首帧写入。
    return h ? [h floatValue] : base;
}

#pragma mark - 配置读取 / 颜色解析

// 读取偏好值，缺失时返回默认值；若磁盘值类型与 default 不一致也退回 default，
// 防止其他插件或旧版本把错误类型（如 NSDictionary）写进偏好，导致读取 boolValue/integerValue 崩溃。
- (id)readValueForKey:(NSString *)key default:(id)def expectedClass:(Class)cls {
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPrefsDomain);
    if (v) {
        id obj = (__bridge_transfer id)v;
        if (cls && [obj isKindOfClass:cls]) return obj;
        if (!cls) return obj;
    }
    return def;
}

// 兼容旧调用：不强制类型，仅做 CFPreferences 读取
- (id)readValueForKey:(NSString *)key default:(id)def {
    return [self readValueForKey:key default:def expectedClass:nil];
}

// #RRGGBB / RRGGBB / #RGB → UIColor，非法返回 nil
static UIColor *MKColorFromHex(NSString *hex) {
    if (!hex || hex.length == 0) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (s.length >= 2 && [[s substringToIndex:2] caseInsensitiveCompare:@"0x"] == NSOrderedSame) {
        s = [s substringFromIndex:2];
    }
    if (s.length == 3) {
        s = [NSString stringWithFormat:@"%c%c%c%c%c%c",
              [s characterAtIndex:0], [s characterAtIndex:0],
              [s characterAtIndex:1], [s characterAtIndex:1],
              [s characterAtIndex:2], [s characterAtIndex:2]];
    }
    if (s.length != 6) return nil;
    unsigned int rgb = 0;
    if ([[NSScanner scannerWithString:s] scanHexInt:&rgb]) {
        return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
                               green:((rgb >> 8) & 0xFF) / 255.0f
                                blue:(rgb & 0xFF) / 255.0f
                               alpha:1.0f];
    }
    return nil;
}

#pragma mark - 玻璃头图(实时预览)

// 构建一次头图视图；纯视觉，失败时静默跳过
- (void)ensureHero {
    if (self.heroView) return;
    @try {
        CGFloat W = (self.view.bounds.size.width > 0) ? self.view.bounds.size.width : 320.0f;

        UIView *hero = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, kHeroHeight)];
        hero.backgroundColor = [UIColor clearColor];
        hero.clipsToBounds = YES;

        // 毛玻璃底
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:blur];
        glass.frame = hero.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.userInteractionEnabled = NO;
        [hero addSubview:glass];

        // 内容层(透明，浮在玻璃上)
        UIView *content = [[UIView alloc] initWithFrame:hero.bounds];
        content.autoresizingMask = glass.autoresizingMask;
        content.backgroundColor = [UIColor clearColor];
        [hero addSubview:content];

        // 模拟 App 图标（圆角方块，强调色填充；尺寸与真实图标一致）
        // 图标固定在左侧，与 v1.6.18 一致
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(kHeroPad, kIconTopY, kIconSize, kIconSize)];
        icon.layer.cornerRadius = kIconRadius;
        icon.layer.masksToBounds = YES;
        [content addSubview:icon];

        // 图标内白色 glyph（比例适中，避免绿色外圈过粗）
        CGFloat glyphInset = (kIconSize - kGlyphSize) / 2.0f;
        UIView *glyph = [[UIView alloc] initWithFrame:CGRectMake(glyphInset, glyphInset, kGlyphSize, kGlyphSize)];
        glyph.backgroundColor = [UIColor whiteColor];
        glyph.layer.cornerRadius = kGlyphRadius;
        glyph.layer.masksToBounds = YES;
        [icon addSubview:glyph];

        // 标题行（图标右侧，左对齐）
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        title.textAlignment = NSTextAlignmentLeft;
        if (@available(iOS 13.0, *)) title.textColor = [UIColor labelColor];
        else title.textColor = [UIColor blackColor];
        [content addSubview:title];

        // 副标题（图标右侧，左对齐）
        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectZero];
        cap.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        cap.textAlignment = NSTextAlignmentLeft;
        if (@available(iOS 13.0, *)) cap.textColor = [UIColor secondaryLabelColor];
        else cap.textColor = [UIColor grayColor];
        [content addSubview:cap];

        // 实时预览指示点/横条(放在图标正下方，像主屏那样替换图标名称)
        UIView *ind = [[UIView alloc] initWithFrame:CGRectZero];
        ind.layer.masksToBounds = YES;
        [content addSubview:ind];

        // v2.0.66.84: 角标模式预览 —— 图标下方保留名称 + 图标角落画 squircle 弧线
        UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
        name.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
        name.textAlignment = NSTextAlignmentCenter;
        name.text = @"App";
        if (@available(iOS 13.0, *)) name.textColor = [UIColor labelColor];
        else name.textColor = [UIColor blackColor];
        name.hidden = YES;
        [content addSubview:name];

        // 弧线层挂在 content 上（不挂 icon，避免被 icon 的 masksToBounds 裁掉外移部分）
        CAShapeLayer *badge = [CAShapeLayer layer];
        badge.fillColor   = [UIColor clearColor].CGColor;
        badge.lineCap     = kCALineCapRound;
        badge.hidden      = YES;
        [content.layer addSublayer:badge];

        self.heroView          = hero;
        self.previewIcon        = icon;
        self.previewGlyph       = glyph;
        self.previewTitle       = title;
        self.previewCaption     = cap;
        self.previewIndicator   = ind;
        self.previewName        = name;
        self.previewBadge       = badge;
    } @catch (NSException *e) {
        self.heroView = nil;
    }
}

// 根据当前配置重算预览指示点的位置/尺寸/圆角
- (void)updateIndicatorFrame {
    if (!self.previewIndicator || !self.previewIcon) return;

    // v2.0.66.84: 角标模式 —— 隐藏圆点/横条，改在图标角落画 squircle 1/4 弧，名称保留
    NSInteger locMode = [[self readValueForKey:@"locationModeHome" default:@0 expectedClass:[NSNumber class]] integerValue];
    if (locMode == 1) {
        self.previewIndicator.hidden = YES;
        self.previewName.hidden      = NO;
        self.previewBadge.hidden     = NO;
        [self updateBadgePreview];
        return;
    }
    // v2.0.66.114: 底沿下划线 —— 名称保留(不藏), 指示器复用 previewIndicator 画在图标底沿下方。
    //   与 drawRect 同构: 宽 = 图标宽 × ratio, 粗 = thickness, y = 图标底沿 + gap;
    //   粗细 <3 画直角(与 drawRect 的分支判据一致), >=3 画 pill 圆角。
    if (locMode == 2) {
        self.previewIndicator.hidden = NO;
        self.previewName.hidden      = NO;
        self.previewBadge.hidden     = YES;
        CGFloat ratio = [[self readValueForKey:@"underlineWidthRatio" default:@55 expectedClass:[NSNumber class]] floatValue];
        if (ratio < 30.0f) ratio = 30.0f; else if (ratio > 90.0f) ratio = 90.0f;
        CGFloat th    = [[self readValueForKey:@"underlineThickness" default:@2  expectedClass:[NSNumber class]] floatValue];
        if (th < 1.0f) th = 1.0f; else if (th > 4.0f) th = 4.0f;
        CGFloat gap   = [[self readValueForKey:@"underlineGap" default:@1 expectedClass:[NSNumber class]] floatValue];
        if (gap < 0.0f) gap = 0.0f; else if (gap > 4.0f) gap = 4.0f;
        CGFloat iconW = self.previewIcon.frame.size.width;
        CGFloat uy = CGRectGetMaxY(self.previewIcon.frame) + gap;
        CGFloat ux = CGRectGetMidX(self.previewIcon.frame) - (iconW * ratio / 100.0f) / 2.0f;
        self.previewIndicator.frame = CGRectMake(ux, uy, iconW * ratio / 100.0f, th);
        self.previewIndicator.layer.cornerRadius = (th < 3.0f) ? 0.0f : th / 2.0f;
        return;
    }
    self.previewIndicator.hidden = NO;
    self.previewName.hidden      = YES;
    self.previewBadge.hidden     = YES;

    NSInteger shape = [[self readValueForKey:@"shape" default:@0 expectedClass:[NSNumber class]] integerValue];
    CGFloat dot = [[self readValueForKey:@"dotSize"  default:@6  expectedClass:[NSNumber class]] floatValue];
    CGFloat bw  = [[self readValueForKey:@"barWidth"  default:@24 expectedClass:[NSNumber class]] floatValue];
    CGFloat bh  = [[self readValueForKey:@"barHeight" default:@4  expectedClass:[NSNumber class]] floatValue];

    CGFloat w, h;
    if (shape == 1) {                 // 横条：与真实桌面使用完全一致尺寸
        w = bw;
        h = bh;
    } else {                           // 圆点：与真实桌面使用完全一致尺寸
        w = dot;
        h = dot;
    }

    // 指示器放在图标名称区域，与主屏真实位置一致
    CGFloat iconBottom = CGRectGetMaxY(self.previewIcon.frame);
    CGFloat iy = iconBottom + 4.0f + (kLabelAreaH - h) / 2.0f;
    CGFloat ix = CGRectGetMidX(self.previewIcon.frame) - w / 2.0f;
    self.previewIndicator.frame = CGRectMake(ix, iy, w, h);
    self.previewIndicator.layer.cornerRadius = h / 2.0f;
}

// v2.0.66.84: 角标模式实时预览 —— 与 MKIndicatorDotView.m drawRect 同一套几何
// (squircle 1/4 三次贝塞尔 k=0.528，inset 沿角落单位向量平移整段弧线)
// v2.0.66.91: 同步新增弧长裁剪(badgeArcLength)。⚠️ 设置 bundle 与 tweak 是两个二进制,
// 不能共享 MKIndicatorDotView.m 里的 static 函数 → 此处必须保留一份【逐字等价】的实现。
// 改任一侧务必同步另一侧(同构铁律, .87/.88 血案由来)。
static inline CGPoint MKPvLerp(CGPoint a, CGPoint b, CGFloat t) {
    return CGPointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}
static void MKPvSplit(const CGPoint p[4], CGFloat t, CGPoint L[4], CGPoint R[4]) {
    CGPoint ab  = MKPvLerp(p[0], p[1], t);
    CGPoint bc  = MKPvLerp(p[1], p[2], t);
    CGPoint cd  = MKPvLerp(p[2], p[3], t);
    CGPoint abc = MKPvLerp(ab, bc, t);
    CGPoint bcd = MKPvLerp(bc, cd, t);
    CGPoint m   = MKPvLerp(abc, bcd, t);
    L[0] = p[0]; L[1] = ab;  L[2] = abc; L[3] = m;
    R[0] = m;    R[1] = bcd; R[2] = cd;  R[3] = p[3];
}
static void MKPvSub(const CGPoint p[4], CGFloat t0, CGFloat t1, CGPoint out[4]) {
    if (t1 <= t0) { for (int i = 0; i < 4; i++) out[i] = p[0]; return; }
    CGPoint L[4], R[4];
    MKPvSplit(p, t1, L, R);
    if (t0 <= 0.0f) { for (int i = 0; i < 4; i++) out[i] = L[i]; return; }
    CGPoint L2[4], R2[4];
    MKPvSplit(L, t0 / t1, L2, R2);
    for (int i = 0; i < 4; i++) out[i] = R2[i];
}

- (void)updateBadgePreview {
    if (!self.previewBadge || !self.previewIcon) return;

    NSInteger corner = [[self readValueForKey:@"badgeCorner" default:@0 expectedClass:[NSNumber class]] integerValue];
    CGFloat t = [[self readValueForKey:@"badgeThickness" default:@4.0f expectedClass:[NSNumber class]] floatValue];
    CGFloat inset = [[self readValueForKey:@"badgeInset" default:@0.0f expectedClass:[NSNumber class]] floatValue];
    // v2.0.66.91: 弧长比例(plist 存 60~100 百分数, 与 MKConfig.badgeArcLength 同一换算)
    CGFloat arcPct = [[self readValueForKey:@"badgeArcLength" default:@90.0f expectedClass:[NSNumber class]] floatValue];
    if (t < 1.0f) t = 1.0f; else if (t > 6.0f) t = 6.0f;
    if (inset < 0.0f) inset = 0.0f; else if (inset > 12.0f) inset = 12.0f;
    if (arcPct < 60.0f) arcPct = 60.0f; else if (arcPct > 100.0f) arcPct = 100.0f;
    CGFloat f = arcPct / 100.0f;

    // 预览图标 52pt / 圆角 12pt；按真实图标比例(60pt/13.5pt)等比缩放粗细与距离，视觉更接近实机
    CGFloat scale = kIconSize / 60.0f;
    CGFloat tt = t * scale;
    CGFloat ss = inset * scale * 0.70710678f;   // 1/√2

    CGRect ic = self.previewIcon.frame;         // 与弧线层同处 content 坐标系
    CGFloat W = ic.size.width, H = ic.size.height;
    CGFloat rc = kIconRadius;
    CGFloat ox = ic.origin.x, oy = ic.origin.y;
    switch (corner) {
        case 1:  ox += ss;  oy -= ss;  break;   // 右上
        case 2:  ox -= ss;  oy += ss;  break;   // 左下
        case 3:  ox += ss;  oy += ss;  break;   // 右下
        default: ox -= ss;  oy -= ss;  break;   // 左上
    }

    CGFloat k = 0.528f;
    // v2.0.66.91: 与 drawRect 同构 —— 先算 4 控制点, 再按 f 沿两端等量裁剪。
    CGPoint cp[4];
    switch (corner) {
        case 1:  // 右上
            cp[0] = CGPointMake(ox + W - rc,     oy);
            cp[1] = CGPointMake(ox + W - rc * k, oy);
            cp[2] = CGPointMake(ox + W,          oy + rc * (1 - k));
            cp[3] = CGPointMake(ox + W,          oy + rc);
            break;
        case 2:  // 左下
            cp[0] = CGPointMake(ox + rc,     oy + H);
            cp[1] = CGPointMake(ox + rc * k, oy + H);
            cp[2] = CGPointMake(ox,          oy + H - rc * (1 - k));
            cp[3] = CGPointMake(ox,          oy + H - rc);
            break;
        case 3:  // 右下
            cp[0] = CGPointMake(ox + W,          oy + H - rc);
            cp[1] = CGPointMake(ox + W,          oy + H - rc * (1 - k));
            cp[2] = CGPointMake(ox + W - rc * k, oy + H);
            cp[3] = CGPointMake(ox + W - rc,     oy + H);
            break;
        default: // 左上
            cp[0] = CGPointMake(ox,          oy + rc);
            cp[1] = CGPointMake(ox,          oy + rc * (1 - k));
            cp[2] = CGPointMake(ox + rc * k, oy);
            cp[3] = CGPointMake(ox + rc,     oy);
            break;
    }
    if (f < 0.9999f) {
        CGFloat t0 = (1.0f - f) * 0.5f;
        CGPoint sub[4];
        MKPvSub(cp, t0, 1.0f - t0, sub);
        for (int i = 0; i < 4; i++) cp[i] = sub[i];
    }
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:cp[0]];
    [p addCurveToPoint:cp[3] controlPoint1:cp[1] controlPoint2:cp[2]];
    self.previewBadge.frame     = self.previewIcon.superview.bounds;
    self.previewBadge.path      = p.CGPath;
    self.previewBadge.lineWidth = tt;

    // 名称占回图标下方（角标模式不藏名）
    self.previewName.frame = CGRectMake(ic.origin.x - 6.0f, CGRectGetMaxY(ic) + 3.0f,
                                       ic.size.width + 12.0f, kLabelAreaH);
}

// 头图内子视图排版：图标(左) + 指示器(图标下居中) + 标题/副标题(右)，与 v1.6.18 一致
- (void)layoutHero {
    if (!self.heroView) return;
    CGFloat W = self.heroView.bounds.size.width;
    if (W < 1) W = (self.view.bounds.size.width > 0) ? self.view.bounds.size.width : 320.0f;

    CGFloat leftW = kHeroPad + kIconSize + 20.0f; // 图标 + 标题左侧间距
    CGRect t1 = CGRectMake(leftW, 44, W - leftW - kHeroPad, 22);
    CGRect t2 = CGRectMake(leftW, 72, W - leftW - kHeroPad, 18);
    self.previewTitle.frame   = t1;
    self.previewCaption.frame = t2;
    [self updateIndicatorFrame];
}

// 刷新头图：读取当前设置 → 重绘预览 + 强调色联动
- (void)refreshHero {
    @try {
        [self ensureHero];
        if (!self.heroView) return;

        NSString *custom = [self readValueForKey:@"customColor" default:@"" expectedClass:[NSString class]];
        NSString *hex = (custom && custom.length > 0)
            ? custom
            : [self readValueForKey:@"color" default:@"#34C759" expectedClass:[NSString class]];
        UIColor *col = MKColorFromHex(hex) ?: [UIColor systemGreenColor];
        NSInteger mode = [[self readValueForKey:@"colorMode" default:@0 expectedClass:[NSNumber class]] integerValue];
        CGFloat opacity = [[self readValueForKey:@"opacity" default:@1.0f expectedClass:[NSNumber class]] floatValue];

        // 预览指示点 = 当前生效色
        self.previewIndicator.backgroundColor = col;
        self.previewIndicator.alpha = opacity;
        // v2.0.66.84: 角标弧线同色同透明度
        self.previewBadge.strokeColor = col.CGColor;
        self.previewBadge.opacity     = opacity;
        // 图标也用强调色，整体更协调
        self.previewIcon.backgroundColor = col;

        NSInteger locMode = [[self readValueForKey:@"locationModeHome" default:@0 expectedClass:[NSNumber class]] integerValue];
        if (locMode == 1) {
            NSInteger corner = [[self readValueForKey:@"badgeCorner" default:@0 expectedClass:[NSNumber class]] integerValue];
            NSArray *names = @[@"左上", @"右上", @"左下", @"右下"];
            NSString *cn = (corner >= 0 && corner < 4) ? names[corner] : names[0];
            self.previewTitle.text   = @"实时预览 · 角标模式";
            self.previewCaption.text = (mode == 1)
                ? [NSString stringWithFormat:@"%@角 · 主色调近似", cn]
                : [NSString stringWithFormat:@"%@角 · 名称保留", cn];
        } else if (mode == 1) {
            self.previewTitle.text   = @"实时预览 · 主色调";
            self.previewCaption.text = @"主色调模式下为近似预览";
        } else {
            self.previewTitle.text   = @"实时预览";
            self.previewCaption.text = @"当前配置随设置变化";
        }

        // 强调色联动：开关/滑块跟随指示器颜色
        if ([self.view respondsToSelector:@selector(setTintColor:)]) {
            self.view.tintColor = col;
        }

        [self layoutHero];
    } @catch (NSException *e) {}
}

// 防御式取表视图：PSListController 在 iOS 各版本上暴露的属性名不同
// （有的叫 table，有的叫 tableView），用 respondsToSelector + performSelector 兜底，
// 避免“未声明选择器”导致的编译失败或运行崩溃
- (UITableView *)mk_table {
    @try {
        if ([self respondsToSelector:@selector(table)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id t = [self performSelector:@selector(table)];
#pragma clang diagnostic pop
            if ([t isKindOfClass:[UITableView class]]) return t;
        }
        if ([self respondsToSelector:@selector(tableView)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id t = [self performSelector:@selector(tableView)];
#pragma clang diagnostic pop
            if ([t isKindOfClass:[UITableView class]]) return t;
        }
    } @catch (NSException *e) {}
    return nil;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    @try {
        UITableView *t = [self mk_table];
        if (t) {
            // 表格背景透出毛玻璃
            t.backgroundColor = [UIColor clearColor];
            if (@available(iOS 13.0, *)) {
                UIBlurEffect *b = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
                UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:b];
                bg.userInteractionEnabled = NO;
                t.backgroundView = bg;
            }
            // 隐藏系统分隔线，改用悬浮玻璃卡片
            t.separatorStyle = UITableViewCellSeparatorStyleNone;
            t.separatorColor  = [UIColor clearColor];
        }

        [self ensureHero];
        if (self.heroView && t) {
            t.tableHeaderView = self.heroView;
            [self refreshHero];
        }
    } @catch (NSException *e) {}
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    @try {
        if (self.heroView) {
            // reload 可能丢弃 tableHeaderView，这里重新挂接
            UITableView *t = [self mk_table];
            if (t) t.tableHeaderView = self.heroView;
            [self refreshHero];

            if (!self.heroAnimated) {
                self.heroAnimated = YES;
                self.heroView.alpha = 0.0f;
                self.heroView.transform = CGAffineTransformMakeTranslation(0, 10);
                [UIView animateWithDuration:0.5
                                      delay:0
                     usingSpringWithDamping:0.82
                      initialSpringVelocity:0.6
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                                     self.heroView.alpha = 1.0f;
                                     self.heroView.transform = CGAffineTransformIdentity;
                                 } completion:nil];
            }
        }
    } @catch (NSException *e) {}
}

// 旋转/尺寸变化时重排头图
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    @try { if (self.heroView) [self layoutHero]; } @catch (NSException *e) {}
}

#pragma mark - 按 locationMode 置灰无关控件 (v2.0.66.86)

// 当前显示位置模式下，哪些偏好项是【无作用】的 → 置灰 + 禁交互。
//   locationMode: 0 = 替换名称(MKLocationReplace)  1 = 角标(MKLocationBadge)  2 = 底沿下划线(MKLocationUnderline)
//
// 角标模式无关项:
//   shape/dotSize/barWidth/barHeight —— 角标只画弧线, 形状与点/横条尺寸全不读取。
//   keepBetaDot                     —— 角标模式不藏名, 小黄点整套 machinery 已交还系统 (Tweak 侧门控)。
//   folderIndicators                —— 角标模式下文件夹指示器【强制生效】, 开关已被 Tweak 侧忽略。
// 替换名称模式无关项:
//   badgeCorner/badgeThickness/badgeInset/badgeArcLength —— 角标专属几何参数。
//
// ⚠️ 不置灰 enabled/colorMode/color/customColor/opacity/locationMode/locationModeHome/locationModeDock/locationModeFolder: 三模式共用 (下划线模式已含替换模式专属参数)。
static BOOL MKKeyDisabledForMode(NSString *key, NSInteger mode) {
    if (!key.length) return NO;
    if (mode == 1) { // 角标模式
        static NSSet *badgeOff = nil;
        if (!badgeOff) badgeOff = [NSSet setWithArray:@[ @"shape", @"dotSize", @"barWidth",
                                                        @"barHeight", @"keepBetaDot",
                                                        @"folderIndicators",
                                                        @"underlineWidthRatio",
                                                        @"underlineThickness",
                                                        @"underlineGap" ]];
        return [badgeOff containsObject:key];
    }
    // v2.0.66.114: 底沿下划线模式 —— 专属参数是 underline*; 角标 + 替换模式专属参数都用不到。
    //   注: 三种模式都【不藏名】, 故与角标共用「不置灰」名单(enabled/colorMode/color/
    //   customColor/opacity/locationMode)。⚠️ 2026-10-06 修正: 之前漏掉替换模式专属参数
    //   → 下划线模式下替换模式的开关仍亮着; 现补 shape/dotSize/barWidth/barHeight/keepBetaDot/
    //   folderIndicators, 与角标模式(mode 1)一致地整组置灰。
    if (mode == 2) { // 底沿下划线
        static NSSet *underlineOff = nil;
        if (!underlineOff) underlineOff = [NSSet setWithArray:@[ @"badgeCorner", @"badgeThickness",
                                                                @"badgeInset", @"badgeArcLength",
                                                                @"shape", @"dotSize", @"barWidth",
                                                                @"barHeight", @"keepBetaDot",
                                                                @"folderIndicators" ]];
        return [underlineOff containsObject:key];
    }
    static NSSet *replaceOff = nil;
    if (!replaceOff) replaceOff = [NSSet setWithArray:@[ @"badgeCorner", @"badgeThickness",
                                                         @"badgeInset", @"badgeArcLength",
                                                         @"underlineWidthRatio",
                                                         @"underlineThickness",
                                                         @"underlineGap" ]];
    return [replaceOff containsObject:key];
}

// v2.0.66.121: 混搭模式 —— 置灰按【三个分区模式的并集】判定: 某控件仅当它在「所有」当前生效的
//   分区模式下都无作用时才置灰(否则只要有一个分区用到它就该亮)。例: shape(替换专属) 仅当没有任何
//   分区为替换模式时才灰; badgeCorner(角标专属) 仅当没有任何分区为角标模式时才灰; 三模式共用项
//   (enabled/color/opacity/三分区模式键) 因各模式下 MKKeyDisabledForMode 均返 NO → 永不灰。
static NSInteger MKReadIntPref(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPrefsDomain);
    if (v) {
        id obj = (__bridge_transfer id)v;
        if ([obj isKindOfClass:[NSNumber class]]) return [obj integerValue];
    }
    return 0;
}
static BOOL MKKeyDisabledForAnyMode(NSString *key) {
    if (!key.length) return NO;
    NSInteger home   = MKReadIntPref(@"locationModeHome");
    NSInteger dock   = MKReadIntPref(@"locationModeDock");
    NSInteger folder = MKReadIntPref(@"locationModeFolder");
    return MKKeyDisabledForMode(key, home)
        && MKKeyDisabledForMode(key, dock)
        && MKKeyDisabledForMode(key, folder);
}

// 对一个 cell 施加/解除「灰化」。
// ⚠️ 只设 cell.userInteractionEnabled = NO 【不够】: PSSwitchTableCell 的 UISwitch、
//    PSSegmentTableCell 的 UISegmentedControl、PSSliderTableCell 的 UISlider 都挂在
//    accessoryView / contentView 上, 各自独立接收 touch。必须同时把 -control 置 enabled=NO。
static void MKApplyDimmed(UITableViewCell *cell, BOOL dimmed) {
    if (!cell) return;
    cell.userInteractionEnabled = !dimmed;
    cell.selectionStyle = dimmed ? UITableViewCellSelectionStyleNone
                                 : UITableViewCellSelectionStyleDefault;
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor       = dimmed ? [UIColor tertiaryLabelColor]
                                                : [UIColor labelColor];
        cell.detailTextLabel.textColor = dimmed ? [UIColor quaternaryLabelColor]
                                                : [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.textColor       = dimmed ? [UIColor lightGrayColor] : [UIColor blackColor];
        cell.detailTextLabel.textColor = dimmed ? [UIColor lightGrayColor] : [UIColor darkGrayColor];
    }
    // PSControlTableCell 家族: -control 返回真实控件
    if ([cell respondsToSelector:@selector(control)]) {
        id ctl = [(NSObject *)cell control];
        if ([ctl isKindOfClass:[UIControl class]]) {
            UIControl *c = (UIControl *)ctl;
            c.enabled = !dimmed;
            c.alpha   = dimmed ? 0.40f : 1.0f;
        }
    }
    // 兜底: 某些 cell 把控件放 accessoryView 而未实现 -control
    if ([cell.accessoryView isKindOfClass:[UIControl class]]) {
        UIControl *a = (UIControl *)cell.accessoryView;
        a.enabled = !dimmed;
        a.alpha   = dimmed ? 0.40f : 1.0f;
    }
}

// v2.0.66.119: 大号滑块卡片 —— 把 PSSliderCell 重排成「标题左 / 数值右 / 通栏滑块」卡片。
//   动机: 原来 10 个滑块外观完全一致, 用户看不出哪条调哪个参数(尤其下划线三条
//   宽度/粗细/距离)。分行布局 + 常显数值后, 每条滑块自解释。
// ⚠️ v2.0.66.119 起改为【自建 UISlider】: 原生滑块藏死不再复用(见函数内注释),
//    持久化仍走 PSSliderCell 原生链路(拖动值转发回去触发它自己的 value-changed)。
static NSString *MKSliderDisplayValue(PSSpecifier *spec, id current) {
    CGFloat v = [current respondsToSelector:@selector(floatValue)] ? [current floatValue] : 0.0f;
    NSString *k = [spec propertyForKey:@"key"] ?: @"";
    // 比例类参数(%) 显示百分号; 其余显示 pt, 去掉无意义的 .0
    if ([k hasSuffix:@"Ratio"] || [k hasSuffix:@"Length"]) {
        return [NSString stringWithFormat:@"%.0f%%", v];
    }
    if (fabs(v - (long)v) < 0.005f) return [NSString stringWithFormat:@"%ld", (long)v];
    return [NSString stringWithFormat:@"%.1f", v];
}

// v2.0.66.119: 自建滑块拖动 —— 数值 label 同步 + 转发给 PSSliderCell 的原生滑块。
// ⚠️ 写入绝不自己做: 把值塞回原生滑块再 sendActions, 由 PSSliderCell 自己的
//    value-changed 链路完成「写偏好 + 发 Darwin 通知 + 头图实时预览」, 行为零差异。
- (void)mk_ownSliderChanged:(UISlider *)sender {
    @try {
        UITableViewCell *cell = nil;
        UIView *v = sender;
        while (v && !cell) {
            if ([v isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)v;
            v = v.superview;
        }
        if (!cell) return;
        // 1) 转发给原生滑块(它在 PSSliderCell 里挂着真正的持久化 target)
        UISlider *orig = nil;
        @try {
            if ([cell respondsToSelector:@selector(control)]) {
                id c = [(NSObject *)cell control];
                if ([c isKindOfClass:[UISlider class]]) orig = (UISlider *)c;
            }
        } @catch (NSException *e) {}
        if (orig && orig != sender) {
            orig.value = sender.value;
            [orig sendActionsForControlEvents:UIControlEventValueChanged];
            // 若 PSSliderCell 在自己的处理器里做了分段吸附, 把吸附结果回贴到自建滑块
            if (fabs(orig.value - sender.value) > 0.0001f) sender.value = orig.value;
        }
        // 2) 同步右上角数值
        PSSpecifier *spec = nil;
        if ([cell respondsToSelector:@selector(specifier)]) {
            id s = [(NSObject *)cell specifier];
            if ([s isKindOfClass:[PSSpecifier class]]) spec = (PSSpecifier *)s;
        }
        for (UIView *sub in [cell.contentView subviews]) {
            if (sub.tag == 8611 && [sub isKindOfClass:[UILabel class]]) {
                ((UILabel *)sub).text = MKSliderDisplayValue(spec, @(sender.value));
            }
        }
    } @catch (NSException *e) {}
}

#pragma mark - 玻璃卡片（同 section 多行共用一张卡片）

// v2.0.66.118: 按【cell 实际高度】摆放四件套(标题/数值/滑块) —— 绝不写死 y=44。
// 🔴 .116 把滑块写死在 y=44: 一旦行高没真的抬到 78(PSListController 无视 rowHeight),
//    滑块整条落在 contentView 之外被裁掉 = 「滑块不见了」。这里按 H 自适应:
//      H >= 66 → 两行卡片(标题/数值在上, 通栏滑块在下)
//      H <  66 → 退化成单行紧凑(标题左/滑块中/数值右), 宁可小也绝不出界。
// 🔴 标题必须用【自建 label】: .116 实机截图证实 PSSliderCell 的标题跟滑块同住
//    accessoryView 容器, 摘走滑块 + accessoryView=nil 时标题被一起扔掉 → 只剩数值。
//    cell.textLabel 里根本没有字, 不能指望它。
static void MKApplyBigSliderFrames(UITableViewCell *cell, UISlider *slider, UILabel *val, UILabel *title) {
    if (!cell || !slider) return;
    CGFloat W = cell.contentView.bounds.size.width;
    CGFloat H = cell.contentView.bounds.size.height;
    if (W <= 0.0f) W = 320.0f;
    if (H <= 0.0f) H = 44.0f;
    if (H >= 66.0f) {
        if (title) title.frame = CGRectMake(16.0f, 10.0f, W * 0.58f, 24.0f);
        if (val)   val.frame   = CGRectMake(W * 0.62f, 12.0f, W * 0.38f - 16.0f, 20.0f);
        slider.frame = CGRectMake(16.0f, H - 34.0f, W - 32.0f, 28.0f);
    } else {
        if (title) title.frame = CGRectMake(16.0f, (H - 22.0f) / 2.0f, W * 0.30f, 22.0f);
        slider.frame = CGRectMake(W * 0.36f, (H - 28.0f) / 2.0f, W * 0.38f, 28.0f);
        if (val)   val.frame   = CGRectMake(W * 0.76f, (H - 20.0f) / 2.0f, W * 0.24f - 16.0f, 20.0f);
    }
}

// 把一个 PSSliderCell 改造成大号两行卡片布局。返回 NO 表示不是滑块行, 调用方走原逻辑。
// owner = 本控制器(static 函数里没有 self, target 要靠它传进来)。
static BOOL MKLayoutBigSliderCell(id owner, UITableViewCell *cell, PSSpecifier *spec) {
    NSString *cellCls = [spec propertyForKey:@"cell"] ?: @"";
    if ([cellCls rangeOfString:@"Slider"].location == NSNotFound) return NO;
    if (![cell respondsToSelector:@selector(control)]) return NO;

    UISlider *slider = nil;
    @try {
        id c = [(NSObject *)cell control];
        if ([c isKindOfClass:[UISlider class]]) slider = (UISlider *)c;
    } @catch (NSException *e) {}
    if (!slider) return NO;

    // 行高由 -tableView:heightForRowAtIndexPath: 抬到 78(见文件上方)。
    // ⚠️ UITableViewCell 没有 .height 属性(误用会编译失败), 高度只能在 tableView 侧决定。
    // 🔴 v2.0.66.118: 标题一律【自建 label】, 不用 cell.textLabel ——
    //    PSSliderCell 的标题与滑块同住 accessoryView 容器, 摘滑块时标题已被一起扔掉
    //    (实机截图: 行里只剩数值)。自带的 textLabel 若有内容反而会造成重复, 藏掉。
    cell.textLabel.hidden = YES;
    cell.textLabel.text   = nil;
    cell.textLabel.numberOfLines = 1;

    // 自建标题：左上。字重/颜色对齐其他设置行(systemFont regular + labelColor), 字号 14(比 15 再小一档)
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.tag = 8613;
    title.font = [UIFont systemFontOfSize:14.0f weight:UIFontWeightRegular];
    title.textColor = [UIColor labelColor];
    title.backgroundColor = [UIColor clearColor];
    title.numberOfLines = 1;
    title.text = [spec propertyForKey:@"label"] ?: @"";
    [cell.contentView addSubview:title];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;

    // 数值：右上, 15pt 等宽数字, 次级色。值直接取滑块当前位置 —— 与拖动天然同步,
    // 无需另挂 KVO/target(避免与 PSSliderCell 自身的 value-changed 链路打架)。
    UILabel *val = [[UILabel alloc] initWithFrame:CGRectZero];
    val.tag = 8611;
    val.font = [UIFont monospacedDigitSystemFontOfSize:15.0f weight:UIFontWeightRegular];
    val.textColor = [UIColor secondaryLabelColor];
    val.textAlignment = NSTextAlignmentRight;
    val.backgroundColor = [UIColor clearColor];
    val.text = MKSliderDisplayValue(spec, @(slider.value));
    [cell.contentView addSubview:val];
    val.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;

    // 🔴 v2.0.66.119: 滑块一律【自建 UISlider】, 不再复用 PSSliderCell 的原生滑块。
    //    .118 实机: 即便把原生滑块摘进 contentView 摆好, 它随后仍被 PSSliderCell 自己的
    //    布局/容器接管(摘走或藏掉) → 行里只剩标题+数值。自建的它动不了。
    //    拖动经 mk_ownSliderChanged: 转发给原生滑块 → 持久化/通知/头图预览零差异。
    UISlider *mine = [[UISlider alloc] initWithFrame:CGRectZero];
    mine.tag = 8614;
    mine.minimumValue = slider.minimumValue;
    mine.maximumValue = slider.maximumValue;
    mine.value        = slider.value;
    mine.continuous   = slider.continuous;
    [mine addTarget:owner action:@selector(mk_ownSliderChanged:)
   forControlEvents:UIControlEventValueChanged];
    mine.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [cell.contentView addSubview:mine];

    // 原生滑块: 摘下来并藏死, 防止它的布局把它递回来造成重复
    [slider removeFromSuperview];
    slider.hidden = YES;
    cell.accessoryView = nil;

    // 已填充轨道用 tintColor, 未填充轨道淡灰; 保留系统默认大圆钮
    mine.minimumTrackTintColor = [UIColor systemBlueColor];
    mine.maximumTrackTintColor = [[UIColor systemFillColor] colorWithAlphaComponent:0.35f];

    // ⚠️ 坐标一律走自适应函数, 不写死 —— 行高没抬起来时退化为单行, 滑块绝不越界。
    MKApplyBigSliderFrames(cell, mine, val, title);

    return YES;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    // ⚠️ 关键修复 v1.6.15：iOS 16 的 PSListController 很可能【未实现】
    //   tableView:willDisplayCell:forRowAtIndexPath:，无条件 [super ...] 会抛
    //   unrecognized selector → 整个设置 App 闪退（进本页即崩，其他页正常）。
    //   仅当父类确实实现该方法时才调 super；同时整段 @try 兜底，绝不外抛异常。
    if ([[self superclass] instancesRespondToSelector:_cmd]) {
        @try {
            [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
        } @catch (NSException *e) {}
    }
    @try {
        cell.backgroundColor = [UIColor clearColor];

        // 同 section 里一共有几行数据（PSGroupCell 是 header/footer，不占 row）
        NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
        BOOL isFirst = (indexPath.row == 0);
        BOOL isLast  = (indexPath.row == rows - 1);

        // 玻璃卡片：半透明 + 柔和阴影
        UIView *bg = [[UIView alloc] init];
        if (@available(iOS 13.0, *)) {
            bg.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:kCardAlpha];
        } else {
            bg.backgroundColor = [UIColor colorWithWhite:1.0f alpha:kCardAlpha];
        }
        bg.layer.masksToBounds = NO;
        bg.layer.shadowColor   = [UIColor blackColor].CGColor;
        bg.layer.shadowOpacity = 0.05f;
        bg.layer.shadowOffset  = CGSizeMake(0, 2.0f);
        bg.layer.shadowRadius  = 8.0f;

        // 按 section 内位置决定圆角：首行只圆上角，末行只圆下角，中间行不圆角，
        // 这样多行分组的子设置拼成【同一张连续卡片】（整体性）。单行 group 则四角都圆。
        // ⚠️ 旧代码此处有 `if (corners == 0) corners = UIRectCornerAllCorners;`
        // 会把中间行也全圆角 → 中间行变成独立小卡片（如「文件夹图标」分组的中间分段控件），
        // 与上下行断开、失去整体性。中间行 corners 必须保持 0（不圆角、与相邻行拼合）。
        UIRectCorner corners = 0;
        if (rows == 1 || isFirst) {
            corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
        }
        if (rows == 1 || isLast) {
            corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
        }

        if (@available(iOS 11.0, *)) {
            bg.layer.maskedCorners = (CACornerMask)corners;
            bg.layer.cornerRadius = kCardRadius;
        } else {
            // iOS 11 以下退化：整组圆角，仍可用
            bg.layer.cornerRadius = kCardRadius;
        }

        // 非末行加底部分隔线，让同 section 多行看起来像一张卡片内的多行
        if (!isLast) {
            UIView *sep = [[UIView alloc] init];
            if (@available(iOS 13.0, *)) {
                sep.backgroundColor = [[UIColor separatorColor] colorWithAlphaComponent:0.30f];
            } else {
                sep.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.08f];
            }
            // 初始按 44pt 标准 cell 高 + 320pt 宽，靠 autoresizing 适配真实尺寸
            sep.frame = CGRectMake(16.0f, 43.5f, 288.0f, 0.5f);
            sep.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
            sep.tag = 8612; // v2.0.66.117: 挂到 backgroundView 之后按真实行高重贴一次
            [bg addSubview:sep];
        }

        cell.backgroundView = bg;

        // v2.0.66.117: 行高涨到 78 后, 写死 y=43.5 的分隔线会停在行的【中间】。
        //   backgroundView 挂上去后 UIKit 才会把它的 frame 设成 cell.bounds —— 所以必须
        //   在这之后按真实高度贴底, 不能只靠 autoresizing(初始 bounds 是 CGRectZero, 换算会漂)。
        for (UIView *s in [bg subviews]) {
            if (s.tag != 8612) continue;
            CGFloat bh = bg.bounds.size.height;
            if (bh <= 0.0f) bh = cell.bounds.size.height;
            if (bh <= 0.0f) bh = 44.0f;
            CGFloat bw = bg.bounds.size.width;
            if (bw <= 0.0f) bw = 320.0f;
            s.frame = CGRectMake(16.0f, bh - 0.5f, bw - 32.0f, 0.5f);
        }

        // label 背景透明，文字才浮在玻璃上
        cell.textLabel.backgroundColor       = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];

        // v2.0.66.86: 按当前「显示位置」模式置灰无关控件, 让用户一眼看出哪些项对本模式无作用。
        // specifier 从 cell 自带的 -specifier (PSTableCell 属性) 取; 拿不到就不做灰化,
        // 绝不影响原有视觉逻辑。
        PSSpecifier *spec = nil;
        if ([cell respondsToSelector:@selector(specifier)]) {
            id s = [(NSObject *)cell specifier];
            if ([s isKindOfClass:[PSSpecifier class]]) spec = (PSSpecifier *)s;
        }
        NSString *rowKey = spec ? [spec propertyForKey:@"key"] : nil;
        // v2.0.66.116: 滑块行改造成大号两行卡片(标题/数值/通栏滑块三层)。
        //   放在灰化判定【之前】—— 灰化只改 userInteractionEnabled + alpha, 与布局正交。
        if (spec) {
            // 先清掉上一次布局可能残留的自建视图(cell 复用), 再重建 ——
            //   顺序反了会把刚建好的那个也删掉。(8611=数值, 8613=标题, 8614=自建滑块)
            for (UIView *v in [cell.contentView subviews]) {
                if (v.tag == 8611 || v.tag == 8613 || v.tag == 8614) [v removeFromSuperview];
            }
            if (MKLayoutBigSliderCell(self, cell, spec)) {
                // v2.0.66.117: 行高走【逐行回调 + 缓存】, 不再碰全局 rowHeight。
                //   首帧 super 可能仍返 44(即它没读 specifier 的 height 属性) → 记下
                //   「本行=滑块, 要 78」, 再让 tableView 重算一次高度
                //   (空 beginUpdates/endUpdates 即触发重查)。缓存命中后不再触发, 不会自激循环。
                if (!self.rowHeights) self.rowHeights = [NSMutableDictionary dictionary];
                if (![self.rowHeights objectForKey:indexPath]) {
                    [self.rowHeights setObject:[NSNumber numberWithFloat:78.0f] forKey:indexPath];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            [tableView beginUpdates];
                            [tableView endUpdates];
                        } @catch (NSException *e) {}
                    });
                }
                // v2.0.66.119: 行高变化后(44→78)再贴一次坐标, 让滑块从紧凑行切换到通栏。
                //   自建滑块(tag 8614)谁也动不了, 这里纯粹是几何刷新。
                UISlider *sl = nil;
                for (UIView *v in [cell.contentView subviews]) {
                    if (v.tag == 8614 && [v isKindOfClass:[UISlider class]]) sl = (UISlider *)v;
                }
                if (sl) {
                    UITableViewCell *theCell = cell;
                    UISlider *theSlider = sl;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            if (theSlider.superview != theCell.contentView) return;
                            UILabel *v = nil, *t = nil;
                            for (UIView *sub in [theCell.contentView subviews]) {
                                if (![sub isKindOfClass:[UILabel class]]) continue;
                                if (sub.tag == 8611) v = (UILabel *)sub;
                                else if (sub.tag == 8613) t = (UILabel *)sub;
                            }
                            MKApplyBigSliderFrames(theCell, theSlider, v, t);
                        } @catch (NSException *e) {}
                    });
                }
            }
        }
        // v2.0.66.93: 无 key 的行 = 操作按钮(PSButtonCell「恢复默认 / 注销」)。
        //   MKApplyDimmed(cell, NO) 会把 textLabel.textColor 强写成 labelColor,
        //   把按钮文字画成普通黑字, 失去「这是可点操作」的视觉线索(PSButtonCell 本应用 tintColor)。
        //   故这类行【整段跳过灰化逻辑】, 保留系统默认外观。
        //   现有 16 个偏好行全部带 key, 此分支对它们无影响。
        if (rowKey != nil) {
            BOOL dimmed = MKKeyDisabledForAnyMode(rowKey);
            MKApplyDimmed(cell, dimmed);
            // v2.0.66.119: 自建标题/数值/滑块不在 -control 链路上, 灰化要单独跟上,
            //   否则滑块已半透明而标题仍是全黑, 视觉上不成一组。
            for (UIView *v in [cell.contentView subviews]) {
                if (v.tag == 8611 || v.tag == 8613) v.alpha = dimmed ? 0.40f : 1.0f;
                if (v.tag == 8614 && [v isKindOfClass:[UIControl class]]) {
                    UIControl *c = (UIControl *)v;
                    c.enabled = !dimmed;
                    c.alpha   = dimmed ? 0.40f : 1.0f;
                }
            }
        }

        // v2.0.24: folderIndicatorMode 选择已移除，代表 App 固定为位置靠前活跃（原 mode 0）。
    } @catch (NSException *e) {}
}

#pragma mark - 操作按钮 (v2.0.66.93)

// 广播「配置已变」通知 + 刷新头图预览。setPreferenceValue: 与恢复默认共用。
- (void)mk_postReloadAndRefresh {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kReloadNotification,
        NULL, NULL, TRUE);
    [self refreshHero];
}

// 「恢复默认设置」—— 二次确认后删除本域全部键, 让读取侧回落到默认值。
// ⚠️ 必须 reloadSpecifiers 而不是只 reloadSpecifier: 所有行的显示值都变了,
//    且 locationMode 归零会让置灰集合整体反转(见 MKKeyDisabledForMode)。
- (void)mkResetDefaults:(PSSpecifier *)specifier {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"恢复默认设置"
                         message:@"将把本插件的全部选项恢复为出厂默认值（形状、颜色、尺寸、位置模式、角标参数等）。此操作不可撤销。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"恢复默认"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *a) {
        @try {
            for (NSString *k in MKAllPrefKeys()) {
                CFPreferencesSetValue((__bridge CFStringRef)k, NULL,
                                      (__bridge CFStringRef)kPrefsDomain,
                                      kCFPreferencesCurrentUser,
                                      kCFPreferencesAnyHost);
            }
            CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
            [self reloadSpecifiers];
            [self mk_postReloadAndRefresh];
        } @catch (NSException *e) {}
    }]];
    @try { [self presentViewController:ac animated:YES completion:nil]; } @catch (NSException *e) {}
}

// 「注销 SpringBoard」—— 设置 App 自己没权限杀 SpringBoard, 只发 Darwin 通知,
// 由注入在 SpringBoard 内的 dylib 收到后 exit(0)(launchd 负责重启)。
// 若插件未加载/被紧急开关关掉, 通知无人接收 → 什么也不会发生, 不会崩、不会卡。
- (void)mkRespring:(PSSpecifier *)specifier {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"注销 SpringBoard"
                         message:@"桌面将立即重启，未保存的界面状态会丢失。正常情况下修改设置无需注销。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"注销"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *a) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)kRespringNotification,
            NULL, NULL, TRUE);
    }]];
    @try { [self presentViewController:ac animated:YES completion:nil]; } @catch (NSException *e) {}
}

#pragma mark - 拦截写值

// 拦截写值: 先写偏好, 再广播通知让 Tweak 实时刷新
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)value,
                              (__bridge CFStringRef)kPrefsDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
    }
    // 同步刷新界面显示
    // v2.0.66.84: 连续滑块（badgeThickness/badgeInset 等 isContinuous）在拖动中每 tick 都会
    //   进来一次，此时 reloadSpecifier 会重建 cell → 滑块被打断/回弹，无法平滑拖动。
    //   故仅对非滑块 cell 做 reload；滑块靠头图实时预览反馈即可。
    NSString *cellCls = [specifier propertyForKey:@"cell"];
    BOOL isSlider = (cellCls && [cellCls rangeOfString:@"Slider"].location != NSNotFound);
    if (!isSlider) {
        [self reloadSpecifier:specifier animated:YES];
    }

    // v2.0.66.86: 切换「显示位置」模式 → 整表重载, 让 willDisplayCell: 重新按新模式
    //   计算灰化状态 (仅 reloadSpecifier 只刷本行, 其他行的灰/亮不会跟着变)。
    if ([key isEqualToString:@"locationMode"] || [key isEqualToString:@"locationModeHome"]
        || [key isEqualToString:@"locationModeDock"] || [key isEqualToString:@"locationModeFolder"]) {
        @try { [self reloadSpecifiers]; } @catch (NSException *e) {}
    }

    // 广播 Darwin 通知 + 头图实时预览同步刷新
    [self mk_postReloadAndRefresh];
}

// 颜色选择等需要返回当前值的 cell
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPrefsDomain);
    if (v) {
        id result = (__bridge_transfer id)v;
        return result;
    }
    return [specifier propertyForKey:@"default"];
}

@end
