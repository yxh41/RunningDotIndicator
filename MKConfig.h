//
//  MKConfig.h
//  RunningDotIndicator
//
//  v1.4.8: 简化为 Lynx2 风格 — 只有两种形状（圆点/横条），固定替换 App 名字位置
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MKShape) {
    MKShapeDot   = 0,  // 圆点（经典 Lynx2 圆形指示器）
    MKShapeBar   = 1   // 横条（pill 形状，类似 Lynx2 条形指示器）
};

typedef NS_ENUM(NSInteger, MKColorMode) {
    MKColorModeFixed    = 0,  // 固定颜色（用户配置的 #RRGGBB）
    MKColorModeAutoIcon = 1   // 从图标取主色调(dominant color)（Lynx2 风格）
};

typedef NS_ENUM(NSInteger, MKLocationMode) {
    MKLocationReplace   = 0,  // 替换名称（原默认，藏名）
    MKLocationBadge     = 1,  // 角标模式：贴图标角落，不抢名字
    // v2.0.66.114: 底沿下划线 —— 指示器画在图标底沿与名称之间的窄缝里，名称保持可见。
    //   与角标模式同源(MKBadgeBaseView 几何基准)，同样【不写任何 label 属性】
    //   ⇒ 继承角标模式「零三顽疾」的结构性优势，但不必挤在角落。
    //   Dock 等无名称区容器自动降级为图标内右下角小圆点(见 Tweak.x MKIndicatorFrameInOverlay)。
    MKLocationUnderline = 2
};

typedef NS_ENUM(NSInteger, MKBadgeCorner) {
    MKBadgeCornerTopLeft     = 0,  // 左上（默认，避开系统通知 badge/小黄点）
    MKBadgeCornerTopRight    = 1,
    MKBadgeCornerBottomLeft  = 2,
    MKBadgeCornerBottomRight = 3
};

@interface MKConfig : NSObject

+ (instancetype)sharedConfig;

// 重新从磁盘读取偏好设置
- (void)reload;

@property (nonatomic, readonly) BOOL       enabled;        // 总开关, 默认 YES
@property (nonatomic, readonly) UIColor   *color;          // 指示器颜色, 默认 #34C759
@property (nonatomic, readonly) MKColorMode colorMode;     // 颜色模式, 默认 Fixed
@property (nonatomic, readonly) MKShape    shape;          // 形状, 默认 圆点
@property (nonatomic, readonly) CGFloat    dotSize;        // 圆点直径(pt), 默认 6
@property (nonatomic, readonly) CGFloat    barWidth;       // 横条宽度(pt), 默认 24
@property (nonatomic, readonly) CGFloat    barHeight;      // 横条高度(pt), 默认 4
@property (nonatomic, readonly) CGFloat    opacity;        // 不透明度, 默认 1.0
@property (nonatomic, readonly) BOOL       folderIndicators;   // 桌面文件夹是否显示指示器, 默认 YES
@property (nonatomic, readonly) BOOL       keepBetaDot;     // 是否保留运行中 TestFlight/beta App 的小黄点, 默认 YES

// 位置模式：替换名称 / 角标模式
// v2.0.66.121: 混搭模式 —— 主屏 / Dock / 文件夹 三个分区各持一个独立模式键。
//   locationMode 保留为「主屏模式」的兼容别名(旧 prefs / 脚本仍可读取), 其余两区用 locationModeDock / locationModeFolder。
@property (nonatomic, readonly) MKLocationMode locationMode;       // 默认 MKLocationReplace（= 主屏分区）
@property (nonatomic, readonly) MKLocationMode locationModeHome;   // 主屏 App 分区模式, 默认 MKLocationReplace
@property (nonatomic, readonly) MKLocationMode locationModeDock;   // Dock 分区模式, 默认 MKLocationReplace
@property (nonatomic, readonly) MKLocationMode locationModeFolder; // 文件夹分区模式, 默认 MKLocationReplace
@property (nonatomic, readonly) MKBadgeCorner   badgeCorner;   // 角标角落, 默认 左上
@property (nonatomic, readonly) CGFloat    badgeThickness; // 角标线条粗细(pt), 默认 4, 钳制 1-6, 支持小数
@property (nonatomic, readonly) CGFloat    badgeInset;     // 角标与图标距离(pt), 默认 0(内贴图标边角), 越大越向外, 钳制 0-12
// v2.0.66.91: 角标弧线长度【比例】—— 返回 0.60~1.00 的小数(plist 里存的是 60~100 的百分数, 已在 getter 内换算)。
// 语义: 沿原三次贝塞尔曲线【两端各裁掉 (1-f)/2】, 保留中段 f 比例。曲率完全不变 ->
// 弧线仍严丝合缝贴在图标圆角上, 只是变短; 绝不可用「缩小 rc」实现(那会改曲率并脱离图标轮廓)。
@property (nonatomic, readonly) CGFloat    badgeArcLength;

// v2.0.66.114: 底沿下划线专属几何 —— 三者共同描述「图标底沿与名称之间那条窄缝里的横线」。
// 之所以做成可调：真机窄缝实际宽度需实测(推断 2~4pt)，一次性做可调可终结「改死值→推包→再改」循环。
@property (nonatomic, readonly) CGFloat underlineWidthRatio;  // 横线宽 = 图标宽 × 此值，钳制 0.30~0.90，默认 0.55（plist 存百分数 30~90，此处已换算）
@property (nonatomic, readonly) CGFloat underlineThickness;   // 线粗(pt)，钳制 1~4，默认 2.0；<3 画直角、>=3 画 pill 圆角
@property (nonatomic, readonly) CGFloat underlineGap;         // 距图标底沿的间隙(pt)，钳制 0~4，默认 1.0

// 把 #RRGGBB / #RGB 解析为 UIColor
+ (UIColor *)colorFromHex:(NSString *)hex;

@end
