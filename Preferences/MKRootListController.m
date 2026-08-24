//
//  MKRootListController.m
//  设置页主控制器 —— 在原生 PSListController 外层做 2026 Liquid-Glass 视觉包装
//  所有 Root.plist 控件(开关/形状/滑块/颜色/不透明度)保持原样，仅做视觉美化
//

#import "MKRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>

// 偏好设置域名(与 Tweak 读取的文件一致)
static NSString * const kPrefsDomain = @"com.mk.runningdotindicatorprefs";
// 每次值变化时广播的 Darwin 通知名
static NSString * const kReloadNotification = @"com.mk.runningdotindicator.reload";

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
@end

@implementation MKRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
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
    NSInteger locMode = [[self readValueForKey:@"locationMode" default:@0 expectedClass:[NSNumber class]] integerValue];
    if (locMode == 1) {
        self.previewIndicator.hidden = YES;
        self.previewName.hidden      = NO;
        self.previewBadge.hidden     = NO;
        [self updateBadgePreview];
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
- (void)updateBadgePreview {
    if (!self.previewBadge || !self.previewIcon) return;

    NSInteger corner = [[self readValueForKey:@"badgeCorner" default:@0 expectedClass:[NSNumber class]] integerValue];
    CGFloat t = [[self readValueForKey:@"badgeThickness" default:@4.0f expectedClass:[NSNumber class]] floatValue];
    CGFloat inset = [[self readValueForKey:@"badgeInset" default:@0.0f expectedClass:[NSNumber class]] floatValue];
    if (t < 1.0f) t = 1.0f; else if (t > 6.0f) t = 6.0f;
    if (inset < 0.0f) inset = 0.0f; else if (inset > 12.0f) inset = 12.0f;

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
    UIBezierPath *p = [UIBezierPath bezierPath];
    switch (corner) {
        case 1:  // 右上
            [p moveToPoint:CGPointMake(ox + W - rc, oy)];
            [p addCurveToPoint:CGPointMake(ox + W, oy + rc)
                 controlPoint1:CGPointMake(ox + W - rc * k, oy)
                 controlPoint2:CGPointMake(ox + W, oy + rc * (1 - k))];
            break;
        case 2:  // 左下
            [p moveToPoint:CGPointMake(ox + rc, oy + H)];
            [p addCurveToPoint:CGPointMake(ox, oy + H - rc)
                 controlPoint1:CGPointMake(ox + rc * k, oy + H)
                 controlPoint2:CGPointMake(ox, oy + H - rc * (1 - k))];
            break;
        case 3:  // 右下
            [p moveToPoint:CGPointMake(ox + W, oy + H - rc)];
            [p addCurveToPoint:CGPointMake(ox + W - rc, oy + H)
                 controlPoint1:CGPointMake(ox + W, oy + H - rc * (1 - k))
                 controlPoint2:CGPointMake(ox + W - rc * k, oy + H)];
            break;
        default: // 左上
            [p moveToPoint:CGPointMake(ox, oy + rc)];
            [p addCurveToPoint:CGPointMake(ox + rc, oy)
                 controlPoint1:CGPointMake(ox, oy + rc * (1 - k))
                 controlPoint2:CGPointMake(ox + rc * k, oy)];
            break;
    }
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

        NSInteger locMode = [[self readValueForKey:@"locationMode" default:@0 expectedClass:[NSNumber class]] integerValue];
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

#pragma mark - 玻璃卡片（同 section 多行共用一张卡片）

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
            [bg addSubview:sep];
        }

        cell.backgroundView = bg;

        // label 背景透明，文字才浮在玻璃上
        cell.textLabel.backgroundColor       = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];

        // v2.0.24: folderIndicatorMode 选择已移除，代表 App 固定为位置靠前活跃（原 mode 0）。
    } @catch (NSException *e) {}
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

    // 广播 Darwin 通知
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kReloadNotification,
        NULL, NULL, TRUE);

    // 设置变化 → 头图实时预览同步刷新
    [self refreshHero];
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
