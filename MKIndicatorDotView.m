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

// v2.0.66.99: 与 Preferences/MKRootListController.m 的 kIconRadius(12.0f) / kIconSize(52.0f)
//   同构的圆角比例(12/52 ≈ 0.23077); 与 Tweak.x 的 MKBadgeCornerRatio 等价。
//   两个独立二进制不共享 static, 各留等价常量(同 MKLerpP/MKBezierSplit ↔ MKPvLerp/MKPvSplit)。
static const CGFloat MKDotCornerRatio = 12.0f / 60.0f;

// ─────────────────────────────────────────────────────────────────────────────
// v2.0.66.91: 三次贝塞尔【子曲线提取】(de Casteljau) —— 角标弧线长度调节的数学基础。
//
// 为什么不能用「缩小 rc」来缩短弧线:
//   rc 就是图标圆角半径, 改它 = 换成另一个曲率的弧 → 弧线不再贴合图标轮廓, 两端脱开。
// 正确做法: 保留同一条曲线, 只沿参数 t 截取中段 [t0, t1]。曲率逐点完全不变,
//   弧线仍严丝合缝贴在图标圆角上, 只是两头各短一点。
// de Casteljau 分割是精确的(不是近似采样): 子曲线仍是标准三次贝塞尔, 4 个新控制点闭式可得。
// ─────────────────────────────────────────────────────────────────────────────
static inline CGPoint MKLerpP(CGPoint a, CGPoint b, CGFloat t) {
    return CGPointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}

// 在参数 t 处把曲线一刀两断, 输出左半 L[4] 与右半 R[4](各自都是标准三次贝塞尔)。
static void MKBezierSplit(const CGPoint p[4], CGFloat t, CGPoint L[4], CGPoint R[4]) {
    CGPoint ab  = MKLerpP(p[0], p[1], t);
    CGPoint bc  = MKLerpP(p[1], p[2], t);
    CGPoint cd  = MKLerpP(p[2], p[3], t);
    CGPoint abc = MKLerpP(ab, bc, t);
    CGPoint bcd = MKLerpP(bc, cd, t);
    CGPoint m   = MKLerpP(abc, bcd, t);   // 曲线上 t 处的实际点
    L[0] = p[0]; L[1] = ab;  L[2] = abc; L[3] = m;
    R[0] = m;    R[1] = bcd; R[2] = cd;  R[3] = p[3];
}

// 取 [t0, t1] 段。做法: 先在 t1 断开取左半 → 再在 t0/t1(t0 映射到左半曲线的参数)断开取右半。
static void MKBezierSub(const CGPoint p[4], CGFloat t0, CGFloat t1, CGPoint out[4]) {
    if (t1 <= t0) { for (int i = 0; i < 4; i++) out[i] = p[0]; return; }
    CGPoint L[4], R[4];
    MKBezierSplit(p, t1, L, R);
    if (t0 <= 0.0f) { for (int i = 0; i < 4; i++) out[i] = L[i]; return; }
    CGPoint L2[4], R2[4];
    MKBezierSplit(L, t0 / t1, L2, R2);
    for (int i = 0; i < 4; i++) out[i] = R2[i];
}

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
    //    (k / 跨度 rc / inset 对角平移 / v2.0.66.91 起的弧长裁剪 四者)。改任一处务必同步另一处，
    //    否则预览又与桌面不一致 —— .87/.88 只改桌面没改预览，就是「预览比桌面好看」问题的由来。
    //
    // v2.0.66.91: 新增「角标弧线长度」滑块(badgeArcLength, 60%~100%, 默认 90%)。
    //   用户实机看过 .90 的 100% 后要求「再短 10%」—— 但这个参数已被反复推翻三次
    //   (.87 太长 / .88 太短 / .82 好 / 又要再短 10%), 说明它是纯审美变量、无客观正解,
    //   故一次性做成可调滑块并把默认设为 90, 终结「改死值 → 推送 → 装包 → 再改」的循环。
    //   实现是沿曲线两端等量裁剪(见 MKBezierSub), 曲率不变 → 依旧贴合图标圆角。
    if (cfg.locationMode == MKLocationBadge) {
        // v2.0.66.105: 线宽随预览同构缩放 52/60 —— 原不缩放会让桌面弧线比预览粗 15%, 显得"重、不贴"
        CGFloat t = cfg.badgeThickness * (52.0f / 60.0f);
        CGFloat inset = cfg.badgeInset;
        if (inset < 0) inset = 0; else if (inset > 12.0f) inset = 12.0f;
        // v2.0.66.83: frame 四周各扩了 MKBadgeFrameExtra，W/H 必须扣掉扩边换算回图标实际尺寸
        CGFloat W = rect.size.width  - 2 * MKBadgeFrameExtra;
        CGFloat H = rect.size.height - 2 * MKBadgeFrameExtra;
        if (W < 1) W = rect.size.width;
        if (H < 1) H = rect.size.height;
        CGFloat rc = self.iconCornerRadius;
        // v2.0.66.105: 兜底比例改 12/60(=0.2), 与 Tweak.x 的 MKBadgeCornerRatio、预览 kIconRadius=12
        //   绝对对齐。原 12/52 让 60pt 图标 rc≈13.85 比预览 rc=12 大 → 弧线更平; 0.2 使标准图标 rc=12 同曲率。
        if (rc <= 0) rc = MIN(W, H) * MKDotCornerRatio;
        // 钳位：弧线端点沿边跨度 rc 不得越过半边中点，否则两端自相交（极小图标兜底）
        CGFloat halfMin = MIN(W, H) * 0.5f;
        if (halfMin > 0 && rc > halfMin) rc = halfMin;
        if (rc <= 0) return;

        // inset：沿 45° 对角单位向量平移整段弧线（形状恒为原样，不随距离变形）
        // v2.0.66.105: inset 随预览同构缩放 52/60 —— 否则桌面比预览外移多 15%, 弧线"离开"角不够贴
        CGFloat ss = inset * (52.0f / 60.0f) * 0.70710678f;        // 1/√2
        // 图标原点在 view 坐标 = (extra, extra)，再按所选角落方向外移
        CGFloat ox = MKBadgeFrameExtra, oy = MKBadgeFrameExtra;
        switch (self.badgeCorner) {
            case MKBadgeCornerTopRight:    ox += ss; oy -= ss; break;
            case MKBadgeCornerBottomLeft:  ox -= ss; oy += ss; break;
            case MKBadgeCornerBottomRight: ox += ss; oy += ss; break;
            default /*TopLeft*/:           ox -= ss; oy -= ss; break;
        }

        const CGFloat k = 0.528f;
        // v2.0.66.91: 先把该角落的完整 1/4 弧写成 4 个控制点(p0=起点, p1/p2=控制, p3=终点),
        // 再按 badgeArcLength 沿曲线两端等量裁剪。原先四个 switch 分支直接 addCurve,
        // 无法插入裁剪 → 改为「先算控制点、后统一裁剪 + 统一入路径」。
        CGPoint cp[4];
        switch (self.badgeCorner) {
            case MKBadgeCornerTopRight:
                cp[0] = CGPointMake(ox + W - rc,     oy);
                cp[1] = CGPointMake(ox + W - rc * k, oy);
                cp[2] = CGPointMake(ox + W,          oy + rc * (1 - k));
                cp[3] = CGPointMake(ox + W,          oy + rc);
                break;
            case MKBadgeCornerBottomLeft:
                cp[0] = CGPointMake(ox + rc,     oy + H);
                cp[1] = CGPointMake(ox + rc * k, oy + H);
                cp[2] = CGPointMake(ox,          oy + H - rc * (1 - k));
                cp[3] = CGPointMake(ox,          oy + H - rc);
                break;
            case MKBadgeCornerBottomRight:
                cp[0] = CGPointMake(ox + W,          oy + H - rc);
                cp[1] = CGPointMake(ox + W,          oy + H - rc * (1 - k));
                cp[2] = CGPointMake(ox + W - rc * k, oy + H);
                cp[3] = CGPointMake(ox + W - rc,     oy + H);
                break;
            default /*TopLeft*/:
                cp[0] = CGPointMake(ox,          oy + rc);
                cp[1] = CGPointMake(ox,          oy + rc * (1 - k));
                cp[2] = CGPointMake(ox + rc * k, oy);
                cp[3] = CGPointMake(ox + rc,     oy);
                break;
        }

        // v2.0.66.91: 弧长比例 —— 保留中段 f, 两端各裁 (1-f)/2。f=1 时 t0=0/t1=1(恒等, 零开销差异)。
        CGFloat f = cfg.badgeArcLength;
        if (f < 0.60f) f = 0.60f; else if (f > 1.0f) f = 1.0f;
        if (f < 0.9999f) {
            CGFloat t0 = (1.0f - f) * 0.5f;
            CGPoint sub[4];
            MKBezierSub(cp, t0, 1.0f - t0, sub);
            for (int i = 0; i < 4; i++) cp[i] = sub[i];
        }

        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:cp[0]];
        [path addCurveToPoint:cp[3] controlPoint1:cp[1] controlPoint2:cp[2]];

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
