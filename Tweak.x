//
//  Tweak.x — RunningDotIndicator v1.6.28
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

// ─── MKSBIconViewClass 前向声明（定义见刷新辅助区，MKCachedIconColorForBundleID 先调用）──
static Class MKSBIconViewClass(void);

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
static char kMKIndicatorKey;
static char kMKLabelKey;     // 缓存的名字标签视图
static char kMKBidKey;       // 缓存的 bundleID
static char kMKIconKey;      // 缓存的 icon 指针（检测视图回收复用）
static char kMKPendBidKey;  // v1.6.37: "待定 bid"（去抖：疑似回收时先记一笔，确认连续 2 次才采用）
static char kMKBidOfIndicatorKey; // v1.6.39: bundleID associated onto the indicator view (stale detection / logging)
static char kMKTransitKey;  // v1.6.42: recycle-settle counter (NSNumber) for MKSlotTransitioning
static char kMKBidTransitionCountKey; // v1.6.44: bid 变化后稳定帧计数器（applicationBundleID 滞后于视觉）

// v1.6.39: own the indicator by bundleID, NOT by SBIconView instance.
// Root cause: iOS recycles SBIconView instances (same object re-shows a different app
//   during scroll / page-swipe). The old model attached the indicator to the instance,
//   so the dot rode the recycled instance onto another app's icon ("runs around").
// New model: each running bid keeps ONE indicator view in sIndicatorByBid.
//   Every MKUpdate/layoutSubviews just re-parents that one view onto whatever
//   view currently shows the bid. When a view is recycled to another bid we only
//   DETACH the old bid's indicator from that slot (keep it alive); it re-attaches
//   when the correct view shows up -> no hopping, no rebuild.
static NSMutableDictionary<NSString*, UIView*> *sIndicatorByBid = nil;

static UIView *MKIndicatorForBid(NSString *bid) {
    if (!bid || !sIndicatorByBid) return nil;
    return sIndicatorByBid[bid];
}
// Only destroy on a REAL exit (bid removed from running set); scroll/recycle only detaches.
static void MKDestroyIndicatorForBid(NSString *bid) {
    if (!bid || !sIndicatorByBid) return;
    UIView *ind = sIndicatorByBid[bid];
    if (ind) [ind removeFromSuperview];
    [sIndicatorByBid removeObjectForKey:bid];
    // stale kMKIndicatorKey caches on views self-heal via the stale check in MKUpdate/layoutSubviews
}

static UIView *MKGetIndicator(SBIconView *iv) {
    return objc_getAssociatedObject(iv, &kMKIndicatorKey);
}
static void MKSetIndicator(SBIconView *iv, UIView *dot) {
    objc_setAssociatedObject(iv, &kMKIndicatorKey, dot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// v1.6.42: recycle/scroll transition guard (fixes "indicator hops to wrong icon on scroll").
// Root cause: the indicator is a subview of the recyclable SBIconView slot. During scroll,
// iOS reuses a slot's SBIconView instance to display a DIFFERENT app; because
// [iv icon].applicationBundleID is unreliable during the swap (returns the OLD bid for the
// frames where the slot already shows the new app), MKUpdate keeps gluing the old app's
// indicator onto the slot now displaying a different app -> the dot "hops". The per-bid
// registry (v1.6.39) fixed churn/persistence but NOT this visual ride-along.
// Fix: detect the recycle via the ICON OBJECT POINTER. The visual content is derived from
// the same object, so they change together -- unlike applicationBundleID. When the pointer
// changes we HIDE this slot's indicator and suppress show/create until the pointer is stable
// for MK_TRANSIT_FRAMES consecutive layout passes; then MKUpdate re-attaches the correct
// indicator (per-bid registry) to the settled slot. No churn, no hop.
static const NSInteger MK_TRANSIT_FRAMES = 2;
static const NSInteger MK_BID_SETTLE_FRAMES = 5; // v1.6.44: bid 变化后需稳定这么多帧才信任（应用 id 滞后于视觉）
static BOOL MKSlotTransitioning(SBIconView *self) {
    id cur = [self icon];
    if (!cur) return NO;
    id last = objc_getAssociatedObject(self, &kMKIconKey);
    if (last && last != cur) {
        // icon object swapped this pass -> slot is being recycled to another app.
        UIView *ind = MKGetIndicator(self);
        if (ind) ind.hidden = YES;
        objc_setAssociatedObject(self, &kMKTransitKey, @(MK_TRANSIT_FRAMES), OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(self, &kMKBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kMKIconKey, cur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    objc_setAssociatedObject(self, &kMKIconKey, cur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSInteger t = [objc_getAssociatedObject(self, &kMKTransitKey) integerValue];
    if (t > 0) {
        t -= 1;
        objc_setAssociatedObject(self, &kMKTransitKey, @(t), OBJC_ASSOCIATION_COPY_NONATOMIC);
        UIView *ind = MKGetIndicator(self);
        if (ind) ind.hidden = YES;
        return YES;
    }
    return NO;
}


// 前向声明（MKFindLabelView 定义在后面，但 MKGetCachedLabel 需要调用它）
static UIView *MKFindLabelView(SBIconView *iconView);
// 前向声明（取色 miss 重试时需要调用）
static void MKRefreshIconForBundleID(NSString *bid);
// 前向声明（miss 重试的 dispatch 块内需要判断运行状态）
static BOOL MKIsAppRunning(NSString *bundleID);
static BOOL MKIsForeground(NSString *bid);

// 缓存 bundleID（避免每次 layoutSubviews 都调 applicationBundleID）
// v1.5.4: 检测 icon 变化（SBIconView 回收复用）+ 过滤文件夹图标
static NSString *MKGetCachedBid(SBIconView *iv) {
    id icon = [iv icon];
    if (!icon) return nil;

// 检测图标是否"真的"变了（SBIconView 回收复用：同一个 view 可能从 App A 变成文件夹）
    // v1.6.40: 已移除 v1.6.37 的"待定 bid 去抖" —— 去抖让回收瞬间仍返回旧 bid，
    //   致 layoutSubviews（无过渡守卫）把旧 App 指示器 reposition 到已变成别的 App 的槽位（"翻页粘到别的图标"）。
    //   现在指示器按 bundleID 持有、回收只 detach 不重建，瞬时翻转代价极小，故直接采用真实新 bid。
    //   根因：iOS 的 SBIconView.icon 在布局/滚动/角标刷新等过渡期，会**瞬时返回别的 App 的 icon 对象**
    //     （指针不同 + applicationBundleID 返回别的 bid）。旧逻辑（含 v1.6.35 的纯 bid 比较）把这种瞬时翻转
    //     误判成"duti 变成别的 App" → removeFromSuperview + MKSetIndicator(iv,nil)
    //     → 下一轮 MKUpdate 发现 !indicator → 重建 Indicator CREATE(animate=0)。
    //   这就是 rd_log(66) 里 79/92 次 recreate、全 App 周期批量重建的抖动（问题①），也是 FALLBACK（问题②）的间接来源
    //     （指示器先被误杀、再建于 label 还没挂上的瞬间 → 落 fallback）。
    //   去抖：本轮看到与旧 bid 不同的 newBid 时，**只记为"待定 bid"并仍返回旧 bid**，
    //     让 MKUpdate 这一瞬按稳定 bid 操作（保留指示器）；只有 newBid 连续 2 次出现才确认是真回收，
    //     采用新 bid 并清标签缓存。对"仍在运行 App"的瞬时翻转**零误杀**。
    //   真回收的指示器清理不在此处做 —— 采用新 bid 后，MKUpdate 的 !running 分支会按新 bid 自然清理
    //     （新 bid 若不在运行集则移除；若仍在运行则该视图本就属于新 App，指示器跟随即可），行为正确且无 churn。
    NSString *oldBid = objc_getAssociatedObject(iv, &kMKBidKey);
    NSString *newBid = nil;
    if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        newBid = [icon applicationBundleID];
    }
    // 更新缓存的 icon 指针（仅记录，供下一轮比较；此处绝不触发任何指示器清除）
    objc_setAssociatedObject(iv, &kMKIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // v1.6.40 / v1.6.44: 去抖与 bid-settle。
    //   v1.6.37 的"待定 bid 去抖"在回收瞬间仍返回旧 bid，导致 layoutSubviews 把旧 App
    //   指示器 reposition 到已变成别的 App 的槽位；v1.6.40 去掉它，直接采用真实新 bid。
    //   但 v1.6.43 实测仍发现 applicationBundleID 滞后于视觉（回收槽仍报旧 bid 几帧），
    //   因此 v1.6.44 引入 bid-settle：bid 变化后先返回 nil 若干帧，等连续稳定后再返回真实新 bid。
    //   这样 MKUpdate 在 settle 期间直接跳过，不会把旧 App 指示器挂到错误槽位。
    // v1.6.44: bid 变化后不能立即信任 —— applicationBundleID 在回收/翻页时可能滞后于视觉。
    //   在 settle 期间返回 nil，让 MKUpdate 跳过（不显示/不创建/不重父化），避免把旧 App 指示器粘到错误槽位。
    if (oldBid && newBid && ![oldBid isEqualToString:newBid]) {
        objc_setAssociatedObject(iv, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(iv, &kMKBidTransitionCountKey, @(MK_BID_SETTLE_FRAMES), OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(iv, &kMKBidKey, newBid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }

    NSInteger settleCount = [objc_getAssociatedObject(iv, &kMKBidTransitionCountKey) integerValue];
    if (settleCount > 0) {
        settleCount--;
        objc_setAssociatedObject(iv, &kMKBidTransitionCountKey, @(settleCount), OBJC_ASSOCIATION_COPY_NONATOMIC);
        return nil;
    }

    // v1.6.40: 去掉 v1.6.37 的"待定 bid 去抖"（已由 v1.6.44 bid-settle 取代）。
    //   这里只处理 newBid 为 nil 时的 fallback。
    NSString *resolved = newBid ? newBid : oldBid;
    objc_setAssociatedObject(iv, &kMKPendBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // v1.6.40: 不再有待定状态
    objc_setAssociatedObject(iv, &kMKBidKey, resolved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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
    if (label) objc_setAssociatedObject(iv, &kMKLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return label;
}

// ─── 状态去重：同一个 bundleID 的 (running, foreground) 没变就不刷新 ──
static NSMutableDictionary<NSString*, NSDictionary*> *sLastState = nil;

// v1.6.34: 标签未找到时的"延迟重试"去重集合（每个 bid 仅重试一次，防无限重试）
// v1.6.35: 标签重试计数（取代 v1.6.34 的 sLabelRetryBids 单次布尔）。
// 同一 bid 最多重试 N 次、延迟递增，捕获 App 退到后台后 1~2s 才挂上的标签视图。
static NSMutableDictionary<NSString*, NSNumber*> *sLabelRetryCount = nil;
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
static BOOL  sDebugLog = NO;
static void MKUpdateDebugFlag(void) {
    MKConfig *cfg = [MKConfig sharedConfig];
    sDebugLog = cfg ? [cfg debugLog] : NO;
}
// 文件夹打开/滚动刷新合并：避免同一事件多次触发全量刷新
static BOOL  sFolderRefreshScheduled = NO;   // 文件夹刷新是否已排程（300ms 内只排一次）
static NSTimeInterval sLastFolderOpenTS = 0; // 上次文件夹打开时间戳（0.4s 内去重）
static BOOL  sScrollRefreshScheduled = NO;   // 滚动刷新是否已排程（120ms 内只排一次）

static BOOL sScrolling = NO;        // v1.6.43: 滚动进行中 -> 隐藏所有指示器（不显示/不创建），滚动停后由 MKRefreshSubviews 重显
static dispatch_block_t sScrollStopBlock; // v1.6.43: 滚动心跳 -> 末次 scroll 事件后 200ms 清 sScrolling 并重刷（静态默认零初始化即 nil）

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
        // ── Strategy 1: SBIconView accessor 方法（iOS 16 运行时头文件）──
        // SBIconView 有 labelView / listLabelView → SBIconListLabel
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

        // ── Strategy 2: 父视图兄弟节点（iOS 16 核心！标签是 SBIconView 的兄弟）──
        // SBIconView 和 SBIconListLabel 是同一个父容器的子视图
        // v1.6.33: 移除 <=8 子视图限制，文件夹/Dock 等布局里父容器可能更大；
        // 靠评分阈值（>=50）和 SBIconListLabel 精确匹配避免误把 badge/close button 当标签。
        UIView *parent = iconView.superview;
        if (parent) {
            // 用评分机制避免误把 badge/close button 等当标签
            UIView *bestMatch = nil;
            NSInteger bestScore = 0;
            for (UIView *sv in parent.subviews) {
                if (sv == iconView) continue;  // 跳过自己
                NSString *cls = NSStringFromClass([sv class]);
                NSInteger score = 0;
                if ([cls isEqualToString:@"SBIconListLabel"])        score = 100;
                else if ([cls containsString:@"IconListLabel"])      score = 90;
                else if ([cls containsString:@"ListLabel"])          score = 80;
                else if ([cls containsString:@"IconLabel"])          score = 70;
                else if ([sv isKindOfClass:[UILabel class]])          score = 60;
                else if ([cls containsString:@"LabelView"])           score = 50;
                else if ([cls containsString:@"Label"])              score = 40;
                if (score > bestScore) {
                    bestScore = score;
                    bestMatch = sv;
                }
            }
            if (bestMatch && bestScore >= 50) {
                return bestMatch;
            }
        }

        // ── Strategy 3: 直接子视图搜索 ──
        for (UIView *sv in iconView.subviews) {
            NSString *cls = NSStringFromClass([sv class]);
            if ([sv isKindOfClass:[UILabel class]] ||
                [cls containsString:@"IconLabel"] ||
                [cls containsString:@"Label"]) {
                return sv;
            }
        }

        // ── Strategy 4: 递归子视图搜索 ──
        // v1.6.33: 增加 containsString:@"Label" 兜底，捕获 SBIconLabel 等无 View/List/Title 字样的标签类。
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
                [cls containsString:@"TextLabel"] ||
                [cls containsString:@"Label"]) {
                return v;
            }
            [stack addObjectsFromArray:v.subviews];
        }

        // ── 诊断：标签未找到 → dump iconView + 父视图层级 ──
        static int sNoLabelLogs = 0;
        if (sNoLabelLogs < 60) {  // v1.6.34: 放宽上限，便于下次日志直接看到受影响 App 的视图层级（标签类名为何偶发查不到）
            sNoLabelLogs++;
            NSMutableString *dump = [NSMutableString stringWithFormat:@"NO LABEL — %@ direct:[", NSStringFromClass([iconView class])];
            for (UIView *sv in iconView.subviews) {
                [dump appendFormat:@" %@", NSStringFromClass([sv class])];
            }
            [dump appendString:@"]"];
            UIView *parent = iconView.superview;
            if (parent) {
                [dump appendFormat:@" parent(%@, %lu kids):[", NSStringFromClass([parent class]), (unsigned long)parent.subviews.count];
                for (UIView *sv in parent.subviews) {
                    [dump appendFormat:@" %@(y=%.0f,h=%.0f)", NSStringFromClass([sv class]), sv.frame.origin.y, sv.frame.size.height];
                }
                [dump appendString:@"]"];
            }
            RDLog(@"%@", dump);
        }

    } @catch (NSException *e) {
        RDLog(@"MKFindLabelView exception: %@", e.reason);
    }
    return nil;
}

// ====================================================================
// 主更新函数 — v1.5.1：标签找到→指示器在标签位置，标签未找到→图标底部边缘（不遮挡）
// ====================================================================

// v1.6.41: 无标签时的「估算标签位置」——Dock 专用收紧。
//   Dock 图标（SBDockIconListView 内）没有名称标签，旧兜底把指示器放在图标底 +8pt 左右，
//   看着像悬空在 Dock 下方一截；改成紧贴图标底（≈ App 名称实际位置）。
//   普通图标（名称标签偶发找不到时）沿用旧逻辑（+4pt 间隙、14pt 标签高）。
static CGRect MKEstimateLabelFrame(SBIconView *iconView) {
    UIView *sup = iconView.superview ? iconView.superview : (UIView *)iconView;
    CGRect f = iconView.frame;
    BOOL inDock = [NSStringFromClass([sup class]) containsString:@"Dock"];
    CGFloat iconBottom = f.origin.y + f.size.height;
    CGFloat gap    = inDock ? 4.0f : 4.0f;    // Dock 名称紧贴图标（与旧逻辑一致）
    CGFloat labelH = inDock ? 12.0f : 14.0f;  // Dock 名称更矮，居中后整体更贴图标
    CGFloat labelY = iconBottom + gap;
    return CGRectMake(f.origin.x, labelY, f.size.width, labelH);
}

static void MKUpdate(SBIconView *self) {
    MKSafe(^{
        if (!sInitDone) return;

        // v1.6.42: while this slot is mid-recycle (icon object swapped during scroll),
        // hide its indicator and skip show/create; the per-bid registry re-attaches
        // the correct indicator once the slot settles on its new app.
        if (MKSlotTransitioning(self)) return;

        // v1.6.43: 滚动进行中 -> 隐藏本槽指示器、不显示/不创建；滚动停后统一重刷。
        //   结构根治「翻页粘到别的图标」：滚动时啥都不显示，自然谈不上粘错。
        if (sScrolling) {
            UIView *ind = MKGetIndicator(self);
            if (ind) ind.hidden = YES;
            return;
        }

        sCallCount++;

        NSString *bundleID = MKGetCachedBid(self);
        if (!bundleID || bundleID.length == 0) return;

        // v1.6.39: grab both "indicator cached on this slot" and "indicator this bid SHOULD have".
        //   If they differ, the cache belongs to a previously-recycled bid -> detach from our slot, don't destroy.
        UIView *label = MKGetCachedLabel(self);
        UIView *hostView = label ? label.superview : (self.superview ? self.superview : self);
        UIView *cachedInd = MKGetIndicator(self);
        UIView *bidInd     = MKIndicatorForBid(bundleID);
        if (cachedInd && cachedInd != bidInd) {
            if (cachedInd.superview == hostView) [cachedInd removeFromSuperview];
            MKSetIndicator(self, nil);
            cachedInd = nil;
        }
        UIView *indicator = (bidInd ? bidInd : cachedInd);

        // v1.6.38: icon recycle / reuse transition guard -- kills the "mis-attributed flash".
        //   During the transition we only HIDE whatever is in our slot, don't create/show, return;
        //   (v1.6.39: once the bid settles, below re-parents correctly, never onto the wrong app.)
        BOOL bidTransitioning = (objc_getAssociatedObject(self, &kMKPendBidKey) != nil);
        if (bidTransitioning) {
            if (indicator) indicator.hidden = YES;
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (MKIsDisabled() || !cfg || !cfg.enabled) {
            if (indicator) {
                if (indicator.superview == hostView) [indicator removeFromSuperview];
                MKSetIndicator(self, nil);
            }
            if (label) { label.hidden = NO; label.alpha = 1.0f; label.layer.opacity = 1.0f; label.opaque = YES; }
            return;
        }

        BOOL running     = MKIsAppRunning(bundleID);
        BOOL isForeground = MKIsForeground(bundleID);
        BOOL isPending   = MKIsPending(bundleID);
        BOOL isFading   = MKIsFadingLabel(bundleID);

        if (label) {
            if (!sLabelRetryCount) sLabelRetryCount = [NSMutableDictionary dictionary];
            [sLabelRetryCount removeObjectForKey:bundleID];
        }

        // ---- current bid should NOT show in our slot -> just detach (real exit handled by MKDestroyIndicatorForBid) ----
        if (!running || isForeground || isFading || isPending) {
            if (indicator) {
                if (!running) {
                    if (indicator.superview == hostView) [indicator removeFromSuperview];
                    MKSetIndicator(self, nil);
                } else {
                    indicator.hidden = YES; // foreground / fading / pending: keep attached, just hide; reappears when backgrounded
                }
            }
            if (label) { label.hidden = NO; label.alpha = 1.0f; label.layer.opacity = 1.0f; label.opaque = YES; }
            if (!running) { MKRemovePending(bundleID); MKRemoveFadingLabel(bundleID); }
            return;
        }

        // ---- running (background) -> show THIS bid's indicator, re-parented into our slot ----
        RDLogRunning(bundleID);
        if (label) { label.hidden = YES; label.alpha = 0.0f; label.layer.opacity = 0.0f; label.opaque = NO; }
        else { if (sDebugLog) RDLog(@"NO LABEL for running app: %@", bundleID); }

        CGFloat indicatorW, indicatorH;
        if (cfg.shape == MKShapeDot) { indicatorW = cfg.dotSize; indicatorH = cfg.dotSize; }
        else { indicatorW = cfg.barWidth; indicatorH = cfg.barHeight; }

        CGRect labelFrameInHost;
        if (label && label.superview) {
            labelFrameInHost = label.frame;
        } else if (self.superview) {
            labelFrameInHost = MKEstimateLabelFrame((SBIconView *)self);
        } else {
            CGSize s = self.bounds.size;
            if (s.width < 10 || s.height < 10) return;
            labelFrameInHost = CGRectMake(0, s.height - 16.0f, s.width, 14.0f);
        }
        CGRect indicatorFrame = CGRectMake(
            labelFrameInHost.origin.x + (labelFrameInHost.size.width - indicatorW) / 2.0f,
            labelFrameInHost.origin.y + (labelFrameInHost.size.height - indicatorH) / 2.0f,
            indicatorW, indicatorH);

        if (!indicator) {
            // v1.6.39: create ONCE per bid, store in sIndicatorByBid; afterwards only re-parent -> zero rebuild/churn.
            if (!sIndicatorByBid) sIndicatorByBid = [NSMutableDictionary dictionary];
            indicator = [[MKIndicatorDotView alloc] initWithFrame:indicatorFrame];
            indicator.tag = kDotTag;
            [(MKIndicatorDotView *)indicator applyConfig];
            if (cfg.colorMode == MKColorModeAutoIcon) {
                UIColor *iconColor = MKCachedIconColorForBundleID(bundleID);
                [(MKIndicatorDotView *)indicator setIndicatorColor:iconColor];
                [indicator setNeedsDisplay];
            }
            BOOL shouldAnimate = MKShouldAnimateIndicator(bundleID);
            MKRemoveAnimateIndicator(bundleID);
            if (sDebugLog) RDLog(@"Indicator CREATE: %@ shape=%d animate=%d label=%@",
                  bundleID, (int)cfg.shape, shouldAnimate, label ? @"YES" : @"NO(FALLBACK)");
            [sIndicatorByBid setObject:indicator forKey:bundleID];
            objc_setAssociatedObject(indicator, &kMKBidOfIndicatorKey, bundleID, OBJC_ASSOCIATION_COPY_NONATOMIC);
            MKSetIndicator(self, indicator);
            if (shouldAnimate) {
                indicator.alpha = 0.0f;
                [hostView addSubview:indicator];
                CGFloat finalAlpha = cfg.opacity;
                if (sDebugLog) RDLog(@"Indicator FADE-IN: %@ alpha 0->%.2f", bundleID, finalAlpha);
                [UIView animateWithDuration:0.2 animations:^{ indicator.alpha = finalAlpha; }];
            } else {
                [hostView addSubview:indicator];
            }
        } else {
            // v1.6.39: already exists (same single indicator for this bid) -> only re-parent + reposition, no rebuild, no re-animate.
            if (indicator.superview != hostView) {
                [hostView addSubview:indicator]; // auto-detaches from the old slot
                if (sDebugLog) RDLog(@"Indicator REPARENT: %@ -> new slot", bundleID);
            }
            indicator.frame = indicatorFrame;
            indicator.hidden = NO;
            MKSetIndicator(self, indicator);
        }

        if (cfg.colorMode == MKColorModeAutoIcon && indicator) {
            UIColor *iconColor = MKCachedIconColorForBundleID(bundleID);
            MKIndicatorDotView *dot = (MKIndicatorDotView *)indicator;
            UIColor *cur = dot.indicatorColor;
            if (!cur || !CGColorEqualToColor(cur.CGColor, iconColor.CGColor)) {
                [dot setIndicatorColor:iconColor];
                [indicator setNeedsDisplay];
            }
        }

        if (!label) {
            if (!sLabelRetryCount) sLabelRetryCount = [NSMutableDictionary dictionary];
            NSInteger tries = [sLabelRetryCount[bundleID] integerValue];
            if (tries < 4) {
                sLabelRetryCount[bundleID] = @(tries + 1);
                NSArray *delays = @[@200, @600, @1200, @2000];
                NSInteger d = [delays[MIN(tries, 3)] integerValue];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_MSEC)),
                               dispatch_get_main_queue(), ^{
                    if (MKIsAppRunning(bundleID) && !MKIsForeground(bundleID)) {
                        MKUpdate(self);
                    } else {
                        [sLabelRetryCount removeObjectForKey:bundleID];
                    }
                });
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
        while (stack.count > 0) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            if ([v isKindOfClass:MKSBIconViewClass()]) {
                MKUpdate((SBIconView *)v);
                refreshed++;
            }
            [stack addObjectsFromArray:v.subviews];
        }
        if (refreshed > 0 && sDebugLog) {
            RDLog(@"FOLDER REFRESH: refreshed %d icons inside container", refreshed);
        }
    });
}

// ====================================================================
// 刷新所有图标
// ====================================================================

static void MKRefreshAllIcons() {
    MKSafe(^{
        if (!sInitDone) return;
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

// v1.6.44: 统一的滚动开始检测入口。SBIconScrollView 的 delegate 钩子不一定被 SpringBoard 调到，
//   因此也 hook setContentOffset: 系列，确保任何滚动/动画偏移都能置 sScrolling=YES。
//   300ms 心跳：末次偏移事件后 300ms 清 sScrolling 并刷新图标。
static void MKSetScrollingFlag(UIView *scrollView) {
    if (!sInitDone) return;
    BOOL wasScrolling = sScrolling;
    sScrolling = YES;
    if (sDebugLog && !wasScrolling) RDLog(@"PAGE SCROLL: scrolling started");
    if (sScrollStopBlock) dispatch_block_cancel(sScrollStopBlock);
    sScrollStopBlock = dispatch_block_create(0, ^{
        if (sDebugLog) RDLog(@"PAGE SCROLL: scrolling stopped (300ms idle)");
        sScrolling = NO;
        MKRefreshSubviews(scrollView);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), sScrollStopBlock);
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
        // v1.6.39: App exited -> destroy the indicator for real (scroll/recycle only detaches)
        MKDestroyIndicatorForBid(bid);
        MKRemovePending(bid);     // clear pending state
        MKRemoveFadingLabel(bid); // v1.5.8: 清除渐隐状态
        dispatch_async(dispatch_get_main_queue(), ^{
            MKRefreshIconForBundleID(bid);
        });
    }
}

// ====================================================================
// v1.6.33: 自愈 —— 定期清除 stale running set 误报（对应问题③）
// 现象：App 被系统杀（内存压力等）但退出通知/状态回调未送达本插件，
//   running set 残留 → 桌面仍显示指示器，但点击 App 是冷启动（需重载）。
// 这是 iOS 进程状态事件可能丢通知的机制限制，无法 100% 杜绝；
// 此自愈作为缓解：周期性用 SBApplicationController.runningApplications 的
//   实时 processState 交叉校验，把"集合里有、但系统已确认进程不在跑"的条目清掉。
// ====================================================================
static void MKScheduleSelfHeal(void);  // 前向声明（递归调度）

static void MKSelfHealRunningSet(void) {
    if (!sInitDone || MKIsDisabled()) return;
    @try {
        id appCtrl = [SBApplicationController sharedInstance];
        if (!appCtrl) return;
        SEL runningSel = NSSelectorFromString(@"runningApplications");
        if (![appCtrl respondsToSelector:runningSel]) return;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *runningApps = [appCtrl performSelector:runningSel];
#pragma clang diagnostic pop
        if (!runningApps) return;

        // 构建"当前确实活着"的 bundleID 集合（用 processState 权威校验，而非仅名单成员）
        NSMutableSet *aliveBids = [NSMutableSet set];
        Class sbAppCls = NSClassFromString(@"SBApplication");
        for (id app in runningApps) {
            if (![app isKindOfClass:sbAppCls]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id ps = [app performSelector:NSSelectorFromString(@"processState")];
            NSString *bid = [app performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
            BOOL alive = YES;
            if (ps) {
                BOOL isRunning = MKGetBoolFromState(ps, @"isRunning");
                int taskState = MKGetIntFromState(ps, @"taskState");
                alive = (isRunning || taskState == 2 || taskState == 3);
            }
            if (bid.length && alive) [aliveBids addObject:bid];
        }

        // 交叉校验：集合里的条目若既不在 alive 集合、又非前台（前台一定活着）→ 视为 stale，清除
        for (NSString *bid in [sRunningSet copy]) {
            if ([aliveBids containsObject:bid]) continue;
            if (MKIsForeground(bid)) continue;     // 前台 App 必然活着，不被误清
            MKSetForeground(bid, NO);              // 同步清前台标记（防退出通知也丢时前台位残留）
            MKRemoveFromRunningSet(bid);
            if (sDebugLog) RDLog(@"SELF-HEAL: removed stale running entry %@", bid);
            MKOnStateChange(bid, NO, NO);         // 刷新图标：移除残留指示器、恢复名字
        }
    } @catch (NSException *e) {
        RDLog(@"SELF-HEAL EXCEPTION: %@", e.reason);
    }
}

// v1.6.33: 每 25 秒递归调度一次自愈（不阻塞、轻量；仅对集合中少数 App 做交叉校验）
static void MKScheduleSelfHeal(void) {
    if (!sInitDone) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MKSelfHealRunningSet();
        MKScheduleSelfHeal();
    });
}

// ====================================================================
// 延迟初始化（15 秒后执行，不阻塞 SpringBoard 启动）
// ====================================================================

static void MKDelayedInit() {
    RDLog(@"DELAYED INIT: starting heavy work...");

    // ─── 步骤 1：系统黑名单 ──────
    MKInitBlacklist();

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

    // v1.6.33: 启动 stale running set 自愈定时器（每 25 秒交叉校验，缓解问题③）
    MKScheduleSelfHeal();
}

static void MKPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    [[MKConfig sharedConfig] reload];
    MKUpdateDebugFlag(); // v1.6.26: 设置变更后刷新调试开关
    MKRefreshAllIcons();
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
            label.hidden = NO;
            label.alpha = 1.0f;
            label.layer.opacity = 1.0f;
            label.opaque = YES;
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
                      MKGetIndicator(self) ? @"YES" : @"NO",
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

    // v1.6.42: same recycle guard as MKUpdate (see MKSlotTransitioning).
    if (MKSlotTransitioning(self)) return;

    // v1.6.43: 同 MKUpdate 的滚动隐藏守卫。
    if (sScrolling) {
        UIView *ind = MKGetIndicator(self);
        if (ind) ind.hidden = YES;
        return;
    }

    // v1.5.3 性能优化：快速跳过不需要处理的图标
    UIView *indicator = MKGetIndicator(self);
    // v1.6.39: stale detection -- after an instance is recycled to another app, the cached
    //   indicator may belong to a different bid. If so, detach it from our slot and clear the
    //   cache; let the logic below re-evaluate for the current bid.
    {
        NSString *lsBid = MKGetCachedBid(self);
        UIView *lsBidInd = (sIndicatorByBid ? sIndicatorByBid[lsBid] : nil);
        if (indicator && indicator != lsBidInd) {
            UIView *host = (self.superview ? self.superview : self);
            if (indicator.superview == host) [indicator removeFromSuperview];
            MKSetIndicator(self, nil);
            indicator = nil;
        }
    }
    if (!indicator || (indicator && indicator.superview == nil)) {
        // v1.6.28: 孤儿自愈 —— 指示器被 SpringBoard 在重布局时从宿主移除
        // （SBIconView 对象仍在，关联对象仍指向这个 superview=nil 的不可见视图）。
        // 若不处理，要等到下次滚动触发 MKUpdate 才发现 superview!=hostView 而重建
        // （表现为「指示器偶尔消失，滑动一下又回来」）。这里在每次布局时立即重建。
        // 无指示器 → 只有运行中的后台 App 才需要创建
        NSString *bid = MKGetCachedBid(self);
        if (!bid || !MKIsAppRunning(bid) || MKIsForeground(bid)) return;

        // v1.5.8: 标签正在渐隐中 → 不干扰动画，等渐隐完成后再处理
        if (MKIsFadingLabel(bid)) return;

        // v1.5.6+: pending 期间只隐藏标签，不创建指示器
        if (MKIsPending(bid)) {
            UIView *label = MKGetCachedLabel(self);
            if (label) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
            }
            return;  // 等待300ms后才创建指示器
        }

        // 运行中的后台 App → 需要 MKUpdate 创建指示器
        MKUpdate(self);
        return;
    }

    // 有指示器 → 先检查是否还应该有（icon 可能变成文件夹或 App 退出了）
    NSString *bid = MKGetCachedBid(self);
    if (!bid || !MKIsAppRunning(bid) || MKIsForeground(bid)) {
        // 不再需要指示器 → 走 MKUpdate 移除
        MKUpdate(self);
        return;
    }


    // v1.5.8: 标签正在渐隐 → 只重定位指示器，不操作标签（让动画自然播放）
    if (MKIsFadingLabel(bid)) {
        UIView *label = MKGetCachedLabel(self);
        if (indicator && label && label.superview) {
            CGRect lf = label.frame;  // v1.6.36: 还原 1.6.31 —— 指示器现挂 label.superview，label.frame 即其同坐标系位置
            CGFloat indW, indH;
            MKConfig *cfg = [MKConfig sharedConfig];
            if (cfg.shape == MKShapeDot) { indW = cfg.dotSize; indH = cfg.dotSize; }
            else { indW = cfg.barWidth; indH = cfg.barHeight; }
            indicator.frame = CGRectMake(
                lf.origin.x + (lf.size.width - indW) / 2.0f,
                lf.origin.y + (lf.size.height - indH) / 2.0f,
                indW, indH);
        }
        return;
    }

    // 仍然需要指示器 → 重新定位 + 重新隐藏标签
    MKConfig *cfg = [MKConfig sharedConfig];
    if (!cfg || !cfg.enabled) return;

    CGFloat indW, indH;
    if (cfg.shape == MKShapeDot) {
        indW = cfg.dotSize;
        indH = cfg.dotSize;
    } else {
        indW = cfg.barWidth;
        indH = cfg.barHeight;
    }

    UIView *label = MKGetCachedLabel(self);
    if (label && label.superview) {
        // 重新强制隐藏标签（防止系统 layout 恢复）
        label.hidden = YES;
        label.alpha = 0.0f;
        label.layer.opacity = 0.0f;
        label.opaque = NO;
        // 标签找到 → 指示器在标签中心
        CGRect lf = label.frame;  // v1.6.36: 还原 1.6.31 —— 指示器现挂 label.superview，label.frame 即其同坐标系位置
        indicator.frame = CGRectMake(
            lf.origin.x + (lf.size.width - indW) / 2.0f,
            lf.origin.y + (lf.size.height - indH) / 2.0f,
            indW, indH
        );
    } else if (self.superview) {
        // v1.6.41: 无标签 → 估算标签位置（Dock 紧贴图标底，≈ App 名称位置）
        CGRect elf = MKEstimateLabelFrame((SBIconView *)self);
        indicator.frame = CGRectMake(
            elf.origin.x + (elf.size.width - indW) / 2.0f,
            elf.origin.y + (elf.size.height - indH) / 2.0f,
            indW, indH
        );
    }
}

%end

// ====================================================================
// v1.6.0: Hook — SBFolderView / SBFolderController
// 文件夹打开时，内部 SBIconView 需要刷新以显示运行指示器
// iOS 16 文件夹内的 App 图标可能在文件夹打开时才出现在视图层级
// 如果 SBFolderView/SBFolderController 类不存在，hook 自动跳过
// ====================================================================

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
        if (sDebugLog) RDLog(@"FOLDER OPEN: SBFolderView appeared in window");
        // v1.6.26: 合并刷新 —— 只排一次 300ms 后的整子树刷新。
        // 旧逻辑：SBFolderView + SBFolderController + SBIconListPageView 三个 hook 各自刷新，
        //   造成同秒多次 FOLDER REFRESH（先 26 图标后又 54 图标），整天累计 16,203 次图标快照。
        // SBFolderView 的整子树下降遍历已覆盖内部所有页面图标，无需再单独 hook 子容器。
        if (!sFolderRefreshScheduled) {
            sFolderRefreshScheduled = YES;
            __strong UIView *target = me;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                sFolderRefreshScheduled = NO;
                MKRefreshSubviews(target);
            });
        }
    } else if (!me.window) {
        if (sDebugLog) RDLog(@"FOLDER CLOSE: SBFolderView removed from window");
    }
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

// v1.6.44: 滚动期间隐藏指示器（根治翻页粘错）。
//   v1.6.43 只 hook scrollView delegate 方法，但实测 SpringBoard paging 时这些 delegate
//   方法未必被调到（指示器在滚动中仍被重父化）。这里同时 hook setContentOffset: 系列，
//   任何内容偏移（拖动/减速/动画）都会置 sScrolling=YES，300ms 心跳后刷新。
- (void)scrollViewWillBeginDragging:(id)scrollView {
    %orig;
    MKSetScrollingFlag((UIView *)self);
}

- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    MKSetScrollingFlag((UIView *)self);
}

- (void)setContentOffset:(CGPoint)offset {
    %orig;
    MKSetScrollingFlag((UIView *)self);
}

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    %orig;
    MKSetScrollingFlag((UIView *)self);
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

    NSLog(@"[RunningDotIndicator] v1.6.44 ctor: scroll + bid-settle guard kills 'indicator hops to wrong icon on scroll' (setContentOffset: hook + 5-frame bid settle); see comments below for full history.");

    // v1.6.37: 根除问题①(churn) + 问题②的瞬时部分。
    //   根因(rd_log(66) 确证)：iOS 的 SBIconView.icon 在布局/滚动/角标刷新等过渡期，会瞬时返回
    //     别的 App 的 icon 对象(指针不同 + applicationBundleID 返回别的 bid)。旧 MKGetCachedBid 的
    //     图标复用检测把这种"duti 变成别的 App"误判 → removeFromSuperview + MKSetIndicator(iv,nil)
    //     → 下一轮 MKUpdate 发现 !indicator → 重建 Indicator CREATE(animate=0)。
    //     rd_log(66) 共 92 次 CREATE、79 次是 animate=0，且 RUNNING SET 仅 +8/-2(运行集稳定)
    //     → 证明不是运行集移除、也不是指针误判(1.6.35 已改 bid 比较仍抖)，而是"瞬时 bid 翻转"误杀。
    //   修复：MKGetCachedBid 用"待定 bid 去抖"——同一新 bid 连续 2 次调用都出现才确认是真回收
    //     (采用新 bid、清标签缓存，随后由 MKUpdate 的 !running 分支按新 bid 自然清理)；
    //     本轮看到不同 newBid 时只记为待定、仍返回旧 bid，让 MKUpdate 按稳定 bid 操作(保留指示器)。
    //     对"仍在运行 App"的瞬时翻转零误杀 → churn 根除。FALLBACK(问题②)的瞬时部分随之消失
    //     (不再因误杀后建于 label 未挂上的瞬间而落 fallback)；仅 Dock 等无独立标签视图的 App
    //     仍有 fallback，属该环境已知限制(标签视图确不在层级中)。

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
