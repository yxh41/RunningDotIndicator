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
#include <objc/runtime.h>

// ─── RDLog 前向声明（避免 C99 "use before declaration" 错误）──
static void RDLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);

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
static char kMKBetaOrigSuperKey;   // v2.0.16: 小黄点 accessory 脱离 label 挂到 iconView 前的原父视图（用于恢复层级）
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
static int    sFolderCloseDiag = 0;   // v2.0.3: 关文件夹诊断计数（每轮关闭最多记若干条，避免刷屏）
static int    sFolderCloseVisDiag = 0; // v2.0.5: 探针 B 计数（FOLDER-CLOSE-VISIBLE 有界前 8 条）
static BOOL  sLocked        = NO;  // v1.6.69: 设备是否处于锁屏态（解锁动画期间保持 YES，避免指示器透出）
static NSTimeInterval sLockAt = 0;   // v1.6.70: 最近一次锁屏时刻；用于 MKUpdate 时间闸门自动复位（不依赖解锁通知）
static dispatch_source_t sFolderCloseGuard = NULL;  // v2.0.1: 关文件夹缩回动画期间(~0.5s)持续堵窗定时器，防新建 label 漏藏
static BOOL  sDebugLog      = NO;  // v1.6.26: 调试日志开关；声明提前到此处，确保 MKLockStateCallback()(v1.6.69) 等在其定义前即可引用。
static char kMKIndicatorContainerKey;    // 指示器记录的所属容器（仅供调试/稳健性）
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
static NSMutableDictionary<NSString*, NSNumber*> *sLastMsgTime = nil; // v1.6.85: 各 App「最近活动/消息」时间戳，供文件夹图标指示器选代表 App
// 前向声明（定义见文件后部）
static NSString *MKLabelToBid(UIView *label);
static void MKInstallLabelHook(void);
static void MKTouchMsg(NSString *bid);

// v1.6.75: 锁屏后兜底「解锁复原」定时器句柄（不依赖 iOS 解锁通知/布局事件）
static dispatch_source_t sUnlockTimer = NULL;

// v1.6.64: 以下 helpers 管理「按 bid 索引、挂在稳定 overlay 层」的指示器。
static UIView *MKGetCachedLabel(SBIconView *iv); // 前向声明（定义于文件后部）
static void MKAssocLabelBid(UIView *label, NSString *bid); // 前向声明（定义于 v1.6.86 区域；MKGetCachedBid 回收分支需用到）
static UIView *MKIconViewForLabel(UIView *label);          // v2.0.7: label→所属 SBIconView 几何反解（关联键/层级失效时终极兜底）
static void MKLabelDidMoveToWindowHook(id self, SEL _cmd);  // v2.0.7: 创建点拦截（label 进入 window 即刻藏名）
static void MKArmFolderCloseGuard(void);  // v2.0.8: 关闭保护(缩回动画进行中即武装 guard)；SBFolderView/-didMoveToWindow 与 SBFolderController/-viewWillDisappear 共调用
static void MKSafeSnapshotProbe(UIView *snapView);  // v2.0.10: 快照截图【前】探针——扫子树里「该藏却可见」的 label，打 SNAP-PRE-NAME，定位「截图带名飞回」漏点
static UIView *MKFindBetaDotView(UIView *root);     // v2.0.16: 查找 SBIconView 子树里的 TestFlight 小黄点视图
// v2.0.16: TestFlight 小黄点（Beta 标记）正确定位与状态机
// iOS 16 的小黄点是 icon.labelAccessoryType=beta 驱动的「标签 accessory 子视图」
// （类如 SBIconLabelAccessoryView，其 className 不含 "Beta"），藏在名称 label 内 ——
// 旧 MKFindBetaDotView 按 "Beta" 匹配永远找不到 → 开关完全失效。
// 故优先在 label.subviews 找 class 含 "Accessory" 的视图；找不到再退回整树找 "Beta"（兼容老系统）。
typedef NS_ENUM(NSUInteger, MKBetaMode) {
    MKBetaHide = 0,          // 隐藏（开关开 + 运行中）
    MKBetaShowDetached = 1,  // 保持可见（脱离 label 挂到 iconView，开关关 + 运行中）
    MKBetaRestore = 2,        // 恢复（App 退出/前台化：挂回 label 并可见）
};
static UIView *MKFindBetaAccessory(UIView *iconView); // 找小黄点 accessory 视图
static void MKApplyBetaDot(UIView *iconView, MKBetaMode mode); // 按状态机应用
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
            NSString *cls = NSStringFromClass([anc class]);
            if ([cls hasPrefix:@"SBIconListView"] ||
                [cls hasPrefix:@"SBDock"] ||
                [cls isEqualToString:@"SBRootFolderView"] ||
                [cls isEqualToString:@"SBIconController"]) {
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
        if (sDebugLog) RDLog(@"FOLDER-FLOATY: iv=%@ cls=%@", iv, cls);
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
    NSString *cls = NSStringFromClass([icon class]);
    static NSMutableSet *sFolderIconLog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sFolderIconLog = [NSMutableSet new]; });
    if (sDebugLog && cls.length) {
        if (![sFolderIconLog containsObject:cls]) {
            [sFolderIconLog addObject:cls];
            RDLog(@"FOLDER-ICON-CLS: %@", cls);
        }
    }
    return [cls isEqualToString:@"SBFolderIcon"] || [cls isEqualToString:@"SBIconFolderIcon"];
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
        objc_setAssociatedObject(ind, &kMKIndicatorContainerKey, nil, OBJC_ASSOCIATION_ASSIGN);
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
    // v2.0.16: 清空前先把所有受影响的图标上的 TestFlight 小黄点恢复，避免总开关/禁用后仍残留隐藏。
    if (sBidToIconView) {
        NSArray *iconViews = [[sBidToIconView objectEnumerator] allObjects];
        for (id iv in iconViews) {
            if (iv) MKApplyBetaDot((UIView *)iv, MKBetaRestore);
        }
    }
    NSArray *all = [[sBidToIndicator objectEnumerator].allObjects copy];
    for (UIView *ind in all) { if (ind) [ind removeFromSuperview]; }
    [sBidToIndicator removeAllObjects];
    if (sHiddenBids) [sHiddenBids removeAllObjects]; // v1.6.85: 全清
    if (sHiddenLabelToBid) [sHiddenLabelToBid removeAllObjects]; // v2.0.7+GAP-FIX: 同步清空指针表
}
// v1.6.71: 改为隐藏/恢复所有 overlay（而非逐个 indicator）。
// 锁屏时 overlay.hidden=YES 即隐藏其下全部指示器；解锁时 overlay.hidden=NO 立即全局恢复，
// 不再依赖逐图标 MKUpdate 重新布局 → 根治"解锁后指示器长时间空白、需滑动才出现"。
static void MKSetAllIndicatorsHidden(BOOL hidden) {
    if (!sContainerToOverlay) return;
    NSArray *all = [sContainerToOverlay.objectEnumerator.allObjects copy];
    for (UIView *ov in all) { if (ov) ov.hidden = hidden; }
}
// v2.0.1: 解锁复原统一入口。收到任意解锁信号后，不立即显示，而是延迟 0.45s
// （解锁动画 ~0.5s 已基本结束）再把所有 overlay 解除隐藏，并从 alpha=0 淡入到 1，
// 使指示器随锁屏消散柔和浮现，而非硬跳。用 sUnlockToken 防重入/过期：
// 期间若重锁（sLocked=YES）或又来更新的解锁，旧 block 自动失效。
static NSInteger sUnlockToken = 0;
// 前向声明（翻停后刷新所有页面图标，定义在文件后部 2279 行）；必须在 MKUnlockRestore
// (323 行) 之前声明，因为 MKUnlockRestore 内调用了它，否则新版 clang -Werror 报
// implicit-function-declaration（v2.0.1 回归：前向声明原在 531 行、晚于调用点）。
static void MKRefreshAllIcons(void);
static void MKUnlockRestore(void) {
    if (!sContainerToOverlay) return;
    NSInteger myToken = ++sUnlockToken;
    if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (myToken != sUnlockToken) return;   // 已被更新的解锁覆盖
        if (sLocked) return;                   // 期间又锁屏了
        @try {
            NSArray *all = [sContainerToOverlay.objectEnumerator.allObjects copy];
            for (UIView *ov in all) { ov.hidden = NO; ov.alpha = 0.0f; }
            MKRefreshAllIcons();  // 重建/重定位（单个指示器自带 0.2s 淡入，叠加更柔和）
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseOut
                animations:^{ for (UIView *ov in all) ov.alpha = 1.0f; }
                completion:nil];
            if (sDebugLog) RDLog(@"UNLOCK(fade): restored all indicators with fade-in");
        } @catch (NSException *e) { RDLog(@"UNLOCK(fade) EXCEPTION: %@", e.reason); }
    });
}
// v1.6.67: 计算某 bid 的指示器在 overlay 坐标系中的 frame（transform/滚动偏移安全）。
// 使用传入的图标视图 iv，而不是去 sBidToIconView 注册表里取——注册表里存的是"最后一次
// 调用 MKUpdate 的图标实例"，在多页桌面中如果当前 layout 的是另一页的图标，会拿错位置
// 导致指示器飘到别的页面（"左右滑动后重叠/错位"的根因之一）。
// 无 live 视图（图标离屏/被回收）→ 返回 CGRectZero，调用方保留其最后位置不重算。
static CGRect MKIndicatorFrameInOverlay(SBIconView *iv, UIView *overlay, MKConfig *cfg) {
    if (!iv || !overlay || !cfg) return CGRectZero;
    CGFloat indW = (cfg.shape == MKShapeDot) ? cfg.dotSize : cfg.barWidth;
    CGFloat indH = (cfg.shape == MKShapeDot) ? cfg.dotSize : cfg.barHeight;
    UIView *label = MKGetCachedLabel(iv);
    CGRect r;
    if (label && label.superview) {
        r = [label.superview convertRect:label.frame toView:overlay];
    } else {
        r = [overlay convertRect:iv.bounds fromView:iv];
        r = CGRectMake(CGRectGetMidX(r) - 20.0f, CGRectGetMaxY(r) + 4.0f, 40.0f, 14.0f);
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
static NSString *MKFolderChosenBid(NSArray<NSString*> *bids, NSInteger mode, BOOL fixedColor); // 选代表 App
static void      MKRefreshFolderIcons(void);                              // 刷新所有文件夹图标
static NSInteger  MKUpdateFolderIconsUnder(UIView *view, Class ivCls);        // 递归找文件夹图标

// v1.6.75: 读取 App 角标数（消息数量近似）。
// v1.6.76: 文件夹【图标】（桌面/Dock 上、未打开）显示 1 个圆点。
// 里面 ≥1 个后台运行 App 时，圆点颜色按 folderIndicatorMode 取「代表 App」主色（auto 模式）；
// 固定色模式圆点用全局固定色、两种策略灰掉无意义。
// 形状/尺寸走全局 cfg（与里面 App 的圆点自动同步）。
// 入参 bids = 文件夹内后台运行 App 的 bid 数组（已按文件夹顺序）；
//   mode 0 = 数组序最前（≈视觉排序靠前），mode 1 = 角标最多；fixedColor 退化为 mode 0。
// 返回被选中的代表 bid；无运行 App 返回 nil。
// v1.6.96: 文件夹指示器「代表 App」只留两种选择（设置页 2 段控件）：
//   mode 0 = 文件夹内视觉位置最靠前的 App（≈用户看到的顺序第一个）；
//   mode 1 = 文件夹内来信息最新的 App（按最近消息时间戳）。
// 不再有「角标最多」与「优先最近消息」开关两个独立概念——二者合并为 mode 1。
// 固定色模式下退化回 mode 0（圆点用全局固定色，代表谁不影响颜色）。
static NSString *MKFolderChosenBid(NSArray<NSString*> *bids, NSInteger mode, BOOL fixedColor) {
    if (!bids || bids.count == 0) return nil;
    if (bids.count == 1) return bids.firstObject;
    if (fixedColor) mode = 0; // 固定色：代表谁不影响颜色，取位置靠前
    if (mode == 1) { // 来信息最新
        NSString *best = nil;
        double bestT = -1.0;
        for (NSString *b in bids) {
            double t = (sLastMsgTime && sLastMsgTime[b]) ? [sLastMsgTime[b] doubleValue] : 0.0;
            if (t > bestT) { bestT = t; best = b; }
        }
        if (best && bestT > 0.0) return best;
        return bids.firstObject; // 无任何时间戳：兜底位置靠前
    }
    return bids.firstObject; // 位置靠前 = 视觉序第一个
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
    if (sDebugLog) {
        NSInteger nApp = 0;
        for (id s in icons) if (appCls && [s isKindOfClass:appCls]) nApp++;
        RDLog(@"FOLDERCOLLECT cls=%@ icons=%ld appIcons=%ld", NSStringFromClass([folder class]), (long)(icons?icons.count:0), (long)nApp);
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
            if (sDebugLog && [b isKindOfClass:[NSString class]] && b.length && (run || out.count == 0)) {
                static int sFCILogs = 0;
                if (sFCILogs < 100) { sFCILogs++; RDLog(@"FOLDERCOLLECT-ITEM bid=%@ running=%d fg=%d", b, (int)run, (int)fg); }
            }
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
// v2.0.1: 解锁复原统一入口 —— 延迟 ~0.45s（等解锁动画结束）+ alpha 0→1 淡入，
// 替代原先三处（lockstate "0" / MKUpdate 闸门 / DidBecomeActive）的立即硬显示（指示器在
// 解锁动画进行中硬跳出、不和谐）。用 sUnlockToken 防重入/过期（期间重锁或又来更新的解锁即失效）。
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
            MKSetAllIndicatorsHidden(NO);  // v1.6.75: 复原所有 overlay（之前只重建不 unhide，主屏/Dock 指示器解锁后永久不显）
            MKRefreshAllIcons();
            if (sDebugLog) RDLog(@"UNLOCK(timer): restored all indicators");
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
                if (sDebugLog) RDLog(@"UNLOCK(lockstate): scheduled fade-in restore");
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
            if (sDebugLog) RDLog(@"LOCK: hid all indicators");
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
    }
    objc_setAssociatedObject(iv, &kMKIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // v1.6.0: 过滤文件夹图标 — 精确匹配，不误杀文件夹内App
    // 旧版 containsString:@"Folder" 可能误杀类名含 Folder 的App图标
    // 只过滤 SBFolderIcon（文件夹本身的复合图标），不过滤文件夹内的App图标
    // v1.6.31: 常量类静态化 —— 避免每个图标每次 layoutSubviews 都跑
    // NSStringFromClass + 2×NSClassFromString + 2×字符串比较（纯边角料、行为不变）
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
static UIView *MKGetCachedLabel(SBIconView *iv) {
    UIView *label = objc_getAssociatedObject(iv, &kMKLabelKey);
    if (label && label.superview) return label;  // 仍然有效
    // 缓存失效 → 重新查找
    label = MKFindLabelView(iv);
    if (label) {
        objc_setAssociatedObject(iv, &kMKLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // v2.0.3: 同时给 label 挂「指向所属 SBIconView 的直接指针」（层级无关）。
        // 关文件夹缩回动画期间 iOS 会把内部 App 的 label 临时重父到动画层，
        // 使 MKLabelToBid 的 superview 层级查找全部失效 → 漏藏 → 名称闪现。
        // 直接指针随 label 对象自身走，重父/重建时仍可被 MKLabelToBid 取出，绕过层级解出 bid。
        objc_setAssociatedObject(label, &kMKLabelIconKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return label;
}

// v2.0.16: 在 SBIconView 子树里查找 TestFlight 小黄点（Beta dot）视图。
// iOS 历史类名包含 SBIconBetaLabelAccessoryView / SBIconBetaBadgeView / SBIconBetaDotView 等，
// 统一按 className 包含 "Beta" 匹配（只匹配真正的 Beta 标记，不碰红色数字角标 SBIconBadgeView）。
static UIView *MKFindBetaDotView(UIView *root) {
    if (!root) return nil;
    for (UIView *v in root.subviews) {
        NSString *cls = v ? NSStringFromClass([v class]) : @"";
        if (cls.length && [cls rangeOfString:@"Beta" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return v;
        }
        UIView *found = MKFindBetaDotView(v);
        if (found) return found;
    }
    return nil;
}

// v2.0.16: 正确定位 iOS 16 的 TestFlight 小黄点（Beta 标记 accessory）。
// 旧 MKFindBetaDotView 按 className 含 "Beta" 匹配，但 iOS 16 里该标记是
// icon.labelAccessoryType=beta 驱动的「标签 accessory 子视图」（类如 SBIconLabelAccessoryView），
// 其 className 不含 "Beta" → 永远找不到 → 开关完全失效。
// 故优先在 label.subviews 找 class 含 "Accessory" 的视图；找不到再退回整树找 "Beta"（兼容老系统）。
static UIView *MKFindBetaAccessory(UIView *iconView) {
    if (!iconView) return nil;
    // 优先：名称 label 的子视图里找 accessory
    UIView *label = MKGetCachedLabel((SBIconView *)iconView);
    if (label) {
        for (UIView *v in label.subviews) {
            NSString *cls = v ? NSStringFromClass([v class]) : @"";
            if (cls.length && [cls rangeOfString:@"Accessory" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return v;
            }
        }
        // 诊断：debug 开时把 label 的 subviews 类名 dump 出来，
        // 万一 iOS 16 的 accessory 类名不含 "Accessory"（我的启发式漏了），下份日志即可定位真类名。
        if (sDebugLog) {
            NSMutableString *subs = [NSMutableString string];
            for (UIView *v in label.subviews) [subs appendFormat:@"%@ ", NSStringFromClass([v class])];
            RDLog(@"BETA-SCAN: label=%@ subs=[%@]", NSStringFromClass([label class]), subs);
        }
    } else if (sDebugLog) {
        RDLog(@"BETA-SCAN: no cached label bid=%@", MKGetCachedBid((SBIconView *)iconView));
    }
    // 退回：整棵子树找 class 含 "Beta"（老系统 SBIconBetaLabelAccessoryView 等）
    return MKFindBetaDotView(iconView);
}

// v2.0.16: 按状态机控制小黄点（见 MKBetaMode）。
// 关键：小黄点是名称 label 的子视图，藏名(label.hidden=YES)会连带藏它。
// 故开关【关】+ 运行中 时，把它从 label 脱离、挂到 SBIconView 上，
// 就能在「藏名」状态下仍保持小黄点可见；开关【开】时直接隐藏；
// App 退出/前台化 时挂回原 label 并恢复可见。
static void MKApplyBetaDot(UIView *iconView, MKBetaMode mode) {
    if (!iconView) return;
    UIView *acc = MKFindBetaAccessory(iconView);
    if (!acc) {
        if (sDebugLog) RDLog(@"BETA-APPLY: notfound mode=%lu bid=%@", (unsigned long)mode, MKGetCachedBid((SBIconView *)iconView));
        return;
    }
    UIView *label = MKGetCachedLabel((SBIconView *)iconView);
    if (mode == MKBetaHide) {
        // 隐藏：若此前被脱离过，先挂回原 label 再藏，保持层级干净
        UIView *orig = objc_getAssociatedObject(acc, &kMKBetaOrigSuperKey);
        if (orig && acc.superview != orig) {
            CGRect f = [acc.superview convertRect:acc.frame toView:orig];
            [acc removeFromSuperview];
            [orig addSubview:acc];
            acc.frame = f;
        }
        objc_setAssociatedObject(acc, &kMKBetaOrigSuperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        acc.hidden = YES;
        if (sDebugLog) RDLog(@"BETA-APPLY: HIDE bid=%@ cls=%@", MKGetCachedBid((SBIconView *)iconView), NSStringFromClass([acc class]));
    } else if (mode == MKBetaShowDetached) {
        // 保持可见：若仍在 label 内（label 会被我们藏名 → 连带藏 dot），脱离到 iconView
        if (label && acc.superview == label) {
            CGRect f = [acc.superview convertRect:acc.frame toView:iconView];
            objc_setAssociatedObject(acc, &kMKBetaOrigSuperKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [acc removeFromSuperview];
            [iconView addSubview:acc];
            acc.frame = f;
        }
        acc.hidden = NO;
        if (sDebugLog) RDLog(@"BETA-APPLY: SHOW-DETACHED bid=%@ cls=%@", MKGetCachedBid((SBIconView *)iconView), NSStringFromClass([acc class]));
    } else { // MKBetaRestore
        UIView *orig = objc_getAssociatedObject(acc, &kMKBetaOrigSuperKey);
        if (orig && acc.superview != orig) {
            CGRect f = [acc.superview convertRect:acc.frame toView:orig];
            [acc removeFromSuperview];
            [orig addSubview:acc];
            acc.frame = f;
        }
        objc_setAssociatedObject(acc, &kMKBetaOrigSuperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        acc.hidden = NO;
        if (sDebugLog) RDLog(@"BETA-APPLY: RESTORE bid=%@ cls=%@", MKGetCachedBid((SBIconView *)iconView), NSStringFromClass([acc class]));
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
static int   sCallCount    = 0;
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
static BOOL  sPathCacheReady = NO;
static NSMutableDictionary<NSString*, NSNumber*> *sRunLogCounts = nil; // 日志限流
static NSMutableSet<NSString*> *sForegroundBIDs = nil; // 当前前台 App 不显示其桌面指示器
static NSMutableSet<NSString*> *sPendingBIDs    = nil; // v1.5.6+: 等待300ms后才显示指示器的App（标签已隐藏，指示器待创建）
static NSMutableSet<NSString*> *sAnimateIndicatorBIDs = nil; // v1.5.7: 指示器需要渐显动画的 App（状态切换时创建）
static NSMutableSet<NSString*> *sFadingLabelBIDs    = nil; // v1.5.8: 标签正在渐隐中的 App（250ms 动画期间不干扰）
static NSMutableDictionary<NSString*, UIColor*> *sIconColorCache = nil; // v1.5.7: bundleID → 图标主色调缓存
static NSMutableSet<NSString*> *sIconColorMissLogged = nil; // v1.6.12: 取色失败诊断（每 bid 只记一次）

// ─── v1.6.26: 调试日志开关 + 刷新合并 ───
// 默认 NO（生产安静）。存在 /var/mobile/Documents/rd_debug 文件即开启详细日志。
// 注意：sDebugLog 全局已在文件顶部（sLocked 旁边）声明，此处仅赋值。
static void MKUpdateDebugFlag(void) {
    MKConfig *cfg = [MKConfig sharedConfig];
    sDebugLog = cfg ? [cfg debugLog] : NO;
}
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

// 尝试从 SBIconView/SBIcon 获取图标 UIImage
static UIImage *MKGetIconImage(SBIconView *iv) {
    @try {
        id icon = [iv icon];

        // 策略 1: SBIcon 的 scale 方法（NSInvocation 正确传 CGFloat，避免 ABI 不匹配导致取色全灰）
        if (icon) {
            NSArray *iconImageSelectors = @[
                @"applicationIconImageForScreenScale:",
                @"iconImageForScreenScale:",
            ];
            CGFloat scale = [UIScreen mainScreen].scale;
            for (NSString *selName in iconImageSelectors) {
                SEL sel = NSSelectorFromString(selName);
                if ([icon respondsToSelector:sel]) {
                    NSMethodSignature *sig = [icon methodSignatureForSelector:sel];
                    // 3 参数 (self,_cmd,scale:CGFloat) → NSInvocation
                    if (sig && sig.numberOfArguments == 3) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:icon];
                        [inv setSelector:sel];
                        [inv setArgument:&scale atIndex:2];
                        [inv invoke];
                        __unsafe_unretained id result = nil;
                        [inv getReturnValue:&result];
                        if ([result isKindOfClass:[UIImage class]]) return result;
                    }
                    // 2 参数 (self,_cmd) 无 scale → 直接 performSelector
                    else if (sig && sig.numberOfArguments == 2) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        id result = [icon performSelector:sel];
#pragma clang diagnostic pop
                        if ([result isKindOfClass:[UIImage class]]) return result;
                    }
                }
            }
            // 无参数版本：applicationIconImage / iconImage 等
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

// 获取指定 bundleID 的图标主色调（带缓存）
static UIColor *MKCachedIconColorForBundleID(NSString *bid) {
    if (!sIconColorCache) sIconColorCache = [NSMutableDictionary dictionary];
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

    if (result) {
        sIconColorCache[bid] = result;
        RDLog(@"IconColor: %@ → %@", bid, result);
        return result;
    }
    // v1.6.11: 取不到图标 → 返回固定色用于即时显示，但【不缓存】
    // 这样下次 layout/刷新会重试取色；一旦图标可取到就自动修正（见 MKUpdate 重绘逻辑）
    // 否则首次取色失败会被永久缓存成绿兜底 → 表现为"全是绿色"
    // v1.6.12: 加诊断 —— 取色失败只记录一次，便于下次日志定位根因
    if (!sIconColorMissLogged) sIconColorMissLogged = [NSMutableSet set];
    if (![sIconColorMissLogged containsObject:bid]) {
        [sIconColorMissLogged addObject:bid];
        if (sDebugLog) RDLog(@"IconColor MISS: %@ (SBIconView 存在但 MKGetIconImage 未取到图标)", bid);
        // v1.6.26: 图标未就绪导致取色失败 → 下一 runloop 重试一次，错色不闪
        // sIconColorMissLogged 已保证每个 bid 只触发一次，不会无限重试
        dispatch_async(dispatch_get_main_queue(), ^{
            if (MKIsAppRunning(bid) && !MKIsForeground(bid)) {
                MKRefreshIconForBundleID(bid);
            }
        });
    }
    return [[MKConfig sharedConfig] color];
}

// ─── 文件日志 ────────────────────────────────────────────────
static void RDLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[RD] %@", msg);
    NSString *path = @"/var/mobile/Documents/rd_log.txt";
    @try {
        NSString *ts = [NSDate date].description;
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", ts, msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *e) {}
}

// ─── 限流日志（同一 bundleID 最多记录 5 次 RUNNING）──────────────
static void RDLogRunning(NSString *bid) {
    if (!sDebugLog) return; // v1.6.26: 默认安静，仅调试模式记录 RUNNING 噪声
    if (!sRunLogCounts) sRunLogCounts = [NSMutableDictionary dictionary];
    NSNumber *countObj = sRunLogCounts[bid];
    NSInteger count = countObj ? [countObj integerValue] : 0;
    if (count < 5) {
        sRunLogCounts[bid] = @(count + 1);
        RDLog(@"RUNNING: %@ (call=%d, log=%ld)", bid, sCallCount, (long)(count+1));
    }
}

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
        static int sBlacklistLogs = 0;
        if (sBlacklistLogs < 10) {
            sBlacklistLogs++;
            RDLog(@"BLACKLIST: skipped %@", bid);
        }
        return;
    }
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    BOOL wasNew = ![sRunningSet containsObject:bid];
    [sRunningSet addObject:bid];
    if (wasNew) RDLog(@"+ RUNNING SET: %@", bid);
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    BOOL wasIn = sRunningSet && [sRunningSet containsObject:bid];
    [sRunningSet removeObject:bid];
    if (wasIn) RDLog(@"- RUNNING SET: %@", bid);
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
    RDLog(@"PathCache: starting NSFileManager scan...");
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

    sPathCacheReady = YES;
    RDLog(@"PathCache: cached %d apps", added);
}

// ─── SBApplicationController.runningApplications 初始同步 ────
static void MKSyncFromSBAppCtrl() {
    @try {
        id appCtrl = [SBApplicationController sharedInstance];
        if (!appCtrl) {
            RDLog(@"SBAppCtrl: sharedInstance is nil");
            return;
        }

        SEL runningSel = NSSelectorFromString(@"runningApplications");
        if (![appCtrl respondsToSelector:runningSel]) {
            RDLog(@"SBAppCtrl: does not respond to runningApplications");
            return;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *runningApps = [appCtrl performSelector:runningSel];
#pragma clang diagnostic pop

        if (!runningApps) {
            RDLog(@"SBAppCtrl: runningApplications returned nil");
            return;
        }

        int count = 0;
        for (id app in runningApps) {
            if (![app isKindOfClass:NSClassFromString(@"SBApplication")]) continue;
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
        RDLog(@"SBAppCtrl: synced %d running apps (total=%lu)", count, (unsigned long)runningApps.count);

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
        static int sNoLabelLogs = 0;
        if (!skipDump && sNoLabelLogs < 20) {
            sNoLabelLogs++;
            NSMutableString *dump = [NSMutableString stringWithFormat:@"NO LABEL - %@ direct:[", NSStringFromClass([iconView class])];
            for (UIView *sv in iconView.subviews) {
                [dump appendFormat:@" %@", NSStringFromClass([sv class])];
            }
            [dump appendString:@"]"];
            UIView *parent = iconView.superview;
            NSInteger lvl = 0;
            while (parent && lvl < 8) {
                [dump appendFormat:@" | L%ld(%@, %lu kids):[", (long)lvl, NSStringFromClass([parent class]), (unsigned long)parent.subviews.count];
                for (UIView *sv in parent.subviews) {
                    [dump appendFormat:@" %@(y=%.0f,h=%.0f)", NSStringFromClass([sv class]), sv.frame.origin.y, sv.frame.size.height];
                }
                [dump appendString:@"]"];
                parent = parent.superview;
                lvl++;
            }
            RDLog(@"%@", dump);
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

// v1.6.86: 源头级强制隐藏核心 —— 每类独立保存原始 IMP（用类名做 key，避免多类共享同一指针）。
// 关键修复：iOS 16.4.1 图标名字标签的真实类是 SBIconLegibilityLabelView
// （日志 FICON-LABEL cls=SBIconLegibilityLabelView 证实）；原 v1.6.85 只尝试
// SBIconListLabel / SBIconLabelView，二者在本机均不存在 → lbl=nil → 直接 return →
// 钩子从未安装 → 名字与圆点重叠 race、关文件夹名称闪现、文件夹缩小内层 app 名称闪现 三症全在。
// 故改为：枚举全部已知标签类名 + 各自子类树，全部 setHidden:/setAlpha: 替换。
static NSMutableDictionary *sOrigSetHiddenByClass = nil;
static NSMutableDictionary *sOrigSetAlphaByClass  = nil;
static NSMutableDictionary *sOrigDidMoveToWindowByClass = nil; // v2.0.7: didMoveToWindow: 原始 IMP（创建点拦截用）

// v2.0.12: 原 MKLabelHostInFolder() 已删除——v2.0.9 用它实现「关合窗口内对文件夹内 label 让步原生」，
// 而 v2.0.12 已撤销该让步(关合窗口内文件夹内 label 一律强藏,见 MKSetHiddenHook/MKSetAlphaHook/
// MKLabelDidMoveToWindowHook/主路径 mustHide 四处撤销)。该函数已无调用点,留之则 -Werror unused-function 编不过,故删。
static void MKSetHiddenHook(id self, SEL _cmd, BOOL hidden) {
    @try {
        NSString *bid = MKLabelToBid((UIView *)self);
        // v2.0.3: 关文件夹窗口内有界定向诊断（仅 debug 开 + sFolderClosing 时）
        if (sDebugLog && sFolderClosing && !hidden && sFolderCloseDiag < 8) {
            UIView *ivForLbl = objc_getAssociatedObject((UIView *)self, &kMKLabelIconKey);
            if (!bid) {
                sFolderCloseDiag++;
                RDLog(@"FOLDER-CLOSE-MISS(H): cls=%@ selfCls=%@ iconPtr=%@ sup=%@",
                      [(UIView *)self class], object_getClass(self),
                      ivForLbl ? @"Y" : @"N",
                      ((UIView *)self).superview ? NSStringFromClass([((UIView *)self).superview class]) : @"nil");
            }
        }
        NSString *mapBid = (sHiddenLabelToBid ? [sHiddenLabelToBid objectForKey:(id)self] : nil);
        BOOL hasBid = (bid && sHiddenBids && [sHiddenBids containsObject:bid]);
        BOOL inMap  = (mapBid.length && sHiddenBids && [sHiddenBids containsObject:mapBid]);
        if ((hasBid || inMap)) {   // v2.0.9 的「关闭动画窗口内让步原生」已在 v2.0.12 撤销：关合窗口内文件夹内 label 也强制藏名(不让步原生)，根治 sub-16ms settle 单帧闪现(第④点残留真凶)。证据 rd_log(63): FOLDER-CLOSE-VISIBLE=0 表明无 strobe 互搏，去掉安全。
            hidden = YES; // 有指示器 -> 名字必须隐藏，压制系统任何复显
            // v1.6.99: 写回直接关联键，使「该 label 属于需藏名 bid」的标记自持。
            // 关文件夹缩回动画途中(层级重组、label 被临时重父)MKLabelToBid 的
            // 兄弟/祖先兜底查找会瞬时失效一帧 -> 那一帧名称被系统复显即闪现(第4点)。
            // 一旦此处强制过藏名，后续任何 setHidden:NO 即使兜底查找失效也能靠
            // 直接关联键重新命中 -> 动画全程压制复显，根除闪现。
            // v2.0.7+GAP-FIX: 额外凭「label 指针 -> bid」弱键表兜底 -- 当 MKLabelToBid 瞬态
            // 返回 nil（关联键/层级/几何全失效的那一帧，正是第1点主屏偶发重叠根因）而该
            // label 先前确被强制藏名过，凭指针表继续压住，根除偶发重叠 race。
            NSString *useBid = hasBid ? bid : mapBid;
            MKAssocLabelBid((UIView *)self, useBid);
            [((UIView *)self).layer removeAllAnimations]; // v2.0.16: 掐掉关合动画给 label 挂的 opacity CAAnimation（presentation layer 无视 opacity=0 把名字画出来的真凶）
            if (sDebugLog && !hasBid && inMap)
                RDLog(@"OVERLAP-GAP: caught via ptr-map cls=%@ bid=%@", object_getClass(self), useBid);
        }
    } @catch (NSException *e) {}
    void(*orig)(id,SEL,BOOL) = NULL;
    if (sOrigSetHiddenByClass) {
        // v1.6.87: 沿继承链向上查 orig（叶子类可能继承自已钩基类，本身无登记项）
        Class c = object_getClass(self);
        while (c) {
            NSValue *v = [sOrigSetHiddenByClass objectForKey:NSStringFromClass(c)];
            if (v) { orig = (void(*)(id,SEL,BOOL))[v pointerValue]; break; }
            c = class_getSuperclass(c);
        }
    }
    // v1.6.88: 终防自递归/坏 orig —— 若继承链查表误把 hook 自身当 orig 捕回（未来回归），
    // 调用它会无限递归直至栈爆崩；这里硬拒 hook 自身，物理上杜绝该类崩溃。
    if (orig && orig != (void(*)(id,SEL,BOOL))MKSetHiddenHook) {
        @try { orig(self, _cmd, hidden); }
        @catch (NSException *e) { RDLog(@"MKSetHiddenHook orig EXCEPTION: %@", e.reason); }
    }
}
static void MKSetAlphaHook(id self, SEL _cmd, CGFloat a) {
    @try {
        NSString *bid = MKLabelToBid((UIView *)self);
        // v2.0.3: 关文件夹窗口内有界定向诊断（setAlpha: 复显路径）
        if (sDebugLog && sFolderClosing && a > 0.0f && sFolderCloseDiag < 8) {
            UIView *ivForLbl = objc_getAssociatedObject((UIView *)self, &kMKLabelIconKey);
            if (!bid) {
                sFolderCloseDiag++;
                RDLog(@"FOLDER-CLOSE-MISS(A): cls=%@ selfCls=%@ iconPtr=%@ sup=%@ a=%.2f",
                      [(UIView *)self class], object_getClass(self),
                      ivForLbl ? @"Y" : @"N",
                      ((UIView *)self).superview ? NSStringFromClass([((UIView *)self).superview class]) : @"nil", (float)a);
            }
        }
        NSString *mapBid = (sHiddenLabelToBid ? [sHiddenLabelToBid objectForKey:(id)self] : nil);
        BOOL hasBid = (bid && sHiddenBids && [sHiddenBids containsObject:bid]);
        BOOL inMap  = (mapBid.length && sHiddenBids && [sHiddenBids containsObject:mapBid]);
        if ((hasBid || inMap)) {   // v2.0.12: 撤销 v2.0.9 关合窗口内让步原生(label 在文件夹内也强制藏名), 根治 sub-16ms settle 单帧闪现。详见 MKSetHiddenHook 同款注释。
            a = 0.0f; // 同上，压制 alpha 复显
            // v1.6.99: 同 MKSetHiddenHook —— 写回直接关联键，藏名标记自持，
            // 杜绝关文件夹缩回动画途中 label 被临时重父导致的名称闪现(第4点)。
            // v2.0.7+GAP-FIX: 额外凭「label 指针 -> bid」弱键表兜底偶发重叠(第1点)，见 MKSetHiddenHook。
            NSString *useBid = hasBid ? bid : mapBid;
            MKAssocLabelBid((UIView *)self, useBid);
            [((UIView *)self).layer removeAllAnimations]; // v2.0.16: 掐掉关合动画给 label 挂的 opacity CAAnimation（presentation layer 无视 opacity=0 把名字画出来的真凶）
            if (sDebugLog && !hasBid && inMap)
                RDLog(@"OVERLAP-GAP: caught via ptr-map cls=%@ bid=%@", object_getClass(self), useBid);
        }
    } @catch (NSException *e) {}
    void(*orig)(id,SEL,CGFloat) = NULL;
    if (sOrigSetAlphaByClass) {
        Class c = object_getClass(self);
        while (c) {
            NSValue *v = [sOrigSetAlphaByClass objectForKey:NSStringFromClass(c)];
            if (v) { orig = (void(*)(id,SEL,CGFloat))[v pointerValue]; break; }
            c = class_getSuperclass(c);
        }
    }
    // v1.6.88: 终防自递归/坏 orig（见 MKSetHiddenHook 注释）
    if (orig && orig != (void(*)(id,SEL,CGFloat))MKSetAlphaHook) {
        @try { orig(self, _cmd, a); }
        @catch (NSException *e) { RDLog(@"MKSetAlphaHook orig EXCEPTION: %@", e.reason); }
    }
}

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
    void (*orig)(id, SEL) = NULL;
    Class c = object_getClass(self);
    while (c) {
        NSValue *v = sOrigDidMoveToWindowByClass ? [sOrigDidMoveToWindowByClass objectForKey:NSStringFromClass(c)] : nil;
        if (v) { orig = (void(*)(id,SEL))[v pointerValue]; break; }
        c = class_getSuperclass(c);
    }
    if (orig) {
        @try { orig(self, _cmd); }
        @catch (NSException *e) { RDLog(@"MKLabelDidMoveToWindowHook orig EXCEPTION: %@", e.reason); }
    }
    @try {
        UIView *lbl = (UIView *)self;
        // 只在「已进 window 且当前可见」时检查；移除(window=nil)不处理
        if (lbl.window && !lbl.hidden && lbl.alpha > 0.0f) {   // v2.0.12: 撤销 v2.0.9 关合窗口内文件夹内 label 让步原生(label 一进 window 即刻强藏, 根除 sub-16ms settle 单帧闪现); 详见 MKSetHiddenHook 同款注释。
            NSString *bid = MKLabelToBid(lbl); // v2.0.7: 含几何兜底，瞬态也能解出
            if (bid && sHiddenBids && [sHiddenBids containsObject:bid]) {
                lbl.hidden = YES;
                lbl.alpha = 0.0f;
                lbl.layer.opacity = 0.0f;
                lbl.opaque = NO;
                MKAssocLabelBid(lbl, bid);
                [lbl.layer removeAllAnimations]; // v2.0.16: 同上，新建 label 进 window 即刻掐动画
            }
        }
    } @catch (NSException *e) {}
}

static void MKHookOneLabelClass(Class cls) {
    if (!cls) return;
    NSString *k = NSStringFromClass(cls);
    if (!sOrigSetHiddenByClass) {
        sOrigSetHiddenByClass = [NSMutableDictionary dictionary];
        sOrigSetAlphaByClass  = [NSMutableDictionary dictionary];
    }
    if ([sOrigSetHiddenByClass objectForKey:k]) return; // 已钩，幂等
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
        method_setImplementation(m1, (IMP)MKSetHiddenHook);
    }
    if (m2 && m2 != supM2 && method_getImplementation(m2) != (IMP)MKSetAlphaHook) {
        IMP orig = method_getImplementation(m2);
        [sOrigSetAlphaByClass setObject:[NSValue valueWithPointer:(void *)orig] forKey:k];
        method_setImplementation(m2, (IMP)MKSetAlphaHook);
    }
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
            if (origW) [sOrigDidMoveToWindowByClass setObject:[NSValue valueWithPointer:(void *)origW] forKey:k];
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
            if (sDebugLog) RDLog(@"MKInstallLabelHook: hooked %lu label class(es)", (unsigned long)toHook.count);
        } @catch (NSException *e) {
            RDLog(@"MKInstallLabelHook EXCEPTION: %@", e.reason);
        }
    });
}
// v1.6.85: 记录各 App「最近活动/消息」时间戳，供文件夹图标指示器挑代表 App 用。
// 在三个 SBApplication 状态钩子里（进程状态变化）调用 —— 涵盖启动/切前台/退后台，
// 即「最近被你打开/用过」的 App；对聊天类 App 约等于「最近来消息」。
// 如需精确「未读消息」时间戳，可后续加 BBObserver 通知钩子（更高风险，本版先用活动代理）。
static void MKTouchMsg(NSString *bid) {
    if (!bid.length) return;
    if (!sLastMsgTime) sLastMsgTime = [NSMutableDictionary dictionary];
    sLastMsgTime[bid] = @([NSDate date].timeIntervalSince1970);
}

static void MKUpdate(SBIconView *self) {
    MKSafe(^{
        if (!sInitDone) return;

        // v1.6.70: 锁屏/解锁处理改为"时间闸门"——锁屏时 sLocked=YES 并记录 sLockAt；
        // 解锁动画(~0.5s)结束(>0.7s)后，下一次布局自动复位 sLocked=NO 并正常显示指示器。
        // 不再依赖 lockstate 解锁通知（某些环境不送达/对象语义不符），根治"解锁后空白长/需滑动才出现"。
        if (sLocked) {
            NSTimeInterval now = [NSDate date].timeIntervalSince1970;
            if (now - sLockAt > 0.7) {
                sLocked = NO;  // 解锁动画已结束，交给定时淡入复原
                if (sUnlockTimer) { dispatch_source_cancel(sUnlockTimer); sUnlockTimer = NULL; }
                MKUnlockRestore();  // v2.0.1: 延迟 0.45s + alpha 淡入，避开解锁动画、和谐过渡
                return;  // 翻闸后直接返回，避免下面正常流程立即硬显示当前图标
            } else {
                UIView *ind = MKFindIndicator(MKGetCachedBid(self));
                if (ind) ind.hidden = YES;
                return;
            }
        }

        sCallCount++;
        if (MKIsDisabled()) {
            MKRemoveAllIndicators();
            UIView *label = MKGetCachedLabel(self);
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
                MKAssocLabelBid(label, nil);
            }
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (!cfg || !cfg.enabled) {
            MKRemoveAllIndicators();
            UIView *label = MKGetCachedLabel(self);
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
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
            if (sDebugLog) RDLog(@"FICON-ENTER bid=%@ cls=%@ folderIndicators=%d", fBid, NSStringFromClass([fIcon class]), (int)[MKConfig sharedConfig].folderIndicators);
            if (!fBid.length) return;
            // v1.6.92: 文件夹打开动画中，桌面文件夹图标 view 可能被临时 reparent 到
            // SBFloatyFolderScrollView 等容器下；此时若走 FICON 创建/重定位，会把圆点
            // 画到打开的文件夹内部（见截图）。只让桌面/Dock 容器下的文件夹图标显指示器，
            // 其它容器一律跳过，等关闭后 MKRefreshFolderIcons 再刷新。
            UIView *fContainer = MKContainerForIconView((UIView *)self);
            NSString *fContainerCls = fContainer ? NSStringFromClass([fContainer class]) : @"";
            BOOL fIsHomeOrDock = [fContainerCls isEqualToString:@"SBIconScrollView"] || [fContainerCls hasPrefix:@"SBDock"];
            if (!fIsHomeOrDock) {
                if (sDebugLog) RDLog(@"FICON-ABORT bid=%@ reason=container=%@ (not home/dock)", fBid, fContainerCls);
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
                    if (lbl) { lbl.hidden = YES; lbl.alpha = 0.0f; lbl.layer.opacity = 0.0f; lbl.opaque = NO; MKAssocLabelBid(lbl, fBid); }
                }
                if (sDebugLog) RDLog(@"FICON-SKIP bid=%@ gen=%lu (unchanged, cheap reposition)", fBid, (unsigned long)sFolderContentGen);
                return;
            }
            NSArray<NSString*> *contained = MKContainedRunningBids((SBIconView *)self);
            if (sDebugLog && contained.count > 0) RDLog(@"FICON-CONTAINED bid=%@ running-bids=%@", fBid, [contained componentsJoinedByString:@","]);
            if (contained.count == 0) {
                if (sDebugLog) RDLog(@"FICON-ABORT bid=%@ reason=no-running-apps", fBid);
                UIView *lbl = MKGetCachedLabel(self);
                if (lbl) { lbl.hidden = NO; lbl.alpha = 1.0f; lbl.layer.opacity = 1.0f; lbl.opaque = YES; MKAssocLabelBid(lbl, nil); }
                UIView *fi = MKFindIndicator(fBid);
                if (fi) MKRemoveIndicatorForBid(fBid);
                return;
            }
            MKConfig *fCfg = [MKConfig sharedConfig];
            if (!fCfg || !fCfg.folderIndicators) {
                if (sDebugLog) RDLog(@"FICON-ABORT bid=%@ reason=folderIndicators-off", fBid);
                UIView *lbl = MKGetCachedLabel(self);
                if (lbl) { lbl.hidden = NO; lbl.alpha = 1.0f; lbl.layer.opacity = 1.0f; lbl.opaque = YES; MKAssocLabelBid(lbl, nil); }
                UIView *fi = MKFindIndicator(fBid);
                if (fi) MKRemoveIndicatorForBid(fBid);
                return;
            }
            // 有运行 App → 显示 1 个圆点（按策略取代表 App 主色）
            BOOL fixedColor = (fCfg.colorMode == MKColorModeFixed);
            NSString *rep = MKFolderChosenBid(contained, fCfg.folderIndicatorMode, fixedColor);
            UIView *label = MKGetCachedLabel(self);
            if (sDebugLog) RDLog(@"FICON-LABEL bid=%@ label=%@ cls=%@ frame=%@", fBid, label ? @"YES" : @"NO", label ? NSStringFromClass([label class]) : @"-", label ? NSStringFromCGRect(label.frame) : @"-");
            if (label) { label.hidden = YES; label.alpha = 0.0f; label.layer.opacity = 0.0f; label.opaque = NO; MKAssocLabelBid(label, fBid); }
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
                [(MKIndicatorDotView *)indicator applyConfig];
                if (!fixedColor && rep.length) {
                    UIColor *c = MKCachedIconColorForBundleID(rep);
                    if (c) [(MKIndicatorDotView *)indicator setIndicatorColor:c];
                }
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:fBid];
                if (sHiddenBids) [sHiddenBids addObject:fBid]; // v1.6.85: 文件夹合成 key 也要藏名
                if (sDebugLog) RDLog(@"FICON-CREATE v2.0.16: %@ rep=%@ mode=%ld fixed=%d container=%@ frame=%@", fBid, rep, (long)fCfg.folderIndicatorMode, fixedColor, fContainerCls, NSStringFromCGRect(indicatorFrame));
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
                }
            }
            return;
        }

        if (sFolderOpen && !MKIsIconInFolder((UIView *)self)) {
            if (sDebugLog) RDLog(@"MKU-FOLDER-GUARD skip bid=%@ (main-screen icon while folder open)", MKGetCachedBid(self));
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
        // v1.6.60 诊断：仅针对「后台运行中 App」的 MKUpdate 打点（不刷屏）。
        // 能看到：MKUpdate 是否真的被调到、当时 sScrolling/hasIndicator 状态、最终是否建出。
        // 若 REFRESH 命中却无本行 → MKUpdate 没被调（触发链断）；
        // 若有本行却无 Indicator CREATE → MKUpdate 内部早退；据此一击定位。
        if (sDebugLog && running && !isForeground) {
            RDLog(@"MKU-bg bid=%@ scroll=%d hasInd=%d", bundleID, sScrolling, (int)!!existingIndicator);
        }
        // v1.6.81: folder icons don't participate in scroll gate; opening animation is mis-detected as scrolling
        BOOL isInFolder = MKIsIconInFolder((UIView *)self);
        // v1.6.70: 移除"文件夹打开期间一律显示名称并 return"的压制。
        // 现在文件夹内运行中 App 也要显示指示器（与主屏一致）：名称隐藏、指示器
        // 建在文件夹自己的 overlay 上（MKOverlayForContainer 按当前容器懒建）。
        // 非运行中 App 自然落到下方 !running 分支恢复名称。
        if (sScrolling && !isInFolder) {
            if (sDebugLog) {
                static NSMutableSet *sGateScroll; static dispatch_once_t sOnceS;
                dispatch_once(&sOnceS, ^{ sGateScroll = [NSMutableSet new]; });
                NSString *k = bundleID ? bundleID : NSStringFromClass([self class]);
                if (![sGateScroll containsObject:k]) { [sGateScroll addObject:k]; RDLog(@"RDGATE %@ ret=scroll", k); }
            }
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
                if (sDebugLog) RDLog(@"RET-folder bid=%@ container=%@", bundleID,
                      NSStringFromClass([MKContainerForIconView((UIView *)self) class]));
            }
        }
        if (!bundleID || bundleID.length == 0) {
            if (sDebugLog) {
                static NSMutableSet *sGateBid; static dispatch_once_t sOnceB;
                dispatch_once(&sOnceB, ^{ sGateBid = [NSMutableSet new]; });
                NSString *k = NSStringFromClass([self class]);
                if (![sGateBid containsObject:k]) { [sGateBid addObject:k]; RDLog(@"RDGATE %@ ret=nobid", k); }
            }
            return;
        }

        BOOL isPending = MKIsPending(bundleID);       // v1.5.6+: 等待300ms的App
        BOOL isFading = MKIsFadingLabel(bundleID);    // v1.5.8: 标签正在渐隐中

        // v1.6.55: 入口门控快照 —— 只给"正在运行的后台 App"打，定位主屏指示器为何不创建。
        // 若某 App 走到这里却既没建指示器、也没打 NO LABEL/RUNNING 日志，看这行即可知卡在哪道门控。
        if (sDebugLog && running) {
            RDLog(@"RDUPD %@ fg=%d scroll=%d pend=%d fade=%d bid=%@",
                  NSStringFromClass([self class]), isForeground, sScrolling, isPending, isFading, bundleID);
        }

        // v1.6.76: 文件夹「内部」运行的 App 现在走下方常规主功能路径各自显示圆点
        // （用户要求「保留里面各自显」）。文件夹【图标】本身挂圆点的逻辑在上方 MKIsFolderIcon 分支。


        // v1.5.3: 使用缓存的标签视图（避免每次都跑 MKFindLabelView 4 重策略）
        UIView *label = MKGetCachedLabel(self);
        UIView *indicator = existingIndicator;

        // 当前被用户打开在前台的 App，桌面上不再显示指示器（避免启动动画残留）
        if (!running || isForeground) {
            if (sDebugLog) RDLog(@"RET-fg bid=%@ running=%d fg=%d", bundleID, running, isForeground);
            // ── App 不在运行 / 在前台 → 移除指示器，恢复名字 ──
            if (indicator) MKRemoveIndicatorForBid(bundleID);
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
                MKAssocLabelBid(label, nil);
            }
            // v2.0.16: App 退出/前台化 → 恢复 TestFlight 小黄点（挂回 label 并可见）。
            MKApplyBetaDot(self, MKBetaRestore);
            MKRemovePending(bundleID);  // v1.5.6+: 清除 pending 状态
            MKRemoveFadingLabel(bundleID); // v1.5.8: 清除渐隐状态
            return;
        }

        // v1.5.8: 标签正在渐隐中 → 不干扰动画，不创建指示器
        // 让 250ms 渐隐动画自然播放，300ms后才创建指示器
        if (isFading) {
            if (sDebugLog) RDLog(@"RET-fading bid=%@", bundleID);
            return;  // 不做任何操作，让渐隐动画继续
        }

        // v1.5.6+: pending 期间只隐藏标签，不创建指示器（等300ms回调）
        // 标签渐隐已完成（alpha=0），但仍需保持隐藏状态防止系统恢复
        if (isPending) {
            if (sDebugLog) RDLog(@"RET-pending bid=%@", bundleID);
            if (label) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
                MKAssocLabelBid(label, bundleID);
            }
            return;  // 不创建指示器，等300ms后 MKRefreshIconForBundleID 回调
        }

        RDLogRunning(bundleID);

        // ── App 正在运行 → 隐藏名字，显示指示器 ──
            if (label) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
                MKAssocLabelBid(label, bundleID);
            } else {
            // v1.5.5 诊断：App 在运行但找不到标签
            if (sDebugLog) RDLog(@"NO LABEL for running app: %@", bundleID);
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
            if (sDebugLog) RDLog(@"Indicator CREATE v2.0.16: %@ shape=%d animate=%d label=%@",
                  bundleID, (int)cfg.shape, shouldAnimate,
                  label ? @"YES" : @"NO(FALLBACK)");

            if (shouldAnimate) {
                indicator.alpha = 0.0f;
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:bundleID];
                if (sHiddenBids) [sHiddenBids addObject:bundleID]; // v1.6.85: 标记此 bid 名字必须隐藏
                CGFloat finalAlpha = cfg.opacity;
                if (sDebugLog) RDLog(@"Indicator FADE-IN: %@ alpha 0→%.2f", bundleID, finalAlpha);
                [UIView animateWithDuration:0.2 animations:^{
                    indicator.alpha = finalAlpha;
                }];
            } else {
                [overlay addSubview:indicator];
                if (!sBidToIndicator) sBidToIndicator = [NSMapTable strongToStrongObjectsMapTable];
                [sBidToIndicator setObject:indicator forKey:bundleID];
                if (sHiddenBids) [sHiddenBids addObject:bundleID]; // v1.6.85: 标记此 bid 名字必须隐藏
            }
            [overlay bringSubviewToFront:indicator];  // v1.6.71: 确保指示器在文件夹 overlay 顶层（z-order）
            if (sDebugLog) RDLog(@"IND-OVERLAY bid=%@ container=%@ frame=%@ hidden=%d alpha=%.2f",
                  bundleID, NSStringFromClass([container class]),
                  NSStringFromCGRect(indicator.frame), indicator.hidden, (float)indicator.alpha);
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
                if (sDebugLog) RDLog(@"IND-REPARENT bid=%@ from=%@ to=%@",
                      bundleID, NSStringFromClass([oldParent class]),
                      NSStringFromClass([overlay class]));
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
        // v2.0.16: 按设置处理 TestFlight 小黄点（Beta dot）。
        // 开关开 → 隐藏（藏进 label 内）；开关关 → 脱离 label 挂到 iconView 保持可见（藏名不影响小黄点）。
        MKApplyBetaDot(self, [MKConfig sharedConfig].hideBetaDot ? MKBetaHide : MKBetaShowDetached);
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
        if (refreshed > 0 && sDebugLog) {
            RDLog(@"FOLDER REFRESH: refreshed %d icons inside container", refreshed);
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
                if (sDebugLog) RDLog(@"FOLDER-WATCHDOG: reset sFolderOpen=NO (no SBFolderView in window)");
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
                if (sDebugLog) RDLog(@"REFRESH bid=%@ via=registry", bid);
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
        if (sDebugLog) RDLog(@"REFRESH bid=%@ via=walk matched=%d", bid, walked);
    });
}

// ====================================================================
// v1.5.8: 标签渐隐动画（前台→后台时，标签 alpha 1→0 的 250ms 渐隐）
// 替代 v1.5.6 的瞬间隐藏，让过渡更自然
// ====================================================================

static void MKFadeOutLabelForBundleID(NSString *bid) {
    MKSafe(^{
        if (!sInitDone || !bid.length) return;
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
                                label.opaque = YES;
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
    sFolderContentGen++;
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
        if (sDebugLog) RDLog(@"ONSTATE-FOLDER bid=%@ running=%d fg=%d", bid, (int)running, (int)foreground);
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
    RDLog(@"DELAYED INIT: starting heavy work...");

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

    RDLog(@"DELAYED INIT: runningSet has %lu items", (unsigned long)sRunningSet.count);
    RDLog(@"runningSet: %@", [[sRunningSet allObjects] componentsJoinedByString:@", "]);

    // ─── 标记初始化完成 ──────
    sInitDone = YES;
    MKUpdateDebugFlag(); // v1.6.26: 初始化完成后读取调试开关
    RDLog(@"DELAYED INIT: done. sInitDone=YES");

    // ─── 首次刷新所有图标 ──────
    MKRefreshAllIcons();
    MKRefreshFolderIcons();
}

static void MKPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    [[MKConfig sharedConfig] reload];
    MKUpdateDebugFlag(); // v1.6.26: 设置变更后刷新调试开关
    MKRefreshAllIcons();
    MKRefreshFolderIcons();
}

// ====================================================================
// Hook — SBIconView
// ====================================================================

%hook SBIconView

// v2.0.16: 拦截 SBIconView 的「图标名 alpha」专用 setter，根治关普通文件夹缩回末尾名称闪现(第④点)。
// 铁证(rd_log(64)): 14:21:03 FLOATY 行 SBIconView.description 打印 iconLabelAlpha=0.0 → 该属性真实存在；
// iOS 16 控 label 显隐走此【上层】setter —— 其内部直接动 label.layer.opacity / presentation layer，
// 完全绕过我们对 SBIconLegibilityLabelView.setAlpha:/setHidden: 的 hook → 缩回到最小那 sub-16ms 单帧
// 把名字带出来 = 用户实测「关普通文件夹闪一下名称」。
// 修法: 本 bid 当前有指示器(∈sHiddenBids)时, 强制把 iconLabelAlpha 压到 0 并直接设 cached label hidden/alpha,
// 三保险压住缩回动画末尾那一帧的名称闪现。仅对运行 App 生效，其余走 %orig 透传。
- (void)setIconLabelAlpha:(CGFloat)a {
    NSString *b = MKGetCachedBid((SBIconView *)self);
    if (b.length && sHiddenBids && [sHiddenBids containsObject:b]) {
        if (sDebugLog) RDLog(@"SET-ICONLABELALPHA: forced 0 bid=%@ a=%.2f", b, (float)a);
        // v2.0.16: 不单纯 return。若当前 label 已处于可见态，或系统传入 a>0 想显示名称，
        // return 会维持可见。这里强制把 iconLabelAlpha 压到 0，并直接找到 cached label 设
        // hidden/alpha/layer.opacity，三保险压住缩回动画末尾那一帧的名称闪现。
%orig(0.0f);
UIView *lbl = MKGetCachedLabel(self);
        if (lbl && b.length && sHiddenBids && [sHiddenBids containsObject:b]) [lbl.layer removeAllAnimations]; // v2.0.16: 掐掉关合动画 opacity 动画（仅追踪中的运行 App）
        if (lbl) {
            lbl.hidden = YES;
            lbl.alpha = 0.0f;
            lbl.layer.opacity = 0.0f;
            lbl.opaque = NO;
        }
        return;
    }
    %orig;
}

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
            if (bid2 && (MKFindIndicator(bid2) || (MKIsAppRunning(bid2) && !MKIsForeground(bid2)))) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
            } else {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
                MKAssocLabelBid(label, nil);
            }
        }
        // 注意：保留 indicator（关联对象）+ kMKBidKey/kMKIconKey/kMKLabelKey 缓存
        return;
    }
    if (sInitDone) {
        // v1.6.0: 诊断日志 — 追踪 App 图标出现时机（特别是文件夹内图标）
        if (sDebugLog) {
            NSString *bid = MKGetCachedBid(self);
            if (bid && MKIsAppRunning(bid)) {
                RDLog(@"IconView.APPEAR: %@ running=YES fg=%d hasIndicator=%@ iconCls=%@ superviewCls=%@",
                      bid, MKIsForeground(bid),
                      MKFindIndicator(bid) ? @"YES" : @"NO",
                      NSStringFromClass([[self icon] class] ?: [NSObject class]),
                      NSStringFromClass([self.superview class] ?: [NSObject class]));
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MKUpdate(self);
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if (!sInitDone) return;

    // v1.6.70: 移除"文件夹打开期间一律显示名称并 return"的压制。
    // 现在文件夹内运行中 App 也要显示指示器（与主屏一致），故交下方
    // MKIsIconInFolder / 常规 running 分支处理（运行中→藏名+指示器；非运行→恢复名称）。

    NSString *bid = MKGetCachedBid(self);
    // v2.0.16: 关文件夹缩回时 SBIconView 为新建实例，MKGetCachedBid(self) 此刻
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
        id fIcon = [self icon];
        NSString *fBid = fIcon ? [NSString stringWithFormat:@"__folder__%p", fIcon] : nil;
        if (fBid.length) {
            // v2.0.4: sHiddenBids 权威（见上方注释）。只要 fBid 仍在集合即强制藏名，
            // 不再依赖指示器对象当场在场——对齐 App 分支 2782 的不变量。
            BOOL mustHide = (MKFindIndicator(fBid) != nil) || (sHiddenBids && [sHiddenBids containsObject:fBid]);
            if (mustHide) {
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
    // running 分支（隐藏名称、显示指示器在文件夹 overlay）；非运行中 App 落到
    // !running 分支恢复名称。MKIsIconInFolder 仅留作诊断打点（仍被引用，避免 -Wunused）。
    if (MKIsIconInFolder((UIView *)self)) {
        if (sDebugLog) RDLog(@"INFOLDER layout bid=%@ fg=%d", MKGetCachedBid(self), MKIsForeground(MKGetCachedBid(self)));
    }

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
    if (mustHide) {   // v2.0.12: 撤销 v2.0.9 关合窗口内文件夹内 icon 让步原生(无条件强制藏名), 根治 sub-16ms settle 单帧闪现(第④点残留)。详见 MKSetHiddenHook 同款注释。
        // v2.0.8: 主路径仍藏缓存 label；额外 BFS 当前子树，藏任何 label-like 子视图——
        // 缩回动画中 SpringBoard 给内层 App 新建/重父的 label 是【新对象】，MKGetCachedLabel
        // 取不到、MKLabelToBid 也解不出，仅靠缓存 label 会漏藏→名称闪现。每帧 layout
        // 兜底，与 10ms guard 形成双保险（仅对确有指示器的图标执行，开销可忽略）。
        if (label && label.superview) {
            label.hidden = YES;
            label.alpha = 0.0f;
            label.layer.opacity = 0.0f;
            label.opaque = NO;
            if (bid.length) MKAssocLabelBid(label, bid);
        }
        NSMutableArray *mkSub = [NSMutableArray arrayWithArray:(NSArray *)[(UIView *)self subviews]];
        while (mkSub.count > 0) {
            UIView *mkS = [mkSub lastObject]; [mkSub removeLastObject];
            BOOL mkIsL = [mkS isKindOfClass:[UILabel class]] ||
                ([NSStringFromClass([mkS class]) rangeOfString:@"Label"].location != NSNotFound);
            if (mkIsL && !mkS.hidden && mkS.alpha > 0.0f) {
                mkS.hidden = YES; mkS.alpha = 0.0f; mkS.layer.opacity = 0.0f; mkS.opaque = NO;
                if (bid.length) MKAssocLabelBid(mkS, bid);
            }
            [mkSub addObjectsFromArray:mkS.subviews];
        }
    }

    // v1.6.67: 滚动期间不重定位/创建指示器（避免 churn），但必须保持 label 状态同步。
    // 若 App 后台运行且已有指示器，系统可能在滚动中恢复 label，导致"指示器与名称重叠"。
    // v1.6.82: 通用不变量——只要本 bid 当前有指示器（圆点），名字必须隐藏，
    // 否则滚动/转场布局把 label 复显会与圆点重叠。注意 folder 容器图标的 bid 是
    // __folder__%p（非 App），MKIsAppRunning 恒为 NO，旧条件 running&&!fg 会漏藏它 → 改判 indicator。
    if (sScrolling) {
        if (indicator) {
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
        if (sDebugLog) RDLog(@"FOLDER-GUARD skip bid=%@ (main-screen icon while folder open)", MKGetCachedBid(self));
        return;
    }

        if (!indicator) {
            // 无 overlay 指示器 → 仅当本图标是运行中后台 App 时才需要创建
            if (!running || isForeground) return;

            // v1.6.70: 后台运行中、指示器待建(pending)或正在渐隐(fading)期间，
            // 立即把名称强制隐藏——否则回桌面转场动画会把 label 复显(系统图标入场
            // 把 alpha 拉回 1)，与 300ms 后建出的指示器同显一瞬 = 名称与指示器重叠。
            // 原先在 isFading 时直接 return 不藏名，正是重叠窗口的成因。
            if (MKIsPending(bid) || MKIsFadingLabel(bid)) {
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
    if (label && label.superview) {
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
        if (sDebugLog) RDLog(@"IND-REPARENT-LS bid=%@ to=%@",
              bid, NSStringFromClass([overlay class]));
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
// 在截图【之前】扫 snapView 子树里「该藏却可见」的 label，有即打 SNAP-PRE-NAME（受 sDebugLog 门控）。
// 纯诊断、不改行为；release/debug 都不藏名，只报。若命中，v2.0.10+ 真修法：截图前先藏、截图后复原。
static void MKSafeSnapshotProbe(UIView *snapView) {
    if (!snapView || !sDebugLog || !sHiddenBids || sHiddenBids.count == 0) return;
    @try {
        __block int hit = 0;
        NSMutableArray *st = [NSMutableArray arrayWithObject:snapView];
        while (st.count > 0 && hit < 8) {
            UIView *c = [st lastObject]; [st removeLastObject];
            // label-like 判定：UILabel 类 或 类名含 "Label"
            BOOL isL = [c isKindOfClass:[UILabel class]] ||
                        ([NSStringFromClass([c class]) rangeOfString:@"Label"].location != NSNotFound);
            if (isL && !c.hidden && c.alpha > 0.0f) {
                // 该 label 所属图标 bid（用几何反解，不依赖关联键）
                NSString *b = MKLabelToBid(c);
                BOOL mustHide = (b.length && [sHiddenBids containsObject:b]);
                if (!mustHide && sHiddenLabelToBid) {
                    NSString *mb = [sHiddenLabelToBid objectForKey:(id)c];
                    if (mb.length && [sHiddenBids containsObject:mb]) { mustHide = YES; b = mb; }
                }
                if (mustHide) {
                    hit++;
                    RDLog(@"SNAP-PRE-NAME: cls=%@ bid=%@ frame=%@ snapCls=%@",
                          NSStringFromClass([c class]), b, NSStringFromCGRect(c.frame),
                          NSStringFromClass([snapView class]));
                }
            }
            [st addObjectsFromArray:c.subviews];
        }
    } @catch (NSException *e) {}
}

// 现抽成独立函数，由 SBFolderController -viewWillDisappear:（关闭起始，sFolderOpen 仍 YES）与
// didMoveToWindow(nil)（结束兜底）共调用，使 10ms 全树 BFS 在缩回动画进行中即运行，根治末尾闪现。
static void MKArmFolderCloseGuard(void) {
    sFolderClosing = YES;
    sFolderCloseDiag = 0;
    sFolderCloseVisDiag = 0;
        if (sFolderCloseGuard) { dispatch_source_cancel(sFolderCloseGuard); sFolderCloseGuard = NULL; }
        sFolderCloseGuard = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (sFolderCloseGuard) {
            // v2.0.6: 由 0.016s×50(≈0.8s) 升为 0.010s×150(≈1.5s)。
            // ① 采样间隙 ~16ms→~10ms（≈半帧），亚帧级复显更易被抓到；
            // ② 窗口拉长到完全覆盖缩回动画【之外】的 settle——实测「末尾闪一下」常在旧 0.8s 末拍之后
            //    （图标 snap 回主屏格栅那一两帧）才出现，故拉到 1.5s 保底；
            // ③ guard 结束后另追加一次 0.4s 延迟全树扫描（见 fcTicks>=150 分支），双保险压住 settle 复显。
            dispatch_source_set_timer(sFolderCloseGuard, DISPATCH_TIME_NOW, (int64_t)(0.010 * NSEC_PER_SEC), 0);
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
                            if (ivCls2 && [cur isKindOfClass:ivCls2]) {
                                SBIconView *iv = (SBIconView *)cur;
                                NSString *b = MKGetCachedBid(iv);
                                // v2.0.12: 彻底删除 v2.0.9 引入、v2.0.10 收窄的「末拍让步原生」。
                                // 问题: 普通文件夹关合缩回到最小(sub-16ms 单帧)时, UIKit 动画 commit 把本该隐藏的
                                // 文件夹内 App 名 label 又带出来一瞬 → 肉眼见「闪一下」; 而我们的 guard 每 0.010s 采样
                                // 抓不到这单帧(VISIBLE=0), 与 v2.0.6 注释 self-admitted "sub-16ms frame at settle" 一致。
                                // 证据(rd_log(63)): 关合窗口内 FOLDER-CLOSE-VISIBLE=0 / SNAP-PRE-NAME=0 / 无 Indicator 重建 → 根本不 strobe 互搏。
                                // 故关合窗口内对文件夹内 label 干脆【全程强藏】, 不留任何让步窗口。FloatyFolder 识别由 MKIsIconInFolder 单独负责, 不受影响。
                                // (无 yieldNative 变量, 避免 -Werror 未使用告警)
                                if (b.length && sHiddenBids && [sHiddenBids containsObject:b]) {
                                    UIView *lbl = MKGetCachedLabel(iv);
                                    // v2.0.5 探针 B：关文件夹窗口内，本该隐藏的 label 仍可见 = 泄漏。
                                    // 分两类报：① 缓存 label 可见（guard 抓到，至多晚 1 帧）→ via=guard；
                                    // ② 缓存拿不到、但 iv 子树里有别的可见 label（iOS 新建的）→ via=guard-new（常规每帧藏名漏掉的那种）。
                                    // v2.0.6: 调试态先报缓存 label 可见（via=guard）；
                                    // 全子树 BFS 强制藏名（含 iOS 新建的嵌套 label）【无条件执行，release 也生效】，
                                    // 仅命中时的 FOLDER-CLOSE-VISIBLE via=guard-new 诊断受 debug 门控。
                                    if (sDebugLog && sFolderCloseVisDiag < 8) {
                                        if (lbl && !lbl.hidden && lbl.alpha > 0.0f) {
                                            sFolderCloseVisDiag++;
                                            RDLog(@"FOLDER-CLOSE-VISIBLE: via=guard bid=%@ cls=%@ frame=%@",
                                                  b, NSStringFromClass([lbl class]), NSStringFromCGRect(lbl.frame));
                                        }
                                    }
                                    NSMutableArray *lstack = [NSMutableArray arrayWithArray:(NSArray *)[(UIView *)iv subviews]];
                                    while (lstack.count > 0) {
                                        UIView *s2 = [lstack lastObject]; [lstack removeLastObject];
                                        BOOL isLbl = [s2 isKindOfClass:[UILabel class]] ||
                                            ([NSStringFromClass([s2 class]) rangeOfString:@"Label"].location != NSNotFound);
                                        if (isLbl && !s2.hidden && s2.alpha > 0.0f && s2 != lbl) {
                                            if (sDebugLog && sFolderCloseVisDiag < 8) {
                                                sFolderCloseVisDiag++;
                                                RDLog(@"FOLDER-CLOSE-VISIBLE: via=guard-new bid=%@ cls=%@ frame=%@",
                                                      b, NSStringFromClass([s2 class]), NSStringFromCGRect(s2.frame));
                                            }
                                            s2.hidden = YES; s2.alpha = 0.0f; s2.layer.opacity = 0.0f; s2.opaque = NO;
                                            MKAssocLabelBid(s2, b);
                                        }
                                        [lstack addObjectsFromArray:s2.subviews];
                                    }
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
                    if (sDebugLog) RDLog(@"FOLDER-CLOSE-ARM on=0 ticks=150");
                    // v2.0.6: settle 末尾保护 —— 缩回动画 snap 回主屏格栅的复显常在 guard 末拍之后才出现，
                    // 故结束后再延迟 0.4s 补一次全窗口树扫描：对所有 bid∈sHiddenBids 的图标强制藏名（含全子树新 label）。
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        MKSafe(^{
                            Class ivC = MKSBIconViewClass();
                            NSArray *ws = [UIApplication sharedApplication].windows;
                            for (UIWindow *w in ws) {
                                NSMutableArray *st = [NSMutableArray arrayWithObject:w];
                                while (st.count > 0) {
                                    UIView *c = [st lastObject]; [st removeLastObject];
                                    if (ivC && [c isKindOfClass:ivC]) {
                                        NSString *bb = MKGetCachedBid((SBIconView *)c);
                                        if (bb.length && sHiddenBids && [sHiddenBids containsObject:bb]) {
                                            UIView *ll = MKGetCachedLabel((SBIconView *)c);
                                            if (ll && !ll.hidden) { ll.hidden = YES; ll.alpha = 0.0f; ll.layer.opacity = 0.0f; ll.opaque = NO; MKAssocLabelBid(ll, bb); }
                                            NSMutableArray *ls = [NSMutableArray arrayWithArray:(NSArray *)[c subviews]];
                                            while (ls.count > 0) {
                                                UIView *s2 = [ls lastObject]; [ls removeLastObject];
                                                BOOL isL = [s2 isKindOfClass:[UILabel class]] || ([NSStringFromClass([s2 class]) rangeOfString:@"Label"].location != NSNotFound);
                                                if (isL && !s2.hidden && s2.alpha > 0.0f) { s2.hidden = YES; s2.alpha = 0.0f; s2.layer.opacity = 0.0f; s2.opaque = NO; MKAssocLabelBid(s2, bb); }
                                                [ls addObjectsFromArray:s2.subviews];
                                            }
                                        }
                                    }
                                    [st addObjectsFromArray:c.subviews];
                                }
                            }
                        });
                    });
                }
            });
            dispatch_resume(sFolderCloseGuard);
        } else { sFolderClosing = NO; if (sDebugLog) RDLog(@"FOLDER-CLOSE-ARM on=0 (guard-alloc-fail)"); }}

// v2.0.8: 关闭保护提前到「关闭起始」武装（见 MKArmFolderCloseGuard 注释）。
// SBFolderController 是文件夹 VC，-viewWillDisappear: 在关闭动画【起始】(文件夹仍在窗口内、
// 内层 App 图标可见) 即触发；门控 sFolderOpen 仅当确在打开态才武装，避免切 App 等其它 disappear 误触发。
%hook SBFolderController
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (sFolderOpen) {
        if (sDebugLog) RDLog(@"FOLDER-CLOSE-ARM on=1 (vc)");
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
        if (sDebugLog) RDLog(@"FOLDER OPEN: SBFolderView appeared in window");
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
        if (sDebugLog) RDLog(@"FOLDER-CLOSE-ARM on=1");  // v2.0.5 探针 A：确认关文件夹窗口是否真的被置位

        // v1.6.86: 动画关闭瞬间先把所有「有指示器」的图标 label 强制隐藏（含文件夹内层运行 App），
        // 防止系统把 label 复显一帧。与源头级 swizzle 形成双保险，杜绝缩回动画里名称闪现。
        MKSafe(^{
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
                    if (lbl && b.length && sHiddenBids && [sHiddenBids containsObject:b]) {
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
                        if (lbl && b.length && sHiddenBids && [sHiddenBids containsObject:b]) {
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
// v2.0.10: UIView 快照截图探针（定位「截图带名飞回」漏点）。
// 关合缩回动画里 SpringBoard 常用这两个方法给图标拍「此刻长啥样」的快照，
// 截图拍的那刻若名字仍可见 → 快照图里【带着名字】飞回主屏（显示的是 bitmap 不是活 label，
// 完全绕过 setHidden / MkLabelDidMoveToWindowHook / 让步门控 所有拦截）。
// 在两个方法【截图之前】调用 MKSafeSnapshotProbe 扫子树里「该藏却可见」的 label，
// 有即打 SNAP-PRE-NAME（受 sDebugLog 门控）。纯诊断，不改行为（不藏名）。
// 若命中 → v2.0.10+ 真修法：截图前先藏、截图后复原。
%hook UIView

- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)afterUpdates {
    MKSafeSnapshotProbe((UIView *)self);
    return %orig;
}

- (UIView *)resizableSnapshotViewFromRect:(CGRect)rect afterScreenUpdates:(BOOL)afterUpdates withCapInsets:(UIEdgeInsets)capInsets {
    MKSafeSnapshotProbe((UIView *)self);
    return %orig;
}

%end

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
        if (sDebugLog) RDLog(@"PAGE SCROLL: decelerating ended");
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
        if (sDebugLog) RDLog(@"PAGE SCROLL: animation ended");
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
        MKSetForeground(bid, isForeground);

        if (sDebugLog) RDLog(@"SBApp._noteProcess: %@ → isRunning=%d taskState=%d foreground=%d",
              bid, isRunning, taskState, isForeground);

        // FBProcessState.taskState: 2=Running, 3=Suspended → app alive
        // FBProcessState.taskState: 1=NotRunning/Dead → app exited
        // FBProcessState.isRunning: YES → app process exists
        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        // v1.6.31: 仅前台（用户打开/使用中）才进入 running set。
        // 纯后台被 iOS 拉起（日历同步等）foreground=0 → 不进集合 → 不显示指示器。
        // 注意：alive 但后台（用户退回后台的 App）走 else-if(!isRunningNow) 不命中 → 保留在集合（点保留）。
        if (isRunningNow && isForeground) {
            MKAddToRunningSet(bid);
        } else if (!isRunningNow) {
            MKRemoveFromRunningSet(bid);
            isRunningNow = NO;
        }

        // v1.6.85: 记录「最近活动/消息」时间戳，供文件夹图标指示器选代表 App
        MKTouchMsg(bid);
        // v1.5.3: 定向+延迟刷新（替代 MKClearAllIndicators + MKRefreshAllIcons）
        MKOnStateChange(bid, isRunningNow, isForeground);
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
        MKSetForeground(bid, isForeground);

        if (sDebugLog) RDLog(@"SBApp._setInternalProcState: %@ → isRunning=%d taskState=%d foreground=%d",
              bid, isRunning, taskState, isForeground);

        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        // v1.6.31: 仅前台（用户打开/使用中）才进入 running set。
        // 纯后台被 iOS 拉起（日历同步等）foreground=0 → 不进集合 → 不显示指示器。
        // 注意：alive 但后台（用户退回后台的 App）走 else-if(!isRunningNow) 不命中 → 保留在集合（点保留）。
        if (isRunningNow && isForeground) {
            MKAddToRunningSet(bid);
        } else if (!isRunningNow) {
            MKRemoveFromRunningSet(bid);
            isRunningNow = NO;
        }

        // v1.6.85: 记录「最近活动/消息」时间戳，供文件夹图标指示器选代表 App
        MKTouchMsg(bid);
        // v1.5.3: 定向+延迟刷新（替代 MKClearAllIndicators + MKRefreshAllIcons）
        MKOnStateChange(bid, isRunningNow, isForeground);
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

        if (sDebugLog) RDLog(@"SBApp._setActivationState: %@ → state=%d", bid, state);

        MKSetForeground(bid, state == 2);

        BOOL isRunningNow = (state >= 1);
        // v1.6.31: 仅前台（state==2）才进入 running set；纯后台（state==1）不进。
        if (isRunningNow && state == 2) {
            MKAddToRunningSet(bid);
        } else if (!isRunningNow) {
            MKRemoveFromRunningSet(bid);
            isRunningNow = NO;
        }

        // v1.6.85: 记录「最近活动/消息」时间戳，供文件夹图标指示器选代表 App
        MKTouchMsg(bid);
        // v1.5.3: 定向+延迟刷新（替代 MKClearAllIndicators + MKRefreshAllIcons）
        BOOL isFg = (state == 2);
        MKOnStateChange(bid, isRunningNow, isFg);
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
        if (sDebugLog) RDLog(@"FOLDER-REFRESH: found %ld folder icon(s)", (long)total);
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
    MKUpdateDebugFlag(); // v1.6.26: 读取调试开关（默认 NO，生产安静）

    NSLog(@"[RunningDotIndicator] v1.6.30 ctor: 1.6.1 baseline + dominant-color icon mode + fix icon capture (snapshot full-size) + remove respring + 2026 glass settings UI + settings list icon + Depends mobilesubstrate (reverted ellekit) + v1.6.26 perf: coalesce folder/scroll refresh (drop redundant SBFolderController/SBIconListPageView hooks, 0.4s open-dedupe, single 300ms pass); keep indicator across off-screen (no destroy/recreate on scroll); icon-color miss one-shot retry; v1.6.28 relaxed iOS guard (block iOS 15 and lower only) + layoutSubviews orphan self-heal (fix 'indicator vanishes, reappears after swipe'); v1.6.29 debug-log toggle moved to settings UI (PSSwitchCell key=debugLog, live via prefs callback; rd_debug file kept as fallback); v1.6.30 blacklisted apps (incl. jailbreak tools with home-screen icons like Sileo/Dopamine/Filza) skip MKOnStateChange entirely -> no name fade-out, name stays visible");
    RDLog(@"======== RDBUILD v2.0.16 (CREATION-POINT INTERCEPT + GEOMETRIC FALLBACK; prior v2.0.6 was RESIDUAL-FLASH FIX — v2.0.5 diagnostic build proved sFolderClosing DOES arm and the cached label is always hidden at every 0.016s sample, so the point-4 flash is a sub-16ms frame at the shrink-animation settle (icon snaps back to grid) that lands AFTER the old 0.8s guard window; v2.0.6 fixes it by (a) guard interval 0.016s->0.010s and length 50->150 ticks (~1.5s) to cover the settle, (b) guard label hunt now a full-subtree BFS that force-hides + re-associates any freshly-created nested visible label, (c) one-shot 0.4s delayed full-window-tree scan after the guard ends to nail the settle re-show; probes FOLDER-CLOSE-ARM + FOLDER-CLOSE-VISIBLE retained for confirmation; v2.0.3: NEW folder-close fix - label holds a hierarchy-independent direct pointer to its SBIconView (kMKLabelIconKey) so MKLabelToBid resolves bid even when iOS reparents/recreates the label during the shrink animation; sFolderCloseGuard now per-frame (0.016s, ~0.8s) instead of 0.05s x10; unlock fallback timer routed through MKUnlockRestore for consistent fade-in; v2.0.1: BUILD-FIX — MKRefreshAllIcons forward declaration moved from 531 to before MKUnlockRestore (323) because the 334 call created an implicit non-static decl under clang -Werror implicit-function-declaration; v2.0.0: FIRST CLEAN RELEASE — removed all RDBREAD runtime breadcrumb logs (the 7 debug RDLog calls buried in dispatch_once init blocks + the unlock-timer fired log) so the tweak no longer prints crash-tracing breadcrumbs; this is the stable release after the 1.6.x dev/debug series; v1.6.99: FIX swipe-page name-dropout + harden folder-close flash; (A) MKGetCachedBid recycle branch now clears the stale kMKLabelBidKey on the old label so a recycled SBIconView cannot leak a previous running-app's bid onto a new non-running app's label -> setHidden: no longer mis-hides it (the 'app name randomly vanishes while swiping pages' bug); (B) MKSetHiddenHook/MKSetAlphaHook now write the bid back onto the label's own kMKLabelBidKey on every forced-hide, so the 'this label belongs to a hidable bid' mark self-sustains through folder-close shrink animation reparenting where MKLabelToBid's sibling/ancestor fallback lookup transiently fails for one frame -> kills the residual in-folder app name flash at end of folder close (point 4); v1.6.98: SBIconView didMoveToWindow(nil) keeps in-folder app label hidden while app still running-in-background, not only when indicator object exists -> kills in-folder app name flash at end of folder-close shrink (point 4); v1.6.97: label swizzle now hooks ONLY override classes + superclass-chain orig lookup + @try around orig()/unlock-timer; kills unlock safe-mode from corrupted orig map; source-level label hook (SBIconListLabel setHidden:/setAlpha: swizzle) supersedes layoutSubviews alpha=0 -> kills name+dot overlap race AND folder-close name flash; folder-icon indicator now prefers latest-msg app (MKTouchMsg+MKFolderChosenBid); previous: proactive label-hide in SBIconView layoutSubviews: unconditionally hide icon name when this bid has an indicator, placed right after %%orig before any branch/return, closing the race window that caused occasional name+dot overlap; v1.6.83 label-overlap fix: scroll-layout keeps any indicator-bearing icon's label hidden via indicator-present check, covering folder-container icons whose bid is not an app; SBIconView didMoveToWindow(nil) no longer restores label while an indicator exists, killing the in-folder app name flash on folder close; v1.6.81 perf: folder/scroll refresh coalesced; indicator reused across off-screen; icon-color miss self-heals next runloop; relaxed iOS guard: block <iOS16 only; layoutSubviews orphan self-heal; debug log toggleable in Settings UI live via prefs callback, rd_debug kept as fallback; v1.6.31 blacklisted apps skip state-change -> name never fades; running-set now gated on foreground (pure-background iOS launches like Calendar sync no longer show indicator); MKGetCachedBid + refresh loops use static Class lookups; folder-open now refreshes async to prevent label-overlap; v1.6.54 MKFindLabelView Strategy2 geometry-pins label (horizontal-center + below-icon) to fix folder overlap + WeChat/Phone no-label; fallback now hosts on list-view via convertRect so dot is never clipped; v1.6.83 folder refresh-storm fix: FICON branch skips expensive recompute when sFolderContentGen unchanged (reuse kMKFIconGenKey), cheap reposition only); v1.6.90 CRASH-FIX: MKInstallLabelHook delayed-init dispatch_once now uses class_isSubclassOfClass() C runtime call instead of [sub isSubclassOfClass:c] selector send -> removes the ___forwarding___ hard-trap (SIGTRAP) safe-mode that fired ~15s after every reboot during delayed init (proven via rd_log(44) breadcrumb: last line before death was RDBREAD: once MKInstallLabelHook) ========");

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
                        if (sDebugLog) RDLog(@"FOLDER-WATCHDOG(active): reset sFolderOpen=NO");
                    }
                }
                if (!sLocked) return;   // 非锁屏态（如普通切 App 回前台），不动
                sLocked = NO;
                // v2.0.1: 解锁用「延迟淡入复原」替代立即全量重建（见 MKUnlockRestore 注释）。
                // 等解锁动画结束后指示器随锁屏消散柔和浮现，避免动画进行中硬跳出。
                MKUnlockRestore();
                if (sDebugLog) RDLog(@"UNLOCK(active): scheduled fade-in restore");
            } @catch (NSException *e) {}
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
                RDLog(@"EXIT NOTE: %@ bid=%@", nm, bid ?: @"(nil)");
                if (!bid) return;
                MKRemoveFromRunningSet(bid);
                if (sInitDone) MKOnStateChange(bid, NO, NO);
            } @catch (NSException *e) {
                RDLog(@"EXIT NOTE exception: %@", e.reason);
            }
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }

    RDLog(@"======== ctor done (heavy work pending) ========");

    // ─── 延迟 15 秒执行重量级初始化 ──────────
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        MKSafe(^{ MKDelayedInit(); });
    });

    // ─── 无定时器：_setInternalProcessState hook 已实时检测所有状态变化 ──
    // v1.4.4~v1.4.6 曾用8秒定时器做补充扫描，但 hook 已完全覆盖所有 App 启动/退出
}
