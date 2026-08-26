//
//  Tweak.x — RunningDotIndicator v1.6.68
//  v1.6.67: 修复滑动重叠 + 文件夹内 App 名称消失（基于 rd_log(25) 真机日志定位）——
//           · 抽出 inFolder 检测为 MKIsIconInFolder()，layoutSubviews 也共享：
//             旧逻辑只有 MKUpdate 识别文件夹，layoutSubviews 没有保护，会把文件夹内
//             运行中 App 的 label 隐藏，造成"文件夹内看不到 App 名称"。
//           · MKIndicatorFrameInOverlay 改用传入的图标视图 iv，不再读取 sBidToIconView：
//             多页桌面中同一 bid 在不同页面有独立图标，注册表里存的是"最后一次
//             MKUpdate 的图标"，layoutSubviews 重定位时若拿错实例，会把指示器
//             漂到非当前页，与当前页名字形成"重叠/错位"。
//           · layoutSubviews 滚动期间不再直接 return，而是同步隐藏 label（不重定位），
//             解决滚动中系统恢复 label 导致的"指示器与名称重叠"。
//           · FOLDER CLOSE 刷新改为同步+异步双保险，进一步消除关闭动画中名称闪现。
//  v1.6.68: 修复「文件夹内 App 名称闪一下」（基于 rd_log(26) 真机日志定位）——
//           · 根因：MKIsIconInFolder 同时要求 sFolderOpen 且容器被识别成文件夹容器，
//             但文件夹打开动画的某一帧图标临时挂在裸 UIView 下、层级未组装，容器检测
//             误判成主屏/Dock（SBIconListView*/SBDock* 回退）→ inFolder 返回 NO →
//             走进"有指示器"分支隐藏 label，下一帧层级组装完才恢复 → 名称闪一下。
//           · 修复：在 layoutSubviews 与 MKUpdate 最顶部加 sFolderOpen 守卫——
//             只要文件夹开着，任何图标一律"显示 label、直接 return"，根本不碰 label/指示器。
//             文件夹浮层覆盖主屏，主屏图标即便 label 暂显也不可见；关闭时 FOLDER CLOSE
//             刷新会复位，从根上消除那一帧误判。
//  v1.6.66: 修复文件夹场景三处回归（基于 rd_log(24) 真机日志定位）——
//           · 重叠/文件夹内误建指示器：inFolder 检测从「祖先链爬 SBFolderView」
//             改为「sFolderOpen 时按容器类型判定」(主屏 SBIconScrollView / Dock SBDock* 之外即文件夹)。
//             旧逻辑在 iOS16 下因 SBFloatyFolderScrollView 祖先未必含 SBFolderView、
//             且打开动画早期图标临时挂 UIView 而漏判，导致文件夹内 App 被错误建桌面指示器。
//           · 文件夹内 App 名称消失：inFolder 分支不再 MKRemoveIndicatorForBid
//             （同一 bid 在主屏与文件夹是两个图标实例、共享 sBidToIndicator 唯一对象，
//              误删会丢失主屏指示器），改为只恢复名字。
//           · 关闭文件夹名称闪现：FOLDER CLOSE 时下一 runloop 立即刷新主屏 SBIconScrollView，
//             避免运行 App 名称在文件夹缩回后才被藏回而闪一下。
//  v1.6.64: 结构性修复「指示器乱飞 / 滚出屏幕消失」——指示器从被回收的 SBIconView 子视图
//           解耦到稳定的 overlay 层（挂在图标滚动容器上，按 bundleID 索引）。
//           · 图标滚出屏幕/被回收 → 指示器不再随 view 消失或漂到别的 App（彻底解决乱飞）。
//           · 容器滚动时 overlay 与图标同移，指示器自动跟随，无需逐帧重定位。
//           · 坐标用 convertRect:toView:overlay（transform/滚动偏移安全），一并修复「位置歪」。
//           · 新增 sBidToIndicator / sContainerToOverlay / kMKIndicatorContainerKey 及配套 helpers。
//  v1.6.28: 重加宽松 iOS 版本守卫（只挡 iOS 15 及更低，16.0+ 均挂钩）；
//           修复「部分 App 指示器偶尔消失、桌面滑动才回来」——layoutSubviews 加孤儿自愈
//           （指示器存在但 superview==nil 时立即 MKUpdate 重建，不等滚动触发）。
//  v1.6.27: 移除 v1.6.24 加的 iOS 16.3-16.5.1 版本守卫（不再限制系统版本）
//  v1.6.26: 性能优化（基于 16.4.1/roothide 真实运行日志分析）
//    ✅ 文件夹/滚动刷新合并：删除冗余的 SBFolderController/SBIconListPageView hook，
//       单次文件夹打开只排一次 300ms 合并刷新（0.4s 时间窗去重），消除同秒多次 FOLDER REFRESH
//    ✅ 指示器复用：SBIconView 离屏时不再销毁指示器/清缓存，消除滚动导致的反复销毁重建（旧 CREATE≈2×RUNNING）
//    ✅ 调试日志门控：新增 MKConfig.debugLog（/var/mobile/Documents/rd_debug 文件开关，默认 NO），
//       用 if(sDebugLog) 包裹 RUNNING/NO LABEL/Indicator CREATE/FADE-IN/FOLDER OPEN·REFRESH·CLOSE/IconView.APPEAR/PAGE SCROLL/进程状态等噪声日志，错误与 EXIT 日志保留
//    ✅ 取色 miss 自愈：取色失败时下一 runloop 重试一次（sIconColorMissLogged 保证每 bid 只触发一次）
//  v1.6.1: 修复文件夹/Dock指示器不显示 + 设置页添加图标主色调
//    ✅ 修复文件夹内App指示器不显示 — sFadingLabelBIDs 卡住（渐隐动画没启动→MKRemoveFadingLabel从没调用）
//    ✅ 修复Dock App指示器不显示 — 同根因（Dock无label→渐隐跳过→isFading永远=YES）
//    ✅ MKFadeOutLabelForBundleID: 渐隐没启动时250ms后自动清除fading状态
//    ✅ 300ms/800ms回调也清除fading+pending状态（双重保险）
//  v1.6.0: 文件夹内App指示器 + 上滑回桌面指示器可靠性
//    ✅ 修复文件夹内App完全无指示器 — Hook SBFolderView/SBFolderController 打开事件
//    ✅ 文件夹图标过滤改为精确匹配 SBFolderIcon（避免误杀文件夹内App）
//    ✅ 上滑回桌面指示器延迟 — 增加 800ms 备用刷新（动画期间主线程堆积）
//    ✅ didMoveToWindow 添加诊断日志（追踪 App 图标出现时机）
//    ✅ MKRefreshSubviews 辅助函数（遍历容器内所有 SBIconView）
//  v1.5.9: 修复横条渐显被打断 + NO LABEL 位置优化
//    ✅ layoutSubviews 不再调用 applyConfig（之前会打断 200ms 渐显动画）
//    ✅ MKUpdate 已有指示器时也不调用 applyConfig（防止打断渐显）
//    ✅ NO LABEL 估算 fallback 位置：图标下方居中（替代图标底部边缘）
//    ✅ 添加指示器创建/渐显日志，方便追踪
//    ✅ SBIconView 回收复用检测：存储 icon 指针，icon 变化时清缓存
//    ✅ 过滤文件夹图标：SBFolderIcon 直接跳过
//  v1.5.3: 性能优化 + 转场闪烁修复
//    ✅ 状态去重：同一 (running, foreground) 不变时跳过刷新（消除重复 hook 触发）
//    ✅ 定向刷新：只更新状态变化的 App 图标（不再全量遍历视图层级）
//    ✅ 动画感知延迟：返回桌面延迟 400ms 显示指示器（等动画结束，不再闪烁）
//    ✅ layoutSubviews 优化：跳过非运行 App，有指示器时只重定位不重查找
//    ✅ bundleID + 标签缓存（associated objects）：避免重复调用 applicationBundleID / MKFindLabelView
//    ✅ 移除状态变化时的 MKClearAllIndicators（消除 name→indicator 闪烁）
//  v1.5.1: Dock / 文件夹图标指示器放到图标底部边缘（不遮挡图标内容）
//    ✅ 无名字标签时：指示器在父视图中位于图标底部下方（Lynx2 风格）
//    ✅ 标签查找加评分机制，避免误把 badge 等当名字标签
//  v1.5.0: 修复指示器定位 — 标签搜索加 superview 兄弟节点策略
//    ✅ MKFindLabelView 四重策略：accessor → superview兄弟 → 直接子视图 → 递归
//    ✅ 指示器定位：标签找到→在标签位置(替换名字)，标签未找到→图标底部(Dock)
//    ✅ objc associated objects 跨层级追踪指示器（不再依赖 viewWithTag）
//    ✅ didMoveToWindow 清理：视图移除时同步清理指示器+恢复标签
//  v1.4.8: Lynx2 风格重构 — 两种形状（圆点/横条），固定替换 App 名字位置
//    ✅ 核心检测已验证成功（_setInternalProcessState hook）
//    ✅ 简化 UI：只有圆点(Dot)和横条(Bar/Pill)两种形状
//    ✅ 位置固定：替换 App 名字标签区域（运行中→指示器，退出→恢复名字）
//    ✅ 移除 6 种复杂形状、3 种位置选项
//  紧急开关：/var/mobile/Documents/rd_disabled 存在则整机不生效。
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"
#import "MKIndicatorDotView.h"
#include <spawn.h>
#include <string.h>          // v2.0.22: strcmp 用于无分配类名比较（MKIsFolderIcon 每帧热路径）
#include <objc/runtime.h>

// ─── RDLog 已改为编译期 no-op 宏（.71 起彻底去掉诊断/探针输出；参数不求值，故 (void*)owner 等 ARC 桥接错误一并消失；全部 sDebugLog/sProbeLog 调试门控与探针函数体已在 .73 最终优化中删除，仅 RDLogRunning 守卫保留）──
#define RDLog(fmt, ...) ((void)0)

// libproc 函数声明（iOS 运行时存在，但 iPhoneOS SDK 不含此头文件）
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#define PROC_PIDPATHINFO_MAXSIZE 4096

// ─── 私有类前向声明 ──────────────────────────────────────────
@interface SBIconView : UIView
- (id)icon;
@end

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
@end

// ─── iOS 16 私有类声明（运行时头文件确认）──────────────
// FBProcessState — 进程状态对象（有 isRunning/taskState/foreground 属性）
@interface FBProcessState : NSObject
@property (getter=isRunning, nonatomic) BOOL running;
@property (nonatomic) int taskState;         // 2=Running, 3=Suspended, 1=NotRunning
@property (getter=isForeground, nonatomic) BOOL foreground;
@end

// FBApplicationProcess — 应用进程对象（有 bundleIdentifier）
@interface FBApplicationProcess : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (getter=isRunning, nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) int pid;
@end

// SBApplicationProcessState — iOS 16.3+ 包装类（有 isRunning/taskState/foreground）
@interface SBApplicationProcessState : NSObject
@property (readonly, nonatomic, getter=isRunning) BOOL running;
@property (readonly, nonatomic) int taskState;
@property (readonly, nonatomic, getter=isForeground) BOOL foreground;
@end

// ─── 常量 ──────────────────────────────────────────────────
static NSInteger const kDotTag  = 9999;

// ─── 关联对象：SBIconView ↔ 指示器视图（跨层级追踪）──
// v1.6.64: kMKIndicatorKey（旧版 self 子视图关联）已弃用，指示器改由 sBidToIndicator 按 bid 索引。
static char kMKLabelKey;     // 缓存的名字标签视图
static char kMKBidKey;       // 缓存的 bundleID
static char kMKIconKey;      // 缓存的 icon 指针（检测视图回收复用）
static char kMKLabelIconKey;  // v2.0.3: label→SBIconView 直接指针关联键（层级无关，关文件夹动画重父 label 时不失效）
static char kMKIndicatorBidKey; // v1.6.63: 指示器归属的 bid（防回收复用导致"乱跑"）
static char kMKOurBetaKey;     // v2.0.33: 标记「我们脱离的小黄点」——退出时只移除这些，不碰系统原生 TestFlight 黄点徽章
// v1.6.60: bid → SBIconView 弱引用注册表（替代不可靠的窗口遍历刷新）
// iOS 16 SpringBoard 在文件夹/滚动/转场等活跃态下，主屏图标视图常不在
// [UIApplication sharedApplication].windows 的常规遍历可达路径，导致 MKRefreshIconForBundleID
// 刷新落空、活跃态下指示器永远建不出来（静止态靠 layoutSubviews 才偶尔建成）。
// 注册表由 MKUpdate(每次有 bid 的图标视图都会跑) 实时维护，不依赖窗口层级，
// 刷新时直接命中图标视图 → MKUpdate，彻底绕开窗口遍历的坑。值用弱引用避免持有视图导致泄漏。
static NSMapTable *sBidToIconView;

// v1.6.64: 指示器从被回收的 SBIconView 子视图解耦到稳定 overlay 层。
// 解决 v1.6.63 两个结构性缺陷：(1) 图标滚出屏幕→指示器随被回收 view 消失；(2) 回收瞬间指示器作为子视图漂到别的 App 下（乱飞）。
// 指示器按 bid 索引，挂在图标滚动容器(SBIconScrollView/Dock scroll)的 overlay 上；
// 图标离屏时随容器自然移出视野（不销毁），滚回自动对齐。坐标用 convertRect:toView:overlay（transform/滚动偏移安全）。
static NSMapTable *sBidToIndicator;
static NSMapTable *sHiddenLabelToBid = nil;   // v2.0.7+GAP-FIX: label(weak key) -> bid(strong) map; records a label that must stay hidden
     // bid(NSString) -> 指示器(UIView) 强引用，跨回收存活
static NSMapTable *sContainerToOverlay; // 滚动容器(UIScrollView) -> overlay(UIView) 弱->强
// v1.6.61: 文件夹是否处于打开态（由 SBFolderView -didMoveToWindow 维护）。
// 仅当为 YES 时才允许把图标判定为"在文件夹内"，消除主屏图标被误判。
// 声明提前到此处，确保 MKIsIconInFolder()(v1.6.67) 等辅助函数在其定义前即可引用，满足 -Werror 先声明后使用。
static BOOL  sFolderOpen     = NO;
static BOOL  sFolderClosing   = NO;  // v2.0.3: 关文件夹动画窗口标志（~0.8s），用于定向诊断日志节流
static BOOL  sLocked        = NO;  // v1.6.69: 设备是否处于锁屏态（解锁动画期间保持 YES，避免指示器透出）
static NSTimeInterval sLockAt = 0;   // v1.6.70: 最近一次锁屏时刻；用于 MKUpdate 时间闸门自动复位（不依赖解锁通知）
static BOOL  sUnlockFading = NO;  // v2.0.50: MKUnlockRestore 显式淡入进行中，抑制逐帧不变量重复叠淡入（防重抖）
static dispatch_source_t sFolderCloseGuard = NULL;  // v2.0.1: 关文件夹缩回动画期间(~0.5s)持续堵窗定时器，防新建 label 漏藏
// v2.0.66.78 (A4): sDebugLog 已删除 —— 唯一引用者 RDLogRunning 同批删除, 该变量运行期恒假, 无其他读者。
static char kMKFIconBidsKey;  // v1.6.76: 文件夹图标缓存的「内部后台运行中 App」bid 数组
static char kMKFIconGenKey;    // v1.6.76: 该缓存的代际（sFolderContentGen 变化时失效）
static NSUInteger sFolderContentGen = 0; // v1.6.76: 文件夹内容代际；App 运行态变化时 +1 使缓存失效
static NSMutableDictionary<NSNumber*, NSArray<NSString*>*> *sFolderVisualOrder = nil; // v1.6.81: 文件夹内图标视觉顺序

// v1.6.85: 「本 bid 有指示器 → 名字必须隐藏」的源头级强制。
// 以往所有藏名都在分支内/事后（layoutSubviews / MKUpdate 各路径），系统布局或转场
// 动画会在我们的藏名之后把 label 复显一帧 → 名字与圆点偶发重叠；且 v1.6.84 的
// 主动式堵窗对关闭文件夹时系统「名字 pop」动画产生 alpha 冲突 → 桌面上运行中 App 名称闪一下。
// 改在标签自身的 setHidden:/setAlpha: 上 hook：凡是当前有指示器的 bid，无论系统怎么
// 复显都强制隐藏 → 空档彻底归零，重叠与关闭闪现一并根除。
static NSMutableSet<NSString*> *sHiddenBids = nil;          // 当前「有指示器、名字必须隐藏」的 bid（含文件夹合成 key __folder__%p）
static void *kMKLabelBidKey = &kMKLabelBidKey;              // v1.6.93: label→bid 直接关联键（藏名时写入，显示名时清 nil）
// 前向声明（定义见文件后部）
static NSString *MKLabelToBid(UIView *label);
static void MKInstallLabelHook(void);

// v1.6.75: 锁屏后兜底「解锁复原」定时器句柄（不依赖 iOS 解锁通知/布局事件）
static dispatch_source_t sUnlockTimer = NULL;

// v1.6.64: 以下 helpers 管理「按 bid 索引、挂在稳定 overlay 层」的指示器。
static UIView *MKGetCachedLabel(SBIconView *iv); // 前向声明（定义于文件后部）
static void MKAssocLabelBid(UIView *label, NSString *bid); // 前向声明（定义于 v1.6.86 区域；MKGetCachedBid 回收分支需用到）
static UIView *MKIconViewForLabel(UIView *label);          // v2.0.7: label→所属 SBIconView 几何反解（关联键/层级失效时终极兜底）
static void MKLabelDidMoveToWindowHook(id self, SEL _cmd);  // v2.0.7: 创建点拦截（label 进入 window 即刻藏名）
static void MKArmFolderCloseGuard(void);  // v2.0.8: 关闭保护(缩回动画进行中即武装 guard)；SBFolderView/-didMoveToWindow 与 SBFolderController/-viewWillDisappear 共调用
static void MKDetachBetaOnce(UIView *iconView);     // v2.0.30: beta 小黄点脱离到 iconView（仅当仍在 label 内，防每帧抖动）
static void MKRestoreBetaOrphan(UIView *iconView);  // v2.0.30: 退出/恢复 移除我们脱离的孤儿点（系统自建原 label 点）
static UIView *MKContainerForIconView(UIView *iv) {
    if (!iv) return nil;
    UIView *anc = iv.superview;
    UIView *fallback = nil;
    while (anc) {
        if ([anc isKindOfClass:[UIScrollView class]]) return anc;
        // v1.6.65: Dock 等不滚动图标的容器回退候选。Dock 图标不在 UIScrollView 下，
        // 而是挂在 SBDockView/SBDockIconListView 等 UIView 子树上；若只认 UIScrollView
        // 会找不到容器，导致 overlay=nil、Dock App 无指示器。
        if (!fallback) {
            // v2.0.66.34-perf: class_getName()+strncmp/strcmp 零分配，替代 NSStringFromClass+hasPrefix/isEqualToString。
            // MKContainerForIconView 在 MKUpdate（每个图标每次布局）热路径被调用，原写法每层祖先分配 NSString。
            const char *cls = class_getName([anc class]);
            if (strncmp(cls, "SBIconListView", 13) == 0 ||
                strncmp(cls, "SBDock", 5) == 0 ||
                strcmp(cls, "SBRootFolderView") == 0 ||
                strcmp(cls, "SBIconController") == 0) {
                fallback = anc;
            }
        }
        anc = anc.superview;
    }
    return fallback;
}
// v1.6.67: 抽出文件夹内检测，供 layoutSubviews 与 MKUpdate 共享，避免 layoutSubviews
// 把文件夹内 App 的 label 隐藏掉（这是"文件夹内看不到 App 名称"的根因）。
// 前向声明：sFolderOpen 已在文件顶部全局区声明（static BOOL sFolderOpen = NO），此处直接使用。
static BOOL MKIsIconInFolder(UIView *iv) {
    UIView *container = MKContainerForIconView(iv);
    NSString *cls = container ? NSStringFromClass([container class]) : @"";
    // 主屏(SBIconScrollView) / Dock(SBDock*) 之外的容器即文件夹内容器(SBFloatyFolderScrollView 等)。
    // 不依赖 isKindOfClass:UIScrollView —— Dock 的 SBDockIconListView 未必是 scrollView 子类，
    // 误判会让 Dock 后台 App 被当成文件夹内而不显指示器（1.6.65 已修好的 Dock 回退）。
    BOOL isHomeOrDock = [cls isEqualToString:@"SBIconScrollView"] || [cls hasPrefix:@"SBDock"];
    if (isHomeOrDock) return NO;
    // v2.0.11: 长按 App 弹出的 FloatyFolder(SBFloatyFolderScrollView) 是一种「文件夹打开态」，
    // 但它不走 SBFolderController、不会把 sFolderOpen 置 YES、还常被 FOLDER-WATCHDOG 复位成 NO。
    // 原先的 `if (!sFolderOpen) return NO;` 前置会让 FloatyFolder 内的 icon 被误判成主屏图标
    // → setHidden/MKLabelDidMoveToWindowHook 的藏名拦截漏掉它们 → 缩回末尾名字复显闪一下(第④点残留真凶)。
    // 故 FloatyFolder 容器无论 sFolderOpen 与否都直接识别为「在文件夹内」，其余容器维持原语义(需 sFolderOpen)。
    if ([cls isEqualToString:@"SBFloatyFolderScrollView"]) {
        
        return YES;
    }
    return (sFolderOpen && container);
}
// v1.6.76: 检测 self 是否为「文件夹图标」（桌面/Dock 上那个，未打开）。
// 用于区分「文件夹图标」与「文件夹内部 App 图标」——后者走正常主功能。
static BOOL MKIsFolderIcon(SBIconView *iv) {
    if (!iv) return NO;
    id icon = [iv icon];
    if (!icon) return NO;
    // v2.0.22: 改用 class_getName()（C 字符串，零分配）替代 NSStringFromClass，
    // 避免 layoutSubviews 每帧为【每个图标】都分配一个 NSString（原实现每个图标每帧一次）。
    // 实际比较用 strcmp，行为与原来 isEqualToString: 完全等价（类名 camelCase）。
    const char *cls = class_getName([icon class]);
    return cls && (strcmp(cls, "SBFolderIcon") == 0 || strcmp(cls, "SBIconFolderIcon") == 0);
}
static UIView *MKOverlayForContainer(UIView *container) {
    if (!container) return nil;
    if (!sContainerToOverlay) sContainerToOverlay = [NSMapTable weakToStrongObjectsMapTable];
    UIView *ov = [sContainerToOverlay objectForKey:container];
    if (!ov) {
        ov = [[UIView alloc] initWithFrame:container.bounds];
        ov.userInteractionEnabled = NO;
        ov.clipsToBounds = NO;
        ov.backgroundColor = [UIColor clearColor];
        ov.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:ov];
        [container bringSubviewToFront:ov];
        [sContainerToOverlay setObject:ov forKey:container];
    }
    return ov;
}

#pragma mark - 角标模式辅助（v2.0.66.80, .81 修 strncmp 死码, .82 改 squircle+扩 frame）
// v2.0.66.82: frame 扩展常量 MKBadgeFrameExtra 定义在 MKIndicatorDotView.h（extern），
// Tweak.x(MKIndicatorFrameInOverlay) 和 MKIndicatorDotView.m(drawRect) 共享
// 取图标图片视图(SBIconImageView / SBIconImageCrossfadeView)，用于角标贴附图标圆角
// v2.0.66.81: 原 strncmp(n,"SBIconImage",12) 比较长度写成12，"SBIconImage" 仅11字符+null=12，
//   第12字节 '\0' 与任何 SBIconImage* 类名第12字节(字母)不等 → 恒不匹配 → 永远回退到 SBIconView
//   (含名字标签区) → 左下/右下弧线圆心下移名字高度，"距离远"。修：长度改11 + 递归查找兜底嵌套。
static UIView *MKIconImageView(UIView *iv) {
    if (!iv) return nil;
    for (UIView *sub in iv.subviews) {
        const char *n = class_getName([sub class]);
        // v2.0.66.84: 文件夹图标的图片视图类名是 SBFolderIconImageView（不以 SBIconImage 开头），
        //   而它内部嵌着一格格迷你 App 图标、每个迷你图标各自带 SBIconImageView。
        //   原实现深度优先递归 → 先命中【迷你图标】的 SBIconImageView 就返回 → 角标按迷你图标
        //   (约 1/3 尺寸、位于文件夹内部) 的 bounds 定位 → 文件夹 4 个角全部"距离远"。
        //   修：先比 SBFolderIconImage 前缀，保证在钻进缩略图之前就命中文件夹本体图片视图。
        if (strncmp(n, "SBFolderIconImage", 17) == 0) return sub;
        if (strncmp(n, "SBIconImage", 11) == 0) return sub;
        UIView *found = MKIconImageView(sub);   // 递归兜底：crossfade 等容器嵌套
        if (found) return found;
    }
    return nil;
}
// v2.0.66.84: 角标定位基准视图。若命中的图片视图宽度明显小于图标视图（说明仍误命中了
// 文件夹缩略图内的迷你图标，或该系统版本类名不符预期），返回 nil 让调用方走正方形兜底。
static UIView *MKBadgeBaseView(UIView *iv) {
    UIView *base = MKIconImageView(iv);
    if (!base) return nil;
    CGFloat bw = base.bounds.size.width;
    CGFloat ivw = iv ? iv.bounds.size.width : 0;
    if (ivw > 1.0f && bw < ivw * 0.5f) return nil;   // 误命中迷你图标 → 判废
    return base;
}
// 取图标图片真实圆角（continuousCornerRadius，iOS13+ 图标圆角真正来源；普通 cornerRadius 常为 0）
static CGFloat MKIconCornerRadius(UIView *iv) {
    UIView *imv = MKBadgeBaseView(iv);   // v2.0.66.84: 用带判废的基准视图，避免取到迷你图标的小圆角
    UIView *target = imv ?: iv;
    CALayer *layer = target.layer;
    if ([layer respondsToSelector:@selector(continuousCornerRadius)]) {
        NSNumber *cr = [layer valueForKey:@"continuousCornerRadius"];
        if (cr && [cr floatValue] > 0) return [cr floatValue];
    }
    if (layer.cornerRadius > 0) return layer.cornerRadius;
    // v2.0.66.84: 兜底按图标图片正方形边长算（不用含名字区的 SBIconView 高度）
    CGFloat m = imv ? MIN(target.bounds.size.width, target.bounds.size.height)
                    : target.bounds.size.width;
    return m * 0.225f;
}
// 角标模式下不抢名字位置 → 所有藏名逻辑统一失效
static BOOL MKHideNames(void) {
    return [MKConfig sharedConfig].locationMode != MKLocationBadge;
}

// v2.0.66.86: 与 MKHideNames() 【正交】的第二类职责门控 —— 「纠正 iOS 原生非法名字」。
//
// 两者语义必须分清, .85 把它们混为一谈是本轮 bug 的根:
//   MKHideNames()     = 「我们主动把运行 App 的名字藏掉, 让位给指示器」。角标模式不抢名字位 → 关。
//   MKFixStrayNames() = 「iOS 自己把某个图标名 label 渲染到了【原生本来不显示名字】的位置
//                        (dock / 负一屏 / widget / 文件夹缩略图网格), 把它纠正掉」。两模式都必须开。
//
// 用户实机反馈(角标模式下 dock 串名 + 文件夹缩略图闪名依旧)的真因就在这里:
// 这两症的机制是 iOS 自身的 SBIconView/label 回收复用 —— 把旧槽位的名字带到新槽位,
// 与我们藏不藏名【毫无关系】; 替换模式下靠 MKDockStrayHide / didMoveToSuperview 清过期键
// 这套「纠正机制」压住, 而 .85 把它们随 MKHideNames() 一并关掉 = 禁用过头, 于是无人纠正。
//
// 判定安全性(default-deny 无误伤空间): dock / 负一屏 / widget / 缩略图网格 原生一律不显示
// 图标名 → 这些容器内出现【任何可见 name label】= 100% 非法; 失败模式退化为「这些位置没名字」,
// 而它们本来就没名字 → 用户零感知。主屏网格由 MKLabelInHomeGrid 守卫排除, 绝不误杀。
//
// 恒真而非配置项: 纠正非法名字在任何模式下都无副作用, 没有关掉它的理由; 保留具名函数是为了
// 让每个调用点自解释「这是纠正 iOS, 不是我们抢名字」, 防止将来又被误挂到 MKHideNames() 上。
//
// ⚠️ v2.0.66.88 重要修订 —— 上面「文件夹缩略图网格也算 stray, 两模式都要擦」这条【已推翻】:
//   实机证实角标模式下文件夹名依旧闪, 真因不是「没人擦」, 而恰恰是「我们擦了」——
//   iOS 开合文件夹走 compositor crossfade, 快照里那个名字还在; 我们只能改 live label,
//   改不了已生成的快照 → live(无名) 与 snapshot(有名) 交叉淡入淡出 = 用户看到的闪。
//   .77 在替换模式下判此路"hook 架构内无解"是对的(替换模式必须藏名, 不一致命里带的),
//   但角标模式的契约本是「名字一律不动」→ 缩略图名也是名字, 不该碰。
//   故 .88 起【角标模式下缩略图那一路全部交还系统】(共 5 个擦名点删除: MKSetHiddenHook /
//   MKSetAlphaHook / setIconLabelAlpha / MKLabelDidMoveToWindowHook / layoutSubviews 每帧兜底)。
//   dock / 负一屏 / widget 三类 foreign 容器【保留】—— 它们没有 crossfade 快照通道, 未观察到闪。
static inline BOOL MKFixStrayNames(void) {
    return YES;
}

// v1.6.66: 递归查找某类的首个后代视图（关闭文件夹时定位主屏滚动容器 SBIconScrollView）
static UIView *MKFindDescendantView(UIView *root, NSString *clsName) {
    if (!root || !clsName) return nil;
    for (UIView *sub in root.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:clsName]) return sub;
        UIView *found = MKFindDescendantView(sub, clsName);
        if (found) return found;
    }
    return nil;
}

static UIView *MKFindIndicator(NSString *bid) {
    if (!bid || !sBidToIndicator) return nil;
    return [sBidToIndicator objectForKey:bid];
}
// v1.6.86: MKIsAppRunning/MKIsForeground 定义在文件后部(~1114/1130)。v1.6.86 在 MKRemoveIndicatorForBid
// 提前调用了 MKIsAppRunning(下方 292 行) → 必须在使用点之前前置声明，否则隐式(非 static)声明与
// 原 343 行 static 前向声明冲突 → -Werror 编译失败。
static BOOL MKIsAppRunning(NSString *bundleID);   // App 是否运行中
static BOOL MKIsForeground(NSString *bid);        // App 是否前台

static void MKRemoveIndicatorForBid(NSString *bid) {
    if (!bid) return;
    UIView *ind = MKFindIndicator(bid);
    if (ind) {
        [ind removeFromSuperview];
    }
    if (sBidToIndicator) [sBidToIndicator removeObjectForKey:bid];
    // v1.6.86: 仅在 App 确实不再运行时才恢复名字。文件夹关闭时内层 App 的指示器视图被拆掉
    // （didMoveToWindow(nil)），但 App 仍在后台运行 → 名字必须继续隐藏，否则缩回动画里闪一下。
    if (sHiddenBids && !MKIsAppRunning(bid)) [sHiddenBids removeObject:bid];
    // v2.0.7+GAP-FIX: 清掉该 bid 对应的 label 指针表项，使 App 退出后名字可正常复显
    // （不漏清会令退出后的 label 仍被源级 hook 凭指针表强制藏住）。
    if (sHiddenLabelToBid) {
        NSArray *keys = [[sHiddenLabelToBid keyEnumerator] allObjects];
        for (id k in keys) {
            NSString *v = [sHiddenLabelToBid objectForKey:k];
            if (v && [v isEqualToString:bid]) [sHiddenLabelToBid removeObjectForKey:k];
        }
    }

}
static void MKRemoveAllIndicators(void) {
    if (!sBidToIndicator) return;
    NSArray *all = [[sBidToIndicator objectEnumerator].allObjects copy];
    for (UIView *ind in all) { if (ind) [ind removeFromSuperview]; }
    [sBidToIndicator removeAllObjects];
    if (sHiddenBids) [sHiddenBids removeAllObjects]; // v1.6.85: 全清
    if (sHiddenLabelToBid) [sHiddenLabelToBid removeAllObjects]; // v2.0.7+GAP-FIX: 同步清空指针表
    // v2.0.30: 清掉所有 iconView 上我们此前脱离的小黄点孤儿（系统会自建原 label 点）
    if (sBidToIconView) {
        NSArray *ivs = [[sBidToIconView objectEnumerator] allObjects];
        for (id iv in ivs) { if (iv) MKRestoreBetaOrphan((UIView *)iv); }
    }
}
// v1.6.71: 改为隐藏/恢复所有 overlay（而非逐个 indicator）。
// 锁屏时 overlay.hidden=YES 即隐藏其下全部指示器；解锁时 overlay.hidden=NO 立即全局恢复，
// 不再依赖逐图标 MKUpdate 重新布局 → 根治"解锁后指示器长时间空白、需滑动才出现"。
static void MKSetAllIndicatorsHidden(BOOL hidden) {
    if (!sContainerToOverlay) return;
    NSArray *all = [sContainerToOverlay.objectEnumerator.allObjects copy];
    for (UIView *ov in all) { if (ov) ov.hidden = hidden; }
}
// v2.0.66.32: 解锁复原统一入口。收到任意解锁信号即刻解除隐藏(alpha=1, 无独立淡入),
// 圆点随 iOS 原生锁屏盖片揭开与主屏一同被揭示, 与桌面解锁动画天然同步。用 sUnlockToken 防重入/过期：
// 期间若重锁（sLocked=YES）或又来更新的解锁，旧调用自动失效。
static NSInteger sUnlockToken = 0;
// 前向声明（翻停后刷新所有页面图标，定义在文件后部 2279 行）；必须在 MKUnlockRestore
// (323 行) 之前声明，因为 MKUnlockRestore 内调用了它，否则新版 clang -Werror 报
// implicit-function-declaration（v2.0.1 回归：前向声明原在 531 行、晚于调用点）。
static void MKRefreshAllIcons(void);
// v2.0.66.3: 关闭「保留小黄点」时对称隐藏全部 beta 点(定义于 ~L804); 必须在 MKRefreshAllIcons
// (3011 行) 之前声明, 否则调用点(L3063)触发 -Werror implicit-function-declaration。
static void MKBetaHideAll(UIView *);
// v2.0.66.32: 解锁即时揭示(原生携带) —— 不再做独立淡入。收到解锁信号即刻 un-hide(alpha=1),
// 圆点随 iOS 原生锁屏盖片揭开与主屏一同被揭示, 与桌面解锁动画天然同步, 消除"第二波晚冒"。
// 当初 v2.0.1 的 0.45s 延迟淡入是为避开过渡期 CA 上下文(块动画不渲染→瞬现); 现改为
// 零延迟即时 un-hide, 把视觉过渡完全交给原生解锁动画, 既统一又无独立动画可失败。
// sUnlockFading 仍置位 0.4s, 抑制紧随其后的逐帧不变量重复叠淡入(防重抖/双淡入)。
static void MKUnlockRevealOverlays(void) {
    if (!sContainerToOverlay) return;
    sUnlockFading = YES;
    @try {
        NSArray *ovs = [[sContainerToOverlay objectEnumerator].allObjects copy];
        for (UIView *ov in ovs) {
            if (!ov) continue;
            ov.alpha  = 1.0f;
            ov.hidden = NO;   // 即时取消隐藏, 交原生锁屏揭开揭示(无独立动画)
            // v2.0.66.36 方案C: 解锁揭示时按 bid 验证精准救回单个指示器 ——
            // 根治「解锁后个别运行 App 指示器短暂消失一会」。根因: 这些 indicator 被锁屏
            // 间接隐藏(ov.hidden=YES), 解锁 reveal overlay 之后, 若其归属 bid 对应 App 仍运行,
            // 立即 hidden=NO 救回, 不再等 MKRefreshAllIcons 在 bid 就绪帧才补显。
            // 无幽灵点: 已退出 App 的 bid 在 MKIsAppRunning 返回 NO, 保持隐藏, 由紧随其后的
            // MKRefreshAllIcons 经 !running 分支(MKRemoveIndicatorForBid)清理。
            for (UIView *ind in ov.subviews) {
                if (ind.tag != kDotTag) continue;
                NSString *indBid = (NSString *)objc_getAssociatedObject(ind, &kMKIndicatorBidKey);
                if (indBid.length && MKIsAppRunning(indBid)) {
                    ind.hidden = NO;
                    
                }
            }
            
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ sUnlockFading = NO; });
    } @catch (NSException *e) { RDLog(@"UNLOCK-REVEAL EXCEPTION: %@", e.reason); }
}
static void MKUnlockRestore(void) {
    if (!sContainerToOverlay) return;
    NSInteger myToken = ++sUnlockToken;
    if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
    // v2.0.66.32: 取消 0.45s 延迟, 解锁信号即刻复原 —— 让圆点随原生解锁动画揭示(统一),
    // 不再做"动画结束后再延迟淡入"的第二波。token 守卫仍保留(防重入/重锁覆盖)。
    if (myToken != sUnlockToken) return;   // 已被更新的解锁覆盖
    if (sLocked) return;                   // 期间又锁屏了
    @try {
        MKUnlockRevealOverlays();   // v2.0.66.32: 即时 un-hide(原生携带), 非延迟淡入
        // 仍触发全量刷新：让每个图标经逐帧不变量重推 hidden/alpha(此刻只解隐、不叠动画,
        // 因 sUnlockFading=YES 抑制逐帧淡入; 同时是离屏未布局图标的安全网)。
        MKRefreshAllIcons();
        // v2.0.66.46: 用户实测「解锁后约 1 秒 dock 串名又冒出来」——串名在解锁 t=0 已随主屏重建归位,
        // 但约 1s 后某过渡又把该 label 拖回 dock 纵带; 该时刻 label 往往已静止(无 layoutSubviews 可依赖),
        // 故保留一次 t=1.3s 的全量刷新兜底(其 BFS 已内联 MKDockStrayHide 判定, 顺带完成 dock 串名复核)。
        // v2.0.66.45 的 0.5s/1.3s 两次独立全树扫描(MKDockBandSweep)已整体删除: 判定并入每帧路径与本刷新, 不再重复遍历。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MKRefreshAllIcons(); });
        
    } @catch (NSException *e) { RDLog(@"UNLOCK EXCEPTION: %@", e.reason); }
}
// v1.6.67: 计算某 bid 的指示器在 overlay 坐标系中的 frame（transform/滚动偏移安全）。
// 使用传入的图标视图 iv，而不是去 sBidToIconView 注册表里取——注册表里存的是"最后一次
// 调用 MKUpdate 的图标实例"，在多页桌面中如果当前 layout 的是另一页的图标，会拿错位置
// 导致指示器飘到别的页面（"左右滑动后重叠/错位"的根因之一）。
// 无 live 视图（图标离屏/被回收）→ 返回 CGRectZero，调用方保留其最后位置不重算。
static CGRect MKIndicatorFrameInOverlay(SBIconView *iv, UIView *overlay, MKConfig *cfg) {
    if (!iv || !overlay || !cfg) return CGRectZero;
    if (cfg.locationMode == MKLocationBadge) {
        // 角标模式：指示器贴在图标图片圆角内沿，按图标图片真实 bounds 计算（不依赖 label 位置）
        // v2.0.66.84: 用 MKBadgeBaseView（带"误命中迷你图标判废"）。判废/取不到时兜底为
        //   SBIconView 顶部的正方形图标区（宽=iv 宽，高=宽），而不是含名字区的整个 iv.bounds
        //   —— 后者会让下方两角下移一个名字高度。
        UIView *base = MKBadgeBaseView((UIView *)iv);
        CGRect r;
        if (base) {
            r = [overlay convertRect:base.bounds fromView:base];
        } else {
            CGFloat side = MIN(iv.bounds.size.width, iv.bounds.size.height);
            r = [overlay convertRect:CGRectMake(0, 0, side, side) fromView:(UIView *)iv];
        }
        // v2.0.66.82: 四周各扩 MKBadgeFrameExtra(15pt)，容纳 max inset(12) + max half-thickness(3)
        // 供 inset>0 时弧线整体外移到角落外 + stroke 圆头不裁。
        // drawRect 内对应按 (MKBadgeFrameExtra, MKBadgeFrameExtra) 平移到 icon 坐标系。
        return CGRectMake(r.origin.x - MKBadgeFrameExtra, r.origin.y - MKBadgeFrameExtra,
                          r.size.width + 2 * MKBadgeFrameExtra, r.size.height + 2 * MKBadgeFrameExtra);
    }
    CGFloat indW = (cfg.shape == MKShapeDot) ? cfg.dotSize : cfg.barWidth;
    CGFloat indH = (cfg.shape == MKShapeDot) ? cfg.dotSize : cfg.barHeight;
    UIView *label = MKGetCachedLabel(iv);
    CGRect r;
    if (label && label.superview) {
        r = [label.superview convertRect:label.frame toView:overlay];
    } else {
        r = [overlay convertRect:iv.bounds fromView:iv];
        r = CGRectMake(CGRectGetMidX(r) - 20.0f, CGRectGetMaxY(r) + 2.0f, 40.0f, 14.0f);
    }
    return CGRectMake(CGRectGetMidX(r) - indW/2.0f, CGRectGetMidY(r) - indH/2.0f, indW, indH);
}
static void MKRepositionIndicator(NSString *bid, SBIconView *iv, MKConfig *cfg) {
    if (!bid || !iv || !cfg) return;
    UIView *ind = MKFindIndicator(bid);
    if (!ind) return;
    UIView *container = MKContainerForIconView((UIView *)iv);
    UIView *overlay = MKOverlayForContainer(container);
    if (!overlay) return;
    CGRect f = MKIndicatorFrameInOverlay(iv, overlay, cfg);
    if (!CGRectIsEmpty(f)) { ind.frame = f; ind.hidden = NO; }
}

// v1.6.75: 前向声明（MKFolderChosenBid 依赖，定义在文件后部）
static NSString *MKGetCachedBid(SBIconView *iv);
// v1.6.76: 文件夹【图标】功能前向声明
static BOOL       MKIsFolderIcon(SBIconView *iv);                              // 检测文件夹图标
static NSArray<NSString*> *MKContainedRunningBids(SBIconView *fiv);          // 取文件夹内后台运行 App
static NSString *MKFolderChosenBid(NSArray<NSString*> *bids); // 选代表 App（固定=位置靠前活跃）
static void      MKRefreshFolderIcons(void);                              // 刷新所有文件夹图标
static NSInteger  MKUpdateFolderIconsUnder(UIView *view, Class ivCls);        // 递归找文件夹图标

// v1.6.75: 读取 App 角标数（消息数量近似）。
// v1.6.76: 文件夹【图标】（桌面/Dock 上、未打开）显示 1 个圆点。
// 里面 ≥1 个后台运行 App 时，圆点颜色按「代表 App」主色（auto 模式）；固定色模式用全局固定色。
// 形状/尺寸走全局 cfg（与里面 App 的圆点自动同步）。
// 入参 bids = 文件夹内后台运行 App 的 bid 数组（已由 MKContainedRunningBids 按视觉顺序排好）。
// 代表 App 固定为「位置靠前活跃」：bids 已按屏幕视觉顺序排序，取第一个即用户看到的最前运行 App。
// v2.0.24: 移除 folderIndicatorMode 二选一设置，行为固定为位置靠前（原 mode 0）。「来信息最新」分支删除。
static NSString *MKFolderChosenBid(NSArray<NSString*> *bids) {
    if (!bids || bids.count == 0) return nil;
    return bids.firstObject; // 位置靠前活跃 = 视觉序第一个
}

// v1.6.81: 按文件夹内图标的视觉顺序对 running bids 排序，确保 folderIndicatorMode=0 的
// 「排序靠前」真正对应用户在屏幕上看到的顺序，而不是内部模型/添加顺序。
static void MKSortRunningBidsByVisualOrder(id folder, NSMutableArray<NSString*> *out) {
    if (!folder || !out || out.count < 2) return;
    NSNumber *key = @((NSUInteger)folder);
    NSArray<NSString*> *visual = sFolderVisualOrder[key];
    if (!visual || visual.count == 0) return;
    NSMutableDictionary<NSString*, NSNumber*> *rank = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < (NSInteger)visual.count; i++) rank[visual[i]] = @(i);
    [out sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ra = [rank objectForKey:a] ? [rank[a] integerValue] : NSIntegerMax;
        NSInteger rb = [rank objectForKey:b] ? [rank[b] integerValue] : NSIntegerMax;
        if (ra < rb) return NSOrderedAscending;
        if (ra > rb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

// v1.6.76: 递归收集文件夹（含嵌套）内「后台运行中」App 的 bid（写入 out）。
// 全程 @try + performSelector + NSClassFromString 防御私有 API（避免 -Werror/崩溃）。
static void MKCollectRunningFromFolder(id folder, NSMutableArray<NSString*> *out) {
    if (!folder || !out) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    Class appCls = NSClassFromString(@"SBApplicationIcon");
    if (!appCls) appCls = NSClassFromString(@"SBLeafIcon");
    Class fCls = NSClassFromString(@"SBFolderIcon");
    if (!fCls) fCls = NSClassFromString(@"SBIconFolderIcon");
    NSArray *icons = nil;
    if ([folder respondsToSelector:NSSelectorFromString(@"allIcons")])
        icons = [folder performSelector:NSSelectorFromString(@"allIcons")];
    if (!icons && [folder respondsToSelector:NSSelectorFromString(@"displayedIcons")])
        icons = [folder performSelector:NSSelectorFromString(@"displayedIcons")];
    if (!icons && [folder respondsToSelector:NSSelectorFromString(@"iconModel")]) {
        id model = [folder performSelector:NSSelectorFromString(@"iconModel")];
        if ([model respondsToSelector:NSSelectorFromString(@"allIcons")])
            icons = [model performSelector:NSSelectorFromString(@"allIcons")];
        else if ([model respondsToSelector:NSSelectorFromString(@"displayedIcons")])
            icons = [model performSelector:NSSelectorFromString(@"displayedIcons")];
    }
    if (!icons && [folder respondsToSelector:NSSelectorFromString(@"lists")]) {
        NSArray *lists = [folder performSelector:NSSelectorFromString(@"lists")];
        NSMutableArray *acc = [NSMutableArray array];
        for (id lst in lists) {
            if ([lst respondsToSelector:NSSelectorFromString(@"icons")])
                [acc addObjectsFromArray:[lst performSelector:NSSelectorFromString(@"icons")]];
        }
        if (acc.count) icons = acc;
    }
    
    if (!icons) return;
    for (id sub in icons) {
        if (appCls && [sub isKindOfClass:appCls]) {
            NSString *b = nil;
            if ([sub respondsToSelector:NSSelectorFromString(@"applicationBundleID")])
                b = [sub performSelector:NSSelectorFromString(@"applicationBundleID")];
            else if ([sub respondsToSelector:NSSelectorFromString(@"applicationBundleIdentifier")])
                b = [sub performSelector:NSSelectorFromString(@"applicationBundleIdentifier")];
            BOOL run = [b isKindOfClass:[NSString class]] && b.length && MKIsAppRunning(b);
            BOOL fg = run && MKIsForeground(b);
            
            if (run && !fg) [out addObject:b];
        } else if (fCls && [sub isKindOfClass:fCls]) {
            id sf = nil; // 嵌套文件夹：递归
            if ([sub respondsToSelector:NSSelectorFromString(@"folder")])
                sf = [sub performSelector:NSSelectorFromString(@"folder")];
            MKCollectRunningFromFolder(sf, out);
        }
    }
#pragma clang diagnostic pop
}

// v1.6.76: 取文件夹图标里「后台运行中」的 App 的 bid 数组（递归含嵌套文件夹）。
// 用关联对象 + 代际(sFolderContentGen) 做缓存：App 运行态变化时代际 +1，缓存自动失效。
static NSArray<NSString*> *MKContainedRunningBids(SBIconView *fiv) {
    if (!fiv) return @[];
    NSArray *cached = objc_getAssociatedObject(fiv, &kMKFIconBidsKey);
    NSNumber *cachedGen = objc_getAssociatedObject(fiv, &kMKFIconGenKey);
    if (cached && cachedGen && [cachedGen unsignedIntegerValue] == sFolderContentGen) {
        return cached;
    }
    NSMutableArray *out = [NSMutableArray array];
    id folder = nil;
    @try {
        id icon = [fiv icon];
        if (!icon) return @[];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([icon respondsToSelector:NSSelectorFromString(@"folder")])
            folder = [icon performSelector:NSSelectorFromString(@"folder")];
#pragma clang diagnostic pop
        if (!folder) return @[];
        MKCollectRunningFromFolder(folder, out);
    } @catch (NSException *e) {
        return out; // 部分结果兜底
    }
    // v1.6.81: 按视觉顺序重排，让 folder 图标指示器颜色真正跟随用户排序
    MKSortRunningBidsByVisualOrder(folder, out);
    objc_setAssociatedObject(fiv, &kMKFIconBidsKey, out, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fiv, &kMKFIconGenKey, @(sFolderContentGen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return out;
}

// v1.6.64: 原 MKIndicatorFrameInSelf（窗口坐标系）已由 MKIndicatorFrameInOverlay（overlay 坐标系，
// 额外吃掉 transform/滚动偏移）取代；此处不再需要，删除旧定义以免 -Werror 报 unused。

// 前向声明（MKFindLabelView 定义在后面，但 MKGetCachedLabel 需要调用它）
static UIView *MKFindLabelView(SBIconView *iconView);
// 前向声明（取色 miss 重试时需要调用）
static void MKRefreshIconForBundleID(NSString *bid);
// 前向声明（滚动守卫刷新需要）
static void MKRefreshSubviews(UIView *containerView);
// v2.0.66.32: 解锁复原统一入口 —— 解锁信号即刻 un-hide(原生携带), 圆点随原生锁屏揭开
// 与主屏一同揭示, 与桌面解锁动画统一。替代原先三处立即硬显示的"第二波"延迟淡入。
// 用 sUnlockToken 防重入/过期（期间重锁或又来更新的解锁即失效）。
static void MKUnlockRestore(void);
// v1.6.69: 锁屏/解锁通知回调 —— 锁屏隐藏所有指示器，解锁动画结束后再复位，避免解锁动画透出指示器圆点。
// v1.6.75: 锁屏后排一个 ~1.0s 兜底定时器，解锁后可靠复原所有指示器。
// 本设备 UIApplicationDidBecomeActive / lockstate 解锁通知未必派发，仅靠 MKUpdate 时间闸门
// 又依赖"解锁后有布局事件"；定时器不依赖任何通知/布局，锁屏满 1.0s 即复原。
// 1.0s > 解锁动画(~0.5s)，故不会在动画途中闪现；仍锁屏时复原发生在锁屏遮罩之下，
// 解锁后干净呈现，无透出。每次锁屏都重建并取消上一轮，避免重锁时旧定时器误触发。
static void MKScheduleUnlock(void) {
    if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
    sUnlockTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!sUnlockTimer) return;
    dispatch_source_set_timer(sUnlockTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(sUnlockTimer, ^{
        @try {
            if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
            if (!sLocked) return;
            NSTimeInterval now = [NSDate date].timeIntervalSince1970;
            if (now - sLockAt < 0.7) return;  // 又有更新的锁屏，等下一轮
            sLocked = NO;
            // v2.0.66.32: 本机解锁 100% 走此 1.0s 兜底路径(lockstate "0" 通知不派发)。
            // 此处仅作"确保 un-hide"的安全网: 若 DidBecomeActive 等解锁信号未达, 此处兜底揭示。
            // 不再做独立淡入(圆点统一由原生解锁动画携带揭示); sUnlockFading 抑制其后逐帧淡入(防重抖)。
            MKUnlockRevealOverlays();   // v2.0.66.32: 即时 un-hide(原生携带) 替代延迟淡入
            MKRefreshAllIcons();
            
        } @catch (NSException *e) {
            RDLog(@"UNLOCK(timer) EXCEPTION: %@", e.reason);
        }
    });
    dispatch_resume(sUnlockTimer);
}

static void MKLockStateCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    @try {
        NSString *n   = (__bridge NSString *)name;
        NSString *obj = (__bridge NSString *)object;
        BOOL lockNow = NO;
        if ([n isEqualToString:@"com.apple.springboard.lockcomplete"]) {
            lockNow = YES;
        } else if ([n isEqualToString:@"com.apple.springboard.lockstate"]) {
            // v1.6.75: lockstate 对象 "0" 即解锁 —— 若本设备派发，立即精确复原（无延迟/无闪现）
            if ([obj isEqualToString:@"0"]) {
                if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
                sLocked = NO;
                MKUnlockRestore();  // v2.0.1: 延迟淡入，不在解锁动画进行中硬显示
                
                return;
            }
            lockNow = [obj isEqualToString:@"1"];
        }
        // v1.6.70: 只在"锁屏"时隐藏所有指示器并记录锁屏时刻。
        // 解锁后的"复位显示"不再依赖 lockstate 解锁通知（某些 roothide/16.x 环境
        // 该通知不送达或对象语义不符，导致解锁后指示器长时间空白、需滑动才出现）。
        // 改为由 MKUpdate 的"时间闸门"自动复位：sLocked=YES 后超过 0.7s
        // （解锁动画 ~0.5s 已结束）的下一次布局即正常显示，无需特定解锁通知。
        if (lockNow) {
            sLocked = YES;
            sLockAt = [NSDate date].timeIntervalSince1970;
            MKSetAllIndicatorsHidden(YES);
            MKScheduleUnlock();  // v1.6.75: 排兜底复原定时器
            
        }
        // 解锁不再在此处理：交由 MKUpdate 时间闸门 + 兜底定时器自动复位（见 sLocked 守卫）。
    } @catch (NSException *e) {
        RDLog(@"LOCK observer exception: %@", e.reason);
    }
}
// 前向声明（setContentOffset: 钩子调用，定义在 sInitDone 之后）
static void MKMarkScrolling(UIView *scrollView);
// 前向声明（v1.6.31: SBIconView 类静态化，定义在文件后部，但前部遍历循环已调用）
static Class MKSBIconViewClass(void);
// 前向声明（beta 点类判定，定义于文件后部 ~L776；MKGetCachedBid 回收清理处需调用）
static BOOL MKBetaClass(UIView *v);

// 缓存 bundleID（避免每次 layoutSubviews 都调 applicationBundleID）
// v1.5.4: 检测 icon 变化（SBIconView 回收复用）+ 过滤文件夹图标
static NSString *MKGetCachedBid(SBIconView *iv) {
    id icon = [iv icon];
    if (!icon) return nil;

// 检测图标是否变了（SBIconView 回收复用：同一个 view 可能从 App A 变成文件夹）
    id cachedIcon = objc_getAssociatedObject(iv, &kMKIconKey);
    if (cachedIcon && cachedIcon != icon) {
        // icon 变了 → 清除所有缓存 + 移除旧指示器
        // v1.6.60: 同步清掉注册表里这个视图的旧 bid 条目（避免回收复用后旧 bid 仍指向它）
        NSString *oldBid = objc_getAssociatedObject(iv, &kMKBidKey);
        if (oldBid && sBidToIconView) [sBidToIconView removeObjectForKey:oldBid];
        // v1.6.99: 回收复用时清掉旧 label 自身残留的 kMKLabelBidKey 关联。
        // 否则 label 视图对象跨 icon 复用会保留上一个运行中 App 的 bid，导致后续
        // 该 view 显示非运行中 App 时，setHidden: 被 hook 误判成「旧 App 仍需藏名」
        // → 新 App 名称被错杀、滑屏时随机消失（用户报告的「名称随机不见一会」）。
        UIView *oldLabel = objc_getAssociatedObject(iv, &kMKLabelKey);
        if (oldLabel) {
            MKAssocLabelBid(oldLabel, nil);
            // v2.0.3: 回收复用时顺手清掉 label→iv 直接指针关联，避免跨 icon 复用残留旧 iv
            objc_setAssociatedObject(oldLabel, &kMKLabelIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(iv, &kMKBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(iv, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // v1.6.64: 不再在此移除指示器——指示器按 bid 索引、挂在稳定的 overlay 层，
        // 图标被回收复用时不随 SBIconView 消失/乱飞；仅在 App 退出/前台/文件夹时才由 MKUpdate 移除。
        // v2.0.66.2: 回收复用清掉残留 iOS 原生 beta 小黄点(SBIconBetaLabelAccessoryView，
        // 名称 label 的兄弟节点直挂 SBIconView)。旧 App 是 beta 时该点被留下(本意保黄点)，
        // icon 换成非 beta App 后 iOS 不自动清 → 残留在普通 App 名称旁("到处出现/捉迷藏"，用户 rd_log135 实锤)。
        // 仅在【换图标(本分支)】时清：iOS 会在布局时按新 App 是否真 beta 自行决定要不要重建该点，
        // 故无条件清旧点不会误删真 beta App 的黄点(它会被 iOS 重建)；只清掉残留的"上一任"点。
        for (UIView *sv in [iv.subviews copy]) {
            if (MKBetaClass(sv)) [sv removeFromSuperview];
        }
    }
    objc_setAssociatedObject(iv, &kMKIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // v1.6.0: 过滤文件夹图标 — 精确匹配，不误杀文件夹内App
    // 旧版 containsString:@"Folder" 可能误杀类名含 Folder 的App图标
    // 只过滤 SBFolderIcon（文件夹本身的复合图标），不过滤文件夹内的App图标
    // v1.6.31: 常量类静态化 —— 避免每个图标每次 layoutSubviews 都跑
    // NSStringFromClass + 2×NSClassFromString + 2×字符串比较（纯边角料、行为不变）
    // v2.0.31: 同类「类名含 Label」判定（布局 BFS L3039 / 快照探针 L3166）已统一改用
    // class_getName()+strstr 零分配，对齐 MKIsFolderIcon(L263) 的写法
    static Class sFolderIconClass = Nil;
    static Class sIconFolderIconClass = Nil;
    static dispatch_once_t sFolderClsOnce;
    dispatch_once(&sFolderClsOnce, ^{
        sFolderIconClass     = NSClassFromString(@"SBFolderIcon");
        sIconFolderIconClass = NSClassFromString(@"SBIconFolderIcon");
    });
    if ((sFolderIconClass     && [icon isKindOfClass:sFolderIconClass]) ||
        (sIconFolderIconClass && [icon isKindOfClass:sIconFolderIconClass])) {
        return nil;
    }

    NSString *bid = objc_getAssociatedObject(iv, &kMKBidKey);
    if (bid) return bid;
    if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        bid = [icon applicationBundleID];
        if (bid) objc_setAssociatedObject(iv, &kMKBidKey, bid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return bid;
}

// 缓存名字标签视图（避免每次 layoutSubviews 都跑 MKFindLabelView 4 重策略）
//
// v2.0.66.47 【结构性改造：把被丢弃的案发对象带出来】
// ─────────────────────────────────────────────────────────────────────
// 本函数在 owner ≠ 当前 iv 时返回 nil。而「owner ≠ 当前 iv」正是【串名的定义本身】。
// 于是形成一个逆向门控：
//     不串名 → 拿得到 label → 上层 dock 防线正常跑；
//     真串名 → label 被丢弃 → 上层三层防线(.31 祖先链 / .38 物理坐标 / .46 二合一)
//               全部挂在这一个取数点上，一个 nil 让它们【同时静默失效】。
// 逐版本核查证实：本函数内 `label = nil` 恒为 2 处，从 .31 出生第一天起未变过
// (.31/.37/.38/.40/.43/.45/.46 全部 =2)，八个版本一直在扩大「什么算 dock」，
// 从没人碰过「拿不到 label 就返回」这一条 —— 这就是 dock 串名 8 战 0 胜的机械原因。
//
// 改造方式：新增 out 参数把「本该被丢弃的那个 label」交给调用方，供 dock 侧做
// default-deny 处置（见 MKDockStrayHide）。签名保持不变的 MKGetCachedLabel 作为
// 薄包装保留，33 个既有调用点【一行不动】，行为完全等价，零回归面。
static UIView *MKGetCachedLabelEx(SBIconView *iv, UIView **outForeign) {
    if (outForeign) *outForeign = nil;
    UIView *label = objc_getAssociatedObject(iv, &kMKLabelKey);
    if (label && label.superview) {
        // v2.0.35: 所有权校验 —— 仅当 label 仍有效归属本 iv 才直接复用；
        // 若它已被「别的（活着的）iconView」占用，说明本 iv 被回收复用、旧 label
        // 残留串台（Dock 槽位 Safari 图标显示成抖音极速版即此），失效重找。
        // 注意：owner==nil（首次/回收后刚被 MKGetCachedBid 清掉 kMKLabelIconKey）属正常，不拒。
        UIView *owner = objc_getAssociatedObject(label, &kMKLabelIconKey);
        if (owner && owner != (id)iv) {
            objc_setAssociatedObject(iv, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (outForeign) *outForeign = label;   // v2.0.66.47: 带出案发对象（原地丢弃 → 上层永远看不见）
            label = nil;
        } else {
            return label;  // 仍然有效
        }
    }
    // 缓存失效 → 重新查找
    label = MKFindLabelView(iv);
    if (label) {
        // v2.0.35: 若找到的 label 已绑定到别的 iconView，说明它是邻位/回收残留，
        // 不缓存给本 iv（否则仍会串台），直接返回 nil 让调用方走 FALLBACK。
        // owner==nil 或 owner==iv 才是本 iv 的合法 label。
        UIView *owner = objc_getAssociatedObject(label, &kMKLabelIconKey);
        if (owner && owner != (id)iv) {
            if (outForeign) *outForeign = label;   // v2.0.66.47: 带出案发对象（此路更权威——策略1 走的是 SBIconView 系统 accessor，返回的就是本 iv 当下真正挂着的那张 label）
            label = nil;
        } else {
            objc_setAssociatedObject(iv, &kMKLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // v2.0.3: 同时给 label 挂「指向所属 SBIconView 的直接指针」（层级无关）。
            // 关文件夹缩回动画期间 iOS 会把内部 App 的 label 临时重父到动画层，
            // 使 MKLabelToBid 的 superview 层级查找全部失效 → 漏藏 → 名称闪现。
            // 直接指针随 label 对象自身走，重父/重建时仍可被 MKLabelToBid 取出，绕过层级解出 bid。
            objc_setAssociatedObject(label, &kMKLabelIconKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (outForeign) *outForeign = nil;     // 已找到本 iv 的合法 label，前面那次陈旧缓存不再视为案发对象
        }
    }
    return label;
}

// 签名不变的薄包装：既有 33 个调用点全部继续走这里，行为与 .46 完全等价。
static UIView *MKGetCachedLabel(SBIconView *iv) {
    return MKGetCachedLabelEx(iv, NULL);
}

// v2.0.30: beta（TestFlight）小黄点保护 —— 运行中 App 藏名时不再连带藏掉小黄点。
// 真因（rd_log(72) 铁证）：小黄点是「名称 label」子树的深层后代；核心藏名把整张 label
// 设 hidden=YES，于是小黄点被连带藏掉。
// 做法（稳定）：
//   运行中 —— 仅当小黄点「仍在 label 内」时把它脱离挂到 SBIconView（脱离后跳过 → 不每帧抖动）；
//               脱离前先清掉 iconView 上我们此前脱离的孤儿点，保证同一时刻最多 1 个。
//   退出/恢复 —— 只移除我们脱离到 iconView 的小黄点，由系统自身在原 label 重建自己的点（原生恢复，稳定）。
// 完全不碰藏名不变量 / 源级 setHidden:/setAlpha: hook。
// v2.0.35: 排除「最近更新」蓝点(SBIconRecentlyUpdatedLabelAccessoryView) —— 其类名含
// "Accessory"，原宽匹配会误判成 TestFlight 小黄点（rd_log(77) 铁证：3 条
// BETA-RESTORE-VIS bid=(null) cls=SBIconRecentlyUpdatedLabelAccessoryView）。
// 真·小黄点无论子版本叫什么（只要含 Accessory/Beta）仍被命中，不回归 v2.0.30。
// v2.0.49: 零分配版 —— 用 class_getName()+strstr 替代 NSStringFromClass+rangeOfString，
// 避免「每帧 layout BFS 对子视图保 beta 点」场景下反复分配 NSString（原写法有性能退化）。
static BOOL MKBetaClass(UIView *v) {
    if (!v) return NO;
    const char *n = class_getName([v class]);
    if (strstr(n, "RecentlyUpdated")) return NO; // 排除最近更新蓝点（同含 "Accessory"）
    return strstr(n, "Accessory") || strstr(n, "Beta");
}
// v2.0.66.3: 隐藏路径专用匹配——只认真·beta 点(类名含 "Beta"), 排除最近更新蓝点。
// 比 MKBetaClass 的宽匹配("Accessory"||"Beta")更保守: 关「保留小黄点」时绝不误藏
// 非 beta 的 accessory 视图(如下载中进度)。keep 开启路径仍用 MKBetaClass(保住未知子类)。
static BOOL MKBetaHideClass(UIView *v) {
    if (!v) return NO;
    const char *n = class_getName([v class]);
    if (strstr(n, "RecentlyUpdated")) return NO;
    return strstr(n, "Beta");
}
// v2.0.66.3: 关「保留小黄点」时, 对称地把一个图标(含未运行 TF App)上所有 beta 小黄点隐藏,
// 修「关了仍有 beta 黄点」(原生 beta 点直挂图标, 插件原本只在运行 App 藏名路径碰它)。
// 仅在 MKRefreshAllIcons(prefs 变更) 走一次, 非每帧。BFS 整棵以确保嵌套的 beta 点也藏掉。
static void MKBetaHideAll(UIView *iv) {
    if (!iv) return;
    // v2.0.66.86: 角标模式 —— 小黄点整套 machinery 交还系统。
    // 这套东西(脱离/复显/对齐/全藏)存在的【唯一】理由是「我们把 label 整张藏掉会把同区的
    // 小黄点一起带走」。角标模式名字全程不动 → 小黄点从未被我们影响 → 任何主动干预都是
    // 无理由地跟系统抢控制权(还会引入偏上/闪烁/孤儿点累积)。故一律不动手。
    // 「保留小黄点」开关在角标模式下同样无意义, 设置页会置灰。
    if (!MKHideNames()) return;
    NSMutableArray *st = [NSMutableArray arrayWithArray:(NSArray *)[iv subviews]];
    while (st.count) {
        UIView *v = [st lastObject]; [st removeLastObject];
        if (MKBetaHideClass(v)) {
            if (!v.hidden && v.alpha > 0.0f) {
                v.hidden = YES; v.alpha = 0.0f; v.layer.opacity = 0.0f; v.opaque = NO;
            }
        }
        [st addObjectsFromArray:v.subviews];
    }
}
// 在 label 子树里 BFS 找小黄点（label → SBUILegibilityContainerView → 更内层，故整棵搜）
static UIView *MKFindBetaInLabel(UIView *label) {
    if (!label) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:label];
    while (stack.count) {
        UIView *v = [stack lastObject]; [stack removeLastObject];
        if (v != label && MKBetaClass(v)) return v;
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}
// 运行中：把小黄点从名称 label 脱离挂到 SBIconView（仅当仍在 label 内才动，脱离后跳过 → 不每帧抖动）。
// 先清掉 iconView 上我们之前脱离的残留孤儿点，避免 UIKit 重建 label 时累积多个。
// v2.0.63: β点(SBIconBetaLabelAccessoryView)是文本标签兄弟节点。iOS 在 label.alpha=0 时把 β点
// y 钉到 label 顶沿(y≈62)而非竖直居中文本中心(y≈72.33)，差半个标签高→"偏上"。复显后把 β点
// center.y 对齐到文本标签 center.y、水平保留 iOS 原生 x，灭偏上。
static void MKEnsureBetaVertAlign(UIView *iconView, UIView *dot) {
    if (!iconView || !dot) return;
    // v2.0.66.86: 角标模式不动小黄点坐标 —— 「偏上」这个 bug 本身就是我们藏 label 导致
    // iOS 把 β点 y 钉到 label 顶沿的次生问题; 名字不藏则 iOS 自己摆得就是对的, 再去纠正
    // 反而与系统布局互搏。见 MKBetaHideAll 同款说明。
    if (!MKHideNames()) return;
    UIView *label = MKGetCachedLabel((SBIconView *)iconView);
    if (label) {
        CGFloat ly = label.center.y;
        dot.center = CGPointMake(dot.center.x, ly);
    }
}

// v2.0.50: 把任意 MKBetaClass 小黄点（无论在 label 内还是兄弟节点）脱离/保住到 iconView，
// 确保它永不困在被藏的 label 内 → 任意时刻可见，不必等滑屏。坐标：优先用点当前
// 父视图转换到 iconView；父视图不存在（极端）则沿用其 center。
static void MKEnsureBetaOnIconView(UIView *iconView, UIView *dot) {
    if (!iconView || !dot) return;
    // v2.0.66.86: 角标模式不脱离小黄点 —— 脱离是为了让它逃出「被我们藏掉的 label」;
    // 角标模式 label 从不被藏, 脱离只会制造孤儿点与坐标偏移。见 MKBetaHideAll 同款说明。
    if (!MKHideNames()) return;
    // v2.0.62: β点兄弟节点(本机 iOS16 实测 SBIconBetaLabelAccessoryView 直挂 SBIconView)→
    // 仅原位保可见、绝不改 center(灭偏上)。已在 iconView 上时直接保可见即返回。
    if (dot.superview == iconView) {
        dot.hidden = NO; dot.alpha = 1.0f; dot.layer.opacity = 1.0f;
        MKEnsureBetaVertAlign(iconView, dot); // v2.0.63: 兄弟节点原地保可见 + 竖直对齐文本中心(灭偏上)
        objc_setAssociatedObject(dot, &kMKOurBetaKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return; // 兄弟节点：原地保可见，零位移
    }
    // 极少数嵌套(β点仍在被藏文本标签内)→ 清残留孤儿点 + 父视图有效才做坐标转换(非退化 dot.center)，安全脱离到 iconView
    for (UIView *sv in [iconView.subviews copy]) {
        if (sv != dot && MKBetaClass(sv)) [sv removeFromSuperview];
    }
    UIView *from = dot.superview;
    CGPoint c = (from && from != iconView) ? [from convertPoint:dot.center toView:iconView] : dot.center;
    [dot removeFromSuperview];
    [iconView addSubview:dot];
    dot.center = c;
    MKEnsureBetaVertAlign(iconView, dot); // v2.0.63: 脱离到 iconView 后竖直对齐文本中心(灭偏上)
    dot.hidden = NO; dot.alpha = 1.0f; dot.layer.opacity = 1.0f;
    objc_setAssociatedObject(dot, &kMKOurBetaKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // v2.0.33: 标记为我们脱离的，退出时只移这些
}



static void MKDetachBetaOnce(UIView *iconView) {
    if (!iconView) return;
    // v2.0.66.86: 角标模式不介入小黄点(交还系统)。见 MKBetaHideAll 同款说明。
    // 放在最前 —— 早于 MKGetCachedLabel + MKFindBetaInLabel 的每帧子树 BFS, 顺带省开销。
    if (!MKHideNames()) return;
    UIView *label = MKGetCachedLabel((SBIconView *)iconView);
     // v2.0.64: 仅调试开时枚举(生产零开销，省每帧 MKGetCachedBid 求值)
    // v2.0.30: 「保留小黄点」开关 —— 关则退回 v2.0.23 行为（不保护，由藏名逻辑连带藏掉 beta 点）
    if (![MKConfig sharedConfig].keepBetaDot) return;
    if (!label) return;
    // v2.0.58: 删除下方「无点」闩锁优化（原 L829 早退 + L832 写标记）—— 锁屏/解锁过渡中
    // iOS 临时摘掉运行中 App 的原生小黄点 -> MKFindBetaInLabel 瞬间假阴性 -> 旧逻辑会把此 label
    // 永久标记"无点" -> 即便点重建回来，MKDetachBetaOnce 也因缓存命中永远跳过 -> 小黄点消失且
    // 只有滑屏重建整页 label 才复位（rd_log(187) 实锤：整个「锁->解->滑->再锁」循环 BETA-DETACH=0）。
    // 回退到 v2.0.30 加缓存前的每帧新鲜扫描，即 v2.0.43 无此 bug 的基线。
    UIView *dot = MKFindBetaInLabel(label);
    if (!dot) {
        return; // 非 beta / 已脱离 -> 不动，保留 iconView 上现有脱离点（v2.0.58: 不再闩锁"无点"）
    }
    MKEnsureBetaOnIconView(iconView, dot); // v2.0.50: 统一走 helper（含坐标退化 + 脱落到 iconView）
    
}
// 退出/恢复：移除我们脱离到 iconView 的小黄点（系统会在原 label 重建自己的点，原生恢复）。
// v2.0.66.86: 本函数【刻意不加 MKHideNames() 门控】—— 它的动作是「撤销我们的干预、还原系统
// 原生状态」, 正是角标模式想要的。从替换模式切到角标模式时, 之前脱离出来的孤儿点必须靠它清掉,
// 否则会与系统在 label 内重建的原生点重影(两个小黄点)。
static void MKRestoreBetaOrphan(UIView *iconView) {
    // v2.0.33: 只移除「我们脱离时打过 kMKOurBetaKey 标记的」小黄点；
    // 绝不动系统原生的 TestFlight 黄点（它也是 MKBetaClass，但非我们脱离的）。
    if (!iconView) return;
    BOOL removed = NO;
    for (UIView *sv in [iconView.subviews copy]) {
        if ([objc_getAssociatedObject(sv, &kMKOurBetaKey) boolValue]) {
            [sv removeFromSuperview]; removed = YES;
        }
    }
    
}

// v2.0.34: force re-show hidden beta dot after keepBetaDot OFF->ON.
// keepBetaDot=NO hides beta (hidden=YES); switching ON only stops hiding but
// does NOT re-show the already-hidden dot. This walks each icon's subtree in
// MKRefreshAllIcons (always runs on prefs change) and re-lights MKBetaClass views.
static void MKBetaReconcile(SBIconView *iconView) {
    if (!iconView) return;
    NSMutableArray *st = [NSMutableArray arrayWithArray:(NSArray *)[iconView subviews]];
    while (st.count > 0) {
        UIView *v = [st lastObject]; [st removeLastObject];
        if (MKBetaClass(v) && (v.hidden || v.alpha <= 0.0f)) {
            v.hidden = NO; v.alpha = 1.0f; v.layer.opacity = 1.0f; v.opaque = NO;
            MKEnsureBetaVertAlign((UIView *)iconView, v); // v2.0.63: 复显后竖直对齐文本中心(灭偏上)
            
        }
        [st addObjectsFromArray:v.subviews];
    }
}

// ─── 状态去重：同一个 bundleID 的 (running, foreground) 没变就不刷新 ──
static NSMutableDictionary<NSString*, NSDictionary*> *sLastState = nil;
static BOOL MKStateDidChange(NSString *bid, BOOL running, BOOL foreground) {
    if (!sLastState) sLastState = [NSMutableDictionary dictionary];
    NSDictionary *prev = sLastState[bid];
    BOOL prevRun = prev ? [prev[@"r"] boolValue] : NO;
    BOOL prevFg = prev ? [prev[@"f"] boolValue] : NO;
    if (prevRun == running && prevFg == foreground) return NO;
    sLastState[bid] = @{@"r": @(running), @"f": @(foreground)};
    return YES;
}

// ─── 系统进程黑名单（只过滤无桌面图标的纯后台服务 + 越狱工具）─────────
// 用户手动打开的系统App（设置、短信、天气、相机等）应该显示绿点
static NSArray *sBlacklist = nil;
static void MKInitBlacklist() {
    sBlacklist = @[
        // ── 无桌面图标的纯后台服务 ──
        @"com.apple.springboard",           // SpringBoard 自身
        @"com.apple.PosterBoard",           // 墙纸/锁屏管理（无桌面图标）
        @"com.apple.AccessibilityUIServer",  // 无障碍服务（无桌面图标）
        @"com.apple.Spotlight",             // Spotlight搜索（无桌面图标）
        @"com.apple.NanoUniverse.AegirProxyApp", // 后台代理
        @"com.apple.SleepLockScreen",       // 锁屏后台
        @"com.apple.GameCenterRemoteAlert", // GameCenter弹窗后台
        @"com.apple.CoreAuthUI",            // 认证UI后台
        // ── 越狱工具 ──
        @"wiki.qaq.trapp",                  // 越狱工具App
        @"wiki.qaq.TrollFools",
        @"com.opa334.Dopamine-roothide",
        @"com.roothide.manager",
        @"com.tigisoftware.Filza",
        @"org.coolstar.SileoStore",
        @"com.muirey03.cr4shedgui",
        @"netdisk_iPhone.files_extension",   // 网盘扩展
    ];
}

static BOOL MKIsBlacklisted(NSString *bid) {
    if (!sBlacklist) MKInitBlacklist();
    for (NSString *b in sBlacklist) {
        if ([bid isEqualToString:b] || [bid hasPrefix:b]) return YES;
    }
    // 通配：所有 .jbroot 路径的越狱 App
    if ([bid containsString:@"qaq."] || [bid containsString:@"roothide"]) return YES;
    // 系统扩展 (.appex)
    if ([bid containsString:@"Extension"] || [bid containsString:@".appex"]) return YES;
    return NO;
}

// ─── 全局状态 ─────────────────────────────────────────────
static BOOL  sInitDone     = NO;

// v1.6.52: 滚动/翻页守卫 —— 滚动中不重定位/创建指示器，避免翻页 churn 与粘错
static BOOL  sScrolling     = NO;
static NSTimeInterval sLastScrollTS = 0;
static BOOL  sScrollSettleScheduled = NO;
static void MKMarkScrolling(UIView *scrollView) {
    (void)scrollView;
    if (!sInitDone) return;
    sScrolling = YES;
    sLastScrollTS = [NSDate date].timeIntervalSince1970;
    if (!sScrollSettleScheduled) {
        sScrollSettleScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 320 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            sScrollSettleScheduled = NO;
            if (sInitDone && [NSDate date].timeIntervalSince1970 - sLastScrollTS >= 0.30) {
                sScrolling = NO;
                MKRefreshAllIcons();  // v1.6.56: 翻停后刷新所有页面图标，确保跨页指示器都正确创建/重定位（不再只刷单个 scrollview）
            }
        });
    }
}
static NSMutableSet<NSString*> *sRunningSet = nil;
static NSMutableDictionary<NSString*, NSString*> *sPathToBundleID = nil;
static NSMutableDictionary<NSString*, NSString*> *sBidToExePath = nil;
static NSMutableArray *sLifecycleObservers = nil;
static NSTimeInterval sDisableTS = 0;
static BOOL  sDisableChecked = NO;
static BOOL  sDisabled = NO;
static NSMutableSet<NSString*> *sForegroundBIDs = nil; // 当前前台 App 不显示其桌面指示器
static NSMutableSet<NSString*> *sPendingBIDs    = nil; // v1.5.6+: 等待300ms后才显示指示器的App（标签已隐藏，指示器待创建）
static NSMutableSet<NSString*> *sAnimateIndicatorBIDs = nil; // v1.5.7: 指示器需要渐显动画的 App（状态切换时创建）
static NSMutableSet<NSString*> *sFadingLabelBIDs    = nil; // v1.5.8: 标签正在渐隐中的 App（250ms 动画期间不干扰）
static NSMutableDictionary<NSString*, UIColor*> *sIconColorCache = nil; // v1.5.7: bundleID → 图标主色调缓存
static NSMutableSet<NSString*> *sIconColorMissLogged = nil; // v1.6.12: 取色失败诊断（每 bid 只记一次）
static dispatch_queue_t sColorDiskQueue = nil; // v2.0.66.6: 颜色缓存写盘串行队列（后台异步，避免主线程 jank）

// v2.0.66.73: 最终优化 —— 删除全部 sDebugLog/sProbeLog 调试门控与 MKDebugDumpBetaLabel/MKLogRevealAttempt 调试函数(RDLog 为编译期 no-op 宏, 参数不求值, 删之零行为影响); 仅 RDLogRunning 守卫保留以维持 .47 行为。
// 调试/探针门控已全部清除(RDLog 为编译期 no-op 宏, 参数不求值; 全部 sDebugLog/sProbeLog 门控已删除)。
// 仅 RDLogRunning 保留 if(!sDebugLog) return; 守卫以维持 .47 行为; sProbeLog 声明已删除。
// v2.0.66.74: 续优化 —— 删除探针遗留 write-only 计数器(sFlashWindow/sFlashStart/sFlashLogCount/sRevealLogCount/sThumbLogCount/sFolderCloseDiag/sFolderCloseVisDiag) 与 sRunLogCounts/sCallCount(仅 RDLogRunning 死体/sCallCount 仅死日志读) 及 kMKIndicatorContainerKey(仅关联 nil 从未读); 全部运行期零副作用, 行为严格等价 .47。
// 文件夹打开/滚动刷新合并：避免同一事件多次触发全量刷新
static BOOL  sFolderRefreshScheduled = NO;   // 文件夹刷新是否已排程（300ms 内只排一次）
static NSTimeInterval sLastFolderOpenTS = 0; // 上次文件夹打开时间戳（0.4s 内去重）
static BOOL  sScrollRefreshScheduled = NO;   // 滚动刷新是否已排程（120ms 内只排一次）

// ─── sPendingBIDs 辅助 ─── v1.5.6+ ───
// 前台→后台时，立即隐藏标签但延迟300ms创建指示器
// pending 期间：layoutSubviews/MKUpdate 只隐藏标签，不创建指示器
static void MKAddPending(NSString *bid) {
    if (!sPendingBIDs) sPendingBIDs = [NSMutableSet set];
    [sPendingBIDs addObject:bid];
}
static BOOL MKIsPending(NSString *bid) {
    return sPendingBIDs && [sPendingBIDs containsObject:bid];
}
static void MKRemovePending(NSString *bid) {
    if (sPendingBIDs) [sPendingBIDs removeObject:bid];
}

// ─── sAnimateIndicatorBIDs 辅助 ─── v1.5.7 ───
// 标记哪些 App 的指示器需要渐显动画（只在状态切换时触发，初始刷新不渐显）
static void MKAddAnimateIndicator(NSString *bid) {
    if (!sAnimateIndicatorBIDs) sAnimateIndicatorBIDs = [NSMutableSet set];
    [sAnimateIndicatorBIDs addObject:bid];
}
static BOOL MKShouldAnimateIndicator(NSString *bid) {
    return sAnimateIndicatorBIDs && [sAnimateIndicatorBIDs containsObject:bid];
}
static void MKRemoveAnimateIndicator(NSString *bid) {
    if (sAnimateIndicatorBIDs) [sAnimateIndicatorBIDs removeObject:bid];
}

// ─── sFadingLabelBIDs 辅助 ─── v1.5.8 ───
// 标签正在渐隐中的 App（250ms 动画期间，layoutSubviews 不干扰）
static void MKAddFadingLabel(NSString *bid) {
    if (!sFadingLabelBIDs) sFadingLabelBIDs = [NSMutableSet set];
    [sFadingLabelBIDs addObject:bid];
}
static BOOL MKIsFadingLabel(NSString *bid) {
    return sFadingLabelBIDs && [sFadingLabelBIDs containsObject:bid];
}
static void MKRemoveFadingLabel(NSString *bid) {
    if (sFadingLabelBIDs) [sFadingLabelBIDs removeObject:bid];
}

// ─── 图标主色调采样 ─── v1.5.7 / v1.6.11 ───
// 从 App 图标取“主色调(dominant color)”，用于 AutoIcon 颜色模式
// 方法：尝试 SBIcon/SBIconView accessor 获取图标 UIImage → 缩到 32x32 采样
//       → 按 HSB 色相分 36 桶(每桶 10°)统计有彩色像素的“面积占比”
//       → 取占比最高的桶 → 该桶内的(平均 HSB)即图标主色
// 排除 透明/纯白/纯黑/灰色（背景/描边/文字底不是“图标颜色”）
// 不强行增强饱和度/亮度、绝不改动色相 → 蓝就是蓝、绿就是绿
static UIColor *MKDominantColorFromImage(UIImage *image) {
    if (!image) return nil;
    CGImageRef cgImg = image.CGImage;
    if (!cgImg) return nil;

    const int S = 32; // 采样分辨率
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *pixels = (unsigned char *)calloc((size_t)S * S, 4);
    CGContextRef ctx = CGBitmapContextCreate(pixels, S, S, 8, S * 4, colorSpace,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!ctx) {
        free(pixels);
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, S, S), cgImg);

    // 36 个色相桶（每桶 10°），统计有彩色像素的“面积占比”
    double binCount[36] = {0};
    double binH[36] = {0}, binS[36] = {0}, binB[36] = {0};
    // 兜底：若整图近灰阶（无彩色像素），退回不透明像素普通均值
    CGFloat pSumR = 0, pSumG = 0, pSumB = 0, pCount = 0;

    for (int i = 0; i < S * S; i++) {
        unsigned char *p = pixels + i * 4;
        CGFloat a = p[3] / 255.0f;
        if (a < 0.5f) continue; // 跳过透明（圆角/遮罩外）

        // 去 premultiply 还原真实 RGB
        CGFloat r = (p[0] / 255.0f) / a;
        CGFloat g = (p[1] / 255.0f) / a;
        CGFloat b = (p[2] / 255.0f) / a;
        pSumR += r; pSumG += g; pSumB += b; pCount += 1.0f;

        CGFloat hue, sat, br, al;
        UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
        [c getHue:&hue saturation:&sat brightness:&br alpha:&al];

        // 这些不是“图标颜色”：背景白、阴影黑、灰阶描边/文字底 → 不计入主色
        if (br > 0.96f && sat < 0.12f) continue; // 近白
        if (br < 0.07f) continue;                 // 近黑
        if (sat < 0.10f) continue;                // 近灰

        // 色相分桶（桶内仅 10°，无需处理色相环绕）
        int bin = (int)(hue * 36.0f) % 36;
        if (bin < 0) bin += 36;
        binCount[bin] += 1.0;
        binH[bin] += hue;
        binS[bin] += sat;
        binB[bin] += br;
    }

    free(pixels);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // 找占比最高的桶 = 图标主色
    int best = -1; double bestN = 0;
    for (int b = 0; b < 36; b++) {
        if (binCount[b] > bestN) { bestN = binCount[b]; best = b; }
    }

    if (best >= 0 && bestN > 0) {
        CGFloat h = (CGFloat)(binH[best] / bestN);
        CGFloat s = (CGFloat)(binS[best] / bestN);
        CGFloat br = (CGFloat)(binB[best] / bestN);
        // 最小可见性保护：只钳亮度，不改色相、不过度增饱和（保持“主色”本意）
        if (br < 0.30f) br = 0.30f;
        if (br > 0.85f) br = 0.85f;
        return [UIColor colorWithHue:h saturation:s brightness:br alpha:1.0f];
    }

    // 没有彩色像素（纯灰阶图标）→ 退回普通均值，至少有个颜色
    if (pCount > 0) {
        return [UIColor colorWithRed:(pSumR / pCount) green:(pSumG / pCount) blue:(pSumB / pCount) alpha:1.0f];
    }
    return nil;
}

// v2.0.66.5: 从 SBIcon 模型对象取图标 UIImage（不依赖 SBIconView 在屏幕上，供文件夹内 App 关窗态取色兜底）
static UIImage *MKIconImageFromIcon(id icon) {
    if (!icon) return nil;
    @try {
        CGFloat scale = [UIScreen mainScreen].scale;
        NSArray *iconImageSelectors = @[ @"applicationIconImageForScreenScale:", @"iconImageForScreenScale:" ];
        for (NSString *selName in iconImageSelectors) {
            SEL sel = NSSelectorFromString(selName);
            if ([icon respondsToSelector:sel]) {
                NSMethodSignature *sig = [icon methodSignatureForSelector:sel];
                if (sig && sig.numberOfArguments == 3) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:icon];
                    [inv setSelector:sel];
                    [inv setArgument:&scale atIndex:2];
                    [inv invoke];
                    __unsafe_unretained id result = nil;
                    [inv getReturnValue:&result];
                    if ([result isKindOfClass:[UIImage class]]) return result;
                } else if (sig && sig.numberOfArguments == 2) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id result = [icon performSelector:sel];
#pragma clang diagnostic pop
                    if ([result isKindOfClass:[UIImage class]]) return result;
                }
            }
        }
        NSArray *noArgSelectors = @[ @"applicationIconImage", @"iconImage", @"getImage" ];
        for (NSString *selName in noArgSelectors) {
            SEL sel = NSSelectorFromString(selName);
            if ([icon respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [icon performSelector:sel];
#pragma clang diagnostic pop
                if ([result isKindOfClass:[UIImage class]]) return result;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// v2.0.66.5: 按 bid 从 SBIconModel 取 SBIcon 模型对象（无论其 SBIconView 是否在屏幕上）
static id MKIconForBundleID(NSString *bid) {
    if (!bid.length) return nil;
    @try {
        Class ctrlCls = NSClassFromString(@"SBIconController");
        if (!ctrlCls) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id ctrl = [ctrlCls performSelector:NSSelectorFromString(@"sharedInstance")];
#pragma clang diagnostic pop
        if (!ctrl) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id model = [ctrl performSelector:NSSelectorFromString(@"iconModel")];
#pragma clang diagnostic pop
        if (!model) return nil;
        SEL sel = NSSelectorFromString(@"applicationIconForBundleIdentifier:");
        if (![model respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id icon = [model performSelector:sel withObject:bid];
#pragma clang diagnostic pop
        return icon;
    } @catch (NSException *e) {}
    return nil;
}

// 尝试从 SBIconView/SBIcon 获取图标 UIImage
static UIImage *MKGetIconImage(SBIconView *iv) {
    @try {
        id icon = [iv icon];

        // 策略 1: 从 SBIcon 取图标（抽出为 MKIconImageFromIcon，供文件夹内 App 关窗态取色兜底复用）
        if (icon) {
            UIImage *img = MKIconImageFromIcon(icon);
            if (img) return img;
        }

        // 策略 2: SBIconView 自身的 iconImage accessor
        NSArray *viewImageSelectors = @[ @"iconImage", @"_iconImage", @"image" ];
        for (NSString *selName in viewImageSelectors) {
            SEL sel = NSSelectorFromString(selName);
            if ([iv respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [iv performSelector:sel];
#pragma clang diagnostic pop
                if ([result isKindOfClass:[UIImage class]]) return result;
            }
        }

        // 策略 3（兜底，v1.6.12 修复）: 快照 SBIconView
        // ⚠️ 旧版用 1x1 上下文 + drawViewHierarchyInRect:iv.bounds → 只截到图标左上角 1x1 透明像素
        //    → 主色算法因 alpha<0.5 跳过 → 返回 nil → 永远走绿兜底（即“全是绿色”真因）
        // 修复：按 SBIconView 真实尺寸建图上下文，截到完整图标
        CGSize sz = iv.bounds.size;
        if (sz.width < 8.0f || sz.height < 8.0f) sz = CGSizeMake(60.0f, 74.0f);
        UIGraphicsBeginImageContextWithOptions(sz, NO, [UIScreen mainScreen].scale);
        [iv drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height) afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if (snapshot) return snapshot;

    } @catch (NSException *e) {
        RDLog(@"MKGetIconImage exception: %@", e.reason);
    }
    return nil;
}

// v2.0.66.6: 图标主色调缓存落盘 —— 跨注销(respring)持久，根治「注销后重来 / 要打开一次」的体验坑。
// 内存字典 sIconColorCache 仍是唯一真源；磁盘只做镜像。仅持久化「成功取到的真实色」，miss 默认色绝不落盘。
static NSString *MKColorCachePath() {
	return @"/var/mobile/Library/Preferences/com.mk.runningdotindicator.colors.plist";
}

// 启动时从磁盘加载已持久化的主色（mobile 可写目录，rootless 安全）。失败/缺失静默忽略，绝不崩 SpringBoard。
static void MKLoadColorCacheFromDisk() {
	@try {
		if (!sIconColorCache) sIconColorCache = [NSMutableDictionary dictionary];
		NSString *path = MKColorCachePath();
		if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
		NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
		if (![dict isKindOfClass:[NSDictionary class]]) return;
		for (NSString *bid in dict) {
			id v = dict[bid];
			if (![v isKindOfClass:[NSArray class]] || [v count] != 4) continue;
			CGFloat r = [v[0] doubleValue], g = [v[1] doubleValue], b = [v[2] doubleValue], a = [v[3] doubleValue];
			UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:a];
			if (c) sIconColorCache[bid] = c;
		}
		
	} @catch (NSException *e) {}
}

// 把当前内存缓存镜像写盘（后台串行队列异步 + atomic，避免主线程 jank 与半写损坏）。写失败静默忽略。
static void MKSaveColorCacheToDisk() {
	@try {
		if (!sColorDiskQueue) sColorDiskQueue = dispatch_queue_create("com.mk.rd.colorcache", DISPATCH_QUEUE_SERIAL);
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:sIconColorCache.count];
		for (NSString *bid in sIconColorCache) {
			UIColor *c = sIconColorCache[bid];
			CGFloat r, g, b, a;
			if ([c getRed:&r green:&g blue:&b alpha:&a]) {
				out[bid] = @[@(r), @(g), @(b), @(a)];
			}
		}
		NSString *path = MKColorCachePath();
		dispatch_async(sColorDiskQueue, ^{
			@try { [out writeToFile:path atomically:YES]; } @catch (NSException *e) {}
		});
	} @catch (NSException *e) {}
}

// 获取指定 bundleID 的图标主色调（带缓存）
static UIColor *MKCachedIconColorForBundleID(NSString *bid) {
    if (!sIconColorCache) { sIconColorCache = [NSMutableDictionary dictionary]; MKLoadColorCacheFromDisk(); }
    UIColor *cached = sIconColorCache[bid];
    if (cached) return cached;

    // 需要找到对应的 SBIconView 才能获取图标
    // 从当前视图层级搜索
    UIColor *result = nil;
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *window in windows) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
        while (stack.count > 0) {
            UIView *current = [stack lastObject];
            [stack removeLastObject];
            if ([current isKindOfClass:MKSBIconViewClass()]) {
                SBIconView *iv = (SBIconView *)current;
                NSString *ivBid = MKGetCachedBid(iv);
                if (ivBid && [ivBid isEqualToString:bid]) {
                    UIImage *img = MKGetIconImage(iv);
                    result = MKDominantColorFromImage(img);
                    if (result) break;  // 找到就停
                }
            }
            for (UIView *child in current.subviews) {
                [stack addObject:child];
            }
        }
        if (result) break;
    }

    // v2.0.66.5: 兜底 —— 文件夹关闭态内 App 的 SBIconView 不在窗口层级，窗口扫描取不到。
    // 改从 SBIconModel 按 bid 取 SBIcon 直接取色（不依赖屏幕上可见）。
    if (!result) {
        id icon = MKIconForBundleID(bid);
        if (icon) {
            UIImage *img = MKIconImageFromIcon(icon);
            if (img) result = MKDominantColorFromImage(img);
        }
    }

    if (result) {
        sIconColorCache[bid] = result;
        MKSaveColorCacheToDisk();
        
        return result;
    }
    // v1.6.11: 取不到图标 → 返回固定色用于即时显示，但【不缓存】
    // 这样下次 layout/刷新会重试取色；一旦图标可取到就自动修正（见 MKUpdate 重绘逻辑）
    // 否则首次取色失败会被永久缓存成绿兜底 → 表现为"全是绿色"
    // v1.6.12: 加诊断 —— 取色失败只记录一次，便于下次日志定位根因
    if (!sIconColorMissLogged) sIconColorMissLogged = [NSMutableSet set];
    if (![sIconColorMissLogged containsObject:bid]) {
        [sIconColorMissLogged addObject:bid];
        
        // v2.0.66.6: 图标未就绪导致取色失败 → 延迟 1s 重试一次（越过 SBIconController 初始化窗口）。
        // 此前用「下一 runloop」会与控制器初始化抢跑、几乎必败，于是文件夹 App 总要先打开一次才取到色。
        // sIconColorMissLogged 已保证每个 bid 只触发一次，不会无限重试。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (MKIsAppRunning(bid) && !MKIsForeground(bid)) {
                MKRefreshIconForBundleID(bid);
            }
        });
    }
    return [[MKConfig sharedConfig] color];
}

// ─── 文件日志（RDLog 已统一改为 no-op 宏，见文件顶部；此函数定义已移除，运行期不再写任何诊断到 rd_log.txt）──

// ─── 限流日志 RDLogRunning 已删除 (v2.0.66.78 / A4) ───
// 函数体自 .73 起仅剩 `if (!sDebugLog) return;`(sDebugLog 运行期恒假) → 空体死函数;
// RDLog 本身是编译期 no-op 宏, 无任何副作用。连同 sDebugLog 变量与唯一调用点一并删除。

// ─── 紧急开关 ────────────────────────────────────────────────
static BOOL MKIsDisabled() {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!sDisableChecked || (now - sDisableTS) > 5.0) {
        sDisableChecked = YES;
        sDisableTS = now;
        sDisabled = [[NSFileManager defaultManager]
                     fileExistsAtPath:@"/var/mobile/Documents/rd_disabled"];
        if (sDisabled) RDLog(@"!!! DISABLED via rd_disabled file !!!");
    }
    return sDisabled;
}

// ─── 安全包裹 ────────────────────────────────────────────────
static void MKSafe(void (^block)(void)) {
    @try { if (block) block(); }
    @catch (NSException *e) {
        RDLog(@"EXCEPTION: %@", e.reason);
    }
}

// ====================================================================
// 运行状态检测
// ====================================================================

static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (MKIsBlacklisted(bid)) {
        return;
    }
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    // v2.0.66.79 (A6): 原 BOOL wasNew = ![sRunningSet containsObject:bid]; 已删除 ——
    // .58 的「进运行态同步推送钉藏」(MKHideLabelForRunningBid) 在 .71 回退时一并删掉,
    // 该变量随之成为 write-only 死值(仅靠 Makefile -Wno-unused-but-set-variable 才编得过)。
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    // v2.0.66.79 (A6): 原 BOOL wasIn = ... 同为 .58 推送日志遗留的 write-only 死值, 已删除。
    [sRunningSet removeObject:bid];
}

static BOOL MKIsAppRunning(NSString *bundleID) {
    return sRunningSet && [sRunningSet containsObject:bundleID];
}

// ─── 前台应用集合：当前被用户打开正在使用的 App ─────────────────
// 这些 App 的桌面图标指示器应隐藏，因为用户已经在看它的 App 界面了
static void MKSetForeground(NSString *bid, BOOL foreground) {
    if (!bid.length) return;
    if (!sForegroundBIDs) sForegroundBIDs = [NSMutableSet set];
    if (foreground) {
        [sForegroundBIDs addObject:bid];
    } else {
        [sForegroundBIDs removeObject:bid];
    }
}

static BOOL MKIsForeground(NSString *bid) {
    return sForegroundBIDs && [sForegroundBIDs containsObject:bid];
}

// ─── NSFileManager 扫描构建 bundleID↔executablePath 映射 ────
static void MKBuildPathCache() {
    
    if (!sBidToExePath) sBidToExePath = [NSMutableDictionary dictionary];
    if (!sPathToBundleID) sPathToBundleID = [NSMutableDictionary dictionary];

    NSFileManager *fm = [NSFileManager defaultManager];
    int added = 0;

    NSArray *scanDirs = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application"
    ];

    for (NSString *baseDir in scanDirs) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:baseDir error:nil];
        if (!uuids) continue;

        for (NSString *uuid in uuids) {
            if ([uuid hasPrefix:@"."]) continue;  // roothide 前缀跳过

            NSString *uuidDir = [baseDir stringByAppendingPathComponent:uuid];
            NSArray *contents = [fm contentsOfDirectoryAtPath:uuidDir error:nil];
            if (!contents) continue;

            for (NSString *item in contents) {
                if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;

                NSString *appDir = [uuidDir stringByAppendingPathComponent:item];
                NSString *plistPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                if (!info) continue;

                NSString *bid = info[@"CFBundleIdentifier"];
                NSString *exeName = info[@"CFBundleExecutable"];
                if (!bid.length || !exeName.length) continue;

                NSString *exePath = [appDir stringByAppendingPathComponent:exeName];
                sBidToExePath[bid] = exePath;
                sPathToBundleID[exePath] = bid;
                added++;
            }
        }
    }

    // ─── 系统内置应用 ──────
    NSArray *sysApps = [fm contentsOfDirectoryAtPath:@"/Applications" error:nil];
    if (sysApps) {
        for (NSString *item in sysApps) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;

            NSString *appDir = [@"/Applications" stringByAppendingPathComponent:item];
            NSString *plistPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            if (!info) continue;

            NSString *bid = info[@"CFBundleIdentifier"];
            NSString *exeName = info[@"CFBundleExecutable"];
            if (!bid.length || !exeName.length) continue;

            NSString *exePath = [appDir stringByAppendingPathComponent:exeName];
            sBidToExePath[bid] = exePath;
            sPathToBundleID[exePath] = bid;
            added++;
        }
    }

    
}

// ─── SBApplicationController.runningApplications 初始同步 ────
static void MKSyncFromSBAppCtrl() {
    @try {
        id appCtrl = [SBApplicationController sharedInstance];
        if (!appCtrl) {
            
            return;
        }

        SEL runningSel = NSSelectorFromString(@"runningApplications");
        if (![appCtrl respondsToSelector:runningSel]) {
            
            return;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *runningApps = [appCtrl performSelector:runningSel];
#pragma clang diagnostic pop

        if (!runningApps) {
            
            return;
        }

        static Class sSBApplicationClass = Nil;
        static dispatch_once_t sSBAppOnce;
        dispatch_once(&sSBAppOnce, ^{
            sSBApplicationClass = NSClassFromString(@"SBApplication");
        });

        int count = 0;
        for (id app in runningApps) {
            if (![app isKindOfClass:sSBApplicationClass]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSString *bid = [app performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
            // v1.6.31: 只补"当前前台"的 App（避免把纯后台 App 加进集合）
            if (bid.length && !MKIsBlacklisted(bid) && MKIsForeground(bid)) {
                MKAddToRunningSet(bid);
                count++;
            }
        }
        

    } @catch (NSException *e) {
        RDLog(@"SBAppCtrl EXCEPTION: %@", e.reason);
    }
}

// ─── 进程路径→bundleID 反查 ──────────
static NSString *MKBidFromPath(NSString *fullPath) {
    NSString *bid = sPathToBundleID[fullPath];
    if (bid) return bid;

    NSString *appBundlePath = [fullPath stringByDeletingLastPathComponent];
    if ([appBundlePath hasSuffix:@".appex"]) {
        appBundlePath = [[appBundlePath stringByDeletingLastPathComponent]
                         stringByDeletingLastPathComponent];
    }
    if ([appBundlePath hasSuffix:@".app"]) {
        NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *bidFromInfo = info[@"CFBundleIdentifier"];
        if (bidFromInfo) {
            sPathToBundleID[fullPath] = bidFromInfo;
            return bidFromInfo;
        }
    }

    NSString *appName = [appBundlePath lastPathComponent];
    if ([appName hasSuffix:@".app"] && sBidToExePath) {
        for (NSString *cachedBid in sBidToExePath) {
            NSString *cachedPath = sBidToExePath[cachedBid];
            if ([cachedPath containsString:appName]) {
                sPathToBundleID[fullPath] = cachedBid;
                return cachedBid;
            }
        }
    }

    return nil;
}

// ─── 进程枚举（辅助，仅补充用户 App）─────────
static void MKComputeRunningSetFromProc() {
    @try {
        int pidBuf[512];
        int retBytes = proc_listallpids(pidBuf, sizeof(pidBuf));
        if (retBytes <= 0) return;
        int numPids = retBytes / sizeof(int);

        for (int i = 0; i < numPids; i++) {
            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;

            NSString *fullPath = [NSString stringWithUTF8String:pathBuf];

            // 只关注用户 App 路径
            BOOL isUserApp = NO;
            if ([fullPath containsString:@"/Bundle/Application/"] &&
                ![fullPath containsString:@".jbroot-"] &&
                ![fullPath containsString:@".appex"]) {
                isUserApp = YES;
            }
            if (!isUserApp) continue;

            NSString *bid = MKBidFromPath(fullPath);
            // v1.6.31: 仅前台 App 才补进集合（纯后台进程忽略）
            if (bid && !MKIsBlacklisted(bid) && MKIsForeground(bid)) {
                MKAddToRunningSet(bid);
            }
        }
    } @catch (NSException *e) {
        RDLog(@"PROC exception: %@", e.reason);
    }
}

// ─── 从通知提取 bundleID ──────────
static NSString *MKBidFromNote(NSNotification *note) {
    @try {
        id obj = note.object;
        if (obj) {
            SEL selectors[] = {
                NSSelectorFromString(@"bundleIdentifier"),
                NSSelectorFromString(@"applicationBundleID"),
                NSSelectorFromString(@"displayIdentifier"),
                NSSelectorFromString(@"applicationIdentifier"),
                NSSelectorFromString(@"bundleID")
            };
            for (int i = 0; i < 5; i++) {
                if ([obj respondsToSelector:selectors[i]]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id b = [obj performSelector:selectors[i]];
#pragma clang diagnostic pop
                    if ([b isKindOfClass:[NSString class]] && [(NSString *)b length] && [(NSString *)b containsString:@"."]) return b;
                }
            }
        }

        NSDictionary *info = note.userInfo;
        if (info) {
            for (NSString *key in @[@"bundleIdentifier", @"applicationBundleID",
                                    @"bundleID", @"displayIdentifier",
                                    @"applicationIdentifier"]) {
                id v = info[key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v containsString:@"."] && ![(NSString *)v containsString:@"/"]) return v;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// ─── 安全获取 FBProcessState / SBApplicationProcessState 属性 ──
static BOOL MKGetBoolFromState(id stateObj, NSString *propName) {
    @try {
        if (!stateObj) return NO;
        // 尝试 valueForKey（KVC）
        id val = [stateObj valueForKey:propName];
        if ([val isKindOfClass:[NSNumber class]]) return [val boolValue];
        // 尝试 performSelector
        SEL sel = NSSelectorFromString(propName);
        if ([stateObj respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id result = [stateObj performSelector:sel];
#pragma clang diagnostic pop
            if ([result isKindOfClass:[NSNumber class]]) return [result boolValue];
        }
    } @catch (NSException *e) {
        RDLog(@"KVC %@ failed: %@", propName, e.reason);
    }
    return NO;
}

static int MKGetIntFromState(id stateObj, NSString *propName) {
    @try {
        if (!stateObj) return 0;
        id val = [stateObj valueForKey:propName];
        if ([val isKindOfClass:[NSNumber class]]) return [val intValue];
        SEL sel = NSSelectorFromString(propName);
        if ([stateObj respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id result = [stateObj performSelector:sel];
#pragma clang diagnostic pop
            if ([result isKindOfClass:[NSNumber class]]) return [result intValue];
        }
    } @catch (NSException *e) {
        RDLog(@"KVC %@ failed: %@", propName, e.reason);
    }
    return 0;
}

// ====================================================================
// 渲染辅助 — Lynx2 风格：替换 App 名字标签区域
// ====================================================================

// 找到 SBIconView 对应的名字标签视图 — v1.5.0 四重策略
// v1.4.9 问题：iOS 16 SBIconListLabel 不在 SBIconView 内部，是其兄弟节点
// 日志证实：NO LABEL — SBIconView subviews: [SBFTouchPassThroughView]
static UIView *MKFindLabelView(SBIconView *iconView) {
    @try {
        // Strategy 1: SBIconView accessor 方法（iOS 16 运行时头文件）
        NSArray *accessorNames = @[
            @"labelView", @"listLabelView", @"_listLabelView",
            @"_titleLabelView", @"titleLabel", @"_labelView",
            @"iconLabelView", @"_iconLabelView",
            @"nameLabelView", @"_nameLabelView"
        ];
        for (NSString *name in accessorNames) {
            SEL sel = NSSelectorFromString(name);
            if ([iconView respondsToSelector:sel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [iconView performSelector:sel];
                #pragma clang diagnostic pop
                if (result && [result isKindOfClass:[UIView class]]) {
                    return result;
                }
            }
        }

        // Strategy 2: 祖先视图兄弟节点（v1.6.52 修复 iOS16 wrapper 包裹问题）
        // iOS 16 中 SBIconView 常被包进一个只有它自己的 wrapper(UIView)，
        // 真正的 SBIconListLabel 在 wrapper 的父容器（SBIconListView / SBDockIconListView）中。
        // 因此从 iconView.superview 开始向上遍历最多 8 层祖先，在每一层找兄弟标签。
        UIView *levelView = iconView.superview;
        NSInteger mkLevels = 0;
        while (levelView && mkLevels < 8) {
            if (levelView.subviews.count > 0 && levelView.subviews.count <= 256) {
                // v1.6.54: 几何命中优先 —— 标签必须与"本图标"水平居中且位于图标正下方，
                // 避免密集排列（文件夹/多页）时误命中邻居标签，导致"名称亮着 + 圆点画在别处"的重叠。
                CGRect iconFrameInLevel = [iconView convertRect:iconView.bounds toView:levelView];
                CGFloat iconCX = iconFrameInLevel.origin.x + iconFrameInLevel.size.width / 2.0f;
                CGFloat iconBY = iconFrameInLevel.origin.y + iconFrameInLevel.size.height;
                UIView *bestMatch = nil;
                NSInteger bestScore = 0;
                for (UIView *sv in levelView.subviews) {
                    if (sv == iconView) continue;
                    NSString *cls = NSStringFromClass([sv class]);
                    NSInteger score = 0;
                    if ([cls isEqualToString:@"SBIconListLabel"])        score = 100;
                    else if ([cls containsString:@"IconListLabel"])      score = 90;
                    else if ([cls containsString:@"ListLabel"])          score = 80;
                    else if ([cls containsString:@"IconLabel"])          score = 70;
                    else if ([sv isKindOfClass:[UILabel class]])          score = 60;
                    else if ([cls containsString:@"LabelView"])           score = 50;
                    else if ([cls containsString:@"Label"])              score = 40;
                    if (score < 50) continue;
                    // 几何校验：水平居中接近 + 位于图标下方
                    CGFloat labelCX = sv.frame.origin.x + sv.frame.size.width / 2.0f;
                    CGFloat labelTY = sv.frame.origin.y;
                    BOOL aligned = fabs(labelCX - iconCX) < (iconFrameInLevel.size.width * 0.6f);
                    BOOL below   = labelTY > (iconBY - 6.0f);
                    if (!aligned || !below) continue;
                    if (score > bestScore) {
                        bestScore = score;
                        bestMatch = sv;
                    }
                }
                if (bestMatch) {
                    return bestMatch;
                }
            }
            levelView = levelView.superview;
            mkLevels++;
        }

        // Strategy 3: 直接子视图搜索
        for (UIView *sv in iconView.subviews) {
            NSString *cls = NSStringFromClass([sv class]);
            if ([sv isKindOfClass:[UILabel class]] ||
                [cls containsString:@"IconLabel"] ||
                [cls containsString:@"Label"]) {
                return sv;
            }
        }

        // Strategy 4: 递归子视图搜索
        NSMutableArray *stack = [NSMutableArray arrayWithArray:iconView.subviews];
        while (stack.count > 0) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            NSString *cls = NSStringFromClass([v class]);
            if ([v isKindOfClass:[UILabel class]] ||
                [cls containsString:@"IconLabel"] ||
                [cls containsString:@"LabelView"] ||
                [cls containsString:@"ListLabel"] ||
                [cls containsString:@"TitleLabel"] ||
                [cls containsString:@"TextLabel"]) {
                return v;
            }
            [stack addObjectsFromArray:v.subviews];
        }

        // 诊断：标签未找到 -> dump（跳过 Dock / 多任务切换器里的图标，避免浪费预算）
        BOOL skipDump = NO;
        UIView *dd = iconView.superview;
        while (dd) {
            NSString *dc = NSStringFromClass([dd class]);
            if ([dc containsString:@"Dock"] || [dc containsString:@"Switcher"] ||
                [dc containsString:@"Snapshot"] || [dc containsString:@"Recycled"]) {
                skipDump = YES; break;
            }
            dd = dd.superview;
        }
        

    } @catch (NSException *e) {
        RDLog(@"MKFindLabelView exception: %@", e.reason);
    }
    return nil;
}

// v2.0.7: label→所属 SBIconView 几何反解（MKFindLabelView 的反函数）。
// 当 label 被 iOS 新建/重父（关合动画瞬态），kMKLabelBidKey/kMKLabelIconKey 关联随旧对象丢失、
// 且 superview 链查找失效时，按「label 几何位于哪个 SBIconView 正下方且水平居中」反解其归属图标。
// 图标 bid 由 MKGetCachedBid 独立缓存（不依赖 label），故反解出的 icon view 必能稳定取到 bid，
// 使源级 setHidden:/setAlpha: hook 在动画瞬态仍能把名字压下去。
static UIView *MKIconViewForLabel(UIView *label) {
    if (!label) return nil;
    @try {
        Class ivCls = MKSBIconViewClass();
        if (!ivCls) return nil;
        // label.superview 及其向上 8 层祖先容器里，找几何匹配本 label 的 SBIconView 兄弟
        UIView *lv = label.superview;
        NSInteger levels = 0;
        while (lv && levels < 8) {
            if (lv.subviews.count > 0 && lv.subviews.count <= 256) {
                CGRect lf = [label convertRect:label.bounds toView:lv];
                CGFloat labelCX = lf.origin.x + lf.size.width / 2.0f;
                CGFloat labelTY = lf.origin.y;
                UIView *best = nil;
                CGFloat bestDist = CGFLOAT_MAX;
                for (UIView *sv in lv.subviews) {
                    if (![sv isKindOfClass:ivCls]) continue;
                    CGRect ivf = [sv convertRect:sv.bounds toView:lv];
                    CGFloat ivCX = ivf.origin.x + ivf.size.width / 2.0f;
                    CGFloat ivBY = ivf.origin.y + ivf.size.height;
                    BOOL aligned = fabs(labelCX - ivCX) < (ivf.size.width * 0.6f);
                    BOOL below   = labelTY > (ivBY - 6.0f);
                    if (aligned && below) {
                        CGFloat d = fabs(labelCX - ivCX) + fabs(labelTY - ivBY);
                        if (d < bestDist) { bestDist = d; best = sv; }
                    }
                }
                if (best) return best;
            }
            lv = lv.superview;
            levels++;
        }
    } @catch (NSException *e) {}
    return nil;
}

// ====================================================================
// 主更新函数
// ====================================================================

// ====================================================================
// v1.6.86: 标签隐藏不变量「本 bid 有指示器 → 名字必须隐藏」的源头级强制。
// 拦截图标名字标签（iOS16.4.1 实测真实类为 SBIconLegibilityLabelView，详见 MKInstallLabelHook）
// 的 setHidden:/setAlpha:：凡本 bid 当前有指示器，无论系统（布局/转场/关闭文件夹的
// pop 动画）怎么复显名字，都强制隐藏 → 空档彻底归零。重叠 race 与
// 「关闭文件夹名称闪一下」「文件夹缩小内层 App 名称闪现」一并根除，且不和 alpha 动画打架。
// 指示器自身(MKIndicatorDotView)不受影响。
// ====================================================================
static void MKAssocLabelBid(UIView *label, NSString *bid) {
    if (!label) return;
    // v1.6.93: 藏名时把 bid 写到 label 自身；MKLabelToBid 优先采信，
    // 使藏名与视图层级无关（文件夹开/合动画重组层级时不再失效 -> 名称不再闪现/重叠）。
    objc_setAssociatedObject(label, &kMKLabelBidKey, bid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // v2.0.7+GAP-FIX: 维护「label 指针 -> bid」弱键表（label 仍应藏名时）。
    // 当系统对【同一 label 对象】再次 setHidden:NO / setAlpha:>0 而瞬态 MKLabelToBid
    // 返回 nil（关联键/层级/几何全失效的那一帧）时，源级 hook 可凭此表强制藏名，
    // 根除「名字与圆点偶尔重叠」race（第1点）。弱键 -> label 释放自动移除，不泄漏。
    if (!sHiddenLabelToBid) sHiddenLabelToBid = [NSMapTable weakToStrongObjectsMapTable];
    if (bid.length) {
        if (sHiddenBids && [sHiddenBids containsObject:bid])
            [sHiddenLabelToBid setObject:bid forKey:(id)label];
    } else {
        [sHiddenLabelToBid removeObjectForKey:(id)label];
    }
}

static NSString *MKLabelToBid(UIView *label) {
    if (!label) return nil;
    // v1.6.93: 直接关联优先 —— 仅当该 bid 仍在 sHiddenBids（确有指示器需藏名）时采信，
    // 避免 label 回收复用残留旧 bid 导致误藏。层级遍历仅作兜底。
    NSString *direct = objc_getAssociatedObject(label, &kMKLabelBidKey);
    if (direct.length && sHiddenBids && [sHiddenBids containsObject:direct]) return direct;
    Class ivCls = MKSBIconViewClass();
    // v2.0.3: 层级无关兜底 —— label 直接持有所属 SBIconView 指针，重父/新建到动画层也不丢。
    // 关文件夹缩回动画末尾系统把内部 App label 临时重父/重建，策略1/2 的 superview 链断开 →
    // 漏藏 → 名称闪现；此处直接从 label 自身取 iv 再取 bid，完全不依赖视图层级。
    // 仅当 (1) iv 当前仍声明持有本 label（防回收复用残留）且 (2) 该 bid 确在 sHiddenBids 时采信。
    UIView *ivForLabel = objc_getAssociatedObject(label, &kMKLabelIconKey);
    if (ivForLabel && ivCls && (UIView *)objc_getAssociatedObject(ivForLabel, &kMKLabelKey) == label) {
        if (MKIsFolderIcon((SBIconView *)ivForLabel)) {
            id fIcon = [(SBIconView *)ivForLabel icon];
            if (fIcon) return [NSString stringWithFormat:@"__folder__%p", fIcon];
        }
        NSString *b = MKGetCachedBid((SBIconView *)ivForLabel);
        if (b.length && sHiddenBids && [sHiddenBids containsObject:b]) return b;
    }
    // 策略1：同 wrapper 下的兄弟 SBIconView（iOS16 中 label 与 SBIconView 同挂一个 wrapper 下）
    UIView *p = label.superview;
    if (p && ivCls) {
        for (UIView *s in p.subviews) {
            if ([s isKindOfClass:ivCls]) {
                SBIconView *iv = (SBIconView *)s;
                if (MKIsFolderIcon(iv)) {
                    id fIcon = [iv icon];
                    if (fIcon) return [NSString stringWithFormat:@"__folder__%p", fIcon];
                }
                NSString *b = MKGetCachedBid(iv);
                if (b.length) return b;
            }
        }
    }
    // 策略2：沿祖先链向上找 SBIconView（极少数层级差异时兜底）
    UIView *a = label;
    while (a) {
        if (ivCls && [a isKindOfClass:ivCls]) {
            SBIconView *iv = (SBIconView *)a;
            if (MKIsFolderIcon(iv)) {
                id fIcon = [iv icon];
                if (fIcon) return [NSString stringWithFormat:@"__folder__%p", fIcon];
            }
            NSString *b = MKGetCachedBid(iv);
            if (b.length) return b;
        }
        a = a.superview;
    }
    // v2.0.7: 几何兜底 —— 关联键丢失 + 层级查找失败时，反解 label 所属 SBIconView 取 bid。
    // 图标 bid 由 MKGetCachedBid 独立缓存（不依赖 label），即便 label 对象被重建也能稳定命中，
    // 使源级 setHidden:/setAlpha: hook 在动画瞬态仍能把名字压下去（根治关合末尾名称闪现/重叠残留）。
    UIView *owner = MKIconViewForLabel(label);
    if (owner) {
        if (MKIsFolderIcon((SBIconView *)owner)) {
            id fIcon = [(SBIconView *)owner icon];
            if (fIcon) return [NSString stringWithFormat:@"__folder__%p", fIcon];
        }
        NSString *b = MKGetCachedBid((SBIconView *)owner);
        if (b.length) return b;
    }
    return nil;
}

// ====================================================================
// v2.0.66.12: 几何串名探针(STRAY-NAME) —— 由 v2.0.66.10 纯祖先链判定升级为「几何优先 + 容器兜底」, 覆盖 Dock 与负一屏 Today/Widget; 详见 MKStrayNameProbe
// --------------------------------------------------------------------
// 真因(rd_log 211/194 佐证): 回收复用窗口 L680-694 清掉 kMKLabelIconKey/kMKLabelBidKey,
// 旧 DOCK-NAME-MISMATCH 依赖 owner 指针 → 直接 bail 静默; 且开 debug 也抓不到(rd_log 194
// 实锤: REVEAL-ATTEMPT 在打而 DOCK/STRAY/MISMATCH/OVERLAP 全无)。新探针完全不依赖关联键:
// label 显形时先确认处于 Dock 上下文(祖先链含 SBDock*, 严格排除主屏 SBIconScrollView),
// 再借 MKIconViewForLabel 几何反解其下方 Dock 槽位 SBIconView 取 bid; 该槽 app 不在
// sHiddenBids(即未运行→Dock 中本不应显示任何名称)却仍有可见名称 label → 即串名 bug, 落日志。
// 节流: 同槽 ≥30s 至多 1 条, 防刷屏; 纯只读 + 记日志, 零行为变化。
// ====================================================================

// v2.0.66.12: 判定 label 父链是否落在「已知非标准图标槽」容器；命中返回 ctx 串(否则 nil)。
// 覆盖 Dock 与负一屏 Today/Widget 宿主；主屏标准图标槽(SBIconListView 等)不在其列，本就显示名称不可误报。
static BOOL MKLabelInHomeGrid(UIView *label); // v2.0.66.25: 前向声明(定义见下方) —— 守卫: 主屏网格内 label 绝不判 foreign
// v2.0.66.25: 增补 SBFFocusIsolationView -> TODAY(本机实测负一屏 widget 挂在 SBFFocusIsolationView 内, 无独立 SBTodayView);
// 并加 MKLabelInHomeGrid 守卫 —— 主屏图标网格(含文件夹)内 label 直接返回 nil, 杜绝误杀正常图标名。
// v2.0.66.37: 零分配化(class_getName+strstr/strncmp, 对齐 MKLabelInHomeGrid/MKLabelInDock);
// Dock 判定统一为 strstr(cn,"Dock")(与 MKLabelInHomeGrid 一致), 杜绝两函数口径不一导致漏藏。
static NSString *MKForeignContainerCtx(UIView *label) {
    if (MKLabelInHomeGrid(label)) return nil; // 在主屏网格内 -> 不是 foreign, 不误杀正常名称
    UIView *p = label.superview;
    while (p) {
        const char *cn = class_getName([p class]);
        if (strstr(cn, "Dock"))                   return @"DOCK";
        if (strncmp(cn, "SBToday", 7) == 0)       return @"TODAY";
        if (strncmp(cn, "SBDashboard", 11) == 0)  return @"DASHBOARD";
        if (strncmp(cn, "SBWidget", 8) == 0)      return @"WIDGET";
        if (strstr(cn, "SBFFocusIsolationView"))  return @"TODAY"; // v2.0.66.25: 负一屏宿主(本机 SBIconContentView 内, 无 SBTodayView)
        p = p.superview;
    }
    return nil;
}

// ─────────────────────────────────────────────────────────────────────
// v2.0.66.89 【角标模式擦名许可 —— 唯一谓词】
// ─────────────────────────────────────────────────────────────────────
// .88 只删了「角标专属分支里带 MKViewInFolderThumb 字样」的 5 处, 用户实机结果是
// 「文件夹名闪的次数少很多, 但还是会」。复盘发现漏了一整类:
//   两模式共用、只挂恒真 MKFixStrayNames()、按 dock/owner 判据擦名, 代码里【没有
//   MKViewInFolderThumb 字样】, 却照样能命中文件夹缩略图 label 或动画中被重父的 label。
// 按 .88 的 grep 口径永远搜不到它们 → 修一半。
//
// 【排查铁律】判断「谁还在擦名」不能按判据函数名搜, 必须枚举【所有对 label 写
//   hidden=YES / alpha=0 / layer.opacity=0 的点】, 逐点问两句:
//     ① 角标模式下这条路可达吗?  ② 可达时它擦的是不是一个【本该可见】的名字?
//   判据函数的名字 ≠ 它实际能命中的视图集合(MKForeignContainerCtx 对 dock 内的文件夹
//   缩略图返回 "DOCK", 名字里根本看不出这层)。
//
// 本谓词把散落判据收敛成一处, 语义 = 「角标模式下, 这个 label 所在位置是否允许我们擦掉」:
//   · 允许: 该位置【原生就不显示名字】(dock / 负一屏 / widget) → 出现可见 label = 100% 非法;
//   · 禁止: 该位置存在 compositor 快照 / crossfade 通道 → 我们改 live 改不了快照,
//           「擦掉」本身就是闪源(.88 快照通道铁律)。文件夹缩略图属此类。
//
// ⚠️ 注意此处 MKViewInFolderThumb 是【擦名豁免条件】, 不是擦名触发器 ——
//    与 layoutSubviews 里那条「别把 MKViewInFolderThumb 加回来」的警示注释【不冲突】:
//    那条警告的是「把它当触发器加回去会让擦名复活」, 这里是拿它当 return NO 的守卫。
//    改动此函数前请先读懂这两者方向相反, 勿再来回翻烧饼。
static BOOL MKViewInFolderThumb(UIView *v);   // v2.0.66.89: 前向声明上移(定义见 ~L2670, 本谓词与 MKDockStrayHide 都在其之前)
static BOOL MKBadgeMayEraseName(UIView *v) {
    if (!v) return NO;
    if (MKViewInFolderThumb(v)) return NO;        // 快照通道 → 交还系统(.88/.89)
    return MKForeignContainerCtx(v) != nil;       // 内含 MKLabelInHomeGrid 守卫, 主屏网格名绝不误杀
}




// v2.0.66.13: MKBidOfIconView 废弃 —— 改用工程统一 MKGetCachedBid(走缓存+icon 取值+文件夹过滤, 比自写 [iv icon] 可靠, 修 parentBid 全 nil); 见 MKStrayNameProbe。



// 前向声明(定义见 MKInstallLabelHook 附近)
static BOOL MKClassIsSubclass(Class sub, Class c);




// v2.0.66.14: 判断 name label 是否处于「主屏图标网格」—— 祖先链含 SBIconListView 且该 list 在 SBHomeScreenView/SBFolder 之下。
// 用于揭示「负一屏/widget/App 资源库」等非法位置(这些位置无 SBIconListView 或 list 不在主屏层级), 让探针能抓到此前漏掉的负一屏串名(rd_log(145) 实测 0 命中)。
// v2.0.66.37: 零分配化(class_getName+strstr, 对齐 MKLabelInDock); Dock 判定与 MKForeignContainerCtx 统一为 strstr(cn,"Dock")。
static BOOL MKLabelInHomeGrid(UIView *label) {
    UIView *p = label.superview;
    while (p) {
        const char *cn = class_getName([p class]);
        if (strstr(cn, "SBIconListView")) {
            UIView *q = p.superview;
            while (q) {
                const char *qc = class_getName([q class]);
                if (strstr(qc, "SBHomeScreenView") || strstr(qc, "SBFolder")) return YES;
                if (strstr(qc, "Dock")) return NO;
                q = q.superview;
            }
            return NO; // 找到 list 但不在主屏/文件夹 → 非主屏(如 App 资源库)
        }
        if (strstr(cn, "Dock")) return NO;
        p = p.superview;
    }
    return NO; // 根本不在任何 SBIconListView 内(如负一屏 widget 区) → 非主屏
}

// v2.0.66.14: label 祖先链是否含 Dock 容器
static BOOL MKLabelInDock(UIView *label) {
    UIView *p = label.superview;
    while (p) {
        // v2.0.66.34-perf: class_getName()+strstr 零分配，替代 NSStringFromClass+containsString。
        // 本函数被 setIconLabelAlpha: hook 在每个非藏名 label 每帧调用，原写法每层祖先都分配一个 NSString。
        if (strstr(class_getName([p class]), "Dock")) return YES;
        p = p.superview;
    }
    return NO;
}

// v2.0.66.38: 物理位置判定补刀 —— 治「主屏 name label 漂到 dock 位置显示(祖先链/owner 仍指向主屏)」
// 这类 dock 串名靠祖先含 Dock 类名(MKLabelInDock/MKForeignContainerCtx)与关联 owner 跨图标(didMoveToSuperview)全不命中,
// 现有判定维度(类名祖先链)覆盖不到, 故改按「label 实际 window 坐标是否落在 dock 容器区域」判定。
// dock 容器(SBDockIconListView/SBDockView) frame 缓存于 sDockFrame, 仅在为空/刷新时现找(低频), 热路径只做 convertRect+比较。
static CGRect sDockFrame = {{0,0},{0,0}}; // 编译期常量初始化(不能用 CGRectZero: 它是 extern const, 非编译期常量)
static void MKUpdateDockFrame(void) {
    @try {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            UIView *dock = MKFindDescendantView(w, @"SBDockIconListView");
            if (!dock) dock = MKFindDescendantView(w, @"SBDockView");
            if (dock) { sDockFrame = [dock convertRect:dock.bounds toView:nil]; return; }
        }
    } @catch (NSException *e) {}
}
static BOOL MKLabelPhysicallyInDock(UIView *label) {
    if (CGRectIsEmpty(sDockFrame)) MKUpdateDockFrame();
    if (CGRectIsEmpty(sDockFrame)) return NO;
    if (!label.window) return NO;
    CGRect r = [label convertRect:label.bounds toView:label.window];
    CGFloat midY = CGRectGetMidY(r);
    return midY >= CGRectGetMinY(sDockFrame) && midY <= CGRectGetMaxY(sDockFrame);
}

// v2.0.66.46: dock 串名【统一即时判定】—— 取代 v2.0.66.45 的独立全树扫描(MKDockBandSweep, 已删)。
// 根因复盘：v2.0.66.31 在 SBIconView.layoutSubviews 加的「每帧强制藏名」才是历史上「一出现就藏」的真身,
// 但它只认【祖先链含 Dock 类名】(MKLabelInDock) —— 那对应形态 A: 主屏 iconView 被回收去渲染 dock 槽, iconView 确实在 dock 子树里。
// 当前复发的是形态 B: label 仅【物理位置】被搬到 dock 纵带, 视图层级仍挂主屏(祖先链无 Dock 类名) → 祖先链判定永不命中,
// 于是唯一能被「父容器移动」触发的每帧路径整段跳过(父容器移动不会调 label 自己的任何 setter, 故 .38/.42 的 setter 钩子也抓不到)。
// v2.0.66.38 引入物理判定时只补了 label 自身三个 setter, 独独漏了这条每帧路径 —— 这就是 .38~.45 一路补丁仍复发的结构性缺口。
// 本函数把「祖先链」与「物理位置」两个维度合一, 供 layoutSubviews(每帧即时拦截) 与 MKRefreshAllIcons 的 BFS(事件兜底, 零额外遍历) 共用。
// 返回值 = 是否真 dock 图标(调用方应 return, 不走主屏逻辑); *outStray=YES 表示主屏图标 label 异常漂到 dock 且已被钉藏。
// 开销: 正常帧 = 一次 strstr(零分配) + 一次关联对象读; label 不可见即早退(运行中 App 全走这条); 仅「可见 label」才做一次 convertRect。
// v2.0.66.47 【装眼睛】dock 案发分支专用埋点 —— 刻意【不挂 sDebugLog 门控】。
// 理由: dock 串名随机复现(用户实测「注销后几小时才冒出来一次」), 单次验证周期以小时~天计,
// 用户不可能为了守株待兔长期挂着诊断开关 —— 挂开关 = 继续抓不到, 这正是前 8 版
// 「每版只能靠下次还出不出现来判断成败, 于是每版都敢自称根治」的根源。
// 成本可控: 本分支仅在「iconView 的 label 属主校验失败」这一异常态才进入(正常帧零触发),
// 且硬限流 20 条/开机周期, 日志体积与功耗均可忽略。RDLog 自身无门控(直接写文件), 故必达。
// v2.0.66.47 【配额必须按上下文分开, 否则埋点等于没装】
// rd_log(3) 实测: 文件夹场景孤儿 label(bid=?) 极其密集(FOLDER-FLOATY 684 条/64 秒),
// 若与 dock 共用一个计数器, 开一次文件夹就能把配额吃光 —— 等 dock 串名真正发生时早已限流,
// 结果与「没装埋点」完全等价。故: dock 上下文(真正要抓的稀有事件)独占 20 条且无门控必达;
// 非 dock 上下文仅作参考, 收进 sDebugLog 且只给 5 条, 绝不挤占 dock 配额。
// ─── MKDockForeignProbe (dock 串名专用埋点) 已移除 (.71)：RDLog 改为 no-op 后无诊断输出 ───

static BOOL MKDockStrayHide(SBIconView *iv, BOOL *outStray) {
    if (outStray) *outStray = NO;
    if (!iv) return NO;
    BOOL dockCtx = MKLabelInDock((UIView *)iv);   // 零分配: class_getName + strstr
    UIView *foreign = nil;
    UIView *lbl = MKGetCachedLabelEx(iv, &foreign);
    if (!lbl) {
        // v2.0.66.47 【闭合 8 版失败的机械缺口】原实现此处为 `if (!lbl) return dockCtx;` —— 零埋点静默退出。
        // 而 lbl==nil 的主因恰恰是 owner 校验失败 = 串名本身, 于是三层 dock 防线在真正案发的那一刻集体失效。
        //
        // default-deny 处置, 但严格【容器约束】(dockCtx 成立才动手), 绝不用物理纵带:
        //   · dock 原生不显示任何名称 → dock 容器内出现【任何可见 name label】= 100% 非法, 判定无误伤空间;
        //   · 失败模式退化为「dock 名字不显示」, 而 dock 本来就没名字 → 用户零感知;
        //   · 反之若按纵带(MKLabelPhysicallyInDock 只比 midY 不比 X)放开, 会波及主屏底行/文件夹/
        //     Spotlight, 误伤代价是「名字凭空消失」, 比串名更刺眼 —— 故此处坚决不用。
        BOOL acted = NO;
        if (dockCtx && foreign && !foreign.hidden && foreign.alpha > 0.01f) {
            // v2.0.65 配方(必须成对): 【清两枚过期键 + 藏】。
            // 只藏不清键 → 下一帧 owner 仍不符 → 再次进入本分支 → 每帧重入、永不收敛, 反而不如 v2.0.65;
            // 清键后 owner 回落为 nil, 下帧由 MKGetCachedLabelEx 正常绑定给真实属主并自动解钉(对称 restore)。
            objc_setAssociatedObject(foreign, &kMKLabelIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(foreign, &kMKLabelBidKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // v2.0.66.89 (S3b): 角标模式下若这个 label 属于【dock 里的文件夹缩略图】→ 只清键不藏。
            //   dockCtx 对 dock 文件夹的 mini SBIconView 恒真(祖先链含 SBDockIconListView),
            //   而缩略图有 compositor crossfade 快照通道 → 擦 live 就是闪源(.88 铁律)。
            //   清键仍必须做(否则 owner 校验永远失败, dock 串名无人纠正)。
            //   替换模式 MKHideNames() 恒真 → 短路走原路径, 行为一字不变。
            if (MKHideNames() || !MKViewInFolderThumb(foreign)) {
                foreign.hidden = YES;
                foreign.alpha  = 0.0f;
                foreign.layer.opacity = 0.0f;
                foreign.opaque = NO;
                [foreign.layer removeAllAnimations];
                acted = YES;
                if (outStray) *outStray = YES;
            }
        }
        (void)acted;   // v2.0.66.89: 埋点(.71)移除后仅剩赋值; 显式消耗以免 -Werror 未使用告警
        return dockCtx;
    }
    BOOL hit = dockCtx;
    if (!hit) {
        // ★ v2.0.66.89 【S2】角标模式【不用物理纵带判定】★
        //   MKLabelPhysicallyInDock 只比较 midY ∈ [dock.minY, dock.maxY], 【横向全屏通吃】。
        //   本函数上方 L2266 的注释自己就写着「若按纵带放开, 会波及主屏底行/文件夹/Spotlight,
        //   误伤代价是名字凭空消失, 比串名更刺眼 —— 故此处坚决不用」, 而这里还是用了。
        //   替换模式下这笔账划得来: 名字本就要藏, 误伤退化成「本来也要藏」。
        //   角标模式下方向完全相反: 名字本该显示, 误伤 = 名字凭空消失 / 动画期间闪。
        //   典型命中: 文件夹在底行、或关闭动画收缩轨迹掠过 dock 纵带。
        //   顺带一笔性能账: 角标模式所有 label 可见 → 下面 `hidden||alpha<=0.01` 早退失效
        //   → 每图标每帧都做一次 convertRect + 纵带比较(layoutSubviews 每帧调本函数)。
        //   另: sDockFrame 只在为空时刷新、转屏后不失效 → 横屏纵带整体错位, 角标模式一并免疫。
        //   ⚠️ 这【不是死码】: MKDockStrayHide 是两模式共用函数, 不在 `if (!MKHideNames())` 分支内。
        if (!MKHideNames()) return NO;                     // 角标模式: 只认真 dock 子树(dockCtx), 纵带一概不管
        if (lbl.hidden || lbl.alpha <= 0.01f) return NO;   // 已不可见 → 无需判定(最常见早退路径)
        if (!MKLabelPhysicallyInDock(lbl)) return NO;      // 物理不在 dock 纵带 → 正常主屏标签, 放行
        hit = YES;
        if (outStray) *outStray = YES;
    }
    // v2.0.66.89 (S3b): 同上 —— 角标模式豁免 dock 内文件夹缩略图(快照通道)。
    if (hit && (!lbl.hidden || lbl.alpha > 0.0f) && (MKHideNames() || !MKViewInFolderThumb(lbl))) {
        lbl.hidden = YES;
        lbl.alpha = 0.0f;
        lbl.layer.opacity = 0.0f;
        lbl.opaque = NO;
        [lbl.layer removeAllAnimations];
    }
    return dockCtx;
}


// v2.0.66.21: 暴力 dump —— 不再猜负一屏容器类名(SBDock/SBToday/SBWidget/SBDashboard/TodayView), 改结构判定:












// v1.6.86: 源头级强制隐藏核心 —— 每类独立保存原始 IMP（用类名做 key，避免多类共享同一指针）。
// 关键修复：iOS 16.4.1 图标名字标签的真实类是 SBIconLegibilityLabelView
// （日志 FICON-LABEL cls=SBIconLegibilityLabelView 证实）；原 v1.6.85 只尝试
// SBIconListLabel / SBIconLabelView，二者在本机均不存在 → lbl=nil → 直接 return →
// 钩子从未安装 → 名字与圆点重叠 race、关文件夹名称闪现、文件夹缩小内层 app 名称闪现 三症全在。
// 故改为：枚举全部已知标签类名 + 各自子类树，全部 setHidden:/setAlpha: 替换。
static NSMutableDictionary *sOrigSetHiddenByClass = nil;
static NSMutableDictionary *sOrigSetAlphaByClass  = nil;
static NSMutableDictionary *sOrigDidMoveToWindowByClass = nil; // v2.0.7: didMoveToWindow: 原始 IMP（创建点拦截用）
static NSMutableDictionary *sOrigDidMoveToSuperviewByClass = nil; // v2.0.65: didMoveToSuperview: 原始 IMP（回收复用清过期属主关联用）
// v2.0.66.34-perf: 上述 NSString 字典的零分配镜像——以 Class 指针为键(指针相等、不 retain/release)，
// 供 MKResolveOrigIMP 在【每个 label hook 调用】时 O(1) 取回 orig IMP, 省掉原 while 链里每层 NSStringFromClass 的分配。
// hook 安装期(MKHookOneLabelClass)随 NSString 字典一起填充; NSString 字典保留作兜底。
static CFMutableDictionaryRef sOrigSetHiddenByClassCF = NULL;
static CFMutableDictionaryRef sOrigSetAlphaByClassCF = NULL;
static CFMutableDictionaryRef sOrigDidMoveToWindowByClassCF = NULL;
static CFMutableDictionaryRef sOrigDidMoveToSuperviewByClassCF = NULL;
static CFMutableDictionaryRef sOrigSetIconLabelAlphaByClassCF = NULL; // v2.0.66.34-perf: 第 5 个 hook(setIconLabelAlpha:) 的零分配镜像
// v2.0.66.78 (A1): 原第 6/7 个 hook(setFrame:/setCenter:) 的 IMP 镜像容器已删除 ——
// β2 起这两个 hook 的唯一有效逻辑被 if(NO) 关掉(形态 B 改由 MKDockStrayHide 每帧 owner 校验兜底),
// hook 体退化为纯透传; setFrame:/setCenter: 是布局最热路径, 整棵 label 子类树每次布局白过两次 trampoline。
// 本版按 β3 原定计划整体摘除(hook 函数 + 安装码 + 容器), 运行期行为严格等价 .75。

// v2.0.12: 原 MKLabelHostInFolder() 已删除——v2.0.9 用它实现「关合窗口内对文件夹内 label 让步原生」，
// 而 v2.0.12 已撤销该让步(关合窗口内文件夹内 label 一律强藏,见 MKSetHiddenHook/MKSetAlphaHook/
// MKLabelDidMoveToWindowHook/主路径 mustHide 四处撤销)。该函数已无调用点,留之则 -Werror unused-function 编不过,故删。
// v2.0.41: 关文件夹窗口内,iOS 试图复显运行 App label 时记一笔(无论 bid 能否解析),
// 定位「末拍闪一下」到底走哪条 setter / 是否落在我们 hook 的拦截判据里。gate 在 sFlashWindow。
static void MKFadeInFolderIndicatorIfClosing(UIView *ind); // v2.0.43: 关窗期文件夹缩略图运行点淡入(消除瞬现)
// v2.0.66.1: 文件夹缩略图上下文判定 + 缩略图迷你图标 bid 解析（精准修关窗缩略图运行 App 名称/指示器闪现）
static BOOL MKViewInFolderThumb(UIView *v);
static NSString *MKFolderThumbBid(UIView *v);
// v2.0.66.10: 泛化外来源容器串名探针（定义见 MKLabelToBid 之后）
static NSString *MKForeignContainerCtx(UIView *label);

// v2.0.52: 抽自四个 label hook 的「沿继承链解析原始 IMP」重复（防类簇递归/坏 orig）。
// 返回解析到的原始 IMP（void* 桥接，调用方按自身签名转型）；byClass 为 nil 时返回 NULL。
// 注：沿用原 NSStringFromClass(c) 查表（保持行为一致；若要压 per-call 分配可改 class_getName+strstr，属独立 perf 议题）。
static void *MKResolveOrigIMP(NSMutableDictionary *byClass, CFMutableDictionaryRef byClassCF, id self) {
    if (!byClass) return NULL;
    Class c = object_getClass(self);
    // v2.0.66.34-perf: 零分配快路径——CFDictionary 以 Class 指针为键, CFDictionaryGetValue 不分配任何对象,
    // 直接命中(绝大多数情况: self 的具体类就是被 hook 的类, 一次查中)。仅在快路径缺失时回退 NSString 字典(兼容老逻辑)。
    if (byClassCF) {
        void *imp = (void *)CFDictionaryGetValue(byClassCF, (const void *)c);
        if (imp) return imp;
        Class s = class_getSuperclass(c);
        while (s) {
            imp = (void *)CFDictionaryGetValue(byClassCF, (const void *)s);
            if (imp) return imp;
            s = class_getSuperclass(s);
        }
        return NULL;
    }
    while (c) {
        NSValue *v = [byClass objectForKey:NSStringFromClass(c)];
        if (v) return [v pointerValue];
        c = class_getSuperclass(c);
    }
    return NULL;
}

// v2.0.52: 抽自 MKSetHiddenHook / MKSetAlphaHook 的核心藏名判据（两 hook 此段逐字相同）。
// 判据：label 的 bid∈sHiddenBids（hasBid）或 指针弱键表 sHiddenLabelToBid 命中（inMap）任一成立即藏名。
// v1.6.99: 一旦命中即写回直接关联键(使「该 label 属于需藏名 bid」标记自持) + 掐掉关合动画挂的
//   opacity CAAnimation（presentation layer 无视 opacity=0 把名字画出来的真凶），根除关文件夹缩回/
//   主屏偶发重叠的瞬态复显闪现(第④/①点)。v2.0.7+GAP-FIX: 凭指针弱键兜底偶发重叠(第1点)。
// outMapOnly: 仅经指针弱键命中(直接 bid 未中) —— 对应原 OVERLAP-GAP 诊断条件 !hasBid && inMap。
// 返回 useBid（非 nil = 该藏名）；具体「压制复显」由调用方据自身语义执行(setHidden 改 hidden / setAlpha 改 a 后调 orig)。
static NSString *MKShouldHideLabel(UIView *label, NSString *bid, BOOL *outMapOnly) {
    // v2.0.66.80: 角标模式不抢名字位置 → 源头切断所有藏名判定（名字永不藏）
    if ([MKConfig sharedConfig].locationMode == MKLocationBadge) return nil;
    NSString *mapBid = (sHiddenLabelToBid ? [sHiddenLabelToBid objectForKey:(id)label] : nil);
    // β5: 清过期弱键关联 —— label 对象被跨 icon 复用(同指针不释放)而其当前实时 bid 已变为另一个
    // 有效 bid 时, 旧 mapBid 属回收残留; 此时不采信旧 mapBid 并清掉, 避免误藏/误判。
    // 仅当当前 bid 有效且与 mapBid 不同才清(瞬态 bid=nil 不误清, 与 MKGetCachedBid 回收清扫行为一致)。
    if (mapBid.length && bid.length && ![mapBid isEqualToString:bid]) {
        [sHiddenLabelToBid removeObjectForKey:(id)label];
        mapBid = nil;
    }
    BOOL hasBid = (bid && sHiddenBids && [sHiddenBids containsObject:bid]);
    BOOL inMap  = (mapBid.length && sHiddenBids && [sHiddenBids containsObject:mapBid]);
    if (hasBid || inMap) {
        NSString *useBid = hasBid ? bid : mapBid;
        MKAssocLabelBid(label, useBid);
        [label.layer removeAllAnimations];
        if (outMapOnly) *outMapOnly = (!hasBid && inMap);
        return useBid;
    }
    if (outMapOnly) *outMapOnly = NO;
    return nil;
}

static void MKSetHiddenHook(id self, SEL _cmd, BOOL hidden) {
    // v2.0.66.86: 角标模式不再整段透传 —— .85 的整段早退把「纠正 iOS 原生非法名字」
    // (dock 串名 / 缩略图闪名) 一起关掉了, 那是用户实机两症在角标模式下依旧复现的真因。
    // 现按职责拆两路: 替换模式走原全套(含我们主动藏名); 角标模式只走纠正路径。
    if (!MKHideNames()) {
        // 角标模式纠正路径: 仅当有人试图【显示】(hidden==NO) 时才判定, 已隐藏则零成本跳过。
        if (!hidden && MKFixStrayNames()) {
            @try {
                UIView *lbl = (UIView *)self;
                // v2.0.66.88: 【原①「文件夹缩略图网格擦名」分支已整段删除】
                // 用户实机证实角标模式下文件夹名仍在闪, 真因就是这一路: 我们擦掉 live label,
                // 但 iOS 开合文件夹的 compositor crossfade 快照里那个名字还在
                // → live/snapshot 不一致 = 闪。角标模式契约是「名字一律不动」, 文件夹名
                // 也属于名字, 擦它既违约又是闪源。交还系统: iOS 16 缩略图原生不显示名字
                // → 既不显也不闪; 若某状态原生要显示, 那也是原生行为, 不该我们插手。
                // ⚠️ 注意本块整体在 `if (!MKHideNames())` 内 = 角标模式专属分支,
                //    所以【不能】写成 `MKHideNames() && MKViewInFolderThumb(...)` —— 那是恒假死码。
                //
                // dock / 负一屏 / widget 容器内的图标名 —— 同为原生不显示的位置, 保留擦除
                // (未观察到闪, 且原生确实无名, 常显更难看)。
                // MKForeignContainerCtx 内含 MKLabelInHomeGrid 守卫, 主屏网格名绝不误杀。
                // v2.0.66.89 (S3): 改走 MKBadgeMayEraseName —— 它在 MKForeignContainerCtx 之上
                // 再加一道「快照通道豁免」, 覆盖【dock 里放了文件夹】的情形(其缩略图 mini label
                // 祖先含 SBDockIconListView → MKForeignContainerCtx 返 "DOCK" → 原判据照样擦 → 闪)。
                if (MKBadgeMayEraseName(lbl)) {
                    hidden = YES;
                    [lbl.layer removeAllAnimations];
                }
            } @catch (NSException *e) {}
        }
        void(*o)(id,SEL,BOOL) = (void(*)(id,SEL,BOOL))MKResolveOrigIMP(sOrigSetHiddenByClass, sOrigSetHiddenByClassCF, self);
        if (o && o != (void(*)(id,SEL,BOOL))MKSetHiddenHook) {
            @try { o(self, _cmd, hidden); }
            @catch (NSException *e) { RDLog(@"MKSetHiddenHook orig EXCEPTION: %@", e.reason); }
        }
        return;
    }
    @try {
        NSString *bid = MKLabelToBid((UIView *)self);
        // v2.0.3: 关文件夹窗口内有界定向诊断（仅 debug 开 + sFolderClosing 时）
        
        NSString *useBid = nil; BOOL mapOnly = NO;
        if ((useBid = MKShouldHideLabel((UIView *)self, bid, &mapOnly))) {   // v2.0.9 的「关闭动画窗口内让步原生」已在 v2.0.12 撤销：关合窗口内文件夹内 label 也强制藏名(不让步原生)，根治 sub-16ms settle 单帧闪现(第④点残留真凶)。证据 rd_log(63): FOLDER-CLOSE-VISIBLE=0 表明无 strobe 互搏，去掉安全。
            hidden = YES; // 有指示器 -> 名字必须隐藏，压制系统任何复显
            // v1.6.99: MKShouldHideLabel 已写回直接关联键 + 掐动画(标记自持，根除关文件夹缩回/主屏重叠闪现，详见 helper 注释)
            
            // v2.0.64: 删除原 REVEAL-ATTEMPT 分支 —— hidden 已在上行置 YES，!hidden 恒为 NO，该分支实际不可达(纯 debug 死代码)
        } else if (MKHideNames() && MKViewInFolderThumb((UIView *)self)) {
            // v2.0.66.1: 缩略图内运行 App 名称 label 经 setHidden: 复显时兜底钉藏(仅运行 App + 仅缩略图上下文)
            NSString *fb = MKFolderThumbBid((UIView *)self);
            if (fb.length && sHiddenBids && [sHiddenBids containsObject:fb]) {
                hidden = YES;
                MKAssocLabelBid((UIView *)self, fb);
                [((UIView *)self).layer removeAllAnimations];
            }
        } else if (MKHideNames() && MKForeignContainerCtx((UIView *)self)) {
            // v2.0.66.37: fctx 强制藏名补刀——foreign 容器(dock/负一屏/widget)名经 setHidden:NO 复显
            // (同窗口同 superview, didMoveToWindow/didMoveToSuperview 不触发)时在此压住; 零分配判定, 主屏/文件夹不受影响。
            // β2: 移除原 MKLabelPhysicallyInDock 物理纵带补刀(形态 B 改由 MKDockStrayHide 每帧兜底), 收敛 swizzle 面。
            hidden = YES;
            [((UIView *)self).layer removeAllAnimations];
        }
    } @catch (NSException *e) {}
    void(*orig)(id,SEL,BOOL) = (void(*)(id,SEL,BOOL))MKResolveOrigIMP(sOrigSetHiddenByClass, sOrigSetHiddenByClassCF, self);
    // v1.6.88: 终防自递归/坏 orig —— 若继承链查表误把 hook 自身当 orig 捕回（未来回归），
    // 调用它会无限递归直至栈爆崩；这里硬拒 hook 自身，物理上杜绝该类崩溃。
    if (orig && orig != (void(*)(id,SEL,BOOL))MKSetHiddenHook) {
        @try { orig(self, _cmd, hidden); }
        @catch (NSException *e) { RDLog(@"MKSetHiddenHook orig EXCEPTION: %@", e.reason); }
    }
}
static void MKSetAlphaHook(id self, SEL _cmd, CGFloat a) {
    // v2.0.66.86: 同 MKSetHiddenHook —— 角标模式保留「纠正 iOS 原生非法名字」这一路,
    // 只有我们主动藏名那一路才随 MKHideNames() 关。见 MKFixStrayNames 注释。
    if (!MKHideNames()) {
        if (a > 0.0f && MKFixStrayNames()) {   // 仅当有人试图显示才判定, alpha<=0 零成本跳过
            @try {
                UIView *lbl = (UIView *)self;
                // v2.0.66.88: 原 MKViewInFolderThumb 分支已删除 —— 角标模式不擦文件夹缩略图名
                // (擦 live 但快照里有 → 闪, 见 MKSetHiddenHook 同款说明)。本块在
                // `if (!MKHideNames())` 内, 故【不可】改写成 `MKHideNames() && ...`(恒假死码)。
                // v2.0.66.89 (S3): 收敛到 MKBadgeMayEraseName —— 在 foreign 判据之上再加
                // 「快照通道豁免」, 覆盖【dock 里放了文件夹】时缩略图 label 仍被判 "DOCK" 而被擦的漏洞。
                if (MKBadgeMayEraseName(lbl)) {  // dock / 负一屏 / widget 原生无名, 保留擦除
                    a = 0.0f;
                    [lbl.layer removeAllAnimations];
                }
            } @catch (NSException *e) {}
        }
        void(*o)(id,SEL,CGFloat) = (void(*)(id,SEL,CGFloat))MKResolveOrigIMP(sOrigSetAlphaByClass, sOrigSetAlphaByClassCF, self);
        if (o && o != (void(*)(id,SEL,CGFloat))MKSetAlphaHook) {
            @try { o(self, _cmd, a); }
            @catch (NSException *e) { RDLog(@"MKSetAlphaHook orig EXCEPTION: %@", e.reason); }
        }
        return;
    }
    @try {
        NSString *bid = MKLabelToBid((UIView *)self);
        // v2.0.3: 关文件夹窗口内有界定向诊断（setAlpha: 复显路径）
        
        NSString *useBid = nil; BOOL mapOnly = NO;
        if ((useBid = MKShouldHideLabel((UIView *)self, bid, &mapOnly))) {   // v2.0.12: 撤销 v2.0.9 关合窗口内让步原生(label 在文件夹内也强制藏名), 根治 sub-16ms settle 单帧闪现。详见 MKSetHiddenHook 同款注释。
            // v2.0.66.79 (A6): 原 CGFloat inA = a; 已删除 —— .41 的 REVEAL-ATTEMPT 诊断判据遗留,
            // 探针在 .71 移除后成为 write-only 死值。
            a = 0.0f; // 同上，压制 alpha 复显
            // v1.6.99: MKShouldHideLabel 已写回直接关联键 + 掐动画(标记自持，根除关文件夹缩回/主屏重叠闪现，详见 helper 注释)
            
            // v2.0.66-diag: 关窗内 iOS 经 setAlpha:>0 复显【任意图标(含非运行 app)】label 也记(REVEAL-ATTEMPT); useBid=nil 即非运行,可区分
            
        } else if (MKHideNames() && MKViewInFolderThumb((UIView *)self)) {
            // v2.0.66.1: 缩略图内运行 App 名称 label 经 setAlpha: 复显时兜底钉藏(仅运行 App + 仅缩略图上下文)
            NSString *fb = MKFolderThumbBid((UIView *)self);
            if (fb.length && sHiddenBids && [sHiddenBids containsObject:fb]) {
                a = 0.0f;
                MKAssocLabelBid((UIView *)self, fb);
                [((UIView *)self).layer removeAllAnimations];
            }
        } else if (MKHideNames() && MKForeignContainerCtx((UIView *)self)) {
            // v2.0.66.37: fctx 强制藏名补刀——foreign 容器(dock/负一屏/widget)名经 setAlpha:>0 复显
            // (同窗口同 superview, didMoveToWindow/didMoveToSuperview 不触发)时在此压住; 零分配判定, 主屏/文件夹不受影响。
            // β2: 移除原 MKLabelPhysicallyInDock 物理纵带补刀(形态 B 改由 MKDockStrayHide 每帧兜底), 收敛 swizzle 面。
            a = 0.0f;
            [((UIView *)self).layer removeAllAnimations];
        }
    } @catch (NSException *e) {}
    void(*orig)(id,SEL,CGFloat) = (void(*)(id,SEL,CGFloat))MKResolveOrigIMP(sOrigSetAlphaByClass, sOrigSetAlphaByClassCF, self);
    // v1.6.88: 终防自递归/坏 orig（见 MKSetHiddenHook 注释）
    if (orig && orig != (void(*)(id,SEL,CGFloat))MKSetAlphaHook) {
        @try { orig(self, _cmd, a); }
        @catch (NSException *e) { RDLog(@"MKSetAlphaHook orig EXCEPTION: %@", e.reason); }
    }
}

// v2.0.66.78 (A1): MKSetFrameHook / MKSetCenterHook 已整体删除(β3 收 swizzle 面)。
// 二者自 β2 起 if(NO) 死分支化, 仅剩透传 orig; 形态 B(主屏 label 漂到 dock 位置)由
// MKDockStrayHide 每帧 owner 校验兜底, 与本 hook 无依赖关系。删之运行期零行为变化。

// v2.0.7: 创建点拦截 —— label 一旦进入 window（新建/重父/动画层迁入）即刻检查归属，
// 若其所属图标 bid∈sHiddenBids 则立刻 hidden + 种回关联键。这堵死「新建对象无关联键、
// 且此刻 setHidden: 尚未被调用（或层级查找失败）」那一帧的复显，正是 FICON 周期性
// 重抓 (FICON-LABEL label=YES 重复 40 次) 与关合末尾闪现的根。先于系统任何显示路径生效。
static void MKLabelDidMoveToWindowHook(id self, SEL _cmd) {
    // 先调原始实现，把 label 真正挂上 window
    // v2.0.7+CI-FIX: didMoveToWindow 无参，原始 IMP 签名为 (void(*)(id,SEL))。
    // iOS14+ SDK 中 IMP typedef 为 void(*)(void)（声明 0 个参数），
    // 若用 IMP 类型声明 orig 再 orig(self,_cmd) 调用会触发 -Werror
    // 「too many arguments to function call, expected 0, have 2」。故显式声明函数指针类型。
    void (*orig)(id, SEL) = (void(*)(id,SEL))MKResolveOrigIMP(sOrigDidMoveToWindowByClass, sOrigDidMoveToWindowByClassCF, self);
    if (orig) {
        @try { orig(self, _cmd); }
        @catch (NSException *e) { RDLog(@"MKLabelDidMoveToWindowHook orig EXCEPTION: %@", e.reason); }
    }
    @try {
        // v2.0.66.86: .85 在此整段早退 → 角标模式下 foreign 容器(dock/负一屏/widget)的
        // 「进 window 创建点纠正」也一起没了。现拆两路: 角标模式只走纠正, 不走主动藏名。
        if (!MKHideNames()) {
            if (!MKFixStrayNames()) return;
            UIView *lbl0 = (UIView *)self;
            if (!lbl0.window || lbl0.alpha <= 0.0f || lbl0.hidden) return;  // 不可见 → 无需纠正
            // v2.0.66.88: 原为 `MKViewInFolderThumb(lbl0) || MKForeignContainerCtx(lbl0)`。
            // 角标模式下【不再】擦文件夹缩略图名(擦 live 但快照里有 → 闪, 见 MKSetHiddenHook
            // 同款说明); 这里是第 4 个同类擦点, 不一并短路的话前三处的修复会被它抵消。
            // v2.0.66.89 (S3): 同样收敛到 MKBadgeMayEraseName(见 MKSetAlphaHook 同款说明)。
            if (MKBadgeMayEraseName(lbl0)) {
                lbl0.hidden = YES;
                lbl0.alpha = 0.0f;
                lbl0.layer.opacity = 0.0f;
                [lbl0.layer removeAllAnimations];
            }
            return;
        }
        UIView *lbl = (UIView *)self;
        // 只在「已进 window 且当前可见」时检查；移除(window=nil)不处理
        if (lbl.window && (lbl.alpha > 0.0f)) {   // v2.0.40: 放宽——覆盖半残态(hidden=YES 但 alpha>0), 旧 !lbl.hidden 把 rd_log(168) CLOSE-TAIL lbl(h=1 a=1.00) 漏过   // v2.0.12: 撤销 v2.0.9 关合窗口内文件夹内 label 让步原生(label 一进 window 即刻强藏, 根除 sub-16ms settle 单帧闪现); 详见 MKSetHiddenHook 同款注释。
            // v2.0.41: 关窗内 label 进 window 即带名可见(属运行 App)时记一笔(REVEAL-ATTEMPT)
            
            NSString *bid = MKLabelToBid(lbl); // v2.0.7: 含几何兜底，瞬态也能解出
            if (bid && sHiddenBids && [sHiddenBids containsObject:bid] && MKHideNames()) {
                lbl.hidden = YES;
                lbl.alpha = 0.0f;
                lbl.layer.opacity = 0.0f;
                lbl.opaque = NO;
                MKAssocLabelBid(lbl, bid);
                [lbl.layer removeAllAnimations]; // v2.0.17: 同上，新建 label 进 window 即刻掐动画
            }
            // v2.0.66.25: foreign 容器(dock/负一屏/widget)内出现的图标名 label —— 这些位置本不显示名称。
            // 在「进 window 创建点」即强制藏名, 先于系统任何显示路径, 灭亚秒级闪现; 此前仅 MKStrayNameProbe 的 if(ctx)
            // 于 setHidden/setAlpha/1s 轮询时藏, 漏掉「直接 addSubview 进已可见父视图」(不调 setHidden/setAlpha)的显形路径。
            NSString *fctx = MKForeignContainerCtx(lbl);
            if (fctx && MKHideNames()) {
                lbl.hidden = YES;
                lbl.alpha = 0.0f;
                lbl.layer.opacity = 0.0f;
                [lbl.layer removeAllAnimations];
            }
        }
    } @catch (NSException *e) {}
}

// v2.0.65: 回收复用兜底 —— label 被 iOS 跨槽位复用到「不同图标」时（Dock 串台根因），
// 其残留的 kMKLabelIconKey（旧属主指针）未及时清掉 → MKLabelToBid 解析到过期属主 →
// 外来文字被放行显示在 Dock 上。本 hook 在 superview 变更的「源头」校验属主：
// 若真实当前属主(realIV, 经 MKIconViewForLabel 几何反解) 与存储旧属主不符 → 清掉两枚过期键 +
// 立即隐藏该 label（其文字属旧属主，不该出现在新槽位）。清键后 MKLabelToBid 自然回落到真实
// iv → 运行 App 槽位走既有藏名逻辑稳藏；瞬态动画(superview 链暂不可达 realIV) 与同图标内部
// 重排(realIV==旧属主) 均不触发，零碰决策逻辑/orig IMP 解析。
static void MKLabelDidMoveToSuperviewHook(id self, SEL _cmd) {
    // 先调原始实现，把 label 真正换到新 superview（此后 self.superview 即新父）
    void (*orig)(id, SEL) = (void(*)(id,SEL))MKResolveOrigIMP(sOrigDidMoveToSuperviewByClass, sOrigDidMoveToSuperviewByClassCF, self);
    if (orig) {
        @try { orig(self, _cmd); }
        @catch (NSException *e) { RDLog(@"MKLabelDidMoveToSuperviewHook orig EXCEPTION: %@", e.reason); }
    }
    @try {
        // v2.0.66.86: 本 hook 的两件事都属「纠正 iOS 原生行为」, 与我们是否抢名字位无关:
        //   ① 跨图标复用清过期键(dock 串名的源头级防线) ② foreign 容器内藏非法名。
        // .85 在此整段早退 = 角标模式下 dock 串名源头防线全失。现改为两模式共用同一段,
        // 门控从 MKHideNames() 换成 MKFixStrayNames()。
        if (!MKFixStrayNames()) return;
        UIView *lbl = (UIView *)self;
        UIView *storedOwner = objc_getAssociatedObject(lbl, &kMKLabelIconKey);
        if (!storedOwner) return; // 全新 label（kMKLabelIconKey 尚未/已被清）→ 非复用串台，不处理
        // v2.0.66.4: 改「祖先链属主判定」替代几何反解(MKIconViewForLabel) —— 灭 Dock 串名。
        // 旧判据 realIV=MKIconViewForLabel(lbl) 在 Dock 横向紧凑排布下歧义(相邻槽位中心距≤图标宽)，
        // 常误判隔壁槽位=旧属主 → realIV==storedOwner → 守卫漏触发 → 旧属主键残留 → Dock 串名。
        // 现直接查 storedOwner 是否仍在 label 当前 superview 祖先链中：不在 ⇒ 必为跨图标复用
        // (被 iOS 复用到别的槽位) → 清过期键 + 隐藏；在 ⇒ 同图标内部重排/未动 → 不触发。
        // 瞬态 detach(storedOwner 不在链中且新属主也取不到, curIV==nil) → 不触发，等 reattach 后
        // 由层级/几何兜底，与原 if(realIV && ...) 安全语义一致。
        Class ivCls = MKSBIconViewClass();
        UIView *curIV = nil;
        UIView *a = lbl.superview;
        while (a) { if (ivCls && [a isKindOfClass:ivCls]) { curIV = a; break; } a = a.superview; }
        if (curIV && curIV != storedOwner && MKFixStrayNames()) {
            // 真·跨图标复用：旧属主(如文件夹/其它 app)文字串到新槽位 → 清过期键 + 隐藏
            // v2.0.66.86: 门控由 MKHideNames() 改 MKFixStrayNames() —— 这是纠正 iOS 的回收复用,
            // 与我们抢不抢名字位无关; 角标模式也必须清键, 否则 MKGetCachedLabelEx 的 owner 校验
            // 会一直失败 → dock 串名无人纠正(用户实机 .85 dock 问题依旧的直接原因之一)。
            //
            // ★ v2.0.66.89 【S1 —— 本轮头号修复】把「清过期键」与「藏名」两件事拆开 ★
            //   原实现两件事写在同一个 if 里, 而它【既不判容器、也不判模式】:
            //   任何 label 换到「与 storedOwner 不同的 SBIconView」下就直接藏掉。
            //   本函数注释自陈的触发场景恰恰是文件夹开合 ——
            //     · MKGetCachedLabelEx(L875) 无条件写 kMKLabelIconKey → 角标模式 storedOwner 同样有值;
            //     · iOS 关文件夹缩回时把内层 App 的 label 临时重父到动画层(见 MKLabelToBid/2.0.3 注释);
            //     · 文件夹缩略图的 mini SBIconView 高频回收复用;
            //   → curIV != storedOwner 在动画窗口内几乎必然成立 → 我们在 crossfade 期间擦掉一个
            //     【本该可见】的名字 → live(无名) vs snapshot(有名) = 用户看到的闪。
            //   这是 .88 修完后残留闪名的主因, 且【与文件夹放在哪一行无关】。
            //
            //   两件事的语义完全不同, 必须分开门控:
            //     · 清过期键 = 真·纠正 iOS 回收复用(dock 串名源头防线, MKGetCachedLabelEx 的
            //       owner 校验依赖它) → 【无条件保留, 两模式都做】;
            //     · 藏名     = 干预 → 替换模式照旧(MKHideNames() 恒真短路, 行为一字不变);
            //                  角标模式仅在 MKBadgeMayEraseName 许可的位置(dock/负一屏/widget)才藏。
            objc_setAssociatedObject(lbl, &kMKLabelIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            MKAssocLabelBid(lbl, nil);
            if (MKHideNames() || MKBadgeMayEraseName(lbl)) {
                lbl.hidden = YES;
                lbl.alpha = 0.0f;
                lbl.layer.opacity = 0.0f;
            }
        }
        // v2.0.66.25: foreign 容器(dock/负一屏/widget)内图标名 label 在 superview 变更点也强制藏名,
        // 覆盖「仅换父、window 不变」的显形路径(与 didMoveToWindow 双保险, 灭亚秒级闪现);
        // 守卫在 MKForeignContainerCtx 内(MKLabelInHomeGrid)确保主屏网格名不被误杀。
        // v2.0.66.89 (S3): 判据由裸 MKForeignContainerCtx 换成 MKBadgeMayEraseName ——
        //   dock 里【放了文件夹】时, 其缩略图 mini label 的祖先链是
        //   SBIconView(mini) → SBFolderIconImageView → SBIconView(folder) → SBDockIconListView,
        //   而 strstr("SBDockIconListView","SBIconListView") 不匹配("SB" 后面是 "Dock")
        //   → MKLabelInHomeGrid 返 NO → MKForeignContainerCtx 返 "DOCK" → 缩略图照样被擦 → 闪。
        //   替换模式经 MKHideNames() 短路走原判据, 行为一字不变。
        if (MKHideNames() ? (MKForeignContainerCtx(lbl) != nil) : MKBadgeMayEraseName(lbl)) {
            lbl.hidden = YES;
            lbl.alpha = 0.0f;
            lbl.layer.opacity = 0.0f;
            [lbl.layer removeAllAnimations];
            
        }
    } @catch (NSException *e) {}
}

// v2.0.66.1: 仅命中「文件夹图标缩略图(SBFolderIconImageView 网格)」子树内的视图(迷你图标 SBIconView 或其名称 label)。
// 关键：用 EXACT class 匹配(非 strstr "FolderIcon")，刻意排除文件夹自身名 label——
// 该 label 挂在 SBFolderIcon 容器下、并不在 SBFolderIconImageView 内，故不会被误命中(避免 2.0.81 的过藏回归)。
// 打开文件夹(SBFolderView/SBFloatyFolderScrollView)内的迷你图标不在 SBFolderIconImageView 内 → 不受影响(不动 ②)。
static BOOL MKViewInFolderThumb(UIView *v) {
    if (!v) return NO;
    @try {
        static Class sThumbCls = Nil, sThumbCls2 = Nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sThumbCls  = NSClassFromString(@"SBFolderIconImageView");
            sThumbCls2 = NSClassFromString(@"SBIconFolderImageView");
        });
        UIView *a = v.superview;
        while (a) {
            if ((sThumbCls && [a isKindOfClass:sThumbCls]) ||
                (sThumbCls2 && [a isKindOfClass:sThumbCls2])) return YES;
            a = a.superview;
        }
    } @catch (NSException *e) {}
    return NO;
}

// v2.0.66.87 (B2): 角标模式下 label 的【条件恢复】—— 替代原先三处无条件写回。
//
// 原实现（.80~.86）在角标模式下把 label 显式写成 hidden=NO / alpha=1 / opacity=1 /
// opaque=YES + MKAssocLabelBid(nil)，每帧每图标都写。问题:
//   · 系统本来就维持 label 可见 → 绝大多数帧是与系统抢控制权的无意义写;
//   · 会抹掉系统自己设的中间态(编辑抖动、文件夹开合过渡期的 alpha 插值);
//   · opaque=YES 尤其危险 —— 系统从不这么设(原生 name label 是透明背景), 影响合成路径。
// 现改为: 只在 label 确实处于【被我们藏住】的状态时才恢复一次, 稳态零写入。
//
// 判据与 MKMigrateLocationMode 一致 —— 只认「我们藏的」:
//   带 kMKLabelBidKey 关联键(MKAssocLabelBid 写入) 或 命中 sHiddenLabelToBid 指针表。
// 系统自己藏的(stray 名字被 MKFixStrayNames 擦掉 / 编辑态)一律不碰, 否则会把刚擦掉的
// stray 名字重新翻出来(.85 血案同源)。stray 容器内亦只清键不复显。
static void MKRestoreLabelIfOurs(UIView *label) {
    if (!label) return;
    if (!label.hidden && label.alpha > 0.99f) return;   // 已可见 → 零写入(最常见路径)
    NSString *ourBid = objc_getAssociatedObject(label, &kMKLabelBidKey);
    BOOL ours = (ourBid.length != 0);
    if (!ours && sHiddenLabelToBid && [sHiddenLabelToBid objectForKey:(id)label]) ours = YES;
    if (!ours) return;                                   // 系统藏的 → 不碰
    // v2.0.66.88: 跳过复显的条件收窄。
    //   · foreign 容器(dock/负一屏/widget): 两模式都仍在擦(原生无名) → 复显会与自己互搏, 只清键。
    //   · 文件夹缩略图: 角标模式已【交还系统】(不再擦) → 我们过去藏的必须复原, 否则是残留干预;
    //     替换模式下该位置由既有藏名 machinery 持有 → 仍不复显(本函数虽只在角标模式被调,
    //     判据写全以防将来复用)。
    // v2.0.66.89: 角标模式收敛到 MKBadgeMayEraseName(把 dock 内文件夹缩略图移出「不复显」
    //   名单 —— 既然不再擦它, 过去藏的就必须还回去)。替换模式判据一字不变。
    if (MKHideNames()
          ? (MKForeignContainerCtx(label) != nil || MKViewInFolderThumb(label))
          : MKBadgeMayEraseName(label)) {
        MKAssocLabelBid(label, nil);                     // 只清键不复显
        return;
    }
    label.hidden = NO;
    label.alpha = 1.0f;
    label.layer.opacity = 1.0f;
    MKAssocLabelBid(label, nil);
}

// v2.0.66.1: 缩略图内迷你图标(或其名称 label)解析所属 App bid。
// 优先 MKGetCachedBid(走图标缓存)，失败(关窗瞬态 icon 链接未就绪)则直接读 icon.applicationBundleID 兜底，
// 确保运行 App 的 bid 总能解析到 → 才能被 sHiddenBids 命中而钉藏(灭关窗后 ~2s 周期复显)。
static NSString *MKFolderThumbBid(UIView *v) {
    if (!v) return nil;
    @try {
        Class ivCls = MKSBIconViewClass();
        SBIconView *iv = nil;
        if (ivCls && [v isKindOfClass:ivCls]) iv = (SBIconView *)v;
        else { // v 是 label：向上找最近的迷你图标 SBIconView
            UIView *a = v;
            while (a) { if (ivCls && [a isKindOfClass:ivCls]) { iv = (SBIconView *)a; break; } a = a.superview; }
        }
        if (!iv) return nil;
        NSString *b = MKGetCachedBid(iv);
        if (b.length) return b;
        id icon = [iv icon];
        if (icon && [icon respondsToSelector:@selector(applicationBundleID)]) {
            b = [icon applicationBundleID];
            if (b.length) return b;
        }
    } @catch (NSException *e) {}
    return nil;
}

// v2.0.40: 堵「关文件夹 settle 末拍名称闪现」的 alpha 回弹入口。
// iOS 在缩回动画收尾把 label 的 alpha 经 SBIconView.setIconLabelAlpha: 专用 setter 补回 1.00，
// 该 setter 绕过 MKSetAlphaHook(setAlpha:) -> 名字卡 hidden=YES+alpha=1.00 半残态(rd_log(168) CLOSE-TAIL lbl(h=1 a=1.00) 铁证)，
// 图标回主屏 hidden 被翻 NO 瞬间即以满不透明闪一下(第④点末拍闪名)。
// v2.0.6 曾含此 hook 但被 2.0.26 回归(FOLDER-CLOSE-REGRESS)一并撤掉; 本次仅恢复「钉 alpha」这一精准低耗片段，
// 不恢复其 1.5s guard/全树 BFS/0.4s 扫描(那是当年撤回的 perf 重灾区)。
// 与 MKSetAlphaHook 同判据(仅 sHiddenBids 成员) + 同款按继承链解析 orig(防类簇递归/坏 orig)。
static NSMutableDictionary *sOrigSetIconLabelAlphaByClass = nil;
static BOOL MKClassIsSubclass(Class sub, Class c); // 前向声明（定义于文件后部 ~2106；新增 MKHookSBIconViewAlpha 在 2030 行即用，须先声明以免 -Werror 隐式函数声明）
static void MKSetIconLabelAlphaHook(id self, SEL _cmd, CGFloat a) {
    @try {
        // v2.0.66.85: 角标模式下两分支(hasBid / dock 上下文)注定不成立 → 跳过整段判定,
        // 省 MKGetCachedBid + MKViewInFolderThumb 祖先链 + MKLabelInDock。
        // v2.0.66.86: 改为 if/else —— 角标模式不是"什么都不做", 而是走下方 else 的
        // 「按容器 default-deny 纠正非法名字」路径(缩略图/dock 原生无名字)。
        if (MKHideNames()) {
        NSString *bid = MKGetCachedBid((SBIconView *)self);
        BOOL hasBid = (bid.length && sHiddenBids && [sHiddenBids containsObject:bid]);
        // v2.0.66.1: 关窗缩略图稳态钉藏——迷你图标在 SBFolderIconImageView 内、且属运行中 App(bid∈sHiddenBids)，
        // 即使关窗守卫(sFolderClosing)过期后的周期复显也钉死名称(MKGetCachedBid 瞬态失效时兜底解析)。
        // 仅缩略图上下文 + 仅运行 App，绝不按 FolderIcon 血统 blanket 藏(避免过藏文件夹名)。
        if (!hasBid && MKViewInFolderThumb((UIView *)self)) {
            NSString *fb = MKFolderThumbBid((UIView *)self);
            if (fb.length && sHiddenBids && [sHiddenBids containsObject:fb]) {
                bid = fb;
                hasBid = YES;
            }
        }
        // v2.0.66-diag: 关窗内 iOS 经 setIconLabelAlpha:>0 复显【文件夹内任意图标(含非运行 app)】label 都记(REVEAL-ATTEMPT)，
        // 区分「a 层运行 app(cached-bid 翻转,可修)」vs「非运行/b 层(本 hook 看不到→日志零命中,近似无解)」。via 串含 hasBid。
        
        if (hasBid) {   // 仅藏名 bid 成员：钉死 alpha=0 压制 iOS 经此 setter 补回的回弹（外层已门控 MKHideNames）
            a = 0.0f;
            UIView *lbl = MKGetCachedLabel((SBIconView *)self);
            if (lbl) {
                [lbl.layer removeAllAnimations];
                lbl.hidden = YES;
                MKAssocLabelBid(lbl, bid);
            }
        } else {
            // v2.0.66.31: dock 上下文钉 alpha=0 —— 覆盖「随机名(非运行中 app)经 setIconLabelAlpha: 补回可见」的复用回弹(创建点钩子漏掉的瞬态)。
            // 仅当本 SBIconView 在 dock 容器内生效; 主屏/文件夹走原 hasBid 逻辑, 不受影响。
            if (MKLabelInDock((UIView *)self)) {
                a = 0.0f;
                UIView *dlbl = MKGetCachedLabel((SBIconView *)self);
                if (dlbl) {
                    [dlbl.layer removeAllAnimations];
                    dlbl.hidden = YES;
                    if (bid.length) MKAssocLabelBid(dlbl, bid);
                }
            }
        }
        }   // v2.0.66.85: MKHideNames() 门控块结束
        else if (MKFixStrayNames()) {
            // v2.0.66.86: 角标模式的纠正路径 —— 本 setter 是 iOS 在关文件夹 settle / dock
            // 复用回弹时把 label 区 alpha 补回 1.0 的专用入口, 也是「缩略图闪名 / dock 串名」
            // 的显形通道之一。角标模式不藏名, 但这两个位置原生【本就没有名字】, 故仍需归零。
            // default-deny 按容器判定, 与运行状态无关(角标模式 sHiddenBids 恒空, 旧判据用不了)。
            if (a > 0.0f) {
                // v2.0.66.88: 原 `MKViewInFolderThumb(self) || MKLabelInDock(self)` 中的
                // 缩略图判据已删除 —— 角标模式不擦文件夹缩略图名(擦 live 而快照里有 → 闪,
                // 用户实机证实)。本 else 分支即角标模式专属, 故不可写 `MKHideNames() && ...`。
                // v2.0.66.89 (S3): MKLabelInDock → MKBadgeMayEraseName。三重收益:
                //   ① 补上「快照通道豁免」—— dock 里放文件夹时, 缩略图内 mini SBIconView 的
                //      祖先链既含 Dock 又含 SBFolderIconImageView, 旧判据恒命中 → 擦名 → 闪;
                //   ② 消掉「MKLabelInDock 无主屏守卫 vs MKForeignContainerCtx 有守卫」两套口径并存;
                //   ③ 顺带覆盖负一屏/widget 宿主内的图标(原生同样无名)。
                // 注: 这里传的是 SBIconView 而非 label —— 谓词只爬 superview 链, 两者等效。
                if (MKBadgeMayEraseName((UIView *)self)) {
                    a = 0.0f;
                    UIView *sl = MKGetCachedLabel((SBIconView *)self);
                    if (sl) {
                        [sl.layer removeAllAnimations];
                        sl.hidden = YES;
                        sl.alpha = 0.0f;
                        sl.layer.opacity = 0.0f;
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    void(*orig)(id,SEL,CGFloat) = (void(*)(id,SEL,CGFloat))MKResolveOrigIMP(sOrigSetIconLabelAlphaByClass, sOrigSetIconLabelAlphaByClassCF, self);
    if (orig && orig != (void(*)(id,SEL,CGFloat))MKSetIconLabelAlphaHook) {
        @try { orig(self, _cmd, a); }
        @catch (NSException *e) { RDLog(@"MKSetIconLabelAlphaHook orig EXCEPTION: %@", e.reason); }
    }
    // v2.0.62: β点(SBIconBetaLabelAccessoryView)是文本标签的【兄弟节点】(本机 iOS16 实测直挂 SBIconView)，
    // setIconLabelAlpha:0 经 iOS 原始实现把「整个 label 区(文字+β点)」一起藏掉 → β点随 藏名 消失、
    // 且要等 MKBetaReconcile/滚动 才复显(即"解锁消失/滑屏才出")。藏名生效后立即把 β点兄弟节点
    // 原位复显(不动坐标→绝不偏上)，灭上述两症。仅 keepBetaDot 开时生效(关则连同文字一起藏)。
    // v2.0.66.86: 角标模式整段跳过 —— 我们没藏名, β点不会被我们带走, 系统自己管即可。
    // (.85 曾特意注释"不能在此 return, 尾部这段与藏名无关必须继续执行" —— 那个判断是错的:
    //  这段的因果链源头正是"藏名把 β点一起藏了", 角标模式下它是纯粹的多余干预。)
    if (MKHideNames() && [MKConfig sharedConfig].keepBetaDot) {
        NSMutableArray *mkSt = [NSMutableArray arrayWithArray:(NSArray *)[self subviews]];
        while (mkSt.count > 0) {
            UIView *mkV = [mkSt lastObject]; [mkSt removeLastObject];
            if (MKBetaClass(mkV) && (mkV.hidden || mkV.alpha <= 0.0f)) {
                mkV.hidden = NO; mkV.alpha = 1.0f; mkV.layer.opacity = 1.0f; mkV.opaque = NO;
                MKEnsureBetaVertAlign((UIView *)self, mkV); // v2.0.63: 复显后竖直对齐文本中心(灭偏上)
                
            }
            [mkSt addObjectsFromArray:mkV.subviews];
        }
    }
}
// v2.0.40: 挂 setIconLabelAlpha: 到 SBIconView 及全部子类(类簇安全：仅当本类确实重写该 selector 才替换 IMP，
// 不污染 superclass 共享 IMP，避免 ___forwarding___ 硬陷阱)。
static void MKHookSBIconViewAlpha(void) {
    Class base = MKSBIconViewClass();
    if (!base) return;
    if (!sOrigSetIconLabelAlphaByClass) sOrigSetIconLabelAlphaByClass = [NSMutableDictionary dictionary];
    NSMutableSet<NSString*> *toHook = [NSMutableSet set];
    [toHook addObject:NSStringFromClass(base)];
    int n = objc_getClassList(NULL, 0);
    if (n > 0) {
        Class *buf = (Class *)malloc(sizeof(Class) * n);
        if (buf) {
            objc_getClassList(buf, n);
            for (int i = 0; i < n; i++) {
                Class sub = buf[i];
                if (class_isMetaClass(sub)) continue;
                if (MKClassIsSubclass(sub, base)) [toHook addObject:NSStringFromClass(sub)];
            }
            free(buf);
        }
    }
    for (NSString *cn in toHook) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        NSString *k = NSStringFromClass(cls);
        if ([sOrigSetIconLabelAlphaByClass objectForKey:k]) continue;
        Class sup = class_getSuperclass(cls);
        Method m = class_getInstanceMethod(cls, @selector(setIconLabelAlpha:));
        Method supM = sup ? class_getInstanceMethod(sup, @selector(setIconLabelAlpha:)) : NULL;
        if (m && m != supM && method_getImplementation(m) != (IMP)MKSetIconLabelAlphaHook) {
            IMP orig = method_getImplementation(m);
            [sOrigSetIconLabelAlphaByClass setObject:[NSValue valueWithPointer:(void *)orig] forKey:k];
            if (sOrigSetIconLabelAlphaByClassCF) CFDictionarySetValue(sOrigSetIconLabelAlphaByClassCF, (const void *)cls, (const void *)orig);
            method_setImplementation(m, (IMP)MKSetIconLabelAlphaHook);
        }
    }
}

static void MKHookOneLabelClass(Class cls) {
    if (!cls) return;
    NSString *k = NSStringFromClass(cls);
    if (!sOrigSetHiddenByClass) {
        sOrigSetHiddenByClass = [NSMutableDictionary dictionary];
        sOrigSetAlphaByClass  = [NSMutableDictionary dictionary];
    }
    // v2.0.66.34-perf: 懒建零分配 CFDict 镜像(指针键, 不 retain)
    if (!sOrigSetHiddenByClassCF) {
        sOrigSetHiddenByClassCF = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        sOrigSetAlphaByClassCF  = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        sOrigDidMoveToWindowByClassCF = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        sOrigDidMoveToSuperviewByClassCF = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        sOrigSetIconLabelAlphaByClassCF = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    }
    // v2.0.66.78 (A1): 幂等判据去掉 setFrame:/setCenter: 两项(hook 已删)
    if ([sOrigSetHiddenByClass objectForKey:k] && [sOrigSetAlphaByClass objectForKey:k]) return; // 全部已钩，幂等
    // v1.6.87: 仅当本类「真正重写」setHidden:/setAlpha: 才替换 IMP。
    // 此前对任意（含继承来的）Method 都 method_setImplementation，会把基类 orig 捕成
    // MKSetHiddenHook 自身 → 调用时死循环/向错误 self 发未识别 selector → 解锁安全模式。
    Class sup = class_getSuperclass(cls);
    Method m1 = class_getInstanceMethod(cls, @selector(setHidden:));
    Method m2 = class_getInstanceMethod(cls, @selector(setAlpha:));
    Method supM1 = sup ? class_getInstanceMethod(sup, @selector(setHidden:)) : NULL;
    Method supM2 = sup ? class_getInstanceMethod(sup, @selector(setAlpha:)) : NULL;
    if (m1 && m1 != supM1 && method_getImplementation(m1) != (IMP)MKSetHiddenHook) {
        IMP orig = method_getImplementation(m1);
        [sOrigSetHiddenByClass setObject:[NSValue valueWithPointer:(void *)orig] forKey:k];
        CFDictionarySetValue(sOrigSetHiddenByClassCF, (const void *)cls, (const void *)orig);
        method_setImplementation(m1, (IMP)MKSetHiddenHook);
    }
    if (m2 && m2 != supM2 && method_getImplementation(m2) != (IMP)MKSetAlphaHook) {
        IMP orig = method_getImplementation(m2);
        [sOrigSetAlphaByClass setObject:[NSValue valueWithPointer:(void *)orig] forKey:k];
        CFDictionarySetValue(sOrigSetAlphaByClassCF, (const void *)cls, (const void *)orig);
        method_setImplementation(m2, (IMP)MKSetAlphaHook);
    }
    // v2.0.66.78 (A1): 原 v2.0.66.42 的 setFrame:/setCenter: 强制 override 安装码已整体删除。
    // 两个 hook 自 β2 起纯透传(有效逻辑在 if(NO) 内), 而 class_replaceMethod/class_addMethod 会在
    // 每个 label 子类上真装一层 trampoline —— 布局热路径每帧白付两次调用开销。形态 B 的实际防线是
    // MKDockStrayHide 的每帧 owner 校验, 不依赖此处, 故删之零行为变化。
    // v2.0.7: 创建点拦截 —— 安全替换 didMoveToWindow:（用 class_replaceMethod / class_addMethod，
    // 即便本类未重写也只在本类加 override，绝不污染 superclass IMP → 不触发 ___forwarding___ 陷阱）。
    // label 一旦被 addSubview 进 window（新建/重父/动画层迁入）即刻被 MKLabelDidMoveToWindowHook 接管，
    // 若其所属图标 bid∈sHiddenBids 立刻藏名 + 种回关联键，先于系统任何显示路径生效。
    if (!sOrigDidMoveToWindowByClass) sOrigDidMoveToWindowByClass = [NSMutableDictionary dictionary];
    if ([sOrigDidMoveToWindowByClass objectForKey:k] == nil) {
        Method mw = class_getInstanceMethod(cls, @selector(didMoveToWindow));
        Method supMw = sup ? class_getInstanceMethod(sup, @selector(didMoveToWindow)) : NULL;
        if (mw && supMw) {
            IMP origW = NULL;
            if (class_getInstanceMethod(cls, @selector(didMoveToWindow)) != supMw) {
                // 本类已重写 → class_replaceMethod 取旧 IMP
                origW = class_replaceMethod(cls, @selector(didMoveToWindow), (IMP)MKLabelDidMoveToWindowHook, method_getTypeEncoding(mw));
            } else {
                // 本类未重写 → class_addMethod 加 override，原始 IMP = superclass 的
                class_addMethod(cls, @selector(didMoveToWindow), (IMP)MKLabelDidMoveToWindowHook, method_getTypeEncoding(supMw));
                origW = method_getImplementation(supMw);
            }
            if (origW) { [sOrigDidMoveToWindowByClass setObject:[NSValue valueWithPointer:(void *)origW] forKey:k];
                CFDictionarySetValue(sOrigDidMoveToWindowByClassCF, (const void *)cls, (const void *)origW); }
        }
    }
    // v2.0.65: 回收复用兜底 —— 安全替换 didMoveToSuperview:（同 didMoveToWindow: 的 class_replace/add 策略，
    // 即便本类未重写也只在本类加 override，绝不污染 superclass IMP）。label 跨槽位复用换父时由
    // MKLabelDidMoveToSuperviewHook 接管，清过期属主键 + 隐藏外来文字（灭 Dock 串台）。
    if (!sOrigDidMoveToSuperviewByClass) sOrigDidMoveToSuperviewByClass = [NSMutableDictionary dictionary];
    if ([sOrigDidMoveToSuperviewByClass objectForKey:k] == nil) {
        Method ms = class_getInstanceMethod(cls, @selector(didMoveToSuperview));
        Method supMs = sup ? class_getInstanceMethod(sup, @selector(didMoveToSuperview)) : NULL;
        if (ms && supMs) {
            IMP origS = NULL;
            if (class_getInstanceMethod(cls, @selector(didMoveToSuperview)) != supMs) {
                // 本类已重写 → class_replaceMethod 取旧 IMP
                origS = class_replaceMethod(cls, @selector(didMoveToSuperview), (IMP)MKLabelDidMoveToSuperviewHook, method_getTypeEncoding(ms));
            } else {
                // 本类未重写 → class_addMethod 加 override，原始 IMP = superclass 的
                class_addMethod(cls, @selector(didMoveToSuperview), (IMP)MKLabelDidMoveToSuperviewHook, method_getTypeEncoding(supMs));
                origS = method_getImplementation(supMs);
            }
            if (origS) { [sOrigDidMoveToSuperviewByClass setObject:[NSValue valueWithPointer:(void *)origS] forKey:k];
                CFDictionarySetValue(sOrigDidMoveToSuperviewByClassCF, (const void *)cls, (const void *)origS); }
        }
    }
}

// v1.6.91: 安全判断 sub 是否为 c 的子类，且【完全不发 selector】。
// 启动 15s(MKDelayedInit) 时 objc_getClassList 返回的全局类表可能含半初始化/悬垂 Class，
// 对其发 isSubclassOfClass: 会走 ___forwarding___ 硬陷阱(SIGTRAP) → 安全模式。
// class_isSubclassOfClass() 在构建 SDK 的 stub 中未导出（链接报 undefined symbol），
// 故改用 class_getSuperclass() 沿继承链逐层 C 指针比较：直接读 superclass 字段，
// 不经过 objc_msgSend / forwarding，对任何 Class 指针都安全，且 100% 存在于 SDK stub。
static BOOL MKClassIsSubclass(Class sub, Class c) {
    if (!sub || !c) return NO;
    Class cur = sub;
    while (cur) {
        if (cur == c) return YES;
        cur = class_getSuperclass(cur);
    }
    return NO;
}
static void MKInstallLabelHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            if (!sHiddenBids) sHiddenBids = [NSMutableSet set];
            // 候选标签类：覆盖 iOS 16.x 各子类名变体
            NSArray *candidates = @[
                @"SBIconLegibilityLabelView", // iOS 16.4.1 实测真实类（FICON-LABEL 日志证实）
                @"SBIconListLabel",
                @"SBIconLabelView"
            ];
            // 收集「候选类自身 + 其全部子类」去重后统一钩
            NSMutableSet<NSString*> *toHook = [NSMutableSet set];
            for (NSString *name in candidates) {
                Class c = NSClassFromString(name);
                if (!c) continue;
                [toHook addObject:NSStringFromClass(c)];
                int n = objc_getClassList(NULL, 0);
                if (n > 0) {
                    Class *buf = (Class *)malloc(sizeof(Class) * n);
                    if (buf) {
                        objc_getClassList(buf, n);
                        for (int i = 0; i < n; i++) {
                            Class sub = buf[i];
                            if (class_isMetaClass(sub)) continue;
                            // v1.6.91: 用 MKClassIsSubclass 走 superclass 指针比较，杜绝 ___forwarding___ 硬陷阱
                            if (MKClassIsSubclass(sub, c)) [toHook addObject:NSStringFromClass(sub)];
                        }
                        free(buf);
                    }
                }
            }
            for (NSString *cn in toHook) MKHookOneLabelClass(NSClassFromString(cn));
            MKHookSBIconViewAlpha();   // v2.0.40: 钉关文件夹 settle 的 label alpha 回弹入口
            
        } @catch (NSException *e) {
            RDLog(@"MKInstallLabelHook EXCEPTION: %@", e.reason);
        }
    });
}
// v1.6.85: 记录各 App「最近活动/消息」时间戳，供文件夹图标指示器挑代表 App 用。
// v1.6.85: 原「来信息最新」代表策略依赖 MKTouchMsg 记录各 App 最近活动时间戳(sLastMsgTime)，
// v2.0.24 该策略已移除，MKTouchMsg 及 sLastMsgTime 整条删除，此段注释保留作历史溯源。

static void MKUpdate(SBIconView *self) {
    MKSafe(^{
        if (!sInitDone) return;

        // v1.6.70: 锁屏/解锁处理改为"时间闸门"——锁屏时 sLocked=YES 并记录 sLockAt；
        // 解锁动画(~0.5s)结束(>0.7s)后，下一次布局自动复位 sLocked=NO 并正常显示指示器。
        // 不再依赖 lockstate 解锁通知（某些环境不送达/对象语义不符），根治"解锁后空白长/需滑动才出现"。
        if (sLocked) {
            NSTimeInterval now = [NSDate date].timeIntervalSince1970;
            if (now - sLockAt > 0.7) {
                sLocked = NO;  // v2.0.66.32: 解锁信号(解锁动画已结束)→即时复原, 不再延迟淡入
                if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
                MKUnlockRestore();  // v2.0.66.32: 即时 un-hide(原生携带)
                return;  // 翻闸后直接返回，避免下面正常流程立即硬显示当前图标
            } else {
                UIView *ind = MKFindIndicator(MKGetCachedBid(self));
                if (ind) ind.hidden = YES;
                return;
            }
        }

        if (MKIsDisabled()) {
            MKRemoveAllIndicators();
            UIView *label = MKGetCachedLabel(self);
            // v2.0.66.90 (B2): opaque=YES → NO。系统从不给透明背景的图标名 label 设 opaque,
            // 设 YES 会让 CA 跳过下层合成 → 渲染未定义内容一帧(闪)。此分支仅在插件被禁用时
            // 走到, 不是闪名主路径, 但同属客观错误, 一并纠正。复显本身保留(禁用必须还名字)。
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = NO;
                MKAssocLabelBid(label, nil);
            }
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (!cfg || !cfg.enabled) {
            MKRemoveAllIndicators();
            UIView *label = MKGetCachedLabel(self);
            // v2.0.66.90 (B2): 同上, opaque=YES → NO。
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = NO;
                MKAssocLabelBid(label, nil);
            }
            return;
        }

        // v1.6.73: 文件夹打开期间，主屏/Dock 图标实例不抢指示器所有权。
        // 同一 bid 在主屏与文件夹内各有一个 SBIconView 实例；文件夹打开时主屏实例
        // 仍在窗口内（被文件夹盖住），其 MKUpdate 会把指示器重父回主屏 overlay
        // → 被文件夹盖住不可见，与文件夹图标实例争抢 → "重开空位置 / 有些 App 没反应"。
        // 文件夹图标实例才是该 bid 在文件夹期间的权威所有者，故主屏/Dock 实例在
        // sFolderOpen 时完全跳过指示器管理；FOLDER CLOSE 刷新会复位主屏。

        // v1.6.76: 文件夹【图标】（桌面/Dock 上、未打开）显示 1 个圆点。
        // 里面 ≥1 个后台运行 App 时显示；颜色按 folderIndicatorMode 取「代表 App」主色（auto 模式），
        // 固定色模式圆点用全局固定色；形状/尺寸走全局 cfg（与里面 App 的圆点同步）。
        // 必须在 sFolderOpen 门控之前处理：文件夹图标本身不在文件夹内、其 own bid 不是 App，
        // 若放到门控之后，打开别的文件夹时会被早退跳过、圆点不刷新。
        if (MKIsFolderIcon((SBIconView *)self)) {
            // v1.6.78: folder icons don't have an application bundleID, so MKGetCachedBid returns nil.
            // Use a synthetic key based on the SBFolderIcon object pointer so the overlay indicator
            // can be indexed and reused.
            id fIcon = [self icon];
            NSString *fBid = fIcon ? [NSString stringWithFormat:@"__folder__%p", fIcon] : nil;
            
            if (!fBid.length) return;
            // v1.6.92: 文件夹打开动画中，桌面文件夹图标 view 可能被临时 reparent 到
            // SBFloatyFolderScrollView 等容器下；此时若走 FICON 创建/重定位，会把圆点
            // 画到打开的文件夹内部（见截图）。只让桌面/Dock 容器下的文件夹图标显指示器，
            // 其它容器一律跳过，等关闭后 MKRefreshFolderIcons 再刷新。
            UIView *fContainer = MKContainerForIconView((UIView *)self);
            // v2.0.66.34-perf: 零分配版——class_getName() 直接拿 C 字符串，省掉每次 MKUpdate 的 NSString 分配。
            const char *fContainerCls = fContainer ? class_getName([fContainer class]) : "";
            BOOL fIsHomeOrDock = (strcmp(fContainerCls, "SBIconScrollView") == 0) || (strncmp(fContainerCls, "SBDock", 5) == 0);
            if (!fIsHomeOrDock) {
                
                return;
            }
            // v1.6.83: 文件夹图标重算风暴根因——MKRefreshSubviews 每次布局/滚动都对 folder 图标走完整 FICON 重算
            // （取色 + 排序 + 建/更新指示器 + setNeedsDisplay），约 5 万次空转/会话。复用既有的代际缓存键
            // kMKFIconGenKey/sFolderContentGen：内容未变（无 App 启停/设置变更/文件夹开合）时直接跳过昂贵重算，
            // 仅廉价重定位已有指示器。重算独家交给事件驱动的 MKRefreshFolderIcons（App 启停经 MKOnStateChange 必触发、gen+1）。
            NSNumber *fGen = objc_getAssociatedObject(self, &kMKFIconGenKey);
            if (fGen && [fGen unsignedIntegerValue] == sFolderContentGen) {
                UIView *skipInd = MKFindIndicator(fBid);
                if (skipInd) {
                    MKConfig *fCfg = [MKConfig sharedConfig];
                    UIView *container = MKContainerForIconView((UIView *)self);
                    UIView *overlay = MKOverlayForContainer(container);
                    if (overlay && fCfg) {
                        CGRect f = MKIndicatorFrameInOverlay((SBIconView *)self, overlay, fCfg);
                        if (!CGRectIsEmpty(f)) { skipInd.frame = f; skipInd.hidden = NO; }
                    }
                    // 顺带加固 label 隐藏不变量（呼应 v1.6.82，防与圆点重叠）
                    UIView *lbl = MKGetCachedLabel((SBIconView *)self);
                    if (lbl) {
                        // ★ v2.0.66.90 【B2 —— 本轮头号修复：角标模式不写回 label 可见性】★
                        //  用户实机 .89: 角标模式下【完全合拢文件夹后名字闪一下, 不是每次】。
                        //  .88/.89 一直在查「谁还在藏名」, 方向错了 —— 藏名路径此时已全部门控完毕
                        //  (主屏 label 在 HomeGrid 内, MKForeignContainerCtx 白名单必返 nil)。
                        //  真凶在【反方向】: 角标模式下我们从不藏名, 却仍在多处无条件写
                        //  hidden=NO / alpha=1 / layer.opacity=1 / opaque=YES 去「恢复」它。
                        //
                        //  两层危害:
                        //   ① opaque=YES 对 SpringBoard 的图标名 UILabel 是【客观错误】——
                        //      它背景透明, 系统从不这么设。opaque=YES 等于告诉 CoreAnimation
                        //      「本层完全不透明, 不必合成下层」→ 该区域按不透明处理, 而实际绘制
                        //      内容大量透明像素 → 渲染出未定义内容(黑/白块或上帧残留)一帧,
                        //      随后 UILabel 内部按 backgroundColor 自行纠回 → 肉眼即「闪一下」。
                        //   ② 在 iOS 跑 crossfade 的窗口内直接改 model 值(alpha/opacity),
                        //      与 presentation layer 冲突 → 同样一帧跳变。
                        //  关文件夹时 SBFolderView.didMoveToWindow(nil) 会【同步 + 异步各一次】
                        //  MKRefreshSubviews(主屏) → 遍历全部图标走到这里 → 落在 crossfade 窗口
                        //  内就闪、落在窗口外就不闪 → 精确对应「合拢后闪一下、不是每次」。
                        //
                        //  修法: 角标模式下这些写回是【纯粹的抢控制权无意义写】(我们从未藏过它,
                        //  没有任何东西需要恢复) → 整段删除, 只保留 MKAssocLabelBid 清键
                        //  (纯关联对象, 不触发任何渲染)。替换模式行为保持 —— 仅把 opaque=YES
                        //  一并纠正为 NO(修客观错误, 方向是「少干预」, 不会导致名字不显示)。
                        if (MKHideNames()) { lbl.hidden = YES; lbl.alpha = 0.0f; lbl.layer.opacity = 0.0f; lbl.opaque = NO; MKAssocLabelBid(lbl, fBid); }
                        else MKAssocLabelBid(lbl, nil);
                    }
                }
                
                return;
            }
            NSArray<NSString*> *contained = MKContainedRunningBids((SBIconView *)self);
            
            if (contained.count == 0) {
                
                UIView *lbl = MKGetCachedLabel(self);
                // v2.0.66.90 (B2): 角标模式不写回可见性(我们从未藏它, 无可恢复);
                // 替换模式保留写回, opaque 由 YES 纠正为 NO。详见上方 B2 完整说明。
                if (lbl) {
                    if (MKHideNames()) { lbl.hidden = NO; lbl.alpha = 1.0f; lbl.layer.opacity = 1.0f; lbl.opaque = NO; }
                    MKAssocLabelBid(lbl, nil);
                }
                UIView *fi = MKFindIndicator(fBid);
                if (fi) MKRemoveIndicatorForBid(fBid);
                return;
            }
            MKConfig *fCfg = [MKConfig sharedConfig];
            // v2.0.66.86: 角标模式下文件夹指示器【强制生效】, 不受「文件夹图标显示指示器」开关控制。
            // 理由: 该开关当初存在的意义是「替换名称模式下文件夹图标的名字会被指示器顶掉,
            // 用户可能不愿为文件夹付这个代价」—— 是一个「名字 vs 指示器」的取舍开关。
            // 角标模式根本不碰名字, 这个取舍不存在, 开关退化为纯粹的功能缺失, 故忽略。
            // 设置页会在角标模式下把该开关置灰, 与此处行为一致(见 MKRootListController)。
            if (!fCfg || (MKHideNames() && !fCfg.folderIndicators)) {
                
                UIView *lbl = MKGetCachedLabel(self);
                // v2.0.66.90 (B2): 角标模式不写回可见性(我们从未藏它, 无可恢复);
                // 替换模式保留写回, opaque 由 YES 纠正为 NO。详见上方 B2 完整说明。
                if (lbl) {
                    if (MKHideNames()) { lbl.hidden = NO; lbl.alpha = 1.0f; lbl.layer.opacity = 1.0f; lbl.opaque = NO; }
                    MKAssocLabelBid(lbl, nil);
                }
                UIView *fi = MKFindIndicator(fBid);
                if (fi) MKRemoveIndicatorForBid(fBid);
                return;
            }
            // 有运行 App → 显示 1 个圆点（代表 App 固定为位置靠前的运行 App）
            BOOL fixedColor = (fCfg.colorMode == MKColorModeFixed);
            NSString *rep = MKFolderChosenBid(contained);
            UIView *label = MKGetCachedLabel(self);
            
            if (label) {
                // v2.0.66.90 (B2): 角标模式不写回可见性 —— 这是【文件夹有运行 App】的主路径,
                // 也就是关合文件夹后必然走到的那一支, 闪名的直接来源。详见上方 B2 完整说明。
                if (MKHideNames()) { label.hidden = YES; label.alpha = 0.0f; label.layer.opacity = 0.0f; label.opaque = NO; MKAssocLabelBid(label, fBid); }
                else MKAssocLabelBid(label, nil);
            }
            UIView *container = MKContainerForIconView((UIView *)self);
            UIView *overlay = MKOverlayForContainer(container);
            if (!overlay) {
                dispatch_async(dispatch_get_main_queue(), ^{ MKUpdate(self); });
                return;
            }
            CGRect indicatorFrame = MKIndicatorFrameInOverlay((SBIconView *)self, overlay, fCfg);
            UIView *indicator = MKFindIndicator(fBid);
            if (!indicator) {
                indicator = [[MKIndicatorDotView alloc] initWithFrame:indicatorFrame];
                indicator.tag = kDotTag;
                objc_setAssociatedObject(indicator, &kMKIndicatorBidKey, fBid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [(MKIndicatorDotView *)indicator setIconCornerRadius:MKIconCornerRadius((UIView *)self)];
                [(MKIndicatorDotView *)indicator setBadgeCorner:fCfg.badgeCorner];
                [(MKIndicatorDotView *)indicator applyConfig];
                if (!fixedColor && rep.length) {
                    UIColor *c = MKCachedIconColorForBundleID(rep);
                    if (c) [(MKIndicatorDotView *)indicator setIndicatorColor:c];
                }
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:fBid];
                if (sHiddenBids && MKHideNames()) [sHiddenBids addObject:fBid]; // v1.6.85: 文件夹合成 key 也要藏名
                
                MKFadeInFolderIndicatorIfClosing(indicator); // v2.0.43: 关窗期淡入, 消除缩略图点瞬现
            } else {
                if (indicator.superview != overlay) {
                    [indicator removeFromSuperview];
                    [overlay addSubview:indicator];
                }
                if (!fixedColor && rep.length) {
                    UIColor *c = MKCachedIconColorForBundleID(rep);
                    MKIndicatorDotView *dot = (MKIndicatorDotView *)indicator;
                    UIColor *cur = dot.indicatorColor;
                    if (!cur || !CGColorEqualToColor(cur.CGColor, c.CGColor)) {
                        [dot setIndicatorColor:c];
                        [indicator setNeedsDisplay];
                    }
                }
                if (!CGRectIsEmpty(indicatorFrame)) {
                    indicator.frame = indicatorFrame;
                    indicator.hidden = NO;
                    MKFadeInFolderIndicatorIfClosing(indicator); // v2.0.43: 关窗期淡入, 消除缩略图点瞬现
                }
            }
            return;
        }

        if (sFolderOpen && !MKIsIconInFolder((UIView *)self)) {
            
            return;
        }

        // v1.5.3: 使用缓存的 bundleID（避免每次都调 applicationBundleID）
        NSString *bundleID = MKGetCachedBid(self);
        // v1.6.60: 维护 bid→图标视图 注册表（弱引用），供 MKRefreshIconForBundleID 直接命中
        // 不依赖窗口遍历，文件夹/滚动/转场等活跃态下也能可靠刷新。
        if (bundleID && [self isKindOfClass:MKSBIconViewClass()]) {
            if (!sBidToIconView) sBidToIconView = [NSMapTable strongToWeakObjectsMapTable];
            [sBidToIconView setObject:self forKey:bundleID];
        }
        // v1.6.59: 滚动中不再一律跳过创建（v1.6.57/58 因此导致后台 App 永久零指示器）。
        // 改为：滚动中仅为「运行中+后台+尚无指示器」的 App 即时补建；其余（前台/文件夹/非运行）仍跳过以防 churn。
        // 可靠兜底：MKOnStateChange 在 App 转后台时还会于 300ms/800ms 调 MKRefreshIconForBundleID→MKUpdate，
        // 即使当时仍在滚动也会落点创建，不再依赖翻停重试。
        BOOL running = MKIsAppRunning(bundleID);
        BOOL isForeground = MKIsForeground(bundleID);
        UIView *existingIndicator = MKFindIndicator(bundleID);
        // v2.0.46: 逐帧 overlay(父) 可见性不变量 + 解锁 gate-flip 一次性淡入
        // 根治「解锁后指示器消失」（recycle 竞态）；并在 0.7s 闸门翻 NO 的瞬间触发一次
        // alpha 0→1 淡入，使解锁指示器柔和出现。关键：淡入与 reveal 同源（同一帧翻转触发），
        // 无第二定时器竞态，故不闪。必须跑在 sLastState 去重 return(L2939) 之前。
        // 仅读已存在 overlay（不懒建）；仅在 hidden 不符才写；reveal 时一次性 animate（绝不下每帧 animate，否则抖）。
        if (bundleID.length) {
            UIView *mkCont = MKContainerForIconView((UIView *)self);
            UIView *mkOv = mkCont ? [sContainerToOverlay objectForKey:mkCont] : nil;
            if (mkOv) {
                NSTimeInterval mkNow = [NSDate date].timeIntervalSince1970;
                // v2.0.48: 关文件夹缩回「活闪」修复 —— 缩回动画【进行中】(sFolderClosing=YES,
                // 由 SBFolderController -viewWillDisappear: 在关闭起始武装)且本图标位于文件夹内层
                // (容器非主屏 SBIconScrollView / 非 Dock SBDock*)时，强制隐藏指示器，
                // 避免它一路跟着迷你 app 图标缩回文件夹缩略图而闪现。
                // scoped：仅当 sFolderClosing 且容器是文件夹类型才藏；主屏/Dock 图标(容器=SBIconScrollView/SBDock*)
                // mkInFolderLive=NO 不受影响，文件夹图标本身(桌面/Dock 上的 SBFolderIcon)也不受影响。
                // 复用上方已算出的 mkCont，零额外调用。sFolderClosing 仅在关文件夹~1.2s 窗内为 YES，平常零影响。
                BOOL mkInFolderLive = NO;
                if (sFolderClosing && mkCont) {
                    NSString *mkContCls = NSStringFromClass([mkCont class]);
                    BOOL mkIsHomeOrDock = [mkContCls isEqualToString:@"SBIconScrollView"]
                                          || [mkContCls hasPrefix:@"SBDock"];
                    mkInFolderLive = !mkIsHomeOrDock;
                }
                // v2.0.66.32: 移除 (mkNow - sLockAt <= 0.7) 锁后宽限 —— 解锁信号一到(sLocked=NO)
                // 逐帧即显示圆点, 不再强制藏 0.7s 制造"第二波"。锁屏态仍由 sLocked 守卫隐藏。
                BOOL mkShouldHide = sLocked || (sFolderClosing && mkInFolderLive);
                if (mkOv.hidden != mkShouldHide) {
                    // v2.0.66.79 (A6): 原 BOOL mkWasHidden = mkOv.hidden; 已删除 ——
                    // 它只喂下方 PERFRAME-FIX 诊断行, 探针在 .71 移除后成为 write-only 死值。
                    if (!mkShouldHide) {
                        // v2.0.66.32: 解锁即时揭示改由 MKUnlockRestore 显式 un-hide 负责(原生携带, 无独立淡入),
                        // 不依赖此处逐帧不变量在 overlay 上做动画。此处只确保 overlay 解除隐藏,
                        // 不重置 alpha、不叠动画(sUnlockFading 为真时由 MKUnlockRestore 已即时 un-hide, 避免重抖/双淡入)。
                        if (mkOv.hidden) mkOv.hidden = NO;
                        if (!sUnlockFading) {
                            // 非解锁场景（设置变更/文件夹关闭等）兜底淡入：先归 0 再淡到 1
                            mkOv.alpha = 0.0f;
                            [UIView animateWithDuration:0.25 delay:0
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                                animations:^{ mkOv.alpha = 1.0f; } completion:nil];
                        }
                    } else {
                        // hide（锁屏/关文件夹）：瞬隐 + 复位 alpha，供下次淡入从 0 起
                        mkOv.hidden = YES;
                        mkOv.alpha  = 0.0f;
                    }
                    // 诊断——仅当逐帧不变量「真的纠正了」某个 overlay 才打点（gated by sDebugLog）。
                    // reveal 行带 " fade(reveal)" 标记，grep PERFRAME-FIX 可证触发/救回数。
                    
                }
            }
        }
        // v1.6.60 诊断：仅针对「后台运行中 App」的 MKUpdate 打点（不刷屏）。
        // 能看到：MKUpdate 是否真的被调到、当时 sScrolling/hasIndicator 状态、最终是否建出。
        // 若 REFRESH 命中却无本行 → MKUpdate 没被调（触发链断）；
        // 若有本行却无 Indicator CREATE → MKUpdate 内部早退；据此一击定位。
        
        // v1.6.81: folder icons don't participate in scroll gate; opening animation is mis-detected as scrolling
        BOOL isInFolder = MKIsIconInFolder((UIView *)self);
        // v1.6.70: 移除"文件夹打开期间一律显示名称并 return"的压制。
        // 现在文件夹内运行中 App 也要显示指示器（与主屏一致）：名称隐藏、指示器
        // 建在文件夹自己的 overlay 上（MKOverlayForContainer 按当前容器懒建）。
        // 非运行中 App 自然落到下方 !running 分支恢复名称。
        if (sScrolling && !isInFolder) {
            
            // v1.6.59: 滚动中不再一律跳过。仅为「运行中+后台+尚无指示器」的 App 即时补建，
            // 根治 v1.6.57/58 零指示器回归（滚动门控把创建永久挡在门外、翻停重试又不可靠覆盖）。
            // 其余场景（前台/文件夹/非运行）滚动中仍跳过，避免 v1.6.56 的 fg 闪烁 churn：
            //   · 指示器是图标子视图、随图标一起移动，滚动中创建不会"乱跑/跳错"；
            //   · 前台 App 由下方 !running||isForeground 分支统一移除，不会在滚动中误建；
            //   · 已有指示器的 App 落点走 return，不会被反复重建（这正是 v1.6.56 churn 的根因）。
            if (running && !isForeground && !existingIndicator) {
                // 缺指示器后台 App → 落点直接创建，不 return
            } else {
                return;  // 非「缺指示器后台 App」→ 滚动中跳过即时操作（防 churn）
            }
        }
        // v1.6.57: 跳过"已打开文件夹内部"的 App 图标 —— 文件夹内 App 不应显示桌面指示器
        // （否则重新打开文件夹时名称与指示器重叠、且文件夹内 App 都有指示器，视觉错乱）。
        // 检测 self 的视图层级是否处在某个 SBFolderView 子树内；文件夹【容器】图标本身不在其内部，不受影响。
        {
            // v1.6.66: 重写文件夹内检测 —— 旧逻辑沿祖先链爬 SBFolderView/SBFolderController，
            // 但 iOS16 文件夹内图标实际挂在 SBFloatyFolderScrollView（UIScrollView 子类）下，
            // 其祖先链未必含那两个类名；且打开动画早期图标临时挂在 UIView 下、层级未组装，
            // 都会漏判 → 文件夹内 App 被错误创建桌面指示器、名字被隐藏
            // （日志铁证：IND-OVERLAY bid=taobao container=SBFloatyFolderScrollView）。
            // 同一 bid 在主屏与文件夹里是两个独立图标实例、却共享 sBidToIndicator 里唯一一个指示器对象，
            // 旧逻辑 MKRemoveIndicatorForBid 还会误删主屏那个，导致主屏后台 App 丢失指示。
            // 修正：sFolderOpen 时按"当前容器类型"判定——主屏(SBIconScrollView)/Dock(SBDock*)
            // 之外即视为文件夹内容器(SBFloatyFolderScrollView 等)，不再依赖祖先链爬类名。
            if (MKIsIconInFolder((UIView *)self)) {
                // v1.6.70: 不再"只显示名称并 return"——文件夹内运行中 App 现在也要显示指示器
                // （与主屏一致：名称隐藏、指示器显示在文件夹 overlay）。非运行中 App 自然落到下方
                // !running 分支恢复名称。同一 bid 的主屏/文件夹指示器由 MKOverlayForContainer
                // 自动重父到当前容器，关闭文件夹时 FOLDER CLOSE 刷新会把它重父回主屏 overlay，无重复/无丢失。
                
            }
        }
        if (!bundleID || bundleID.length == 0) {
            
            return;
        }

        BOOL isPending = MKIsPending(bundleID);       // v1.5.6+: 等待300ms的App
        BOOL isFading = MKIsFadingLabel(bundleID);    // v1.5.8: 标签正在渐隐中

        // v1.6.55: 入口门控快照 —— 只给"正在运行的后台 App"打，定位主屏指示器为何不创建。
        // 若某 App 走到这里却既没建指示器、也没打 NO LABEL/RUNNING 日志，看这行即可知卡在哪道门控。
        

        // v1.6.76: 文件夹「内部」运行的 App 现在走下方常规主功能路径各自显示圆点
        // （用户要求「保留里面各自显」）。文件夹【图标】本身挂圆点的逻辑在上方 MKIsFolderIcon 分支。


        // v1.5.3: 使用缓存的标签视图（避免每次都跑 MKFindLabelView 4 重策略）
        UIView *label = MKGetCachedLabel(self);
        UIView *indicator = existingIndicator;

        // 当前被用户打开在前台的 App，桌面上不再显示指示器（避免启动动画残留）
        if (!running || isForeground) {
            
            // ── App 不在运行 / 在前台 → 移除指示器，恢复名字 ──
            if (indicator) MKRemoveIndicatorForBid(bundleID);
            MKRestoreBetaOrphan((UIView *)self); // v2.0.30: 移除我们脱离的孤儿小黄点，系统自建原 label 点
            // ★ v2.0.66.90 (B2): 这是【每个非运行/前台图标每次 MKUpdate 必经】的复显路径 ——
            //   关文件夹触发 MKRefreshSubviews(主屏) 时全屏图标都会走到这里, 是闪名的主路径之一。
            //   角标模式我们从不藏名 → 无条件写回是抢控制权的无意义写, 且 opaque=YES 对透明背景的
            //   name label 是客观错误(CA 跳过下层合成 → 渲染未定义内容一帧)。改为与 L3486/L3504
            //   同构的条件恢复: 稳态零写入, 只在确实被我们藏住时(切模式残留)恢复一次。
            //   替换模式路径不变(仍需无条件复显), 仅把 opaque=YES 纠正为 NO。
            if (label) {
                if (MKHideNames()) {
                    label.hidden = NO;
                    label.alpha = 1.0f;
                    label.layer.opacity = 1.0f;
                    label.opaque = NO;
                    MKAssocLabelBid(label, nil);
                } else {
                    MKRestoreLabelIfOurs(label);
                }
            }
            MKRemovePending(bundleID);  // v1.5.6+: 清除 pending 状态
            MKRemoveFadingLabel(bundleID); // v1.5.8: 清除渐隐状态
            return;
        }

        // v1.5.8: 标签正在渐隐中 → 不干扰动画，不创建指示器
        // 让 250ms 渐隐动画自然播放，300ms后才创建指示器
        if (isFading) {
            
            return;  // 不做任何操作，让渐隐动画继续
        }

        // v1.5.6+: pending 期间只隐藏标签，不创建指示器（等300ms回调）
        // 标签渐隐已完成（alpha=0），但仍需保持隐藏状态防止系统恢复
        if (isPending) {
            
            if (label && MKHideNames()) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
                MKAssocLabelBid(label, bundleID);
            } else if (label) {
                // v2.0.66.87 (B2): 角标模式 —— 名字本就该可见, 交还系统。
                // 只在确实被我们藏住时恢复一次(稳态零写入), 不再无条件写回。
                MKRestoreLabelIfOurs(label);
            }
            return;  // 不创建指示器，等300ms后 MKRefreshIconForBundleID 回调
        }

        // v2.0.66.78 (A4): 原 RDLogRunning(bundleID) 调用已删除(空体死函数)。

        // ── App 正在运行 → 隐藏名字，显示指示器 ──
            MKDetachBetaOnce((UIView *)self); // v2.0.30: beta App 先把小黄点脱离 label，避免被藏名牵连
            if (label) {
                if (MKHideNames()) {
                    label.hidden = YES;
                    label.alpha = 0.0f;
                    label.layer.opacity = 0.0f;
                    label.opaque = NO;
                    MKAssocLabelBid(label, bundleID);
                } else {
                    // v2.0.66.87 (B2): 角标模式 —— 交还系统, 仅条件恢复(见 MKRestoreLabelIfOurs)
                    MKRestoreLabelIfOurs(label);
                }
            } else {
            // v1.5.5 诊断：App 在运行但找不到标签
            
        }

        // v1.6.64: 指示器尺寸改由 MKIndicatorFrameInOverlay 内部按 cfg 计算，此处不再需要。

        // ── v1.6.64: 指示器挂在稳定的 overlay 层（图标滚动容器），不再是被回收 SBIconView 的子视图 ──
        // 这样图标滚出屏幕/被回收时，指示器不会随 view 消失或漂到别的 App（根治乱飞+消失）。
        // 容器滚动时 overlay 与图标同处同一滚动坐标系，指示器自动跟随，无需逐帧重定位。
        UIView *container = MKContainerForIconView((UIView *)self);
        UIView *overlay = MKOverlayForContainer(container);
        if (!overlay) {
            // v1.6.74: 文件夹打开动画尚未把 SBFloatyFolderScrollView 组装入树，
            // 此刻容器 overlay 还拿不到 → 不要静默跳过（否则该运行 App 本次开文件夹
            // 漏建指示器，表现为「重复开文件夹时有些 App 没反应 / 那一瞬是空的」）。
            // 下一帧重试，overlay 就绪后自然建出。
            dispatch_async(dispatch_get_main_queue(), ^{
                MKUpdate(self);
            });
            return;
        }
        CGRect indicatorFrame = MKIndicatorFrameInOverlay(self, overlay, cfg);

        // v1.6.64: 统一用「按 bid 索引的 overlay 指示器」作为唯一真相来源（替代旧的 self 子视图关联）。
        indicator = MKFindIndicator(bundleID);

        if (!indicator) {
            indicator = [[MKIndicatorDotView alloc] initWithFrame:indicatorFrame];
            indicator.tag = kDotTag;
            objc_setAssociatedObject(indicator, &kMKIndicatorBidKey, bundleID, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // v1.6.63: 记录归属，供防乱跑校验
            [(MKIndicatorDotView *)indicator setIconCornerRadius:MKIconCornerRadius((UIView *)self)];
            [(MKIndicatorDotView *)indicator setBadgeCorner:cfg.badgeCorner];
            [(MKIndicatorDotView *)indicator applyConfig];

            // v1.6.11: AutoIcon 模式 — 从图标取主色调作为指示器颜色
            if (cfg.colorMode == MKColorModeAutoIcon) {
                UIColor *iconColor = MKCachedIconColorForBundleID(bundleID);
                [(MKIndicatorDotView *)indicator setIndicatorColor:iconColor];
                [indicator setNeedsDisplay];  // 用新颜色重绘
            }

            // v1.5.7: 渐显动画 — 状态切换时指示器 alpha 0→cfg.opacity 200ms
            BOOL shouldAnimate = MKShouldAnimateIndicator(bundleID);
            MKRemoveAnimateIndicator(bundleID);  // 消费标记（一次性）
            if (sScrolling) shouldAnimate = NO;  // v1.6.56: 滚动中首次创建不渐显，避免 churn 视觉

            // v1.5.9: 添加指示器创建日志（方便追踪横条显示问题）
            // v1.6.55: 创建行自带版本戳，日志被截断也能一眼确认构建版本
            
            // v2.0.66.2: 顺带修主屏 beta 小黄点回收残留(见 MKGetCachedBid 回收清理)

            if (shouldAnimate) {
                indicator.alpha = 0.0f;
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:bundleID];
                if (sHiddenBids && MKHideNames()) [sHiddenBids addObject:bundleID]; // v1.6.85: 标记此 bid 名字必须隐藏
                CGFloat finalAlpha = cfg.opacity;
                
                [UIView animateWithDuration:0.2 animations:^{
                    indicator.alpha = finalAlpha;
                }];
            } else {
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:bundleID];
                if (sHiddenBids && MKHideNames()) [sHiddenBids addObject:bundleID]; // v1.6.85: 标记此 bid 名字必须隐藏
            }
            [overlay bringSubviewToFront:indicator];  // v1.6.71: 确保指示器在文件夹 overlay 顶层（z-order）
            
        } else {
            // v1.6.64: 已存在 → 校验是否还在正确的 overlay 上（容器变了需重父）。
            // v1.6.71: 同一 bid 在主屏/文件夹是两处不同图标实例、各自 overlay；
            // 文件夹打开/关闭切换时，若指示器仍挂在旧 overlay（如已移除的文件夹 overlay）上
            // 会不可见。这里检测到 superview 不匹配就重父到当前 overlay。
            if (indicator.superview != overlay) {
                UIView *oldParent = indicator.superview;
                [indicator removeFromSuperview];
                [overlay addSubview:indicator];
                [overlay bringSubviewToFront:indicator];
                
            }
            // 图标离屏时保留最后位置不重算
            if (!CGRectIsEmpty(indicatorFrame)) {
                indicator.frame = indicatorFrame;
                indicator.hidden = NO;
            }
        }

        // v1.6.11: AutoIcon 主色调 —— 创建时上色；后续 layout 取色成功(或从绿兜底修正)时自动重绘
        // 配合 MKCachedIconColorForBundleID 不缓存失败：首次取不到→绿兜底，下次取到真实色→这里自动更新
        if (cfg.colorMode == MKColorModeAutoIcon && indicator) {
            UIColor *iconColor = MKCachedIconColorForBundleID(bundleID);
            MKIndicatorDotView *dot = (MKIndicatorDotView *)indicator;
            UIColor *cur = dot.indicatorColor;
            if (!cur || !CGColorEqualToColor(cur.CGColor, iconColor.CGColor)) {
                [dot setIndicatorColor:iconColor];
                [indicator setNeedsDisplay];
            }
        }
    });
}

// ====================================================================
// 清理所有指示器（处理动画容器残留）
// ====================================================================

// ====================================================================
// v1.6.0: 刷新容器视图内所有 SBIconView（用于文件夹打开等场景）
// ====================================================================

// v1.6.31: SBIconView 类静态化（刷新遍历每节点原本都 NSClassFromString，提为一次性查找）
static Class MKSBIconViewClass(void) {
    static Class c = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = NSClassFromString(@"SBIconView");
    });
    return c;
}

static void MKRefreshSubviews(UIView *containerView) {
    MKSafe(^{
        if (!sInitDone || !containerView) return;
        NSMutableArray *stack = [NSMutableArray arrayWithArray:containerView.subviews];
        int refreshed = 0;
        // v1.6.81: collect visual order of in-folder icons for folder indicator rep strategy
        NSMutableDictionary<NSNumber*, NSMutableArray<NSDictionary*>*> *tmpVisual = [NSMutableDictionary dictionary];
        while (stack.count > 0) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            if ([v isKindOfClass:MKSBIconViewClass()]) {
                SBIconView *iv = (SBIconView *)v;
                NSString *bid = MKGetCachedBid(iv);
                id icon = [iv icon];
                id fldr = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                if (icon && [icon respondsToSelector:NSSelectorFromString(@"folder")])
                    fldr = [icon performSelector:NSSelectorFromString(@"folder")];
#pragma clang diagnostic pop
                if (bid.length && fldr) {
                    NSNumber *key = @((NSUInteger)fldr);
                    NSMutableArray *arr = tmpVisual[key];
                    if (!arr) { arr = [NSMutableArray array]; tmpVisual[key] = arr; }
                    [arr addObject:@{@"bid": bid, @"y": @(v.frame.origin.y), @"x": @(v.frame.origin.x)}];
                }
                MKUpdate((SBIconView *)v);
                refreshed++;
            }
            [stack addObjectsFromArray:v.subviews];
        }
        if (tmpVisual.count > 0) {
            if (!sFolderVisualOrder) sFolderVisualOrder = [NSMutableDictionary dictionary];
            for (NSNumber *key in tmpVisual) {
                NSArray *arr = [tmpVisual[key] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    CGFloat ya = [a[@"y"] floatValue];
                    CGFloat yb = [b[@"y"] floatValue];
                    if (ya < yb) return NSOrderedAscending;
                    if (ya > yb) return NSOrderedDescending;
                    CGFloat xa = [a[@"x"] floatValue];
                    CGFloat xb = [b[@"x"] floatValue];
                    if (xa < xb) return NSOrderedAscending;
                    if (xa > xb) return NSOrderedDescending;
                    return NSOrderedSame;
                }];
                NSMutableArray *bids = [NSMutableArray arrayWithCapacity:arr.count];
                for (NSDictionary *d in arr) [bids addObject:d[@"bid"]];
                sFolderVisualOrder[key] = bids;
            }
        }
        
    });
}

// v1.6.81: clear pending/fading markers for in-folder running apps before refreshing.
// This eliminates the visible "blank then appears" delay when opening a folder.
static void MKClearPendingInView(UIView *root) {
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([v isKindOfClass:MKSBIconViewClass()]) {
            SBIconView *iv = (SBIconView *)v;
            NSString *bid = MKGetCachedBid(iv);
            if (bid && bid.length && MKIsAppRunning(bid) && !MKIsForeground(bid)) {
                MKRemovePending(bid);
                MKRemoveFadingLabel(bid);
            }
        }
        [stack addObjectsFromArray:v.subviews];
    }
}

// ====================================================================
// 刷新所有图标
// ====================================================================

static void MKRefreshAllIcons() {
    MKSafe(^{
        if (!sInitDone) return;
        MKUpdateDockFrame(); // v2.0.66.38: 刷新时同步 dock 容器 window frame 缓存(供物理位置判定)
        // v1.6.78: folder-open watchdog — if sFolderOpen=YES but no SBFolderView in window,
        // reset it so main-screen icons are no longer skipped.
        if (sFolderOpen) {
            BOOL hasFolder = NO;
            NSArray *wins = [UIApplication sharedApplication].windows;
            for (UIWindow *w in wins) {
                if (MKFindDescendantView(w, @"SBFolderView")) { hasFolder = YES; break; }
            }
            if (!hasFolder) {
                sFolderOpen = NO;
                
            }
        }
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                if ([current isKindOfClass:MKSBIconViewClass()]) {
                    MKUpdate((SBIconView *)current);
                    // v2.0.66.86: 角标模式下小黄点交还系统 —— 不做 reconcile / hideAll,
                    // 只做一次 MKRestoreBetaOrphan 清掉「从替换模式切过来时残留的脱离孤儿点」,
                    // 否则它会与系统在 label 内重建的原生点重影。见 MKBetaHideAll 说明。
                    if (!MKHideNames()) {
                        MKRestoreBetaOrphan((UIView *)current);
                    } else if ([MKConfig sharedConfig].keepBetaDot) {
                        MKBetaReconcile((SBIconView *)current); // v2.0.34: ON → 复显被藏的 beta 点
                    } else {
                        MKBetaHideAll((UIView *)current);   // v2.0.66.3: OFF → 隐藏全部 beta 点(运行+未运行)
                    }
                    // v2.0.66.46: dock 串名事件兜底 —— 内联进本趟 BFS, 零额外遍历
                    // (取代 v2.0.66.45 在函数尾部再独立 BFS 一整棵树的 MKDockBandSweep)。
                    // 必须放在 MKUpdate 之后: MKUpdate 会为非运行 App 复显名称, 先藏会被它覆盖。
                    // v2.0.66.86: 门控由 MKHideNames() 改 MKFixStrayNames() —— MKDockStrayHide 是
                    // dock 串名的【唯一防线】, 其动作虽是「藏 label」但语义是「纠正 iOS 把旧名字
                    // 渲染到原生无名字的 dock」, 与我们抢不抢名字位无关。.85 随藏名一并关掉 →
                    // 角标模式 dock 串名无人纠正(用户实机复现的直接根因)。
                    if (MKFixStrayNames()) MKDockStrayHide((SBIconView *)current, NULL);
                }
                for (UIView *child in current.subviews) {
                    [stack addObject:child];
                }
            }
        }
    });
}

// ====================================================================
// 定向刷新：只更新指定 bundleID 对应的 SBIconView（v1.5.3 性能优化）
// 避免每次状态变化都遍历整个视图层级
// ====================================================================

static void MKRefreshIconForBundleID(NSString *bid) {
    MKSafe(^{
        if (!sInitDone || !bid.length) return;
        // v1.6.60: 优先用 bid→图标视图 注册表（弱引用），不依赖窗口遍历。
        // iOS 16 SpringBoard 在文件夹/滚动/转场等活跃态下，主屏图标视图常不在
        // [UIApplication sharedApplication].windows 的常规遍历可达路径，导致刷新落空、
        // 活跃态下指示器永远建不出来（静止态靠 layoutSubviews 才偶尔建成）。
        if (!sBidToIconView) sBidToIconView = [NSMapTable strongToWeakObjectsMapTable];
        SBIconView *regView = [sBidToIconView objectForKey:bid];
        if (regView && [regView isKindOfClass:MKSBIconViewClass()]) {
            NSString *regBid = MKGetCachedBid(regView);
            if (regBid && [regBid isEqualToString:bid]) {
                
                MKUpdate(regView);
                return;
            }
        }
        // 兜底：原窗口遍历（兼容视图尚未入注册表 / 注册表条目已弱引用失效的情况）
        NSArray *windows = [UIApplication sharedApplication].windows;
        int walked = 0;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                if ([current isKindOfClass:MKSBIconViewClass()]) {
                    SBIconView *iv = (SBIconView *)current;
                    NSString *ivBid = MKGetCachedBid(iv);
                    if (ivBid && [ivBid isEqualToString:bid]) {
                        walked++;
                        MKUpdate(iv);
                    }
                }
                for (UIView *child in current.subviews) {
                    [stack addObject:child];
                }
            }
        }
        
    });
}

// ====================================================================
// v1.5.8: 标签渐隐动画（前台→后台时，标签 alpha 1→0 的 250ms 渐隐）
// 替代 v1.5.6 的瞬间隐藏，让过渡更自然
// ====================================================================

static void MKFadeOutLabelForBundleID(NSString *bid) {
    MKSafe(^{
        if (!sInitDone || !bid.length) return;
        if (!MKHideNames()) return;  // 角标模式：名字永不渐隐，保持可见
        MKAddFadingLabel(bid);  // v1.5.8: 标记渐隐状态

        BOOL fadeStarted = NO;  // v1.6.0: 追踪是否实际启动了渐隐动画
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                if ([current isKindOfClass:MKSBIconViewClass()]) {
                    SBIconView *iv = (SBIconView *)current;
                    NSString *ivBid = MKGetCachedBid(iv);
                    if (ivBid && [ivBid isEqualToString:bid]) {
                        UIView *label = MKGetCachedLabel(iv);
                        if (label) {
                            // v1.5.8: 250ms 渐隐动画（alpha 1→0）
                            fadeStarted = YES;
                            [UIView animateWithDuration:0.25
                                                  delay:0
                                                options:UIViewAnimationOptionAllowAnimatedContent
                                             animations:^{
                                label.alpha = 0.0f;
                                label.layer.opacity = 0.0f;
                            } completion:^(BOOL finished) {
                                // 渐隐完成 → 确保完全隐藏 + 清除渐隐标记
                                label.hidden = YES;
                                label.opaque = NO;
                                MKAssocLabelBid(label, bid);
                                MKRemoveFadingLabel(bid);
                            }];
                        }
                    }
                }
                for (UIView *child in current.subviews) {
                    [stack addObject:child];
                }
            }
        }

        // v1.6.0: 如果渐隐动画没有启动（找不到图标或label=nil），
        // 250ms后自动清除fading状态，防止isFading永远卡住
        // 这处理了文件夹内图标（关闭时不在视图层级）和Dock图标（无label）的情况
        if (!fadeStarted) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                MKRemoveFadingLabel(bid);
            });
        }
    });
}

static void MKRestoreLabelForBundleID(NSString *bid) {
    MKSafe(^{
        if (!sInitDone || !bid.length) return;
        MKRemoveFadingLabel(bid);  // v1.5.8: 清除渐隐标记
        MKRemovePending(bid);      // v1.5.8: 清除 pending 标记
        // v2.0.66.85: 角标模式名字永不藏（MKFadeOutLabelForBundleID 已早退）→ 下面这趟
        // 全窗口 BFS 找到的 label 本来就是可见的, 恢复动画等于给每个匹配图标白跑一次
        // 0.15s 动画。标记清理保留（幂等、廉价）, BFS 整段跳过。
        if (!MKHideNames()) return;
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                if ([current isKindOfClass:MKSBIconViewClass()]) {
                    SBIconView *iv = (SBIconView *)current;
                    NSString *ivBid = MKGetCachedBid(iv);
                    if (ivBid && [ivBid isEqualToString:bid]) {
                        UIView *label = MKGetCachedLabel(iv);
                        if (label) {
                            // v1.5.8: 如果标签正在渐隐中，需要动画恢复
                            // 否则直接恢复可见性
                            [UIView animateWithDuration:0.15 animations:^{
                                label.hidden = NO;
                                label.alpha = 1.0f;
                                label.layer.opacity = 1.0f;
                                label.opaque = NO;   // v2.0.66.90 (B2): YES → NO(客观错误纠正)
                                MKAssocLabelBid(label, nil);
                            }];
                        }
                    }
                }
                for (UIView *child in current.subviews) {
                    [stack addObject:child];
                }
            }
        }
    });
}

// ====================================================================
// 动画感知的状态变更处理（v1.5.8）
// - App 进入前台：立即移除指示器（0ms 延迟，避免动画残留）
// - App 返回后台：标签 250ms 渐隐 + 300ms 后指示器 200ms 渐显
//   → 自然交叉淡入淡出，只有约 50ms 空档
// - App 退出：立即移除指示器 + 恢复标签
// ====================================================================

static void MKOnStateChange(NSString *bid, BOOL running, BOOL foreground) {
    if (!sInitDone || !bid.length) return;
    // v1.6.30: 黑名单 App（含桌面有图标的越狱工具 Sileo / Dopamine / Filza 等）
    // 不走任何名称渐隐 / 指示器逻辑 —— 反正不显示指示器，名字就保持原样，
    // 避免「名字被渐隐淡出、却没有指示器顶上」的空档（之前观察到的问题）。
    if (MKIsBlacklisted(bid)) return;

    // v1.6.76: 文件夹内容代际 +1（里面 App 运行态变了），并刷新所有文件夹图标
    // v2.0.64: 代际 +1 已下放到 MKRefreshFolderIcons 内（避免单次状态变更双 +1），这里仅调度刷新
    if (sInitDone) dispatch_async(dispatch_get_main_queue(), ^{ MKRefreshFolderIcons(); });

    // v1.6.69: 文件夹打开期间，跳过一切 label 渐隐/指示器逻辑。
    // 否则文件夹内 App 发生 fg→bg 状态切换（打开文件夹瞬间前台 App 退后台）会触发
    // 后台分支的 250ms 渐隐，把文件夹内 App 名称淡出、稍后又被 sFolderOpen 守卫拉回可见
    // → 肉眼"名称闪一下"。簿记（running set / foreground）已由 SBApplication hook 在调用前完成，
    // 这里只管视觉副作用；文件夹关闭时 FOLDER CLOSE 刷新会按正确状态复位。
    // 注意：仍调用 MKStateDidChange 保持去重表新鲜，避免关闭后某次状态切换
    // 被误判为"未变"而漏显指示器（否则 sLastState 在文件夹期间会变陈旧）。
    if (sFolderOpen) {
        MKStateDidChange(bid, running, foreground);
        // v1.6.79: while folder open, an app state change (e.g. fg->bg) used to only
        // update bookkeeping; in-folder indicator then waited for the 300ms pending
        // callback to clear -> visible "blank then appears". Clear pending/fading now and
        // refresh immediately (main-screen icons are FOLDER-GUARD skipped, safe);
        // in-folder running apps get their indicator on the next frame.
        
        MKRemovePending(bid);
        MKRemoveFadingLabel(bid);
        dispatch_async(dispatch_get_main_queue(), ^{ MKRefreshAllIcons(); });
        return;
    }

    // 状态去重：同一 bundleID 的 (running, foreground) 没变就跳过
    // 这能消除 _noteProcess + _setInternalProcessState 重复触发的问题
    if (!MKStateDidChange(bid, running, foreground)) return;

    if (foreground) {
        // ── App 进入前台 → 立即移除指示器（避免动画残留）──
        MKRemovePending(bid);     // 清除 pending 状态
        MKRemoveFadingLabel(bid); // v1.5.8: 清除渐隐状态
        dispatch_async(dispatch_get_main_queue(), ^{
            MKRefreshIconForBundleID(bid);
        });
    } else if (running) {
        // v1.6.31: 只在 App 确实在我们的 running set 中（用户打开/用过）才做标签/指示器逻辑。
        // 纯后台被 iOS 拉起、从未前台过的 App 不在集合里 → 直接跳过，名字保持原样、不亮指示器。
        if (!MKIsAppRunning(bid)) return;
        // ── v2.0.66.87 (B1): 角标模式立即建指示器, 整套渐隐排期交还系统 ──
        // 下面 250ms 渐隐 + 300ms 延迟建 + 800ms 备用刷新这一整套排期, 唯一设计动机写在
        // 原注释里: 「等返回动画结束 + 标签渐隐接近完成」再建指示器, 免名字与圆点重叠一瞬。
        // 角标模式【不藏名、不抢名字位】→ 动机整体消失, 而代价是实打实的:
        //   · MKAddPending/MKAddAnimateIndicator 进两个状态集, 而 layoutSubviews 里
        //     `MKIsPending || MKIsFadingLabel` 那处早退是【无条件】的(.85 改)
        //     → 300ms 内该图标 layoutSubviews 全部被跳过, 指示器晚 300ms 才出现;
        //   · 两个 dispatch_after 各带一次全量 MKRefreshIconForBundleID, 主线程忙时堆积;
        //   · 300ms 内 App 又回前台 → 走 MKRestoreLabelForBundleID(自 .85 已早退成空操作) 纯空转。
        // 渐显动画标记保留 —— 那是我们【自己的 overlay 指示器】的 alpha 动画, 与藏名无关。
        if (!MKHideNames()) {
            MKAddAnimateIndicator(bid);
            dispatch_async(dispatch_get_main_queue(), ^{
                MKRefreshIconForBundleID(bid);
            });
            return;
        }
        // ── App 返回后台 → v1.5.8: 标签渐隐 + 指示器渐显 ──
        // 标签不再瞬间消失：250ms 渐隐 alpha 1→0
        // 300ms 后创建指示器并 200ms 渐显 alpha 0→cfg.opacity
        MKAddPending(bid);          // 标记为"等待指示器"
        MKAddAnimateIndicator(bid); // 标记渐显动画（一次性消费）

        // v1.5.8: 标签渐隐动画（替代 v1.5.6 的瞬间隐藏）
        dispatch_async(dispatch_get_main_queue(), ^{
            MKFadeOutLabelForBundleID(bid);
        });

        // 延迟300ms创建指示器（等返回动画结束 + 标签渐隐接近完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            MKRemovePending(bid);      // 清除 pending 状态
            MKRemoveFadingLabel(bid);  // v1.6.0: 清除渐隐状态（防文件夹/Dock无label导致isFading卡住）
            if (!MKIsForeground(bid) && MKIsAppRunning(bid)) {
                MKRefreshIconForBundleID(bid);  // 创建指示器（带渐显动画）
            } else {
                // 300ms内App又变前台或退出了 → 恢复标签
                MKRestoreLabelForBundleID(bid);
                MKRemoveAnimateIndicator(bid);  // 清除渐显标记
            }
        });

        // v1.6.0: 备用刷新 — 800ms后再试一次
        // 300ms dispatch_after 在动画期间可能被堆积，主线程忙碌导致延迟
        // 800ms 后动画一定已结束，此时再刷新确保指示器可靠创建
        // 同时清除残留的 pending/fading 状态（文件夹/Dock图标可能找不到label导致状态卡住）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MKRemoveFadingLabel(bid);  // v1.6.0: 确保清除（防止文件夹/Dock标签找不到导致isFading卡住）
            MKRemovePending(bid);      // v1.6.0: 确保清除
            if (MKIsAppRunning(bid) && !MKIsForeground(bid)) {
                MKRefreshIconForBundleID(bid);
            }
        });
    } else {
        // App exit: remove indicator + restore label immediately
        MKRemovePending(bid);
        MKRemoveFadingLabel(bid);
        // v1.6.78: direct overlay cleanup by bid (in case MKUpdate gates skip removal)
        MKRemoveIndicatorForBid(bid);
        MKRestoreLabelForBundleID(bid);
        dispatch_async(dispatch_get_main_queue(), ^{
            MKRefreshIconForBundleID(bid);
        });
    }
}

// ====================================================================
// 延迟初始化（15 秒后执行，不阻塞 SpringBoard 启动）
// ====================================================================

static void MKDelayedInit() {
    

    // ─── 步骤 1：系统黑名单 ──────
    MKInitBlacklist();

    // ─── v1.6.86：源头级藏名 hook（SBIconLegibilityLabelView + 子类树 setHidden:/setAlpha: swizzle）───
    // 在 MKRefreshAllIcons 之前安装，确保首次刷新时藏名即生效。
    MKInstallLabelHook();

    // ─── 步骤 2：路径缓存 ──────
    MKBuildPathCache();

    // ─── 步骤 3：SBApplicationController 初始同步 ──────
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    MKSyncFromSBAppCtrl();

    // ─── 步骤 4：进程枚举辅助 ──────
    MKComputeRunningSetFromProc();

    
    

    // ─── 标记初始化完成 ──────
    sInitDone = YES;
    


    // ─── 首次刷新所有图标 ──────
    MKRefreshAllIcons();
    MKRefreshFolderIcons();
}

// v2.0.66.87: locationMode 切换一次性迁移 —— 恢复所有被我们藏过的 label + 清权威集合。
//
// 【为什么必须有这段】原先「替换 → 角标」切换时恢复名字的唯一执行路径是
// MKUpdate running 分支的 else（把 label 无条件写回 hidden=NO/alpha=1）。
// .87 要把那三处 else 改成「条件恢复」(B2, 只在确实被藏时才写) 就必须先有一条
// 显式的迁移路径, 否则一旦某图标此刻不在窗口层级里(离屏/文件夹内/dock 回收槽),
// 它的 label 永远等不到那次写回 → 名字保持 hidden=YES 永不复原。
// MKRestoreLabelForBundleID 帮不上: 它自 .85 起 `if (!MKHideNames()) return;` 已早退。
//
// 判据: 只认「我们藏的」—— label 带 kMKLabelBidKey 关联键(MKAssocLabelBid 写入)
// 或 bid ∈ sHiddenBids。系统自己藏的 label(dock/负一屏 stray、编辑抖动中间态)
// 一律不碰 —— 否则会把 MKFixStrayNames() 刚擦掉的 stray 名字重新翻出来(.85 血案同源)。
static void MKMigrateLocationMode(void) {
    MKSafe(^{
        if (!sInitDone) return;
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                // 只认 label-like 视图（与 layoutSubviews 兜底同款零分配判定）
                BOOL isL = [current isKindOfClass:[UILabel class]] ||
                           (strstr(class_getName([current class]), "Label") != NULL);
                if (isL && (current.hidden || current.alpha <= 0.01f)) {
                    NSString *ourBid = objc_getAssociatedObject(current, &kMKLabelBidKey);
                    BOOL ours = (ourBid.length != 0);
                    if (!ours && sHiddenLabelToBid && [sHiddenLabelToBid objectForKey:(id)current]) ours = YES;
                    if (ours) {
                        // stray 容器内的 label 不复显 —— 这些位置原生无名字, 复显 = 制造 bug。
                        // MKFixStrayNames() 恒真, 下一帧也会再擦一遍, 但这里先别添乱。
                        // v2.0.66.88: 判据与 MKRestoreLabelIfOurs 对齐 —— 文件夹缩略图在
                        // 角标模式下已交还系统(不再擦), 故此时【必须】复原我们过去藏的,
                        // 否则切到角标模式后缩略图里那些名字永久 hidden=YES(残留干预)。
                        // 本函数在 reload 之后调用 → MKHideNames() 已是新模式的值。
                        // v2.0.66.89: 角标模式改用 MKBadgeMayEraseName —— 它把「dock 里的
                        // 文件夹缩略图」从不复显名单里排除(我们已不再擦它 → 过去藏的必须还)。
                        // 替换模式分支一字不变(foreign || thumb)。
                        if (MKHideNames()
                              ? (MKForeignContainerCtx(current) != nil || MKViewInFolderThumb(current))
                              : MKBadgeMayEraseName(current)) {
                            objc_setAssociatedObject(current, &kMKLabelBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        } else {
                            current.hidden = NO;
                            current.alpha = 1.0f;
                            current.layer.opacity = 1.0f;
                            [current.layer removeAllAnimations];
                            objc_setAssociatedObject(current, &kMKLabelBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        }
                    }
                }
                for (UIView *child in current.subviews) {
                    [stack addObject:child];
                }
            }
        }
        // 权威集合清空: 两个方向都该清。
        //  · → 角标: sHiddenBids 恒空是该模式的不变量, 残留会让源级 setHidden/setAlpha hook 继续强藏。
        //  · → 替换: 残留的旧表项对应的 label 可能已被回收复用, 留着只会误藏。
        //    正确的表项会在下面 MKRefreshAllIcons → MKUpdate 藏名时重新写入。
        if (sHiddenBids) [sHiddenBids removeAllObjects];
        if (sHiddenLabelToBid) [sHiddenLabelToBid removeAllObjects];
        // 排期状态集合也清: 角标模式不再排 300ms/800ms(见 MKStateDidChange), 残留 bid 会让
        // layoutSubviews 的 `MKIsPending || MKIsFadingLabel` 无条件早退一直命中 → 指示器建不出来。
        if (sPendingBIDs)    [sPendingBIDs removeAllObjects];
        if (sFadingLabelBIDs) [sFadingLabelBIDs removeAllObjects];
    });
}

static void MKPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    // v2.0.66.87: locationMode 变化检测必须在 reload 之前取旧值
    static MKLocationMode sLastLocationMode = MKLocationReplace;
    static BOOL sLastModeValid = NO;
    MKLocationMode oldMode = sLastLocationMode;
    BOOL hadOld = sLastModeValid;
    [[MKConfig sharedConfig] reload];
    MKLocationMode newMode = [MKConfig sharedConfig].locationMode;
    sLastLocationMode = newMode;
    sLastModeValid = YES;
    BOOL modeChanged = (hadOld && oldMode != newMode);
    if (modeChanged) MKMigrateLocationMode();
    // ★ v2.0.66.92 【跨模式切换必须全量重建指示器，不能只重画】★
    //  病灶: 下面那段循环只 setBadgeCorner/setIconCornerRadius/setNeedsDisplay，【不重算 frame】。
    //  但两模式的 frame 完全不是一个量级(见 MKIndicatorFrameInOverlay):
    //    · 角标模式 frame = 图标图片方形 bounds 四周各扩 MKBadgeFrameExtra(15pt) ≈ 90x90, 原点 -15
    //    · 替换模式 frame = 以 name label 矩形为心的 dotSize / barWidth x barHeight ≈ 6~40pt
    //  于是切模式后至少一帧是「新模式的绘制代码 + 旧模式的 frame」:
    //    · 角标→替换: 旧 frame 90x90, 替换分支 CGContextFillEllipseInRect(CGRectInset(rect,0.5,0.5))
    //      把【整个 frame】当圆点本体画 → 一个约 89pt 的巨型圆点糊住图标。
    //    · 替换→角标: 旧 frame 只有 6~40pt → drawRect 里 W = rect.w - 2*15 变负 → 触发兜底
    //      W = rect.size.width → rc = MIN(W,H)*0.2237 ≈ 2pt → 弧线又小又在错位置。
    //  二级病灶: MKUpdate 复用分支「图标离屏时保留最后位置不重算」(!CGRectIsEmpty 守卫) 会让
    //  当前不在视图树内的图标(别页/dock/已关文件夹内)长期滞留【旧模式】frame, 而 MKRefreshAllIcons
    //  只遍历 [UIApplication windows] 可达的 SBIconView, 覆盖不到 → 旧 frame 可以存活很久。
    //
    //  修法: 跨模式一律全量重建 —— 重建必然走 MKUpdate 的创建分支
    //  (initWithFrame:新frame + setIconCornerRadius + setBadgeCorner + applyConfig 一次性按新模式初始化),
    //  离屏残留问题一并消失(指示器直接不存在, 等该图标下次 layout 时按新模式新建)。
    //  MKRemoveAllIndicators 会清 sHiddenBids/sHiddenLabelToBid, 但 MKMigrateLocationMode 上一行
    //  刚跑完、本来就要清这两张表 → 语义不冲突。
    if (modeChanged) {
        MKRemoveAllIndicators();
        MKRefreshAllIcons();
        MKRefreshFolderIcons();
        return;
    }
    // v2.0.66.81: 角标参数(badgeCorner/thickness/inset)变更时刷新已存在的指示器。
    // thickness/inset 在 drawRect 直接读 cfg → setNeedsDisplay 即重画；badgeCorner 是属性需重设。
    // v2.0.66.91: badgeArcLength(弧长比例)同属「drawRect 直接读 cfg」一类 → 无需新增属性,
    //   下面的 setNeedsDisplay 已覆盖, 拖滑块即时生效。
    // v2.0.66.87: iconCornerRadius 也必须重设 —— 原注释「图标本身没变故不重设」漏了一种情形:
    //   setIconCornerRadius 只在【指示器创建时】调一次(MKUpdate L3365)。从替换模式切到角标模式
    //   时指示器往往已存在(MKFindIndicator 非 nil → 不走创建分支) → 用的是当初创建那一刻取到
    //   的值; 若那时图标图层尚未布好 continuousCornerRadius, 取到的是兜底 m*0.2237。
    //   .82 时代弧线本就不准看不出, .87 改同心圆角后 rc 直接决定外轮廓是否等距 → 必须校正。
    // ★ v2.0.66.92: 同模式内参数变更也必须【重算 frame】——原来只 setNeedsDisplay 是错的:
    //   替换模式的 frame 就是圆点本体尺寸(dotSize / barWidth x barHeight), 只重画不换 frame →
    //   拖 dotSize/barWidth/barHeight 滑块【不即时生效】, 得等那个图标下次 layout 才变。
    //   角标模式因为都在固定 90x90 画布内绘制, 所以 thickness/inset/arcLength 看不出这个缺口。
    //   保守原则: 只在能【可信】算出新 frame 时才写, 算不出就一字不动(退化为改动前行为,
    //   等该图标下次 layout 由 MKRepositionIndicator/MKUpdate 复位) —— 绝不 hidden=YES,
    //   否则文件夹指示器(key 是 __folder__%p, 永不进 sBidToIconView)会被一律藏起来,
    //   而 layoutSubviews 对文件夹指示器只管藏名不管几何 → 可能一直藏到下次 gen 变更, 是回归。
    if (sBidToIndicator) {
        MKConfig *cfg = [MKConfig sharedConfig];
        NSArray *bids = [[sBidToIndicator keyEnumerator] allObjects];
        for (NSString *bid in bids) {
            UIView *ind = [sBidToIndicator objectForKey:bid];
            if (![ind isKindOfClass:[MKIndicatorDotView class]]) continue;
            [(MKIndicatorDotView *)ind setBadgeCorner:cfg.badgeCorner];
            SBIconView *iv = sBidToIconView ? [sBidToIconView objectForKey:bid] : nil;
            if (iv) {
                CGFloat rc = MKIconCornerRadius((UIView *)iv);
                if (rc > 0) [(MKIndicatorDotView *)ind setIconCornerRadius:rc];
                // ⚠️ sBidToIconView 存的是「最后一次 MKUpdate 的图标实例」, 多页桌面下可能是
                //   另一页的实例(见 MKIndicatorFrameInOverlay 头部警告) → 用它算出的 frame 属于
                //   另一个 overlay 坐标系, 直接套上去 = 指示器飘到别页。判据: 该图标必须真的在
                //   指示器当前所挂的 overlay 子树内。
                //   直接用 ind.superview 而不调 MKOverlayForContainer —— 后者会懒建 overlay, 在这里
                //   为一个当前没有 overlay 的容器凭空造一个是纯副作用。
                UIView *ov = ind.superview;
                if (ov && [iv isDescendantOfView:ov]) {
                    CGRect f = MKIndicatorFrameInOverlay(iv, ov, cfg);
                    if (!CGRectIsEmpty(f)) ind.frame = f;
                }
            }
            [ind setNeedsDisplay];
        }
    }
    MKRefreshAllIcons();
    MKRefreshFolderIcons();
}

// ====================================================================
// Hook — SBIconView
// ====================================================================

%hook SBIconView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        // v1.6.26: 不再在离屏时销毁指示器 / 清 bid+icon 缓存。
        // 旧逻辑：图标每次滚出屏幕（didMoveToWindow window=nil）都 removeFromSuperview + 清缓存，
        //   再次滚入时 MKUpdate 重新 alloc 一个 → 指示器反复销毁/重建（日志里 CREATE ≈ 2× RUNNING）。
        // 现在只恢复名字标签的可见性；指示器对象与 bid/icon 缓存保留。
        // 真正的图标回收（icon 指针变化）仍由 MKGetCachedBid 检测并清理，不影响正确性。
        UIView *label = MKGetCachedLabel(self);
        if (label) {
            // v1.6.82: 本 bid 当前仍有运行中指示器（名字本就被圆点替代）时，
            // 不要在离屏时恢复名字——否则关文件夹动画期间 in-folder App 名字会闪一下。
            // 图标再次出现在有效上下文（主屏运行中 / 重开文件夹）时由 MKUpdate 重新决断。
            NSString *bid2 = MKGetCachedBid(self);
            // v1.6.98: 关文件夹瞬间（SBFolderView 离窗）内层 App 的 SBIconView 也收到
            // didMoveToWindow(nil)。此时其指示器可能已被文件夹 overlay 拆除、MKFindIndicator
            // 暂返 nil，旧逻辑误判"无指示器"→ 把名字恢复出来 → 缩回动画末尾那一帧
            // 内部 App 名称闪现（第4点）。
            // 改判据：只要该 App 仍在后台运行（名字本就该被圆点替代），无论指示器对象
            // 此刻在否都强制保留隐藏。与 v1.6.96 "sHiddenBids 权威"不变量一致；
            // 关闭后主屏图标 MKUpdate 会接管重显指示器，名字继续由藏名规则压制。
            if (bid2 && (MKFindIndicator(bid2) || (MKIsAppRunning(bid2) && !MKIsForeground(bid2))) && MKHideNames()) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
            } else if (!MKHideNames()) {
                // v2.0.66.87 (B2): 角标模式 —— 交还系统, 仅条件恢复(见 MKRestoreLabelIfOurs)。
                // 注意本 else 是两模式共用: 替换模式下走下面的无条件恢复分支【一字不改】——
                // 那里覆盖的是「App 已退出/前台 → 名字必须复原」, 而替换模式下我们确实
                // 是名字的主动持有者, 无条件写回是正确且必要的(判据失效时也能兜住)。
                MKRestoreLabelIfOurs(label);
            } else {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = NO;   // v2.0.66.90 (B2): YES → NO(客观错误纠正; 本分支仅替换模式可达)
                MKAssocLabelBid(label, nil);
            }
        }
        // 注意：保留 indicator（关联对象）+ kMKBidKey/kMKIconKey/kMKLabelKey 缓存
        return;
    }
    if (sInitDone) {
        // v1.6.0: 诊断日志 — 追踪 App 图标出现时机（特别是文件夹内图标）
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MKUpdate(self);
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if (!sInitDone) return;

    // v2.0.66.31: dock 上下文每帧强制藏名 —— 根治 dock 随机串名(主屏 SBIconView 回收复用渲染 dock 槽, 把任意旧名带进来; 名字随机=回收哪个图标随机)。
    // 不依赖 sHiddenBids(随机名可能非运行中 app), 也不依赖创建点钩子(复用后原地改可见性不触发 moveToWindow/superview)。
    // 仅当本 SBIconView 在 dock 容器内时每帧把 name label 归零; dock 仅 ~4 图标开销可忽略; 主屏/文件夹 MKLabelInDock 返回 NO 即跳过, 不误伤。
    // v2.0.66.46: 判定升级为「祖先链 OR 物理位置」二合一(MKDockStrayHide)。
    // 旧实现只判 MKLabelInDock(祖先链含 Dock 类名) → 只覆盖形态 A(iconView 被回收进 dock 子树);
    // 形态 B(label 仅物理漂到 dock 纵带、层级仍主屏)整段跳过 → 每帧藏名对当前复发的串名完全失效。
    {
        BOOL strayHidden = NO;
        // v2.0.66.86: 门控由 MKHideNames() 改 MKFixStrayNames()(见 L3521 同款说明)。
        // 角标模式下这条每帧防线必须在位, 否则 dock 串名照旧。
        if (MKFixStrayNames() && MKDockStrayHide((SBIconView *)self, &strayHidden)) {
            return;  // 真 dock 图标: 名字已钉藏, 不走下方主屏/文件夹逻辑; 指示器几何由 MKUpdate 全局管理
        }
        if (strayHidden) {
            // 主屏图标但 label 物理漂到 dock 纵带(异常瞬态): 已钉藏, 本帧不再往下走 ——
            // 否则下方「非运行 App 恢复名称」分支会立刻把它复显, 白藏。指示器几何仍由 MKUpdate/MKRepositionIndicator 全局兜。
            return;
        }
    }

    // v2.0.66.86: 【角标模式】每帧纠正「iOS 把名字渲染到原生无名字位置」——
    // v2.0.66.88 修订: 缩略图那一路【已删除】。用户实机证实角标模式文件夹名仍在闪, 真因
    // 就是「我们擦 live label, 而 iOS 开合文件夹的 compositor crossfade 快照里名字还在」
    // → live/snapshot 不一致。角标模式契约本是「名字一律不动」, 缩略图名也是名字。
    // 现只保留 foreign 容器一路:
    //   · foreign 容器(负一屏 SBToday*/SBDashboard*/SBWidget*/SBFFocusIsolationView, 及 dock 的
    //     层级形态): 原生无名字, 且未观察到闪(无 crossfade 快照通道)。dock 另由上方
    //     MKDockStrayHide 每帧兜, 此处补齐其余。
    // 判定按容器 default-deny(与运行状态无关), 误伤空间为零: 这些位置本来就没名字。
    // MKLabelInHomeGrid 守卫在 MKForeignContainerCtx 内, 主屏网格名绝不被误杀。
    // 仅角标模式走(替换模式已有既有链路), 且先做廉价的 hidden/alpha 预筛再爬祖先链。
    if (!MKHideNames() && MKFixStrayNames()) {
        UIView *tl = MKGetCachedLabel((SBIconView *)self);
        if (tl && tl.superview && !tl.hidden && tl.alpha > 0.01f) {
            // ⚠️ 这里曾是第 5 个(也是最强的, 每帧执行)缩略图擦名点 —— 若将来有人把
            //    MKViewInFolderThumb 加回来, 前四处(setHidden/setAlpha/setIconLabelAlpha/
            //    didMoveToWindow)的 .88 修复会被它一并抵消, 文件夹闪名立刻复现。
            // v2.0.66.89 (S3): 改走 MKBadgeMayEraseName —— 该谓词内部把 MKViewInFolderThumb
            //    用作【豁免守卫(return NO)】而非触发器, 与上面这条警告方向相反, 不冲突。
            if (MKBadgeMayEraseName(tl)) {
                tl.hidden = YES;
                tl.alpha = 0.0f;
                tl.layer.opacity = 0.0f;
                tl.opaque = NO;
                [tl.layer removeAllAnimations];
                return;   // 非法位置的图标不参与主屏/文件夹指示器决策
            }
        }
    }

    // v1.6.70: 移除"文件夹打开期间一律显示名称并 return"的压制。
    // 现在文件夹内运行中 App 也要显示指示器（与主屏一致），故交下方
    // MKIsIconInFolder / 常规 running 分支处理（运行中→藏名+指示器；非运行→恢复名称）。

    NSString *bid = MKGetCachedBid(self);
    // v2.0.17: 关文件夹缩回时 SBIconView 为新建实例，MKGetCachedBid(self) 此刻
    // 尚未关联 bid → 用 label 直接关联键兜底（移植 v1.6.99 不变量），避免图标
    // 重建瞬间因 bid 为空、后续 `if (!bid) return` 提前退出而漏藏（日志
    // FOLDER-CLOSE-VISIBLE=2 的真凶：APPEAR 新建视图那一帧被 MKUpdate 误显）。
    // MKLabelToBid 仅在 bid 仍属 sHiddenBids 时采信，回收复用残留旧 bid 已被其自身守卫拦掉。
    if (!bid) {
        UIView *mkL = MKGetCachedLabel((SBIconView *)self);
        if (mkL) bid = MKLabelToBid(mkL);
    }
    // v1.6.94: 文件夹图标纳入 layoutSubviews 每帧藏名（治图1 红条与文件夹名重叠）。
    // v2.0.4: 藏名判据升级为以 sHiddenBids 为权威（与下方 App 分支 2782 对称）。
    // 旧 v1.6.94 实现用 if(MKFindIndicator(fBid)) —— 仅当指示器对象当前存在才藏名。
    // 但文件夹打开/缩回动画中，指示器随 overlay 临时脱离或重父 → MKFindIndicator
    // 暂返 nil → 那几帧不藏名 → iOS 把文件夹名称复显 → 与红条重叠(图1) 残留、
    // 即「情况好转但还有」（日志铁证：FICON-LABEL label=YES 同一文件夹重复 23 次）。
    // fBid(__folder__%p) 已在 FICON 创建时加入 sHiddenBids(1952)，只要它仍在集合
    // （=文件夹里有 App 在后台运行、名字必须隐藏）即每帧强制藏名，与指示器对象
    // 此刻是否存在无关 → 彻底钉死文件夹名不闪不叠。几何仍交 MKUpdate / MKRepositionIndicator。
    BOOL isFolder = MKIsFolderIcon((SBIconView *)self);
    if (isFolder) {
        // v2.0.66.85: 角标模式下本分支唯一工作(藏文件夹名)注定不执行, 但原实现每帧仍要
        // [self icon] + stringWithFormat 造一个 __folder__%p 字符串(每帧一次堆分配) +
        // MKFindIndicator 查表。前置门控直接 return, 文件夹图标每帧零开销。
        if (!MKHideNames()) return;
        id fIcon = [self icon];
        NSString *fBid = fIcon ? [NSString stringWithFormat:@"__folder__%p", fIcon] : nil;
        if (fBid.length) {
            // v2.0.4: sHiddenBids 权威（见上方注释）。只要 fBid 仍在集合即强制藏名，
            // 不再依赖指示器对象当场在场——对齐 App 分支 2782 的不变量。
            BOOL mustHide = (MKFindIndicator(fBid) != nil) || (sHiddenBids && [sHiddenBids containsObject:fBid]);
            if (mustHide && MKHideNames()) {
                UIView *label = MKGetCachedLabel((SBIconView *)self);
                if (label && label.superview) {
                    label.hidden = YES;
                    label.alpha = 0.0f;
                    label.layer.opacity = 0.0f;
                    label.opaque = NO;
                    MKAssocLabelBid(label, fBid); // 种回关联键，使源级 setHidden: hook 稳定命中
                }
            }
        }
        return;  // folder 指示器几何由 MKUpdate / MKRepositionIndicator 负责，layout 只管藏名
    }
    if (!bid) return;

    // v1.6.70: 文件夹内图标不再强制"显示名称并 return"——运行中 App 走下方
    // running 分支（隐藏名称、显示指示器在文件夹 overlay）；非运行中 App 落到 !running 分支恢复名称。
    // v2.0.66.78 (A5): 原此处的空 if(MKIsIconInFolder(self)) {} 块已删除(诊断残留, 无副作用)。
    // ⚠️ MKIsIconInFolder 函数本身【不可删】—— 仍在其他多处参与真实分支判断(文件夹内/外区分)。

    BOOL running = MKIsAppRunning(bid);
    BOOL isForeground = MKIsForeground(bid);
    UIView *indicator = MKFindIndicator(bid);

    // v1.6.84: 主动式堵窗——根治"label 与圆点重叠"残留 race。
    // 根因：%orig(L2393) 内部 SpringBoard 会把 label 复显(alpha=1,hidden=NO)，
    // 而此前所有藏 label 都位于分支内（sScrolling L2413 / 非滚动稳态 L2479 / SKIP L1596 /
    // 完整路径 L1625），分支与分支之间存在空档——那一帧 label 与圆点同显即用户偶见重叠。
    // 修法：在 %orig 之后、任何分支/return 之前，无条件地凡本 bid 有指示器(圆点)即
    // 同步强制藏名。空档被压到同一函数内 = 0。开销可忽略：MKFindIndicator 是 MapTable
    // O(1)、MKGetCachedLabel 已缓存；无指示器图标返回 nil 即 no-op。
    // v1.6.96: 藏名不变量升级为以 sHiddenBids 为权威——
    // 只要本 label 关联的 bid 仍在 sHiddenBids（= App 仍在后台运行、名字必须隐藏），
    // 无论 MKFindIndicator 此刻能否找到指示器（关文件夹瞬间指示器随文件夹 overlay 脱离），
    // 都强制藏名，杜绝缩回动画里名称闪现。
    UIView *label = MKGetCachedLabel(self);
    // v2.0.1: 不变量判据改用本图标自身 bid（= `bid`，MKGetCachedBid(self) 所得），
    // 不再依赖 MKLabelToBid(label) 的层级查找。关文件夹缩回动画中 label 被临时重父/
    // 新建，层级查找失效 → 旧逻辑漏藏 → 内部 App 名称闪现残留。icon bid 可靠、
    // 与层级无关；只要本 bid 仍在 sHiddenBids（App 后台运行、名字须隐藏）即强制藏名。
    // 同时把 bid 种回 label 直接关联键，使源头级 setHidden: hook 稳定命中。
    BOOL mustHide = (indicator != nil) || (bid.length && sHiddenBids && [sHiddenBids containsObject:bid]);
    if (mustHide && MKHideNames()) {   // v2.0.12: 撤销 v2.0.9 关合窗口内文件夹内 icon 让步原生(无条件强制藏名), 根治 sub-16ms settle 单帧闪现(第④点残留)。详见 MKSetHiddenHook 同款注释。
        MKDetachBetaOnce((UIView *)self); // v2.0.30: beta App 每帧兜底脱离（仅当小黄点仍在 label 内才动，脱离后跳过）
        // v2.0.8: 主路径仍藏缓存 label；额外 BFS 当前子树，藏任何 label-like 子视图——
        // 缩回动画中 SpringBoard 给内层 App 新建/重父的 label 是【新对象】，MKGetCachedLabel
        // 取不到、MKLabelToBid 也解不出，仅靠缓存 label 会漏藏→名称闪现。每帧 layout
        // 兜底，与 0.016s guard 形成双保险（仅对确有指示器的图标执行，开销可忽略）。
        if (label && label.superview) {
            label.hidden = YES;
            label.alpha = 0.0f;
            label.layer.opacity = 0.0f;
            label.opaque = NO;
            if (bid.length) MKAssocLabelBid(label, bid);
        }
        // v2.0.49: keepBetaDot 提到循环外（每帧省一次 sharedConfig 取单例）；MKBetaClass 已改零分配版。
        BOOL mkKeepBeta = [MKConfig sharedConfig].keepBetaDot;
        NSMutableArray *mkSub = [NSMutableArray arrayWithArray:(NSArray *)[(UIView *)self subviews]];
        while (mkSub.count > 0) {
            UIView *mkS = [mkSub lastObject]; [mkSub removeLastObject];
            // v2.0.22: 类名判定统一用 class_getName()+strstr（零分配），见 MKIsFolderIcon 同款。
            BOOL mkIsL = [mkS isKindOfClass:[UILabel class]] ||
                (strstr(class_getName([mkS class]), "Label") != NULL);
            if (mkIsL) {
                if (mkKeepBeta && MKBetaClass(mkS)) {
                    // v2.0.51: beta 点(Label 类)若仍嵌套在被藏 name-label 内（非 iconView 直接子视图）
                    // → 脱离到 iconView，而非仅 force-show（隐藏父遮挡子，force-show 无效 → 旧「滑屏才出来」根因）。
                    UIView *mkSp = mkS.superview;
                    if (mkSp && mkSp != (UIView *)self) {
                        // v2.0.59: 嵌套在被藏 name-label 内 → 脱离到 iconView（force-show 无效，隐藏父遮挡子）。
                        MKEnsureBetaOnIconView((UIView *)self, mkS);
                    } else if (mkS.hidden || mkS.alpha <= 0.0f) {
                        mkS.hidden = NO; mkS.alpha = 1.0f; mkS.layer.opacity = 1.0f; mkS.opaque = NO;
                        MKEnsureBetaVertAlign((UIView *)self, mkS); // v2.0.63: 复显后竖直对齐文本中心(灭偏上)
                        
                    } else {
                        // v2.0.63: 已在 iconView 上且可见 → 每帧对齐，防 iOS 重布局把 β点钉回 label 顶沿(偏上复现)
                        MKEnsureBetaVertAlign((UIView *)self, mkS);
                    }
                } else if (!mkS.hidden && mkS.alpha > 0.0f) {
                    mkS.hidden = YES; mkS.alpha = 0.0f; mkS.layer.opacity = 0.0f; mkS.opaque = NO;
                    if (bid.length) MKAssocLabelBid(mkS, bid);
                }
            } else if (MKBetaHideClass(mkS)) {
                // v2.0.66.3: 非 Label 子视图的 beta 点(如 SBIconBetaAccessoryView)。
                // 开关 ON → 保住(原有逻辑); 开关 OFF → 藏掉(修「关了还有 beta 黄点」)。
                if (mkKeepBeta) {
                    // v2.0.50: 非 Label 子视图（TestFlight 小黄点 SBIconBetaAccessoryView 等）。
                    // 若它仍挂在（被藏的）label 内（父 hidden）→ 仅 force-show 无效（隐藏父遮挡子），
                    // 必须脱离到 iconView；否则任意时刻可见。MKEnsureBetaOnIconView 处理坐标+脱离+保住。
                    UIView *mkSp = mkS.superview;
                    if (mkSp && mkSp.hidden) {
                        // v2.0.59: 父 hidden → 脱离到 iconView（force-show 无效，隐藏父遮挡子）。
                        MKEnsureBetaOnIconView((UIView *)self, mkS);
                    } else if (mkS.hidden || mkS.alpha <= 0.0f) {
                        mkS.hidden = NO; mkS.alpha = 1.0f; mkS.layer.opacity = 1.0f; mkS.opaque = NO;
                        MKEnsureBetaVertAlign((UIView *)self, mkS); // v2.0.63: 复显后竖直对齐文本中心(灭偏上)
                        
                    } else {
                        // v2.0.63: 已在 iconView 上且可见 → 每帧对齐，防 iOS 重布局把 β点钉回 label 顶沿(偏上复现)
                        MKEnsureBetaVertAlign((UIView *)self, mkS);
                    }
                } else if (!mkS.hidden && mkS.alpha > 0.0f) {
                    // v2.0.66.3: 关「保留小黄点」→ 直接藏掉 non-Label 类 beta 点(幂等, 无布局回环)。
                    mkS.hidden = YES; mkS.alpha = 0.0f; mkS.layer.opacity = 0.0f; mkS.opaque = NO;
                    
                }
            }
            [mkSub addObjectsFromArray:mkS.subviews];
        }
    }

    // v1.6.67: 滚动期间不重定位/创建指示器（避免 churn），但必须保持 label 状态同步。
    // 若 App 后台运行且已有指示器，系统可能在滚动中恢复 label，导致"指示器与名称重叠"。
    // v1.6.82: 通用不变量——只要本 bid 当前有指示器（圆点），名字必须隐藏，
    // 否则滚动/转场布局把 label 复显会与圆点重叠。注意 folder 容器图标的 bid 是
    // __folder__%p（非 App），MKIsAppRunning 恒为 NO，旧条件 running&&!fg 会漏藏它 → 改判 indicator。
    // v2.0.66.85: 门控位置修正 —— 原写作 `if (sScrolling && MKHideNames())`, 角标模式下整个
    //   条件为假 → 滚动期间不再早退, 反而每帧走到下方重定位/重父路径, 引入 v1.6.67 明确
    //   要避免的滚动 churn。指示器挂在滚动容器自己的 overlay 上、随滚动天然同步, 滚动中
    //   本就无需重定位。故把「滚动早退」与「藏名」拆开: 早退无条件, 藏名仍受门控。
    if (sScrolling) {
        if (indicator && MKHideNames()) {
            UIView *label = MKGetCachedLabel(self);
            if (label && label.superview) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
            }
        }
        return;
    }

    // v1.6.73: 文件夹打开期间，主屏/Dock 图标实例不管理指示器
    // （与 MKUpdate 同款守卫）。否则主屏实例把指示器重父回主屏 overlay
    // → 被文件夹盖住，造成"重开空位置 / 有些 App 没反应"。
    if (sFolderOpen && !MKIsIconInFolder((UIView *)self)) {
        
        return;
    }

        if (!indicator) {
            // 无 overlay 指示器 → 仅当本图标是运行中后台 App 时才需要创建
            if (!running || isForeground) return;

            // v1.6.70: 后台运行中、指示器待建(pending)或正在渐隐(fading)期间，
            // 立即把名称强制隐藏——否则回桌面转场动画会把 label 复显(系统图标入场
            // 把 alpha 拉回 1)，与 300ms 后建出的指示器同显一瞬 = 名称与指示器重叠。
            // 原先在 isFading 时直接 return 不藏名，正是重叠窗口的成因。
            // v2.0.66.85: 同 sScrolling —— 原写作 `&& MKHideNames()`, 角标模式下条件整体
            //   为假 → 不再早退, 每帧都往下走 MKUpdate(self)。而 pending 表示"指示器创建
            //   已排期(300ms 后)", fading 表示"名字正在渐隐中", 两者都应等排期自然落地,
            //   此处提前 MKUpdate 会与排期竞争重复创建。故早退无条件, 藏名仍受门控。
            // v2.0.66.87 (B1): 角标模式已不再排 300ms/800ms → 两个集合是该模式的
            //   【恒空不变量】, 早退永不该命中。但切模式那一刻可能有 ≤800ms 的残留 bid
            //   (MKMigrateLocationMode 已清一次, 这里再兜一道防竞态: 迁移与排期回调
            //    的执行顺序无保证)。若残留而这里仍无条件早退 → 该图标 layoutSubviews
            //   被永久跳过、指示器建不出来。故角标模式跳过早退。
            if ((MKIsPending(bid) || MKIsFadingLabel(bid)) && MKHideNames()) {
                UIView *label = MKGetCachedLabel(self);
                if (label && label.superview) {
                    label.hidden = YES;
                    label.alpha = 0.0f;
                    label.layer.opacity = 0.0f;
                    label.opaque = NO;
                }
                return;
            }
            MKUpdate(self);  // 创建（写入 overlay）
            return;
        }

    // v1.6.76: 文件夹【内部】App 各自显自己的圆点（用户要求「保留里面各自显」，主功能不变）。
    // 直接交给 MKUpdate 决断（创建 + 重父/重定位），不在这里做稳态重定位以免绕过 MKUpdate 的创建逻辑。
    if (MKIsIconInFolder((UIView *)self) && running && !isForeground) {
        MKUpdate(self);
        return;
    }

    // 有 overlay 指示器 → 校验是否还应存在
    if (!running || isForeground) {
        MKUpdate(self);  // 移除（App 退出/前台/文件夹）
        return;
    }

    // 仍在运行 → 重定位（overlay 坐标系，transform/滚动安全）+ 保持名字隐藏
    MKConfig *cfg = [MKConfig sharedConfig];
    if (!cfg || !cfg.enabled) { MKUpdate(self); return; }

    label = MKGetCachedLabel(self);   // v1.6.97: 复用 2683 已声明函数级 label，避免同作用域重定义（-Werror 编译失败）
    if (label && label.superview && MKHideNames()) {
        label.hidden = YES;
        label.alpha = 0.0f;
        label.layer.opacity = 0.0f;
        label.opaque = NO;
    }
    // v1.6.72: 重父到当前容器 overlay（修复"预运行 App 打开其文件夹后指示器不搬到文件夹 overlay"）。
    // 原先稳态路径只 MKRepositionIndicator（在当前容器坐标系内重定位），从不重父，
    // 完全依赖异步 MKUpdate 的 already-exists 分支去搬运；当"主屏在跑的 App 打开
    // 它所在的文件夹"时，指示器若仍挂在主屏 overlay 上，文件夹盖住主屏 → 不可见。
    // 这里若发现指示器不在当前 overlay 上，立即重父（与 MKUpdate already-exists 分支一致），
    // 不再靠异步调用，消除竞态。稳态（主屏在跑 App 没开文件夹）时
    // indicator.superview == overlay，下面 if 不触发，无额外开销/churn。
    UIView *container = MKContainerForIconView((UIView *)self);
    UIView *overlay = MKOverlayForContainer(container);
    if (overlay && indicator.superview != overlay) {
        [indicator removeFromSuperview];
        [overlay addSubview:indicator];
        [overlay bringSubviewToFront:indicator];
        
    }
    MKRepositionIndicator(bid, self, cfg);
}

%end

// ====================================================================
// v1.6.0: Hook — SBFolderView / SBFolderController
// 文件夹打开时，内部 SBIconView 需要刷新以显示运行指示器
// iOS 16 文件夹内的 App 图标可能在文件夹打开时才出现在视图层级
// 如果 SBFolderView/SBFolderController 类不存在，hook 自动跳过
// ====================================================================

// v2.0.8: 关闭保护提前到「关闭起始」武装 —— 原逻辑仅在 SBFolderView -didMoveToWindow(nil)
// （缩回动画【结束】、文件夹移出窗口后）才武装 sFolderClosing+guard；而「缩回【进行中】」内层
// App 新建/重父 label 的复显无人拦截（sFolderClosing 仍 NO、guard 未跑）→ 肉眼见「缩回末尾闪一下」(第③点)。
// v2.0.10: 快照截图【前】探针——定位「截图带名飞回」漏点。
// 关合缩回动画里 SpringBoard 常用 UIView snapshotViewAfterScreenUpdates:/resizableSnapshotViewFromRect:afterScreenUpdates:
// 给图标拍「此刻长啥样」的快照；若拍照那刻名字仍可见，则快照图里【带着名字】，
// 飞回主屏时显示的是这张 bitmap 而非活 label —— 完全绕过 setHidden/MKLabelDidMoveToWindowHook/让步门控所有拦截。
// 在截图【之前】扫 snapView 子树里「该藏却可见」的 label，有即打 SNAP-PRE-NAME（受 sProbeLog 门控）。
// 纯诊断、不改行为；release/debug 都不藏名，只报。若命中，v2.0.10+ 真修法：截图前先藏、截图后复原。
// ─── MKSafeSnapshotProbe (截图前 SNAP-PRE-NAME 探针) 已移除 (.71) ───

// v2.0.66.78 (A3): MKHideFolderThumbLabels 已删除 —— 唯一调用点(关窗守卫主循环的 isFolderIcon 分支)
// 判据把【视图类名】拿去比【模型类名】"SBFolderIcon"(视图侧真名 SBFolderIconView) → 条件恒假,
// 该函数自 .43 引入起从未执行过一次。留之则 -Werror unused-function 编不过, 故整体删除。
// 【类名判据铁律】判"是不是文件夹缩略图/文件夹图标"一律用已验证函数 MKViewInFolderThumb(isKindOfClass)
// 或 MKIsFolderIcon(先取 [iv icon] 再比模型名), 禁止手写 strcmp(视图类名, "SB*Icon")。

// 现抽成独立函数，由 SBFolderController -viewWillDisappear:（关闭起始，sFolderOpen 仍 YES）与
// didMoveToWindow(nil)（结束兜底）共调用，使 0.016s 基础强制藏（每帧对缓存 label 藏名）在缩回动画进行中即运行；不再全树 BFS（回归 2.0.5 方式）。
// v2.0.41: 关窗内 iOS 经任一 hook 试图复显运行 App label 时记一笔(无论 bid 能否解析),定位「末拍闪一下」走哪条 setter。
// v2.0.42: 缩略图探针 —— 关文件夹缩回时, 文件夹缩略图(SBFolderIcon)里的迷你 app 图标是【独立 view】(非 SBIconView),
// 主屏藏名 hook 与现有 walker 都没覆盖 -> 里面 app 名称/我们的指示器几率性「闪一下」。
// 此函数 dump 其子树每个后代: class / 可见性(hidden/alpha/layer.opacity) / 是否带我们的指示器(tag==kDotTag 或类名含 Indicator),
// 用以定位泄漏点(是活 SBIconView 还是合成图、名/指示器哪个在闪)。有界(最多 48 行)防刷屏。
// ─── MKProbeFolderThumb (缩略图 THUMB-CHILD 探针) 已移除 (.71) ───

// v2.0.43: 关文件夹过渡窗(sFolderClosing)内创建/重定位「文件夹缩略图运行点」时若直接 alpha=1 显,
// 会随缩略图缩回「啪」地瞬现(用户报的 ① 缩略图点闪)。改为淡入(alpha 0->1, 0.28s easeOut),
// 与 iOS 缩回动画柔和衔接；非关窗期(普通 home 显点/App 启停)保持原瞬显, 不影响任何其它场景。
static void MKFadeInFolderIndicatorIfClosing(UIView *ind) {
    if (!ind) return;
    if (!sFolderClosing) {
        // v2.0.66.1: 关窗结束/初次创建后确保缩略图指示器稳定可见，避免淡入被打断卡半透明造成「闪」。
        // 仅作用于文件夹缩略图指示器(本函数仅由文件夹 MKUpdate 路径调用)，不影响主屏/Dock/打开内部指示器。
        if (ind.alpha < 0.99f) { ind.hidden = NO; ind.alpha = 1.0f; [ind.layer removeAllAnimations]; }
        return;
    }
    if (ind.alpha > 0.99f) return;    // 已可见则不再重启动画
    ind.hidden = NO;
    ind.alpha = 0.0f;
    [UIView animateWithDuration:0.28
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ ind.alpha = 1.0f; }
                     completion:nil];
}


static void MKArmFolderCloseGuard(void) {
    sFolderClosing = YES;
        // v2.0.66.85: 角标模式 —— 本守卫的唯一工作(每 8ms 全窗口 BFS 强制藏名)整段被
        // MKHideNames() 门控, 在角标模式下 150 拍全是空转(1.2s 内 150 次全窗口视图树遍历)。
        // 但 sFolderClosing 标志本身仍被 overlay 逐帧不变量(关窗期隐藏文件夹内指示器)使用,
        // 故仅把「密集 BFS 定时器」换成一次性延时复位, 保留标志语义、去掉全部空转。
        if (!MKHideNames()) {
            if (sFolderCloseGuard) { dispatch_source_cancel(sFolderCloseGuard); sFolderCloseGuard = NULL; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ sFolderClosing = NO; });
            return;
        }
        if (sFolderCloseGuard) { dispatch_source_cancel(sFolderCloseGuard); sFolderCloseGuard = NULL; }
        sFolderCloseGuard = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (sFolderCloseGuard) {
            // v2.0.26: 回归 2.0.5 方式 —— 由 2.0.6+ 的 0.010s×150(≈1.5s) 撤回到 0.016s×50(≈0.8s)。
            // 撤掉 2.0.6 的「全树 BFS + 0.4s 末尾扫描 + 10ms 亚帧采样」过度增强；
            // 仅保留 2.0.3/4 基础逻辑：每帧对缓存 label 强制藏名(kMKLabelIconKey + sHiddenBids) + 0.8s 窗口。
            // 已知后果：第④点 settle 末尾 sub-16ms 单帧复显本就未被 2.0.5 根治，回归后「最后闪一下」可能重新可见。
            // v2.0.41: 由 0.016s×50(0.8s) 升级为 0.008s×150(≈1.2s) —— 更密+更长,
            // 既延长关窗藏名(本身更稳),又在每帧【重新藏名之前】先打 FLASH-PROBE(带毫秒)抓 sub-16ms 单帧复显。
            dispatch_source_set_timer(sFolderCloseGuard, DISPATCH_TIME_NOW, (int64_t)(0.008 * NSEC_PER_SEC), 0);
            __block int fcTicks = 0;
            dispatch_source_set_event_handler(sFolderCloseGuard, ^{
                fcTicks++;
                @try {
                    Class ivCls2 = MKSBIconViewClass();
                    NSArray *wins = [UIApplication sharedApplication].windows;
                    for (UIWindow *w in wins) {
                        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
                        while (stack.count > 0) {
                            UIView *cur = [stack lastObject]; [stack removeLastObject];
                            // v2.0.66.78 (A3): 原 isFolderIcon 分支已删除 ——
                            // 判据 strcmp(class_getName(object_getClass(cur)), "SBFolderIcon") 拿【视图类名】比
                            // 【模型类名】(SBFolderIcon 是 SBIcon 子类, 视图侧真名 SBFolderIconView) → 恒假,
                            // 自 .43 起从未执行过一次, MKHideFolderThumbLabels 同为死代码故一并删除。
                            // ⚠️ 不要"修活"它: .76 修活过(判据换 MKViewInFolderThumb), 实机证实解决不了文件夹闪
                            // (根因在 iOS 快照/compositor 层), 只会白增藏名面。
                            if (ivCls2 && [cur isKindOfClass:ivCls2]) {
                                SBIconView *iv = (SBIconView *)cur;
                                NSString *b = MKGetCachedBid(iv);
                                // v2.0.12: 彻底删除 v2.0.9 引入、v2.0.10 收窄的「末拍让步原生」。
                                // 问题: 普通文件夹关合缩回到最小(sub-16ms 单帧)时, UIKit 动画 commit 把本该隐藏的
                                // 文件夹内 App 名 label 又带出来一瞬 → 肉眼见「闪一下」; 而我们的 guard 每 0.016s 采样
                                // 抓不到这单帧(VISIBLE=0), 与 v2.0.6 注释 self-admitted "sub-16ms frame at settle" 一致。
                                // 证据(rd_log(63)): 关合窗口内 FOLDER-CLOSE-VISIBLE=0 / SNAP-PRE-NAME=0 / 无 Indicator 重建 → 根本不 strobe 互搏。
                                // 故关合窗口内对文件夹内 label 干脆【全程强藏】, 不留任何让步窗口。FloatyFolder 识别由 MKIsIconInFolder 单独负责, 不受影响。
                                // (无 yieldNative 变量, 避免 -Werror 未使用告警)
                                if (b.length && sHiddenBids && [sHiddenBids containsObject:b] && MKHideNames()) {
                                    UIView *lbl = MKGetCachedLabel(iv);
                                    // v2.0.5 探针 B：关文件夹窗口内，本该隐藏的 label 仍可见 = 泄漏。
                                    // 分两类报：① 缓存 label 可见（guard 抓到，至多晚 1 帧）→ via=guard；
                                    // ② 缓存拿不到、但 iv 子树里有别的可见 label（iOS 新建的）→ via=guard-new（常规每帧藏名漏掉的那种）。
                    // v2.0.26 回归 2.0.5 方式: 仅对【缓存 label】强制藏名(via=guard)，不扫全子树 BFS、不追加 0.4s 扫描。
                    // 第④点 settle 末尾 sub-16ms 单帧复显本就未被 2.0.5 根治，此处回到轻量基础逻辑，
                    // 靠 MKSetHiddenHook/MKSetAlphaHook 的每层 setHidden:/setAlpha: 兜底藏名(2.0.3/4)。
                    // v2.0.41: FLASH-PROBE —— 重新藏名【之前】先记此刻 label 是否可见(带精确毫秒),专抓 sub-16ms 单帧复显。节流 24 条。
                    
                                    if (lbl) { lbl.hidden = YES; lbl.alpha = 0.0f; lbl.layer.opacity = 0.0f; lbl.opaque = NO; MKAssocLabelBid(lbl, b); }
                                }
                            }
                            [stack addObjectsFromArray:cur.subviews];
                        }
                    }
                } @catch (NSException *e) {}
                if (fcTicks >= 150) {
                    dispatch_source_cancel(sFolderCloseGuard); sFolderCloseGuard = NULL;
                    sFolderClosing = NO;
                }
            });
            dispatch_resume(sFolderCloseGuard);
        } else { sFolderClosing = NO;  }}

// v2.0.8: 关闭保护提前到「关闭起始」武装（见 MKArmFolderCloseGuard 注释）。
// SBFolderController 是文件夹 VC，-viewWillDisappear: 在关闭动画【起始】(文件夹仍在窗口内、
// 内层 App 图标可见) 即触发；门控 sFolderOpen 仅当确在打开态才武装，避免切 App 等其它 disappear 误触发。
%hook SBFolderController
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (sFolderOpen) {
        
        MKArmFolderCloseGuard();
    }
}
%end
%hook SBFolderView

- (void)didMoveToWindow {
    %orig;
    UIView *me = (UIView *)self;
    if (me.window && sInitDone) {
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        // v1.6.26: 同一"打开事件"会触发多次 didMoveToWindow(window≠nil)
        // （打开动画过程中视图被反复加/移出窗口），用 0.4s 时间窗去重
        if (now - sLastFolderOpenTS < 0.4) {
            return; // 同一打开事件的重复触发，跳过
        }
        sLastFolderOpenTS = now;
        sFolderOpen = YES;
        sFolderClosing = NO;  // v2.0.3: 开文件夹即退出关动画窗口，避免上一轮关闭的 sFolderClosing 残留误触发诊断
        
        // v1.6.53: 立即刷新 —— 文件夹打开瞬间标签与指示器会重叠；
        // 0.4s 去重已防止同一打开事件多次触发，这里再排一次异步刷新即可。
        // 布局动画期间 layoutSubviews 会重新校正指示器位置，无需再额外 300ms 延迟。
        if (!sFolderRefreshScheduled) {
            sFolderRefreshScheduled = YES;
            __strong UIView *target = me;
            dispatch_async(dispatch_get_main_queue(), ^{
                sFolderRefreshScheduled = NO;
                MKClearPendingInView(target);
                MKRefreshSubviews(target);
            });
            // v1.6.75: 开文件夹动画期间图标可能稍晚入树，补一轮延迟刷新兜底
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                if (sInitDone) { MKRefreshSubviews(target); MKRefreshFolderIcons(); }
            });
        }
    } else if (!me.window) {
        sFolderOpen = NO;
        MKArmFolderCloseGuard();  // v2.0.8: 关闭保护提前到关闭起始武装（见函数注释）
          // v2.0.5 探针 A：确认关文件夹窗口是否真的被置位

        // v1.6.86: 动画关闭瞬间先把所有「有指示器」的图标 label 强制隐藏（含文件夹内层运行 App），
        // 防止系统把 label 复显一帧。与源头级 swizzle 形成双保险，杜绝缩回动画里名称闪现。
        MKSafe(^{
            // v2.0.66.85: 角标模式名字永不藏 → 下面两趟全窗口 BFS 的内层条件必然全部落空,
            // 整树遍历纯空转。外层直接早退（原先只在内层有 && MKHideNames() 判据）。
            if (!MKHideNames()) return;
            Class ivCls = MKSBIconViewClass();
            // v1.6.96: 关文件夹瞬间，文件夹内部 App 图标正随文件夹脱离窗口，
            // 已不在 UIApplication.windows 树里（下方扫描会漏）→ 内部 App 名称闪现。
            // 故先扫描 self(文件夹) 子树，在它脱离窗口前把内部运行 App 的 label 强制藏住。
            NSMutableArray *fstack = [NSMutableArray arrayWithObject:me];
            while (fstack.count > 0) {
                UIView *v = [fstack lastObject];
                [fstack removeLastObject];
                if ([v isKindOfClass:ivCls]) {
                    SBIconView *iv = (SBIconView *)v;
                    // v2.0.1: 改用图标自身 bid（可靠、与层级无关），不依赖 MKLabelToBid 的
                    // 层级查找（关文件夹动画中 label 被重父/新建 → 查找失效 → 漏藏 → 名称闪现）。
                    NSString *b = MKGetCachedBid(iv);
                    UIView *lbl = MKGetCachedLabel(iv);
                    if (lbl && b.length && sHiddenBids && [sHiddenBids containsObject:b] && MKHideNames()) {
                        lbl.hidden = YES; lbl.alpha = 0.0f; lbl.layer.opacity = 0.0f; lbl.opaque = NO;
                        MKAssocLabelBid(lbl, b);  // 种回直接关联键，使源头级 hook 稳定命中
                    }
                }
                [fstack addObjectsFromArray:v.subviews];
            }
            NSArray *wins = [UIApplication sharedApplication].windows;
            for (UIWindow *w in wins) {
                NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count > 0) {
                    UIView *v = [stack lastObject];
                    [stack removeLastObject];
                    if ([v isKindOfClass:ivCls]) {
                        SBIconView *iv = (SBIconView *)v;
                        // v2.0.1: 同子树段 —— 改用图标自身 bid + 种回关联键
                        NSString *b = MKGetCachedBid(iv);
                        UIView *lbl = MKGetCachedLabel(iv);
                        if (lbl && b.length && sHiddenBids && [sHiddenBids containsObject:b] && MKHideNames()) {
                            lbl.hidden = YES; lbl.alpha = 0.0f; lbl.layer.opacity = 0.0f; lbl.opaque = NO;
                            MKAssocLabelBid(lbl, b);
                        }
                    }
                    [stack addObjectsFromArray:v.subviews];
                }
            }
        });
        // v1.6.67: 关闭文件夹立即同步刷新主屏 —— 主屏图标重新可见后系统默认恢复 label 可见，
        // 若不立即重刷，运行 App 的名字会在文件夹缩回动画后才被我们藏回去，肉眼看到"闪一下"。
        // 先同步立即刷一次（动画期间就藏好），再异步补一次确保 layout 稳定后状态仍正确。
        NSArray *wins = [UIApplication sharedApplication].windows;
        for (UIWindow *w in wins) {
            UIView *home = MKFindDescendantView(w, @"SBIconScrollView");
            if (home) { MKRefreshSubviews(home); break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *wins2 = [UIApplication sharedApplication].windows;
            for (UIWindow *w in wins2) {
                UIView *home = MKFindDescendantView(w, @"SBIconScrollView");
                if (home) { MKRefreshSubviews(home); break; }
            }
            MKRefreshFolderIcons();
        });
    }
}

%end

// ====================================================================
// v2.0.66.78 (A2): 原 %hook UIView 的两个快照 hook(snapshotViewAfterScreenUpdates: /
// resizableSnapshotViewFromRect:afterScreenUpdates:withCapInsets:) 已整体删除。
// 探针(MKSafeSnapshotProbe)已在 .71 移除后, 两个方法体只剩 return %orig —— 纯透传。
// 而 %hook UIView 是【全系统 UIView 级】方法替换: SpringBoard 每一次转场/切换动画的
// 内部截图都要绕经我们的 trampoline, 零收益纯风险面。删之运行期零行为变化。
// 注: .77 已实机证实文件夹开合闪属 iOS 快照/compositor 层 crossfade, 在此处 hook 藏名
// (截图前藏、截图后复原)会把爆炸半径扩到全系统转场, 明确不做。

// ====================================================================
// v1.6.26: 移除冗余 hook
//   - SBFolderController -viewDidAppear: 与 SBFolderView -didMoveToWindow 重复（打开时两处都刷）
//   - SBIconListPageView -didMoveToWindow: 内部的页面图标已是 SBFolderView 子树的一部分，
//     顶层 300ms 合并刷新下降遍历即可覆盖，无需再单独 hook（反而造成双刷）
// 二者删除后，单次文件夹打开只触发一次合并刷新。
// ====================================================================

// ====================================================================
// v1.6.0: Hook — SBIconScrollView (桌面页面滚动)
// 当用户滚动到不同页面时，刷新新页面上的图标指示器
// v1.6.26: 合并滚动刷新 —— 120ms 内只排一次，避免快速滑动时反复全页刷新
// ====================================================================

%hook SBIconScrollView

- (void)scrollViewDidEndDecelerating:(id)scrollView {
    %orig;
    if (sInitDone) {
        
        if (!sScrollRefreshScheduled) {
            sScrollRefreshScheduled = YES;
            UIView *me = (UIView *)self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                sScrollRefreshScheduled = NO;
                MKRefreshSubviews(me);
            });
        }
    }
}

- (void)setContentOffset:(CGPoint)offset {
    %orig;
    MKMarkScrolling((UIView *)self);
}

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    %orig;
    MKMarkScrolling((UIView *)self);
}

- (void)scrollViewDidEndScrollingAnimation:(id)scrollView {
    %orig;
    if (sInitDone) {
        
        if (!sScrollRefreshScheduled) {
            sScrollRefreshScheduled = YES;
            UIView *me = (UIView *)self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                sScrollRefreshScheduled = NO;
                MKRefreshSubviews(me);
            });
        }
    }
}

%end

// ====================================================================
// Hook 1 — SBApplication._noteProcess:(id) didChangeToState:(id)
// 🔴 v1.4.5 BUG FIX: arg3 是 FBProcessState* 对象 (id)，不是 NSInteger！
// 之前把指针地址当整数 → state >= 2 永远 true → 所有 App 都加入 runningSet
// 正确方式：用 [arg3 isRunning] / [arg3 taskState] 获取真实状态
// 参考 iOS 16 运行时头文件：FBProcessState 有 running/taskState/foreground 属性
// ====================================================================

// v2.0.43-refactor(F1): 三个 SBApplication 状态 hook 共用的「set 更新 + 定向刷新」逻辑。
// 原三份一字不差重复（MKSetForeground + add/remove 集合 + MKOnStateChange），统一此处，逻辑等价。
// 语义：runningNow&&foreground → 加入集合；!runningNow → 移出集合；其余（alive 但后台）保留并刷新。
static void MKApplyAppState(NSString *bid, BOOL runningNow, BOOL foreground) {
    if (!bid.length) return;
    MKSetForeground(bid, foreground);
    if (runningNow && foreground)      MKAddToRunningSet(bid);
    else if (!runningNow)            MKRemoveFromRunningSet(bid);
    MKOnStateChange(bid, runningNow, foreground);
}

%hook SBApplication

- (void)_noteProcess:(id)process didChangeToState:(id)state {
    %orig;

    @try {
        NSString *bid = [self bundleIdentifier];
        if (!bid.length && process) {
            // 从 FBApplicationProcess 获取 bundleIdentifier
            bid = [process valueForKey:@"bundleIdentifier"];
            if (![bid isKindOfClass:[NSString class]]) bid = nil;
        }
        if (!bid.length) return;

        // 从 FBProcessState 对象获取运行状态（KVC 安全方式）
        BOOL isRunning = MKGetBoolFromState(state, @"isRunning");
        int taskState = MKGetIntFromState(state, @"taskState");
        BOOL isForeground = MKGetBoolFromState(state, @"isForeground");

        

        // FBProcessState.taskState: 2=Running, 3=Suspended → app alive
        // FBProcessState.taskState: 1=NotRunning/Dead → app exited
        // FBProcessState.isRunning: YES → app process exists
        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        // v1.6.31: 仅前台（用户打开/使用中）才进入 running set。
        // 纯后台被 iOS 拉起（日历同步等）foreground=0 → 不进集合 → 不显示指示器。
        // 注意：alive 但后台（用户退回后台的 App）走 else-if(!isRunningNow) 不命中 → 保留在集合（点保留）。
        // v2.0.43-refactor(F1): 三 hook 共用的「set 更新 + 刷新」逻辑抽进 MKApplyAppState，此处只取状态。
        MKApplyAppState(bid, isRunningNow, isForeground);
    } @catch (NSException *e) {
        RDLog(@"_noteProcess EXCEPTION: %@", e.reason);
    }
}

%end

// ====================================================================
// Hook 2 — SBApplication._setInternalProcessState:(id)
// iOS 16.3+ 新增：SBApplicationProcessState 包装类
// 内含 isRunning / taskState / foreground 属性（直接 ObjC 属性）
// 这是更干净的状态更新入口
// ====================================================================

%hook SBApplication

- (void)_setInternalProcessState:(id)internalState {
    %orig;

    @try {
        NSString *bid = [self bundleIdentifier];
        if (!bid.length) return;

        BOOL isRunning = MKGetBoolFromState(internalState, @"isRunning");
        int taskState = MKGetIntFromState(internalState, @"taskState");
        BOOL isForeground = MKGetBoolFromState(internalState, @"isForeground");

        

        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        // v1.6.31: 仅前台（用户打开/使用中）才进入 running set；纯后台被 iOS 拉起 foreground=0 不进集合。
        // v2.0.43-refactor(F1): 共用 MKApplyAppState（见 hook 1）。
        MKApplyAppState(bid, isRunningNow, isForeground);
    } @catch (NSException *e) {
        RDLog(@"_setInternalProcState EXCEPTION: %@", e.reason);
    }
}

%end

// ====================================================================
// Hook 3 — SBApplication._setActivationState:(int)
// 备用入口：App UI 激活状态变化
// 实际签名是 (int)，不是 (NSInteger)
// state 值：0=Inactive/Dead, 1=Background, 2=Foreground
// ====================================================================

%hook SBApplication

- (void)_setActivationState:(int)state {
    %orig;

    @try {
        NSString *bid = [self bundleIdentifier];
        if (!bid.length) return;

        

        BOOL isForeground = (state == 2);
        BOOL isRunningNow = (state >= 1);
        // v1.6.31: 仅前台（state==2）才进入 running set；纯后台（state==1）不进。
        // v2.0.43-refactor(F1): 共用 MKApplyAppState（见 hook 1）。
        MKApplyAppState(bid, isRunningNow, isForeground);
    } @catch (NSException *e) {
        RDLog(@"_setActivationState EXCEPTION: %@", e.reason);
    }
}

%end

// ====================================================================
// 构造函数（只做最轻量工作）
// ====================================================================

// 宽松系统版本守卫（v1.6.28 重加，仅挡老系统）：
//   只挡 iOS 15 及更低（majorVersion < 16），避免 iOS 15/14 上因 16.x 私有 API 崩溃。
//   上限开放（iOS 16.x / 16.6+ 均挂钩）。
//   注：SBApplicationProcessState 等私有类为 iOS 16.3+ 引入；16.0–16.2 上挂钩不崩，
//       但进程状态检测可能降级（hook 不触发），指示器可能不显示——属已知边界，不硬崩。
static BOOL MKIsSupportedOS(void) {
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    return (v.majorVersion >= 16);
}

// v1.6.76: 刷新所有文件夹图标（桌面/Dock）。
// 遍历主屏 SBIconScrollView 与 Dock（SBDockIconListView/SBDockView）子视图，
// 对文件夹图标类实例调 MKUpdate，使里面 App 运行态变化时文件夹图标的圆点及时刷新。
static NSInteger MKUpdateFolderIconsUnder(UIView *view, Class ivCls) {
    NSInteger count = 0;
    for (UIView *v in view.subviews) {
        if ([v isKindOfClass:ivCls] && MKIsFolderIcon((SBIconView *)v)) {
            MKUpdate((SBIconView *)v);
            count++;
        } else {
            count += MKUpdateFolderIconsUnder(v, ivCls);
        }
    }
    return count;
}
static void MKRefreshFolderIcons(void) {
    if (!sInitDone) return;
    MKSafe(^{
        // v1.6.81: force contained-bids recalculation on every explicit folder refresh,
        // so reordering / new running apps are reflected in folder icon indicator color.
        sFolderContentGen++;
        Class ivCls = MKSBIconViewClass();
        NSInteger total = 0;
        NSArray *wins = [UIApplication sharedApplication].windows;
        for (UIWindow *w in wins) {
            UIView *home = MKFindDescendantView(w, @"SBIconScrollView");
            if (home) total += MKUpdateFolderIconsUnder(home, ivCls);
            UIView *dock = MKFindDescendantView(w, @"SBDockIconListView");
            if (!dock) dock = MKFindDescendantView(w, @"SBDockView");
            if (dock) total += MKUpdateFolderIconsUnder(dock, ivCls);
        }
        
    });
}

%ctor {
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (!MKIsSupportedOS()) {
        NSLog(@"[RunningDotIndicator] ctor: iOS %ld.%ld unsupported (need iOS 16+), skip hooking.",
              (long)v.majorVersion, (long)v.minorVersion);
        RDLog(@"======== ctor: iOS < 16 (need 16+) unsupported, skip hooking ========");
        return; // 不调用 %init → 不挂钩 → 老系统优雅失效
    }

    %init;

    // v2.0.66.39: 启动日志彻底精简 —— 单行版本戳也收进 sDebugLog(诊断关时彻底零输出, 仅 @catch 异常仍可见); 多行改动清单同收进 sDebugLog。
    
    if (MKIsDisabled()) {
        RDLog(@"DISABLED at load; exiting ctor.");
        return;
    }

    // ─── Darwin 通知 ──────────
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKPrefsChangedCallback,
        CFSTR("com.mk.runningdotindicator.reload"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    // ─── 锁屏/解锁通知（v1.6.69）──────────
    // 锁屏时隐藏所有指示器；解锁动画结束（~600ms）后再复位，避免解锁动画透出指示器圆点。
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKLockStateCallback,
        CFSTR("com.apple.springboard.lockcomplete"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKLockStateCallback,
        CFSTR("com.apple.springboard.lockstate"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    // ─── 解锁可靠复位（v1.6.72）──────────
    // v1.6.70 把"解锁后复位"全押在 MKUpdate 时间闸门上，但该闸门依赖
    // "解锁后第一次 layoutSubviews 调用 MKUpdate"才翻闸；若解锁后静置不触发布局，
    // sLocked 卡 YES、overlay 永久 hidden → 指示器消失、得滑动才回来（用户一直反馈的现象）。
    // 改用 UIApplicationDidBecomeActiveNotification：解锁/回到前台时 SpringBoard 必然变 active、
    // 必定触发（不依赖任何布局），立即全局恢复所有指示器。该通知在解锁动画结束后才派发，
    // 故无"动画透出"风险。原 MKUpdate 时间闸门保留为后备（极少数此通知不派发时仍可由布局翻闸）。
    // 注意：普通"切 App 回前台"也会派发此通知，但彼时 sLocked 已为 NO（非锁屏态），
    // 下方 `if (!sLocked) return;` 直接跳过，不误触。
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note){
            @try {
                // v1.6.78: folder-open watchdog — reset stale sFolderOpen when becoming active
                if (sFolderOpen) {
                    BOOL hasFolder = NO;
                    NSArray *wins = [UIApplication sharedApplication].windows;
                    for (UIWindow *w in wins) {
                        if (MKFindDescendantView(w, @"SBFolderView")) { hasFolder = YES; break; }
                    }
                    if (!hasFolder) {
                        sFolderOpen = NO;
                        
                    }
                }
                if (!sLocked) return;   // 非锁屏态（如普通切 App 回前台），不动
                sLocked = NO;
                // v2.0.66.32: 解锁即时 un-hide(原生携带), 圆点随原生锁屏揭开与主屏一同揭示, 统一解锁动画。
                MKUnlockRestore();
                
            } @catch (NSException *e) {}
        }];

    // ─── 屏幕旋转/尺寸变更失效 dock frame 缓存（v2.0.66.39）──────────
    // sDockFrame 缓存 dock 容器 window frame, 仅供 MKLabelPhysicallyInDock 物理位置判定。
    // 旋转/窗口尺寸变化后 dock 位置改变, 旧缓存帧失效 → 既可能让 dock 串名在旋转后复发,
    // 也可能在过渡期误藏主屏标签。监听旋转通知把缓存清空, 下次物理判定惰性重算正确帧。
    // (MKRefreshAllIcons 也会周期刷新, 但旋转不一定立即触发它, 故显式失效更稳。)
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note){
            @try { sDockFrame = CGRectZero; } @catch (NSException *e) {}
        }];

    // ─── 生命周期通知（只保留 exit，iOS 16 上只有 exit 有效）──────────
    if (!sLifecycleObservers) sLifecycleObservers = [NSMutableArray array];
    NSArray *exitNoteNames = @[
        @"SBApplicationDidExitNotification",
        @"SBApplicationProcessDidExitNotification",
    ];
    for (NSString *nm in exitNoteNames) {
        id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:nm object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note){
            @try {
                NSString *bid = MKBidFromNote(note);
                 // v2.0.66.37: 收进 sDebugLog(事件追踪, 关掉即安静; 实际退出处理不依赖此日志)
                if (!bid) return;
                MKRemoveFromRunningSet(bid);
                if (sInitDone) MKOnStateChange(bid, NO, NO);
            } @catch (NSException *e) {
                RDLog(@"EXIT NOTE exception: %@", e.reason);
            }
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }

     // v2.0.66.37: 收进 sDebugLog

    // ─── 延迟 15 秒执行重量级初始化 ──────────
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        MKSafe(^{ MKDelayedInit(); });
    });

    // ─── 无定时器：_setInternalProcessState hook 已实时检测所有状态变化 ──
    // v1.4.4~v1.4.6 曾用8秒定时器做补充扫描，但 hook 已完全覆盖所有 App 启动/退出
}