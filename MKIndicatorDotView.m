//
//  MKIndicatorDotView.m
//

#import "MKIndicatorDotView.h"

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
    UIColor *color = cfg.color;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetFillColorWithColor(ctx, color.CGColor);

    CGRect r = rect;
    // 给形状留一点边距, 避免贴边裁切
    CGFloat pad = 0.5f;
    r = CGRectInset(r, pad, pad);

    switch (cfg.shape) {
        case MKShapeCircle:
            CGContextFillEllipseInRect(ctx, r);
            break;
        case MKShapeSquare:
            CGContextFillRect(ctx, r);
            break;
        case MKShapeTriangle:
            [self fillTriangleInRect:ctx rect:r];
            break;
        case MKShapeDiamond:
            [self fillDiamondInRect:ctx rect:r];
            break;
        case MKShapeStar:
            [self fillStarInRect:ctx rect:r points:5 innerRatio:0.4f];
            break;
        case MKShapeHeart:
            [self fillHeartInRect:ctx rect:r];
            break;
    }
}

#pragma mark - 形状绘制

- (void)fillTriangleInRect:(CGContextRef)ctx rect:(CGRect)r {
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, CGRectGetMidX(r), CGRectGetMinY(r));
    CGContextAddLineToPoint(ctx, CGRectGetMaxX(r), CGRectGetMaxY(r));
    CGContextAddLineToPoint(ctx, CGRectGetMinX(r), CGRectGetMaxY(r));
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

- (void)fillDiamondInRect:(CGContextRef)ctx rect:(CGRect)r {
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, CGRectGetMidX(r), CGRectGetMinY(r));
    CGContextAddLineToPoint(ctx, CGRectGetMaxX(r), CGRectGetMidY(r));
    CGContextAddLineToPoint(ctx, CGRectGetMidX(r), CGRectGetMaxY(r));
    CGContextAddLineToPoint(ctx, CGRectGetMinX(r), CGRectGetMidY(r));
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

- (void)fillStarInRect:(CGContextRef)ctx rect:(CGRect)r
               points:(NSInteger)points innerRatio:(CGFloat)innerRatio {
    CGPoint center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat outer  = MIN(r.size.width, r.size.height) * 0.5f;
    CGFloat inner  = outer * innerRatio;

    CGContextBeginPath(ctx);
    for (NSInteger i = 0; i < points * 2; i++) {
        CGFloat radius = (i % 2 == 0) ? outer : inner;
        CGFloat angle = (CGFloat)(-M_PI / 2.0) + (CGFloat)i * (CGFloat)M_PI / (CGFloat)points;
        CGFloat x = center.x + radius * cosf(angle);
        CGFloat y = center.y + radius * sinf(angle);
        if (i == 0) CGContextMoveToPoint(ctx, x, y);
        else        CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

- (void)fillHeartInRect:(CGContextRef)ctx rect:(CGRect)r {
    CGFloat w = r.size.width;
    CGFloat h = r.size.height;
    CGFloat x = r.origin.x;
    CGFloat y = r.origin.y;

    CGContextBeginPath(ctx);
    // 两个上圆 + 下方尖角组成的心形
    CGFloat radius = w * 0.28f;
    CGContextAddArc(ctx, x + radius, y + radius + h * 0.06f,
                    radius, (CGFloat)M_PI, 0, 0);
    CGContextAddArc(ctx, x + w - radius, y + radius + h * 0.06f,
                    radius, (CGFloat)M_PI, 0, 0);
    CGContextAddLineToPoint(ctx, x + w * 0.5f, y + h);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
}

@end
