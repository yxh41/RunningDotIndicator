//
//  MKIndicatorDotView.h
//  RunningDotIndicator
//
//  v1.4.8: 简化为两种形状 — 圆点 (Dot) 和横条 (Bar/Pill)
//  位置固定：替换 App 名字标签区域
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"

@interface MKIndicatorDotView : UIView

// 根据当前 MKConfig 刷新外观(颜色/形状/不透明度)
- (void)applyConfig;

@end
