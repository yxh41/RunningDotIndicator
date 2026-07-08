//
//  Tweak.x — RunningDotIndicator v1.4.1
//  v1.4.0 日志诊断结果：
//    ✅ proc_listallpids 成功了！（ret=264, 66 PIDs）
//    ❌ LSProxy 缓存崩了：allInstalledApplications 返回 LSApplicationRecord，
//       它没有 executablePath 属性 → 改为用 applicationProxyForIdentifier: 获取 LSApplicationProxy
//    ❌ 只检测到 4 个越狱工具进程（刚 respring 无普通 App 运行）
//    🆕 roothide 路径格式：.jbroot-XXX 前缀 → 需处理
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

// LSApplicationProxy — 有 executablePath 属性（通过 applicationProxyForIdentifier: 获取）
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *executablePath;
@end

// LSApplicationWorkspace — 提供两个关键方法
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;             // 返回 LSApplicationRecord（无 executablePath）
- (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)identifier;  // 返回 LSApplicationProxy（有 executablePath）
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
// 运行状态检测（v1.4.1 — LSProxy 缓存修复 + 路径增强）
// ====================================================================

// ─── 策略 0：LSApplicationProxy 缓存（v1.4.1 修复版）─────────
// v1.4.0 Bug: allInstalledApplications 返回 LSApplicationRecord，
// 它没有 executablePath → 崩溃。
// v1.4.1 Fix: 先从 LSApplicationRecord 取 bundleIdentifier，
// 再用 applicationProxyForIdentifier: 获取 LSApplicationProxy（有 executablePath）。
// 同时逐条处理，单条异常不中断整体缓存构建。
static void MKBuildLSProxyCache() {
    if (!sBidToExePath) sBidToExePath = [NSMutableDictionary dictionary];
    if (!sPathToBundleID) sPathToBundleID = [NSMutableDictionary dictionary];

    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsClass) { RDLog(@"LSProxy: LSApplicationWorkspace NOT found"); return; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id ws = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
        if (!ws) { RDLog(@"LSProxy: defaultWorkspace nil"); return; }

        NSArray *records = [ws performSelector:NSSelectorFromString(@"allInstalledApplications")];
#pragma clang diagnostic pop

        if (!records || ![records count]) { RDLog(@"LSProxy: allInstalledApplications empty"); return; }
        RDLog(@"LSProxy: got %lu records from allInstalledApplications", (unsigned long)records.count);

        int added = 0;
        int failed = 0;

        for (id record in records) {
            @try {
                // Step 1: 从 LSApplicationRecord 取 bundleIdentifier
                NSString *bid = nil;
                if ([record respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    bid = [record performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
                }
                if (!bid || !bid.length) continue;

                // Step 2: 用 applicationProxyForIdentifier: 获取 LSApplicationProxy（有 executablePath）
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id proxy = [ws performSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")
                                       withObject:bid];
#pragma clang diagnostic pop

                if (!proxy) { failed++; continue; }

                // Step 3: 从 LSApplicationProxy 取 executablePath
                NSString *exePath = nil;
                if ([proxy respondsToSelector:NSSelectorFromString(@"executablePath")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    exePath = [proxy performSelector:NSSelectorFromString(@"executablePath")];
#pragma clang diagnostic pop
                }

                if (!exePath || !exePath.length) { failed++; continue; }

                sBidToExePath[bid] = exePath;
                sPathToBundleID[exePath] = bid;
                added++;

            } @catch (NSException *e) {
                failed++;
                if (failed <= 3) RDLog(@"LSProxy: record exception: %@", e.reason);
            }
        }

        sLSProxyReady = YES;
        RDLog(@"LSProxy: cached %d apps (failed=%d, total=%lu)", added, failed, (unsigned long)records.count);

        // 诊断：打印几个示例
        NSArray *sample = [sBidToExePath allKeys];
        for (int i = 0; i < MIN(5, (int)sample.count); i++) {
            RDLog(@"LSProxy sample: %@ → %@", sample[i], sBidToExePath[sample[i]]);
        }

    } @catch (NSException *e) {
        RDLog(@"LSProxy top-level exception: %@", e.reason);
    }
}

// ─── 策略 1：进程枚举（proc_listallpids）──────────────────
static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    [sRunningSet removeObject:bid];
}

// 从进程路径提取 bundleID 的多策略方法
static NSString *MKBidFromPath(NSString *fullPath) {
    // ─── 方法 1：LSProxy 缓存直查（最可靠）─────────
    NSString *bid = sPathToBundleID[fullPath];
    if (bid) return bid;

    // ─── 方法 2：Info.plist 回退 ──────────────────────
    // fullPath 格式: .../UUID/AppName.app/Executable 或 .../AppName.app/Executable
    // Info.plist 在 .app 目录里
    NSString *appBundlePath = [fullPath stringByDeletingLastPathComponent];  // → .../AppName.app
    if ([appBundlePath hasSuffix:@".app"]) {
        NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        bid = info[@"CFBundleIdentifier"];
        if (bid) {
            sPathToBundleID[fullPath] = bid;  // 缓存
            RDLog(@"PROC: Info.plist fallback: %@", bid);
            return bid;
        }
    }

    // ─── 方法 3：从 .app 目录名启发式猜测 ──────────
    // 有些越狱 App 的 Info.plist 不在标准位置
    // 如果 LSProxy 缓存可用，可以用 .app 目录名做模糊匹配
    NSString *appName = [appBundlePath lastPathComponent];  // AppName.app
    if ([appName hasSuffix:@".app"]) {
        // 在 LSProxy 缓存中查找 executablePath 包含此 .app 名的
        if (sBidToExePath) {
            for (NSString *cachedBid in sBidToExePath) {
                NSString *cachedPath = sBidToExePath[cachedBid];
                if ([cachedPath containsString:appName]) {
                    sPathToBundleID[fullPath] = cachedBid;
                    RDLog(@"PROC: fuzzy match %@ → %@", appName, cachedBid);
                    return cachedBid;
                }
            }
        }
    }

    return nil;
}

static void MKComputeRunningSet() {
    @try {
        // ★ 固定缓冲区（已验证 v1.4.0 成功）★
        int pidBuf[512];
        int bufBytes = sizeof(pidBuf);

        int retBytes = proc_listallpids(pidBuf, bufBytes);

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
            // 识别特征：
            //   /var/containers/Bundle/Application/...（标准 iOS App Store 路径）
            //   /private/var/containers/Bundle/Application/...（带 /private 前缀）
            //   /private/var/containers/Bundle/Application/.jbroot-XXX/...（roothide 路径）
            //   /Applications/App.app/...（系统内置 App）
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

            // ★ 诊断：打印所有 App 进程路径 ★
            if (sPathDiagLogs < 20) {
                sPathDiagLogs++;
                RDLog(@"PROC app path: %@", fullPath);
            }

            // ─── 路径 → bundleID（多策略）─────────
            NSString *bid = MKBidFromPath(fullPath);

            if (bid) {
                [newSet addObject:bid];
                matchedCount++;
            } else {
                unmatchedPaths++;
                RDLog(@"PROC: UNMATCHED %@", fullPath);
            }
        }

        // ─── 输出结果 ──────────────────────────────────────────
        RDLog(@"PROC result: %lu running (appProc=%d matched=%d unmatched=%d)",
              (unsigned long)newSet.count, appProcessCount, matchedCount, unmatchedPaths);

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
                                    @"applicationIdentifier", @"processIdentifier"]) {
                id v = info[key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v containsString:@"."] && ![(NSString *)v containsString:@"/"]) return v;
            }
            for (id k in info) {
                id v = info[k];
                if ([v isKindOfClass:[NSString class]]) {
                    NSString *sv = (NSString *)v;
                    if ([sv containsString:@"."] && ![sv containsString:@"/"] && ![sv containsString:@"://"]) return sv;
                }
            }
        }

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

        // ─── 强制测试点（前 5 个图标画蓝色圆点，确认渲染通路）───────
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
// 如果类不存在于当前 iOS 版本，Theos 跳过不崩溃
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
// 构造函数
// ====================================================================

%ctor {
    %init;

    NSLog(@"[RunningDotIndicator] v1.4.1 loaded (fixed LSProxy cache + path matching)");
    RDLog(@"======== v1.4.1 loading ========");
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

    // ─── 构建 LSApplicationProxy 缓存（v1.4.1 修复版）─────
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
