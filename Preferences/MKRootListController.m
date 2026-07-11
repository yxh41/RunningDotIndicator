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
static const CGFloat kHeroHeight = 128.0f;
static const CGFloat kHeroPad    = 16.0f;
static const CGFloat kCardRadius = 12.0f;
static const CGFloat kCardAlpha  = 0.60f; // 卡片半透明 → 透出毛玻璃背景

@interface MKRootListController ()
@property (nonatomic, strong) UIView   *heroView;        // 顶部玻璃头图
@property (nonatomic, strong) UIView   *previewIcon;     // 头图里的模拟 App 图标
@property (nonatomic, strong) UIView   *previewGlyph;    // 图标内白色 glyph
@property (nonatomic, strong) UIView   *previewIndicator;// 实时预览指示点/横条
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

// 读取偏好值，缺失时返回默认值
- (id)readValueForKey:(NSString *)key default:(id)def {
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPrefsDomain);
    if (v) {
        return (__bridge_transfer id)v;
    }
    return def;
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

        // 模拟 App 图标(圆角方块，强调色填充)
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(kHeroPad, 28, 56, 56)];
        icon.layer.cornerRadius = 13;
        icon.layer.masksToBounds = YES;
        [content addSubview:icon];

        // 图标内白色 glyph
        UIView *glyph = [[UIView alloc] initWithFrame:CGRectMake(16, 16, 24, 24)];
        glyph.backgroundColor = [UIColor whiteColor];
        glyph.layer.cornerRadius = 6;
        glyph.layer.masksToBounds = YES;
        [icon addSubview:glyph];

        // 标题行
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        if (@available(iOS 13.0, *)) title.textColor = [UIColor labelColor];
        else title.textColor = [UIColor blackColor];
        [content addSubview:title];

        // 副标题
        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectZero];
        cap.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        if (@available(iOS 13.0, *)) cap.textColor = [UIColor secondaryLabelColor];
        else cap.textColor = [UIColor grayColor];
        [content addSubview:cap];

        // 实时预览指示点/横条(位置在图标右侧，模拟主屏)
        UIView *ind = [[UIView alloc] initWithFrame:CGRectZero];
        ind.layer.masksToBounds = YES;
        [content addSubview:ind];

        self.heroView          = hero;
        self.previewIcon        = icon;
        self.previewGlyph       = glyph;
        self.previewTitle       = title;
        self.previewCaption     = cap;
        self.previewIndicator   = ind;
    } @catch (NSException *e) {
        self.heroView = nil;
    }
}

// 根据当前配置重算预览指示点的位置/尺寸/圆角
- (void)updateIndicatorFrame {
    if (!self.previewIndicator || !self.previewIcon) return;
    NSInteger shape = [[self readValueForKey:@"shape" default:@0] integerValue];
    CGFloat dot = [[self readValueForKey:@"dotSize"  default:@6]  floatValue];
    CGFloat bw  = [[self readValueForKey:@"barWidth"  default:@24] floatValue];
    CGFloat bh  = [[self readValueForKey:@"barHeight" default:@4]  floatValue];

    CGFloat ix = CGRectGetMaxX(self.previewIcon.frame) + 4.0f;
    CGFloat iy = CGRectGetMidY(self.previewIcon.frame);

    CGFloat w, h;
    if (shape == 1) {                 // 横条
        w = MAX(bw * 0.7f, 12.0f);
        h = MAX(bh * 1.5f, 4.0f);
    } else {                           // 圆点
        CGFloat side = MAX(dot * 1.6f, 6.0f);
        w = side; h = side;
    }
    self.previewIndicator.frame = CGRectMake(ix, iy - h / 2.0f, w, h);
    self.previewIndicator.layer.cornerRadius = h / 2.0f;
}

// 头图内子视图按当前宽度排版
- (void)layoutHero {
    if (!self.heroView) return;
    CGFloat W = self.heroView.bounds.size.width;
    if (W < 1) W = (self.view.bounds.size.width > 0) ? self.view.bounds.size.width : 320.0f;

    CGFloat leftW = kHeroPad + 56.0f + 16.0f; // 图标 + 间距
    CGRect t1 = CGRectMake(leftW, 34, W - leftW - kHeroPad, 20);
    CGRect t2 = CGRectMake(leftW, 58, W - leftW - kHeroPad, 16);
    self.previewTitle.frame   = t1;
    self.previewCaption.frame = t2;
    [self updateIndicatorFrame];
}

// 刷新头图：读取当前设置 → 重绘预览 + 强调色联动
- (void)refreshHero {
    @try {
        [self ensureHero];
        if (!self.heroView) return;

        NSString *custom = [self readValueForKey:@"customColor" default:@""];
        NSString *hex = (custom && custom.length > 0)
            ? custom
            : [self readValueForKey:@"color" default:@"#34C759"];
        UIColor *col = MKColorFromHex(hex) ?: [UIColor systemGreenColor];
        NSInteger mode = [[self readValueForKey:@"colorMode" default:@0] integerValue];
        CGFloat opacity = [[self readValueForKey:@"opacity" default:@1.0f] floatValue];

        // 预览指示点 = 当前生效色
        self.previewIndicator.backgroundColor = col;
        self.previewIndicator.alpha = opacity;
        // 图标也用强调色，整体更协调
        self.previewIcon.backgroundColor = col;

        if (mode == 1) {
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

#pragma mark - 玻璃卡片(每组一行圆角半透明)

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

        UIView *bg = [[UIView alloc] init];
        if (@available(iOS 13.0, *)) {
            bg.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:kCardAlpha];
            bg.layer.borderColor = [[UIColor separatorColor] colorWithAlphaComponent:0.30f].CGColor;
        } else {
            bg.backgroundColor = [UIColor colorWithWhite:1.0f alpha:kCardAlpha];
            bg.layer.borderColor = [UIColor colorWithWhite:0.6f alpha:0.3f].CGColor;
        }
        bg.layer.borderWidth  = 0.5f;
        bg.layer.cornerRadius = kCardRadius;
        bg.layer.masksToBounds = YES;
        cell.backgroundView = bg;

        // label 背景透明，文字才浮在玻璃上
        cell.textLabel.backgroundColor       = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
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
    [self reloadSpecifier:specifier animated:YES];

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
