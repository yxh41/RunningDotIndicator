//
//  MKIndicatorDotView.h
//  RunningDotIndicator
//
//  v1.4.8: 简化为两种形状 — 圆点 (Dot) 和横条 (Bar/Pill)
//  位置固定：替换 App 名字标签区域
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"

// v2.0.66.82: 角标模式 indicator frame 四周扩展量 = max inset(12) + max half-thickness(3)
// Tweak.x(MKIndicatorFrameInOverlay) 和 MKIndicatorDotView.m(drawRect 平移) 共享
extern const CGFloat MKBadgeFrameExtra;

@interface MKIndicatorDotView : UIView

// 根据当前 MKConfig 刷新外观(颜色/形状/不透明度)
- (void)applyConfig;

// per-icon 颜色（AutoIcon 模式时覆盖 cfg.color）
@property (nonatomic, strong) UIColor *indicatorColor;

// v2.0.66.80: 角标模式参数
@property (nonatomic, assign) CGFloat iconCornerRadius;  // 图标图片真实圆角
@property (nonatomic, assign) MKBadgeCorner badgeCorner; // 角标所在角落

// v2.0.66.121: 混搭模式 —— 该指示器所属分区的模式, 绘制时取代全局 [MKConfig sharedConfig].locationMode
//   (同一桌面三种模式并存时, 每个指示器按自己分区的模式画: 替换=圆点/横条, 角标=弧线, 下划线=横线)。
@property (nonatomic, assign) MKLocationMode mkLocationMode;

@end
