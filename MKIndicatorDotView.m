//
//  MKIndicatorDotView.m
//  RunningDotIndicator
//
//  v1.4.8: 简化为圆点和横条两种形状，Lynx2 风格
//

#import "MKIndicatorDotView.h"
#import <math.h>

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

    // v2.0.66.80: 角标模式 —— 画单角弧线（贴图标圆角内沿），提前 return
    if (cfg.locationMode == MKLocationBadge) {
        CGFloat t = cfg.badgeThickness;
        CGFloat inset = cfg.badgeInset;
        CGFloat rc = self.iconCornerRadius;
        if (rc <= 0) rc = MIN(rect.size.width, rect.size.height) * 0.225f;
        CGFloat R = rc - inset - t / 2.0f;
        if (R < t / 2.0f) R = t / 2.0f;
        CGFloat W = rect.size.width, H = rect.size.height;
        CGPoint c; CGFloat start, end; BOOL cw;
        switch (self.badgeCorner) {
            case MKBadgeCornerTopLeft:     c = CGPointMake(rc, rc);         start = -M_PI_2; end = -M_PI;   cw = NO;  break;
            case MKBadgeCornerTopRight:    c = CGPointMake(W - rc, rc);     start = -M_PI_2; end = 0.0f;   cw = YES; break;
            case MKBadgeCornerBottomLeft:  c = CGPointMake(rc, H - rc);     start = M_PI;   end = M_PI_2;  cw = NO;  break;
            default /*BottomRight*/:       c = CGPointMake(W - rc, H - rc); start = 0.0f;   end = M_PI_2;  cw = YES; break;
        }
        [color setStroke];
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:R startAngle:start endAngle:end clockwise:cw];
        arc.lineWidth = t;
        arc.lineCapStyle = kCGLineCapRound;
        [arc stroke];
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
