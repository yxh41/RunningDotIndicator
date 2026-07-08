//
//  MKIndicatorDotView.h
//  RunningDotIndicator
//
//  自绘指示点视图, 支持圆形/方形/三角形/菱形/五角星/心形。
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"

@interface MKIndicatorDotView : UIView

// 根据当前 MKConfig 刷新外观(颜色/形状/不透明度)
- (void)applyConfig;

@end
