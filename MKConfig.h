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
@property (nonatomic, readonly) BOOL       debugLog;       // 调试日志, 默认 NO；设置页「调试日志」开关(debugLog)优先，回退 /var/mobile/Documents/rd_debug 文件（临时兼容，稳定后移除）

// 把 #RRGGBB / #RGB 解析为 UIColor
+ (UIColor *)colorFromHex:(NSString *)hex;

@end
