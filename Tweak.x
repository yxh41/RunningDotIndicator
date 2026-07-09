//
//  Tweak.x — RunningDotIndicator v1.5.8
//  v1.5.8: 自然过渡 — 标签渐隐 + 指示器渐显的交叉淡入淡出
//    ✅ 标签不再瞬间消失：前台→后台时 label alpha 1→0 的 250ms 渐隐动画
//    ✅ sFadingLabelBIDs 机制：渐隐期间 layoutSubviews 不干扰动画
//    ✅ 指示器 200ms 渐显 + 标签 250ms 渐隐 → 只约 50ms 空档，在返回动画中不可感知
//    ✅ 退出/前台恢复：渐隐期间 App 变前台或退出 → 立即恢复标签
//  v1.5.4: 修复文件夹图标偶尔出现指示器
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
static char kMKIndicatorKey;
static char kMKLabelKey;     // 缓存的名字标签视图
static char kMKBidKey;       // 缓存的 bundleID
static char kMKIconKey;      // 缓存的 icon 指针（检测视图回收复用）

static UIView *MKGetIndicator(SBIconView *iv) {
    return objc_getAssociatedObject(iv, &kMKIndicatorKey);
}
static void MKSetIndicator(SBIconView *iv, UIView *dot) {
    objc_setAssociatedObject(iv, &kMKIndicatorKey, dot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 前向声明（MKFindLabelView 定义在后面，但 MKGetCachedLabel 需要调用它）
static UIView *MKFindLabelView(SBIconView *iconView);

// 缓存 bundleID（避免每次 layoutSubviews 都调 applicationBundleID）
// v1.5.4: 检测 icon 变化（SBIconView 回收复用）+ 过滤文件夹图标
static NSString *MKGetCachedBid(SBIconView *iv) {
    id icon = [iv icon];
    if (!icon) return nil;

// 检测图标是否变了（SBIconView 回收复用：同一个 view 可能从 App A 变成文件夹）
    id cachedIcon = objc_getAssociatedObject(iv, &kMKIconKey);
    if (cachedIcon && cachedIcon != icon) {
        // icon 变了 → 清除所有缓存 + 移除旧指示器
        objc_setAssociatedObject(iv, &kMKBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(iv, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *oldIndicator = MKGetIndicator(iv);
        if (oldIndicator) { [oldIndicator removeFromSuperview]; MKSetIndicator(iv, nil); }
    }
    objc_setAssociatedObject(iv, &kMKIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 过滤文件夹图标：SBFolderIcon 不是 App 图标，不显示指示器
    NSString *iconCls = NSStringFromClass([icon class]);
    if ([iconCls containsString:@"Folder"]) return nil;

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

// 清除 SBIconView 的所有缓存（didMoveToWindow 时调用，防止 view 回收后缓存过期）
static void MKClearCaches(SBIconView *iv) {
    objc_setAssociatedObject(iv, &kMKLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iv, &kMKBidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iv, &kMKIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
static NSMutableDictionary<NSString*, UIColor*> *sIconColorCache = nil; // v1.5.7: bundleID → 图标平均色缓存

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

// ─── 图标平均色采样 ─── v1.5.7 ───
// 从 App 图标取平均色，用于 AutoIcon 颜色模式
// 方法：尝试 SBIcon/SBIconView accessor 获取图标 UIImage → 渲染到 1x1 位图 → 取像素值
// 加亮度/饱和度调整保证指示器在桌面背景上可见
static UIColor *MKAverageColorFromImage(UIImage *image) {
    if (!image) return nil;
    CGImageRef cgImg = image.CGImage;
    if (!cgImg) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char pixels[4] = {0};
    CGContextRef ctx = CGBitmapContextCreate(pixels, 1, 1, 8, 4, colorSpace,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!ctx) {
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    // 渲染图标到 1x1 位图 → 所有像素被平均为单点
    CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), cgImg);

    CGFloat r = pixels[0] / 255.0f;
    CGFloat g = pixels[1] / 255.0f;
    CGFloat b = pixels[2] / 255.0f;

    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // 转换到 HSB 调整亮度/饱和度保证可见性
    UIColor *raw = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
    CGFloat hue, sat, brightness, alpha;
    [raw getHue:&hue saturation:&sat brightness:&brightness alpha:&alpha];

    // 暗色提亮（亮度 < 0.3 → 提到 0.3+），亮色压暗（亮度 > 0.85 → 压到 0.85-）
    if (brightness < 0.3f) {
        brightness = 0.3f + brightness * 0.5f;
    } else if (brightness > 0.85f) {
        brightness = 0.85f - (1.0f - brightness) * 0.5f;
    }
    // 略增饱和度让指示器更鲜艳
    sat = MIN(sat * 1.3f, 1.0f);

    return [UIColor colorWithHue:hue saturation:sat brightness:brightness alpha:1.0f];
}

// 尝试从 SBIconView/SBIcon 获取图标 UIImage
static UIImage *MKGetIconImage(SBIconView *iv) {
    @try {
        id icon = [iv icon];
        if (!icon) return nil;

        // 策略 1: SBIcon 的 iconImageForScreenScale: / applicationIconImageForScreenScale:
        NSArray *iconImageSelectors = @[
            @"applicationIconImageForScreenScale:",
            @"iconImageForScreenScale:",
            @"applicationIconImage",
            @"iconImage",
            @"getImage"
        ];
        CGFloat scale = [UIScreen mainScreen].scale;
        NSNumber *scaleNum = @(scale);

        for (NSString *selName in iconImageSelectors) {
            SEL sel = NSSelectorFromString(selName);
            if ([icon respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                // 含 scale 参数的方法
                if ([selName hasSuffix:@":"]) {
                    NSMethodSignature *sig = [icon methodSignatureForSelector:sel];
                    if (sig.numberOfArguments == 3) {  // self, _cmd, scale
                        id result = [icon performSelector:sel withObject:scaleNum];
                        if ([result isKindOfClass:[UIImage class]]) return result;
                    }
                } else {
                    id result = [icon performSelector:sel];
                    if ([result isKindOfClass:[UIImage class]]) return result;
                }
#pragma clang diagnostic pop
            }
        }

        // 策略 2: SBIconView 的 iconImage accessor
        NSArray *viewImageSelectors = @[@"iconImage", @"_iconImage", @"image"];
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

        // 策略 3: 快照 SBIconView（兜底）
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 1.0);
        [iv drawViewHierarchyInRect:iv.bounds afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return snapshot;

    } @catch (NSException *e) {
        RDLog(@"MKGetIconImage exception: %@", e.reason);
    }
    return nil;
}

// 获取指定 bundleID 的图标平均色（带缓存）
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
            if ([current isKindOfClass:NSClassFromString(@"SBIconView")]) {
                SBIconView *iv = (SBIconView *)current;
                NSString *ivBid = MKGetCachedBid(iv);
                if (ivBid && [ivBid isEqualToString:bid]) {
                    UIImage *img = MKGetIconImage(iv);
                    result = MKAverageColorFromImage(img);
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
    } else {
        // 无图标 → 用配置的固定色作为 fallback
        sIconColorCache[bid] = [[MKConfig sharedConfig] color];
    }
    return sIconColorCache[bid];
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
            if (bid.length && !MKIsBlacklisted(bid)) {
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
            if (bid && !MKIsBlacklisted(bid)) {
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
        UIView *parent = iconView.superview;
        if (parent && parent.subviews.count <= 8) {
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

        // ── 诊断：标签未找到 → dump iconView + 父视图层级 ──
        static int sNoLabelLogs = 0;
        if (sNoLabelLogs < 10) {
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

static void MKUpdate(SBIconView *self) {
    MKSafe(^{
        if (!sInitDone) return;

        sCallCount++;
        if (MKIsDisabled()) {
            UIView *indicator = MKGetIndicator(self);
            if (indicator) { [indicator removeFromSuperview]; MKSetIndicator(self, nil); }
            UIView *label = MKGetCachedLabel(self);
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
            }
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (!cfg || !cfg.enabled) {
            UIView *indicator = MKGetIndicator(self);
            if (indicator) { [indicator removeFromSuperview]; MKSetIndicator(self, nil); }
            UIView *label = MKGetCachedLabel(self);
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
            }
            return;
        }

        // v1.5.3: 使用缓存的 bundleID（避免每次都调 applicationBundleID）
        NSString *bundleID = MKGetCachedBid(self);
        if (!bundleID || bundleID.length == 0) return;

        BOOL running = MKIsAppRunning(bundleID);
        BOOL isForeground = MKIsForeground(bundleID);
        BOOL isPending = MKIsPending(bundleID);       // v1.5.6+: 等待300ms的App
        BOOL isFading = MKIsFadingLabel(bundleID);    // v1.5.8: 标签正在渐隐中

        // v1.5.3: 使用缓存的标签视图（避免每次都跑 MKFindLabelView 4 重策略）
        UIView *label = MKGetCachedLabel(self);
        UIView *indicator = MKGetIndicator(self);

        // 当前被用户打开在前台的 App，桌面上不再显示指示器（避免启动动画残留）
        if (!running || isForeground) {
            // ── App 不在运行 / 在前台 → 移除指示器，恢复名字 ──
            if (indicator) { [indicator removeFromSuperview]; MKSetIndicator(self, nil); }
            if (label) {
                label.hidden = NO;
                label.alpha = 1.0f;
                label.layer.opacity = 1.0f;
                label.opaque = YES;
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
            if (label) {
                label.hidden = YES;
                label.alpha = 0.0f;
                label.layer.opacity = 0.0f;
                label.opaque = NO;
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
        } else {
            // v1.5.5 诊断：App 在运行但找不到标签
            RDLog(@"NO LABEL for running app: %@", bundleID);
        }

        // 指示器尺寸
        CGFloat indicatorW, indicatorH;
        if (cfg.shape == MKShapeDot) {
            indicatorW = cfg.dotSize;
            indicatorH = cfg.dotSize;
        } else {
            // Bar/Pill 形状
            indicatorW = cfg.barWidth;
            indicatorH = cfg.barHeight;
        }

        // ── 决定宿主视图和位置 ──
        UIView *hostView;
        CGRect indicatorFrame;

        if (label && label.superview) {
            // 标签找到 → 指示器放在标签位置（替换名字）
            hostView = label.superview;
            CGRect labelFrame = label.frame;
            indicatorFrame = CGRectMake(
                labelFrame.origin.x + (labelFrame.size.width - indicatorW) / 2.0f,
                labelFrame.origin.y + (labelFrame.size.height - indicatorH) / 2.0f,
                indicatorW,
                indicatorH
            );
        } else {
            // 无标签（Dock 图标 / 文件夹）→ 指示器放在图标底部边缘略下方（Lynx2 风格）
            // 不要放在图标内部遮挡内容，而是放在父视图中的图标下方
            UIView *host = self.superview;
            if (host) {
                hostView = host;
                CGRect iconFrame = self.frame;
                indicatorFrame = CGRectMake(
                    iconFrame.origin.x + (iconFrame.size.width - indicatorW) / 2.0f,
                    iconFrame.origin.y + iconFrame.size.height - 1.0f,  // 略低于图标底部，1pt 重叠更自然
                    indicatorW,
                    indicatorH
                );
            } else {
                hostView = self;
                CGSize mySize = self.bounds.size;
                if (mySize.width < 10 || mySize.height < 10) return;
                indicatorFrame = CGRectMake(
                    (mySize.width - indicatorW) / 2.0f,
                    mySize.height - indicatorH - 4.0f,
                    indicatorW,
                    indicatorH
                );
            }
        }

        // 宿主视图变了 → 需要重新添加指示器
        if (indicator && indicator.superview != hostView) {
            [indicator removeFromSuperview];
            indicator = nil;
            MKSetIndicator(self, nil);
        }

        if (!indicator) {
            indicator = [[MKIndicatorDotView alloc] initWithFrame:indicatorFrame];
            indicator.tag = kDotTag;
            [(MKIndicatorDotView *)indicator applyConfig];

            // v1.5.7: AutoIcon 模式 — 从图标取平均色作为指示器颜色
            if (cfg.colorMode == MKColorModeAutoIcon) {
                UIColor *iconColor = MKCachedIconColorForBundleID(bundleID);
                [(MKIndicatorDotView *)indicator setIndicatorColor:iconColor];
                [indicator setNeedsDisplay];  // 用新颜色重绘
            }

            // v1.5.7: 渐显动画 — 状态切换时指示器 alpha 0→cfg.opacity 200ms
            BOOL shouldAnimate = MKShouldAnimateIndicator(bundleID);
            MKRemoveAnimateIndicator(bundleID);  // 消费标记（一次性）

            if (shouldAnimate) {
                indicator.alpha = 0.0f;  // 从不可见开始
                [hostView addSubview:indicator];
                MKSetIndicator(self, indicator);
                CGFloat finalAlpha = cfg.opacity;
                [UIView animateWithDuration:0.2 animations:^{
                    indicator.alpha = finalAlpha;
                }];
            } else {
                [hostView addSubview:indicator];
                MKSetIndicator(self, indicator);
            }
        } else {
            indicator.frame = indicatorFrame;
            [(MKIndicatorDotView *)indicator applyConfig];
            indicator.hidden = NO;
        }
    });
}

// ====================================================================
// 清理所有指示器（处理动画容器残留）
// ====================================================================

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
                if ([current isKindOfClass:NSClassFromString(@"SBIconView")]) {
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
                if ([current isKindOfClass:NSClassFromString(@"SBIconView")]) {
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

// ====================================================================
// v1.5.8: 标签渐隐动画（前台→后台时，标签 alpha 1→0 的 250ms 渐隐）
// 替代 v1.5.6 的瞬间隐藏，让过渡更自然
// ====================================================================

static void MKFadeOutLabelForBundleID(NSString *bid) {
    MKSafe(^{
        if (!sInitDone || !bid.length) return;
        MKAddFadingLabel(bid);  // v1.5.8: 标记渐隐状态

        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *current = [stack lastObject];
                [stack removeLastObject];
                if ([current isKindOfClass:NSClassFromString(@"SBIconView")]) {
                    SBIconView *iv = (SBIconView *)current;
                    NSString *ivBid = MKGetCachedBid(iv);
                    if (ivBid && [ivBid isEqualToString:bid]) {
                        UIView *label = MKGetCachedLabel(iv);
                        if (label) {
                            // v1.5.8: 250ms 渐隐动画（alpha 1→0）
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
                if ([current isKindOfClass:NSClassFromString(@"SBIconView")]) {
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
            MKRemovePending(bid);  // 清除 pending 状态
            if (!MKIsForeground(bid) && MKIsAppRunning(bid)) {
                MKRefreshIconForBundleID(bid);  // 创建指示器（带渐显动画）
            } else {
                // 300ms内App又变前台或退出了 → 恢复标签
                MKRestoreLabelForBundleID(bid);
                MKRemoveAnimateIndicator(bid);  // 清除渐显标记
            }
        });
    } else {
        // ── App 退出 → 立即移除指示器 + 恢复标签 ──
        MKRemovePending(bid);     // 清除 pending 状态
        MKRemoveFadingLabel(bid); // v1.5.8: 清除渐隐状态
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
    RDLog(@"DELAYED INIT: done. sInitDone=YES");

    // ─── 首次刷新所有图标 ──────
    MKRefreshAllIcons();
}

static void MKPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    [[MKConfig sharedConfig] reload];
    MKRefreshAllIcons();
}

static void MKDoRespring() {
    RDLog(@"RESPRING: executing");
    pid_t pid;
    const char *shArgs[] = {
        "/bin/sh", "-c",
        "PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH; "
        "sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || killall -9 backboardd 2>/dev/null",
        NULL
    };
    int ret = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)shArgs, NULL);
    RDLog(@"RESPRING: ret=%d pid=%d", ret, pid);
}

static void MKRespringCallback(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    MKSafe(^{ MKDoRespring(); });
}

// ====================================================================
// Hook — SBIconView
// ====================================================================

%hook SBIconView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        // View 从窗口移除 → 清理指示器 + 恢复标签 + 清除缓存
        UIView *indicator = MKGetIndicator(self);
        if (indicator) { [indicator removeFromSuperview]; MKSetIndicator(self, nil); }
        UIView *label = MKGetCachedLabel(self);
        if (label) {
            label.hidden = NO;
            label.alpha = 1.0f;
            label.layer.opacity = 1.0f;
            label.opaque = YES;
        }
        MKClearCaches(self);
        return;
    }
    if (sInitDone) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MKUpdate(self);
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if (!sInitDone) return;

    // v1.5.3 性能优化：快速跳过不需要处理的图标
    UIView *indicator = MKGetIndicator(self);
    if (!indicator) {
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
            CGRect lf = label.frame;
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
        CGRect lf = label.frame;
        indicator.frame = CGRectMake(
            lf.origin.x + (lf.size.width - indW) / 2.0f,
            lf.origin.y + (lf.size.height - indH) / 2.0f,
            indW, indH
        );
    } else if (self.superview) {
        // 无标签（Dock）→ 图标底部边缘
        CGRect icf = self.frame;
        indicator.frame = CGRectMake(
            icf.origin.x + (icf.size.width - indW) / 2.0f,
            icf.origin.y + icf.size.height - 1.0f,
            indW, indH
        );
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

        RDLog(@"SBApp._noteProcess: %@ → isRunning=%d taskState=%d foreground=%d",
              bid, isRunning, taskState, isForeground);

        // FBProcessState.taskState: 2=Running, 3=Suspended → app alive
        // FBProcessState.taskState: 1=NotRunning/Dead → app exited
        // FBProcessState.isRunning: YES → app process exists
        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        if (isRunningNow) {
            MKAddToRunningSet(bid);
        } else {
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

        RDLog(@"SBApp._setInternalProcState: %@ → isRunning=%d taskState=%d foreground=%d",
              bid, isRunning, taskState, isForeground);

        BOOL isRunningNow = (isRunning || taskState == 2 || taskState == 3);
        if (isRunningNow) {
            MKAddToRunningSet(bid);
        } else {
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

        RDLog(@"SBApp._setActivationState: %@ → state=%d", bid, state);

        MKSetForeground(bid, state == 2);

        BOOL isRunningNow = (state >= 1);
        if (isRunningNow) {
            MKAddToRunningSet(bid);
        } else {
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

%ctor {
    %init;

    NSLog(@"[RunningDotIndicator] v1.5.8 ctor: natural label fade-out + indicator fade-in crossfade transition");
    RDLog(@"======== v1.5.8 loading (natural transition: label 250ms fade-out → indicator 200ms fade-in) ========");

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

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKRespringCallback,
        CFSTR("com.mk.runningdotindicator.respring"),
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
