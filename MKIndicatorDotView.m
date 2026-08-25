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

    // v2.0.66.90: 角标模式几何【回归 .82 方案】—— 用户实机对比「设置页实时预览 vs 桌面」
    // 后拍板选预览那一版(方案 B)。三版沿边跨度对照(60pt 图标, rc=13.422pt):
    //   · .82  单段三次贝塞尔 k=0.528，跨度 = rc      ≈ 13.4pt   ← 现行(用户选定)
    //   · .87  完整连续圆角 3 段，跨度 = 1.528665·R  ≈ 20.5pt   (实机「太长、两头拱上直边」)
    //   · .88  只留中段真圆弧，跨度 ≈ 0.512·R        ≈  6.9pt   (实机「太短、不如预览好看」)
    // 结论：.87 过长、.88 过短，.82 恰在中间且是用户唯一明确点名"更好"的那一版。
    //
    // ⚠️ 保留 .87 的数学结论备查，但【不再据此改动几何】：
    //   .82 的 k=0.528 与真·四分之一圆弧(k=0.5523)最大只差 0.17pt，本质是圆弧而非真 squircle；
    //   Apple 连续圆角每角实为 3 段(cubic 入弯 + 圆弧 + cubic 出弯)、曲率连续(G2)。
    //   即：.82 在数学上「不是真连续圆角」，但在 1~6pt 线宽、单角短弧的实际观感下
    //   这 0.17pt 差异不可见，而弧长长短是可见的 —— 观感优先于数学纯度，故按用户选择定稿。
    //   同理 inset 回归「沿 45° 对角平移 inset/√2」：它相对同心圆角规则有最大 1.555pt 的
    //   不等距(inset=12 档)，但形状恒定不变形，且与预览完全一致。
    //
    // frame 已四周各扩 MKBadgeFrameExtra(15pt)：最大外移 12/√2 = 8.49pt + 半线宽 3pt
    // = 11.49pt < 15pt，弧线圆头不会被裁。
    //
    // ⚠️ 本段与 Preferences/MKRootListController.m 的 updateBadgePreview 必须【逐字同构】
    //    (k / 跨度 rc / inset 对角平移三者)。改任一处务必同步另一处，否则预览又与桌面不一致
    //    —— .87/.88 只改桌面没改预览，就是这次「预览比桌面好看」问题的由来。
    if (cfg.locationMode == MKLocationBadge) {
        CGFloat t = cfg.badgeThickness;
        CGFloat inset = cfg.badgeInset;
        if (inset < 0) inset = 0; else if (inset > 12.0f) inset = 12.0f;
        // v2.0.66.83: frame 四周各扩了 MKBadgeFrameExtra，W/H 必须扣掉扩边换算回图标实际尺寸
        CGFloat W = rect.size.width  - 2 * MKBadgeFrameExtra;
        CGFloat H = rect.size.height - 2 * MKBadgeFrameExtra;
        if (W < 1) W = rect.size.width;
        if (H < 1) H = rect.size.height;
        CGFloat rc = self.iconCornerRadius;
        if (rc <= 0) rc = MIN(W, H) * 0.2237f;   // 连续圆角等效半径 ≈ 边长 22.37%
        // 钳位：弧线端点沿边跨度 rc 不得越过半边中点，否则两端自相交（极小图标兜底）
        CGFloat halfMin = MIN(W, H) * 0.5f;
        if (halfMin > 0 && rc > halfMin) rc = halfMin;
        if (rc <= 0) return;

        // inset：沿 45° 对角单位向量平移整段弧线（形状恒为原样，不随距离变形）
        CGFloat ss = inset * 0.70710678f;        // 1/√2
        // 图标原点在 view 坐标 = (extra, extra)，再按所选角落方向外移
        CGFloat ox = MKBadgeFrameExtra, oy = MKBadgeFrameExtra;
        switch (self.badgeCorner) {
            case MKBadgeCornerTopRight:    ox += ss; oy -= ss; break;
            case MKBadgeCornerBottomLeft:  ox -= ss; oy += ss; break;
            case MKBadgeCornerBottomRight: ox += ss; oy += ss; break;
            default /*TopLeft*/:           ox -= ss; oy -= ss; break;
        }

        const CGFloat k = 0.528f;
        UIBezierPath *path = [UIBezierPath bezierPath];
        switch (self.badgeCorner) {
            case MKBadgeCornerTopRight:
                [path moveToPoint:CGPointMake(ox + W - rc, oy)];
                [path addCurveToPoint:CGPointMake(ox + W, oy + rc)
                        controlPoint1:CGPointMake(ox + W - rc * k, oy)
                        controlPoint2:CGPointMake(ox + W, oy + rc * (1 - k))];
                break;
            case MKBadgeCornerBottomLeft:
                [path moveToPoint:CGPointMake(ox + rc, oy + H)];
                [path addCurveToPoint:CGPointMake(ox, oy + H - rc)
                        controlPoint1:CGPointMake(ox + rc * k, oy + H)
                        controlPoint2:CGPointMake(ox, oy + H - rc * (1 - k))];
                break;
            case MKBadgeCornerBottomRight:
                [path moveToPoint:CGPointMake(ox + W, oy + H - rc)];
                [path addCurveToPoint:CGPointMake(ox + W - rc, oy + H)
                        controlPoint1:CGPointMake(ox + W, oy + H - rc * (1 - k))
                        controlPoint2:CGPointMake(ox + W - rc * k, oy + H)];
                break;
            default /*TopLeft*/:
                [path moveToPoint:CGPointMake(ox, oy + rc)];
                [path addCurveToPoint:CGPointMake(ox + rc, oy)
                        controlPoint1:CGPointMake(ox, oy + rc * (1 - k))
                        controlPoint2:CGPointMake(ox + rc * k, oy)];
                break;
        }

        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) return;
        // 路径已直接算在 view 坐标系（ox/oy 内含 MKBadgeFrameExtra），无需再平移 CTM

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
