//
//  MKIndicatorDotView.m
//  RunningDotIndicator
//
//  v1.4.8: 简化为圆点和横条两种形状，Lynx2 风格
//

#import "MKIndicatorDotView.h"
#import <math.h>

// v2.0.66.82: 见 MKIndicatorDotView.h 声明
const CGFloat MKBadgeFrameExtra = 15.0f;

@implementation MKIndicatorDotView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)applyConfig {
    MKConfig *cfg = [MKConfig sharedConfig];
    self.alpha = cfg.opacity;
    [self setNeedsDisplay];
}

+ (Class)layerClass {
    return [CALayer class];
}

- (void)drawRect:(CGRect)rect {
    MKConfig *cfg = [MKConfig sharedConfig];
    UIColor *color = self.indicatorColor ?: cfg.color;

    // v2.0.66.82: 角标模式 —— 沿图标 squircle 1/4 弧（三次贝塞尔，完全贴图标圆角曲率）
    // inset 改为整体往所选角落方向平移（√2/2 归一化），形状保持 squircle 不变形
    // frame 已扩 kBadgeFrameExtra(15pt) 四周，drawRect 内先平移 (extra, extra) 到 icon 坐标系
    if (cfg.locationMode == MKLocationBadge) {
        CGFloat t = cfg.badgeThickness;
        CGFloat inset = cfg.badgeInset;
        CGFloat rc = self.iconCornerRadius;
        if (rc <= 0) rc = MIN(rect.size.width, rect.size.height) * 0.225f;
        CGFloat W = rect.size.width, H = rect.size.height;
        // inset=0: 弧线沿 squircle 内沿 (端点 (extra, extra+rc) 等, 完全贴图标圆角曲率)
        // inset>0: 沿角落单位向量外移，形状保持 (恒为 squircle 1/4，不会因 R 增大变形/出 frame)
        CGFloat s = inset * 0.70710678f;  // 1/√2
        CGFloat tx = 0, ty = 0;
        switch (self.badgeCorner) {
            case MKBadgeCornerTopLeft:     tx =  -s; ty =  -s; break;
            case MKBadgeCornerTopRight:    tx =   s; ty =  -s; break;
            case MKBadgeCornerBottomLeft:  tx =  -s; ty =   s; break;
            default /*BottomRight*/:       tx =   s; ty =   s; break;
        }
        // 先平移 (extra, extra) 到 icon 坐标系，再平移 (tx, ty) 到角落外
        // 整合为 (kBadgeFrameExtra + tx, kBadgeFrameExtra + ty)
        // 端点用 icon 坐标系 (0,rc)/(rc,0) 等
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) return;
        CGContextTranslateCTM(ctx, kBadgeFrameExtra + tx, kBadgeFrameExtra + ty);

        // squircle 1/4 三次贝塞尔近似 (Apple continuous corner 控制点比例 0.528)
        CGFloat k = 0.528f;
        UIBezierPath *path = [UIBezierPath bezierPath];
        switch (self.badgeCorner) {
            case MKBadgeCornerTopLeft:
                [path moveToPoint:CGPointMake(0, rc)];
                [path addCurveToPoint:CGPointMake(rc, 0)
                        controlPoint1:CGPointMake(0, rc * (1 - k))
                        controlPoint2:CGPointMake(rc * k, 0)];
                break;
            case MKBadgeCornerTopRight:
                [path moveToPoint:CGPointMake(W - rc, 0)];
                [path addCurveToPoint:CGPointMake(W, rc)
                        controlPoint1:CGPointMake(W - rc * k, 0)
                        controlPoint2:CGPointMake(W, rc * (1 - k))];
                break;
            case MKBadgeCornerBottomLeft:
                [path moveToPoint:CGPointMake(rc, H)];
                [path addCurveToPoint:CGPointMake(0, H - rc)
                        controlPoint1:CGPointMake(rc * k, H)
                        controlPoint2:CGPointMake(0, H - rc * (1 - k))];
                break;
            default /*BottomRight*/:
                [path moveToPoint:CGPointMake(W, H - rc)];
                [path addCurveToPoint:CGPointMake(W - rc, H)
                        controlPoint1:CGPointMake(W, H - rc * (1 - k))
                        controlPoint2:CGPointMake(W - rc * k, H)];
                break;
        }
        [color setStroke];
        path.lineWidth = t;
        path.lineCapStyle = kCGLineCapRound;
        [path stroke];
        return;
    }

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetFillColorWithColor(ctx, color.CGColor);

    CGRect r = CGRectInset(rect, 0.5f, 0.5f);

    switch (cfg.shape) {
        case MKShapeDot:
            // 圆形指示点
            CGContextFillEllipseInRect(ctx, r);
            break;
        case MKShapeBar: {
            // 横条（pill 形状 — 圆角矩形）
            CGFloat cornerR = r.size.height / 2.0f;
            UIBezierPath *pillPath = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:cornerR];
            [color setFill];
            [pillPath fill];
            break;
        }
    }
}

@end
