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
    MKLocationReplace = 0,  // 替换名称（原默认）
    MKLocationBadge   = 1   // 角标模式：贴图标角落，不抢名字
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
@property (nonatomic, readonly) MKLocationMode locationMode;   // 默认 MKLocationReplace
@property (nonatomic, readonly) MKBadgeCorner   badgeCorner;   // 角标角落, 默认 左上
@property (nonatomic, readonly) CGFloat    badgeThickness; // 角标线条粗细(pt), 默认 4, 钳制 2-10
@property (nonatomic, readonly) CGFloat    badgeInset;     // 角标与图标内线距离(pt), 默认 0(贴合), 钳制 0-12

// 把 #RRGGBB / #RGB 解析为 UIColor
+ (UIColor *)colorFromHex:(NSString *)hex;

@end
