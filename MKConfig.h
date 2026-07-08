//
//  MKConfig.h
//  RunningDotIndicator
//
//  读取偏好设置的单例配置对象。
//  偏好设置文件: com.mk.runningdotindicatorprefs
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MKShape) {
    MKShapeCircle   = 0,
    MKShapeSquare   = 1,
    MKShapeTriangle = 2,
    MKShapeDiamond  = 3,
    MKShapeStar     = 4,
    MKShapeHeart    = 5
};

typedef NS_ENUM(NSInteger, MKPosition) {
    MKPositionLeft        = 0,  // 名称左侧
    MKPositionRight       = 1,  // 名称右侧
    MKPositionReplaceName = 2   // 替换名称(运行中时用指示点替代文字)
};

@interface MKConfig : NSObject

+ (instancetype)sharedConfig;

// 重新从磁盘读取偏好设置
- (void)reload;

@property (nonatomic, readonly) BOOL       enabled;        // 总开关, 默认 YES
@property (nonatomic, readonly) UIColor   *color;          // 指示点颜色, 默认 #34C759
@property (nonatomic, readonly) MKShape    shape;          // 形状, 默认 圆形
@property (nonatomic, readonly) CGFloat    size;           // 点尺寸(pt), 默认 6
@property (nonatomic, readonly) MKPosition position;       // 位置, 默认 名称左侧
@property (nonatomic, readonly) CGFloat    opacity;        // 不透明度, 默认 1.0

// 把 #RRGGBB / #RGB 解析为 UIColor
+ (UIColor *)colorFromHex:(NSString *)hex;

@end
