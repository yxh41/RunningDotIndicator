//
//  Tweak.x — RunningDotIndicator v1.4.0
//  多策略运行检测：① proc_listallpids 进程枚举 ② LSApplicationProxy 查询 ③ 生命周期通知
//  修复 v1.3.6 三大 Bug：
//    - proc_listallpids(NULL,0) 返回 ≤0 时静默退出无日志 → 改为预分配固定缓冲区+诊断日志
//    - Info.plist 读取失败无回退 → 改用 LSApplicationProxy 缓存反查 bundleID
//    - 生命周期通知 bundleID 提取不全 → 增强多种提取策略
//  紧急开关：/var/mobile/Documents/rd_disabled 存在则整机不生效。
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"
#import "MKIndicatorDotView.h"
#include <spawn.h>
#include <objc/runtime.h>

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

@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (id)applicationWithBundleIdentifier:(NSString *)bundleID;
@end

@interface SBApplication : NSObject
@end

// LSApplicationProxy（MobileCoreServices 私有类，可查 bundleID 对应的可执行路径）
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *executablePath;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)identifier;
@end

// ─── 常量 ──────────────────────────────────────────────────
static NSInteger const kDotTag  = 9999;
static NSInteger const kTestTag = 7777;

// ─── 全局状态 ─────────────────────────────────────────────
static int   sCallCount    = 0;
static int   sRunningCount = 0;
static NSMutableSet<NSString*> *sRunningSet = nil;
static NSMutableDictionary<NSString*, NSString*> *sPathToBundleID = nil;  // 缓存：可执行路径→bundleID
static NSMutableDictionary<NSString*, NSString*> *sBidToExePath = nil;    // 缓存：bundleID→可执行路径
static NSMutableArray *sLifecycleObservers = nil;
static NSTimeInterval sDisableTS = 0;
static BOOL  sDisableChecked = NO;
static BOOL  sDisabled = NO;
static BOOL  sLSProxyReady = NO;

// ─── 文件日志 ────────────────────────────────────────────────
static void RDLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
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
        if (sCallCount < 5) RDLog(@"EXCEPTION caught: %@", e.reason);
    }
}

// ====================================================================
// 运行状态检测（v1.4.0 — 多策略）
// ====================================================================

// ─── 策略 0：LSApplicationProxy 缓存 ────────────────────────
static void MKBuildLSProxyCache() {
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsClass) {
            RDLog(@"LSProxy: LSApplicationWorkspace NOT found");
            return;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id ws = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
        if (!ws) { RDLog(@"LSProxy: defaultWorkspace nil"); return; }
        NSArray *apps = [ws performSelector:NSSelectorFromString(@"allInstalledApplications")];
#pragma clang diagnostic pop

        if (!apps || ![apps count]) {
            RDLog(@"LSProxy: allInstalledApplications empty");
            return;
        }

        if (!sBidToExePath) sBidToExePath = [NSMutableDictionary dictionary];
        if (!sPathToBundleID) sPathToBundleID = [NSMutableDictionary dictionary];

        int added = 0;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        for (id proxy in apps) {
            if (proxyClass && ![proxy isKindOfClass:proxyClass]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSString *bid = [proxy performSelector:NSSelectorFromString(@"bundleIdentifier")];
            NSString *exePath = [proxy performSelector:NSSelectorFromString(@"executablePath")];
#pragma clang diagnostic pop
            if (!bid.length || !exePath.length) continue;
            sBidToExePath[bid] = exePath;
            sPathToBundleID[exePath] = bid;
            added++;
        }

        sLSProxyReady = YES;
        RDLog(@"LSProxy: cached %d apps", added);

        // 诊断：打印几个示例
        NSArray *sample = [sBidToExePath allKeys];
        for (int i = 0; i < MIN(3, (int)sample.count); i++) {
            RDLog(@"LSProxy sample: %@ → %@", sample[i], sBidToExePath[sample[i]]);
        }
    } @catch (NSException *e) {
        RDLog(@"LSProxy exception: %@", e.reason);
    }
}

// ─── 策略 1：进程枚举（proc_listallpids）──────────────────
// 关键修复：不再用 proc_listallpids(NULL,0)（可能返回 0 导致静默退出）
// 改为预分配固定缓冲区直接调用 + 优先 LSProxy 缓存查 bundleID

static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    [sRunningSet removeObject:bid];
}

static void MKComputeRunningSet() {
    @try {
        // ★ 修复：用固定大小缓冲区，不再依赖 proc_listallpids(NULL,0) ★
        int pidBuf[512];
        int bufBytes = sizeof(pidBuf);  // 2048 bytes = 512 ints

        int retBytes = proc_listallpids(pidBuf, bufBytes);

        // ★ 诊断日志：无论如何都打印返回值 ★
        static int sProcEntryLogs = 0;
        if (sProcEntryLogs < 5) {
            sProcEntryLogs++;
            RDLog(@"PROC entry: proc_listallpids ret=%d buf=%d", retBytes, bufBytes);
        }

        if (retBytes <= 0) {
            RDLog(@"PROC: proc_listallpids FAILED ret=%d", retBytes);
            return;
        }

        int numPids = retBytes / sizeof(int);

        // ★ 诊断：打印 PID 总数 ★
        static int sPidCountLogs = 0;
        if (sPidCountLogs < 3) {
            sPidCountLogs++;
            RDLog(@"PROC: %d total PIDs", numPids);
        }

        // ─── 遍历进程路径 → 匹配 App → 反查 bundleID ──────
        NSMutableSet *newSet = [NSMutableSet set];
        int appProcessCount = 0;
        int matchedCount = 0;
        int unmatchedPaths = 0;

        static int sPathDiagLogs = 0;

        for (int i = 0; i < numPids; i++) {
            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;

            NSString *fullPath = [NSString stringWithUTF8String:pathBuf];

            // 过滤：只关注 App 进程路径
            // App Store apps: /var/containers/Bundle/Application/UUID/App.app/Executable
            //                  /private/var/containers/Bundle/Application/...
            // System apps:    /Applications/App.app/Executable
            BOOL isAppPath = NO;
            if ([fullPath containsString:@"/Bundle/Application/"]) {
                isAppPath = YES;
            } else if ([fullPath containsString:@"/Applications/"]) {
                NSRange r = [fullPath rangeOfString:@"/Applications/"];
                if (r.location != NSNotFound) {
                    NSString *after = [fullPath substringFromIndex:r.location + r.length];
                    isAppPath = [after containsString:@".app/"];
                }
            }

            if (!isAppPath) continue;
            appProcessCount++;

            // ★ 诊断：打印前几个 App 进程路径 ★
            if (sPathDiagLogs < 10) {
                sPathDiagLogs++;
                RDLog(@"PROC app path: %@", fullPath);
            }

            // ─── 路径 → bundleID ──────────────────────────────
            NSString *bid = nil;

            // 优先：LSApplicationProxy 缓存（最可靠）
            if (sPathToBundleID) {
                bid = sPathToBundleID[fullPath];
            }

            // 回退：读 Info.plist
            if (!bid) {
                NSString *appBundlePath = [fullPath stringByDeletingLastPathComponent];
                NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                bid = info[@"CFBundleIdentifier"];
                if (bid && sPathToBundleID) {
                    sPathToBundleID[fullPath] = bid;
                }
            }

            if (bid) {
                [newSet addObject:bid];
                matchedCount++;
            } else {
                unmatchedPaths++;
                RDLog(@"PROC: UNMATCHED %@ (no bundleID)", fullPath);
            }
        }

        // ─── 输出结果 ──────────────────────────────────────────
        RDLog(@"PROC result: %lu running (appProc=%d matched=%d unmatched=%d)",
              (unsigned long)newSet.count, appProcessCount, matchedCount, unmatchedPaths);

        // 变化时打印完整列表（限 10 次）
        static int sProcDetailLogs = 0;
        static NSSet *sLastProcSet = nil;
        if (sProcDetailLogs < 10 && (!sLastProcSet || ![newSet isEqualToSet:sLastProcSet])) {
            sProcDetailLogs++;
            RDLog(@"PROC enum: %lu → %@",
                  (unsigned long)newSet.count,
                  [[newSet allObjects] componentsJoinedByString:@", "]);
        }
        sLastProcSet = [newSet copy];
        sRunningSet = newSet;

    } @catch (NSException *e) {
        RDLog(@"PROC exception: %@", e.reason);
    }
}

static BOOL MKIsAppLit(NSString *bid) {
    return sRunningSet && [sRunningSet containsObject:bid];
}

// ─── 从通知提取 bundleID（增强版）───────────────────────────
static NSString *MKBidFromNote(NSNotification *note) {
    @try {
        id obj = note.object;
        if (obj) {
            // 尝试多种 bundleID 属性名
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

        // userInfo 中查找
        NSDictionary *info = note.userInfo;
        if (info) {
            for (NSString *key in @[@"bundleIdentifier", @"applicationBundleID",
                                    @"bundleID", @"displayIdentifier",
                                    @"applicationIdentifier", @"processIdentifier"]) {
                id v = info[key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v containsString:@"."] && ![(NSString *)v containsString:@"/"]) return v;
            }
            // 通用扫描
            for (id k in info) {
                id v = info[k];
                if ([v isKindOfClass:[NSString class]]) {
                    NSString *sv = (NSString *)v;
                    if ([sv containsString:@"."] && ![sv containsString:@"/"] && ![sv containsString:@"://"]) return sv;
                }
            }
        }

        // notification.name 尝试提取（格式如 "XXX_com.app.dev"）
        NSString *name = note.name;
        if (name.length > 0) {
            NSArray *parts = [name componentsSeparatedByString:@"_"];
            if (parts.count > 1) {
                NSString *last = [parts lastObject];
                if ([last containsString:@"."] && ![last containsString:@"/"]) return last;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

static BOOL MKIsAppRunning(NSString *bundleID) {
    return MKIsAppLit(bundleID);
}

// ====================================================================
// 渲染辅助
// ====================================================================

static UIView *MKFindLabelView(SBIconView *iconView) {
    for (UIView *sv in iconView.subviews) {
        NSString *cls = NSStringFromClass([sv class]);
        if ([sv isKindOfClass:[UILabel class]] ||
            [cls containsString:@"Label"] || [cls containsString:@"label"]) {
            return sv;
        }
    }
    return nil;
}

// ====================================================================
// 主更新函数
// ====================================================================

static void MKUpdate(SBIconView *self) {
    MKSafe(^{
        sCallCount++;
        if (MKIsDisabled()) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
            [[self viewWithTag:kTestTag] removeFromSuperview];
            UIView *label = MKFindLabelView(self);
            if (label) label.hidden = NO;
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (!cfg || !cfg.enabled) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
            [[self viewWithTag:kTestTag] removeFromSuperview];
            UIView *label = MKFindLabelView(self);
            if (label) label.hidden = NO;
            return;
        }

        id icon = [self icon];
        NSString *bundleID = nil;
        if (icon && [icon respondsToSelector:@selector(applicationBundleID)]) {
            bundleID = [icon applicationBundleID];
        }
        if (!bundleID || bundleID.length == 0) return;

        // ─── 强制测试点（前 5 个图标画蓝色圆点）─────────
        static int sTestDots = 0;
        if (sTestDots < 5 && sCallCount < 100) {
            sTestDots++;
            RDLog(@"TEST DOT #%d on %@ running=%d", sTestDots, bundleID, MKIsAppRunning(bundleID));
            CGFloat sz = MAX(cfg.size, 10.0);
            UIView *testDot = [self viewWithTag:kTestTag];
            if (!testDot) {
                testDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sz, sz)];
                testDot.tag = kTestTag;
                testDot.backgroundColor = [UIColor blueColor];
                testDot.layer.cornerRadius = sz / 2.0;
                [self addSubview:testDot];
            }
            CGSize mySize = self.bounds.size;
            testDot.frame = CGRectMake((mySize.width - sz) / 2.0, mySize.height - sz - 4, sz, sz);
            testDot.hidden = NO;
        }

        BOOL running = MKIsAppRunning(bundleID);
        if (!running) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
            if (cfg.position == MKPositionReplaceName) {
                UIView *label = MKFindLabelView(self);
                if (label) label.hidden = NO;
            }
            return;
        }

        sRunningCount++;
        static int sRunLogs = 0;
        if (sRunLogs < 30) { sRunLogs++; RDLog(@"RUNNING: %@ (call=%d)", bundleID, sCallCount); }

        CGFloat sz = cfg.size;
        UIView *existing = [self viewWithTag:kDotTag];
        if (existing && ![existing isKindOfClass:[MKIndicatorDotView class]]) {
            [existing removeFromSuperview];
            existing = nil;
        }
        if (!existing) {
            MKIndicatorDotView *dot = [[MKIndicatorDotView alloc] initWithFrame:CGRectMake(0, 0, sz, sz)];
            dot.tag = kDotTag;
            dot.backgroundColor = cfg.color;
            dot.layer.cornerRadius = (cfg.shape == MKShapeCircle) ? sz / 2.0 : 0;
            dot.clipsToBounds = (cfg.shape != MKShapeCircle);
            [self addSubview:dot];
        }
        UIView *dot = [self viewWithTag:kDotTag];
        if (!dot) return;
        dot.backgroundColor = cfg.color;
        dot.layer.cornerRadius = (cfg.shape == MKShapeCircle) ? sz / 2.0 : 0;
        dot.alpha = cfg.opacity;

        CGSize mySize = self.bounds.size;
        if (mySize.width < sz || mySize.height < sz) return;

        UIView *label = MKFindLabelView(self);
        switch (cfg.position) {
            case MKPositionLeft:
                dot.frame = CGRectMake(4, (mySize.height - sz) / 2.0, sz, sz);
                if (label) label.hidden = NO;
                break;
            case MKPositionRight:
                dot.frame = CGRectMake(mySize.width - sz - 4, (mySize.height - sz) / 2.0, sz, sz);
                if (label) label.hidden = NO;
                break;
            case MKPositionReplaceName:
                dot.frame = CGRectMake((mySize.width - sz) / 2.0, mySize.height - sz - 4, sz, sz);
                if (label) label.hidden = YES;
                break;
        }
        dot.hidden = NO;
    });
}

// ====================================================================
// 刷新所有图标
// ====================================================================

static void MKRefreshAllIcons() {
    MKSafe(^{
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

static void MKPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    [[MKConfig sharedConfig] reload];
    MKRefreshAllIcons();
}

static void MKDoRespring() {
    RDLog(@"RESPRING: executing kill");
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
// Hook（所有 %hook 在 %ctor 之前）
// ====================================================================

%hook SBIconView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MKUpdate(self);
        });
    }
}

- (void)layoutSubviews {
    %orig;
    MKUpdate(self);
}

%end

// 尝试 hook SBMainSwitcherController（iOS 16+ App 切换器）
// 如果类不存在于当前 iOS 版本，Theos 会跳过，不崩溃
%hook SBMainSwitcherController

- (void)_appActivationStateDidChange:(NSNotification *)notification {
    %orig;
    @try {
        NSString *bid = MKBidFromNote(notification);
        if (!bid.length) {
            RDLog(@"_appActState: bid nil obj=%s",
                  notification.object ? NSStringFromClass([notification.object class]).UTF8String : "nil");
            return;
        }
        id stateVal = notification.userInfo[@"applicationState"];
        if (!stateVal) stateVal = notification.userInfo[@"activationState"];
        if (!stateVal) stateVal = notification.userInfo[@"state"];

        if (stateVal && [stateVal isKindOfClass:[NSNumber class]]) {
            int state = [(NSNumber *)stateVal intValue];
            if (state > 0) {
                MKAddToRunningSet(bid);
                RDLog(@"_appActState: ADD %@ state=%d", bid, state);
            } else {
                MKRemoveFromRunningSet(bid);
                RDLog(@"_appActState: REMOVE %@ state=%d", bid, state);
            }
        } else {
            RDLog(@"_appActState: %@ (no state, proc enum will calibrate)", bid);
        }
    } @catch (NSException *e) {
        RDLog(@"_appActState exception: %@", e.reason);
    }
}

%end

// 尝试 hook SBSceneSwitcherController（某些 iOS 16 版本的替代类名）
%hook SBSceneSwitcherController

- (void)_appActivationStateDidChange:(NSNotification *)notification {
    %orig;
    @try {
        NSString *bid = MKBidFromNote(notification);
        if (bid.length) {
            RDLog(@"_appActState(SBScene): %@", bid);
            MKAddToRunningSet(bid);
        }
    } @catch (NSException *e) {}
}

%end

// ====================================================================
// 构造函数（必须在所有 %hook 之后）
// ====================================================================

%ctor {
    // ★ 必须显式调用 %init 初始化所有 hook ★
    %init;

    NSLog(@"[RunningDotIndicator] v1.4.0 loaded (multi-strategy: proc_enum + LSProxy + lifecycle)");
    RDLog(@"======== v1.4.0 loading (multi-strategy detection) ========");
    if (MKIsDisabled()) {
        RDLog(@"DISABLED at load; doing nothing.");
        return;
    }

    // ─── 偏好设置通知 ──────────────────────────────
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKPrefsChangedCallback,
        CFSTR("com.mk.runningdotindicator.reload"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    // ─── 注销按钮 ──────────────────────────────────
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, MKRespringCallback,
        CFSTR("com.mk.runningdotindicator.respring"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    // ─── 构建 LSApplicationProxy 缓存 ──────────────
    MKBuildLSProxyCache();

    // ─── 进程枚举：立即执行一次 ──────────────────────
    MKComputeRunningSet();
    RDLog(@"Initial scan: %lu items in sRunningSet", (unsigned long)sRunningSet.count);

    // ─── 定时刷新：每 3 秒 ────────────────────────────
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                      dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                              3 * NSEC_PER_SEC, 1.0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        MKSafe(^{ MKComputeRunningSet(); MKRefreshAllIcons(); });
    });
    dispatch_resume(timer);

    // ─── 生命周期通知 ──────────────────────────────────
    if (!sLifecycleObservers) sLifecycleObservers = [NSMutableArray array];
    NSDictionary *lifecycleActions = @{
        @"SBApplicationDidFinishLaunchingNotification":      @"add",
        @"SBApplicationDidBecomeActiveNotification":         @"add",
        @"SBApplicationWillResumeNotification":              @"add",
        @"SBApplicationDidResumeNotification":               @"add",
        @"SBApplicationWillForegroundNotification":          @"add",
        @"SBApplicationDidForegroundNotification":           @"add",
        @"SBApplicationProcessDidLaunchNotification":        @"add",
        @"SBApplicationProcessDidExitNotification":          @"remove",
        @"SBApplicationDidExitNotification":                 @"remove",
        @"SBApplicationWillTerminateNotification":           @"remove",
        @"SBApplicationWillSuspendNotification":             @"ignore",
        @"SBApplicationDidSuspendNotification":              @"ignore",
    };
    [lifecycleActions enumerateKeysAndObjectsUsingBlock:^(NSString *nm, NSString *act, BOOL *_) {
        id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:nm object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note){
            @try {
                static int sNoteDetailLogs = 0;
                NSString *bid = MKBidFromNote(note);
                if (sNoteDetailLogs < 50) {
                    sNoteDetailLogs++;
                    RDLog(@"NOTE: %@ obj=%s info=%s bid=%@",
                          note.name,
                          note.object ? NSStringFromClass([note.object class]).UTF8String : "nil",
                          note.userInfo ? "yes" : "nil",
                          bid ?: @"(nil)");
                }
                if (!bid) {
                    if ([act isEqualToString:@"add"])
                        RDLog(@"NOTE add without bid, proc enum will catch it");
                    return;
                }
                if ([act isEqualToString:@"add"]) {
                    MKAddToRunningSet(bid);
                    RDLog(@"LIFECYCLE + %@ → %@", nm, bid);
                } else if ([act isEqualToString:@"remove"]) {
                    MKRemoveFromRunningSet(bid);
                    RDLog(@"LIFECYCLE - %@ → %@", nm, bid);
                }
            } @catch (NSException *e) {
                RDLog(@"NOTE exception: %@", e.reason);
            }
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }];

    RDLog(@"======== loaded OK ========");
}
