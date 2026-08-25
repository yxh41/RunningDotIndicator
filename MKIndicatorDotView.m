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

    // v2.0.66.87: 角标模式 —— 沿图标【真·连续圆角】(Apple continuous corner / squircle) 画单角弧。
    //
    // ⚠️ 推翻 .82 的两个错误实现（均已数值验证，60pt 图标 rc=13.422pt 为基准）：
    //  ① .82 用「单段三次贝塞尔 k=0.528」称作 squircle —— 它与真·四分之一圆弧(k=0.5523)
    //     最大只差 0.17pt，本质就是圆弧，与 squircle 的曲率分布毫无关系。
    //     Apple 连续圆角每角实为【3 段】：cubic(入弯, 曲率 0→1/R) + 真圆弧(仅扫 90°(1-s)=42.42°)
    //     + cubic(出弯, 曲率 1/R→0)。曲率连续(G2)是「看得出不一样」的感知根源；
    //     普通圆角在直边→圆弧接点处曲率从 0 跳到 1/r(G1)。
    //  ② .82 端点跨度用 rc —— 真实圆角段沿边延伸 p=(1+s)*rc=1.528665*rc，
    //     用 rc 只覆盖 65.4%，弧线两头提前离开圆角、翘到直边上。
    //
    // inset 也一并改正：.82 沿 45° 对角平移 inset/√2 → 各点离图标轮廓不等距
    // (inset=12 档 min 10.08 / max 11.63，差 1.555pt，且系统性小于设定值)。
    // 现改用【同心圆角规则】(Apple 官方嵌套圆角规则)：外框 = CGRectInset(icon, -D, -D)、
    // 外圆角 = rc + D → 数学上保证外轮廓处处离图标轮廓恰好 D，且外轮廓仍是同族连续圆角。
    // 实测不均匀度 D=12 仅 0.117pt（采样离散残留，非几何误差）。
    //
    // frame 已四周各扩 MKBadgeFrameExtra(15pt)；外框原点在 icon 坐标 (-D,-D)
    // → 在 view 坐标即 (extra-D, extra-D)。向外位移上限 12 + 半线宽 3 = 15 恰好不裁。
    if (cfg.locationMode == MKLocationBadge) {
        CGFloat t = cfg.badgeThickness;
        CGFloat inset = cfg.badgeInset;
        if (inset < 0) inset = 0;
        // v2.0.66.83: frame 四周各扩了 MKBadgeFrameExtra，W/H 必须扣掉扩边换算回图标实际尺寸
        CGFloat W = rect.size.width  - 2 * MKBadgeFrameExtra;
        CGFloat H = rect.size.height - 2 * MKBadgeFrameExtra;
        if (W < 1) W = rect.size.width;
        if (H < 1) H = rect.size.height;
        CGFloat rc = self.iconCornerRadius;
        if (rc <= 0) rc = MIN(W, H) * 0.2237f;   // 连续圆角等效半径 ≈ 边长 22.37%

        // ── 同心外扩：外框尺寸与外圆角半径 ──
        CGFloat OW = W + 2 * inset;
        CGFloat OH = H + 2 * inset;
        CGFloat R  = rc + inset;

        // corner smoothing。s=0.528665 = iOS 图标轮廓的等效平滑度(Figma/squircle-js cornerSmoothing)
        const CGFloat kS = 0.528665;
        // 跨度钳位：p 不得超过外框半边，否则两端越过中点自相交（极小图标保险；
        // 迷你缩略图已由 MKBadgeBaseView 判废，此处纯兜底）。钳 R 而非钳 p，保证形状自洽。
        CGFloat halfMin = MIN(OW, OH) * 0.5f;
        if (halfMin > 0 && R * (1.0 + kS) > halfMin) R = halfMin / (1.0 + kS);
        if (R <= 0) return;

        // ── 连续圆角构造参数（figma-squircle 同款，全部与 R 成正比）──
        // 注意用 double 版 sin/cos/tan/atan2：arm64 上 CGFloat = double，
        // 用 sinf/tanf 会先窄化成 float 再算，白丢精度（且 -Wconversion 下可能报警）。
        CGFloat p      = (1.0 + kS) * R;                        // 沿边总跨度 = 1.528665 R
        CGFloat arcM   = (CGFloat)M_PI_2 * (1.0 - kS);          // 中段真圆弧圆心角 = 42.420°
        CGFloat arcSec = sin(arcM * 0.5) * R * (CGFloat)M_SQRT2;
        CGFloat alpha  = ((CGFloat)M_PI_2 - arcM) * 0.5;
        CGFloat beta   = (CGFloat)M_PI_4 * kS;
        CGFloat c      = R * tan(beta * 0.5) * cos(alpha);
        CGFloat d      = c * tan(alpha);
        CGFloat b      = (p - arcSec - c - d) / 3.0;
        CGFloat a      = 2.0 * b;
        CGFloat mid    = p - a - b - c;   // 入弯 cubic 终点(= 圆弧起点)的沿边坐标

        // ── 左上角基准路径（外框局部坐标，原点 = 外框左上角）──
        // 其余三角由镜像变换得到，避免手写四份镜像坐标出错（.81 strncmp 死码同类教训）
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(0, p)];
        [path addCurveToPoint:CGPointMake(d, mid)
                controlPoint1:CGPointMake(0, p - a)
                controlPoint2:CGPointMake(0, p - a - b)];
        // 圆心 (R,R)；起点 (d,mid)、终点 (mid,d) 均在半径 R 上。UIKit 为 y-down 坐标系，
        // clockwise:YES = 角度递增方向，与 atan2 计算出的 a0<a1 一致。
        CGFloat a0 = atan2(mid - R, d - R);
        CGFloat a1 = atan2(d - R, mid - R);
        [path addArcWithCenter:CGPointMake(R, R) radius:R startAngle:a0 endAngle:a1 clockwise:YES];
        [path addCurveToPoint:CGPointMake(p, 0)
                controlPoint1:CGPointMake(p - a - b, 0)
                controlPoint2:CGPointMake(p - a, 0)];

        switch (self.badgeCorner) {
            case MKBadgeCornerTopLeft:
                break;                                                   // 基准，无需变换
            case MKBadgeCornerTopRight:
                [path applyTransform:CGAffineTransformMake(-1, 0, 0,  1, OW,  0)];  // 镜像 x
                break;
            case MKBadgeCornerBottomLeft:
                [path applyTransform:CGAffineTransformMake( 1, 0, 0, -1,  0, OH)];  // 镜像 y
                break;
            default /*BottomRight*/:
                [path applyTransform:CGAffineTransformMake(-1, 0, 0, -1, OW, OH)];  // 镜像 x+y
                break;
        }

        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) return;
        // 外框原点在 icon 坐标 (-inset,-inset)；icon 原点在 view 坐标 (extra,extra)
        CGContextTranslateCTM(ctx, MKBadgeFrameExtra - inset, MKBadgeFrameExtra - inset);

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
