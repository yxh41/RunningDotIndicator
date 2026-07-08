//
//  Tweak.x — RunningDotIndicator v1.4.3
//  v1.4.3 紧急修复：
//    ✅ 所有重量级初始化延迟 15 秒（避免阻塞 SpringBoard 启动导致黑屏）
//    ✅ %ctor 只做最轻量工作：注册通知 + 写日志
//    ✅ 移除 SBApplicationController.runningApplications（已知崩溃）
//    ✅ 移除 SBApplication._noteProcess:didChangeToState: hook（未验证）
//    ✅ 移除测试蓝点（减少干扰）
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

// SBMainWorkspace — iOS 16 进程状态变更入口
@interface SBMainWorkspace : NSObject
@end

// ─── 常量 ──────────────────────────────────────────────────
static NSInteger const kDotTag  = 9999;

// ─── taskState 枚举 ──────────────────────────────────────────
static int const kTaskStateDead      = 1;  // 进程已终止
static int const kTaskStateRunning   = 2;  // 进程正在运行（前台）
static int const kTaskStateSuspended = 3;  // 进程已挂起（后台）

// ─── 全局状态 ─────────────────────────────────────────────
static int   sCallCount    = 0;
static BOOL  sInitDone     = NO;    // 延迟初始化完成后设为 YES
static NSMutableSet<NSString*> *sRunningSet = nil;
static NSMutableDictionary<NSString*, NSString*> *sPathToBundleID = nil;
static NSMutableDictionary<NSString*, NSString*> *sBidToExePath = nil;
static NSMutableArray *sLifecycleObservers = nil;
static NSTimeInterval sDisableTS = 0;
static BOOL  sDisableChecked = NO;
static BOOL  sDisabled = NO;
static BOOL  sPathCacheReady = NO;

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
        RDLog(@"EXCEPTION: %@", e.reason);
    }
}

// ====================================================================
// 运行状态检测
// ====================================================================

static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    [sRunningSet removeObject:bid];
}

static BOOL MKIsAppRunning(NSString *bundleID) {
    return sRunningSet && [sRunningSet containsObject:bundleID];
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
            // 跳过 roothide 前缀目录
            if ([uuid hasPrefix:@"."]) continue;

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

    // ─── 扫描系统内置应用 ──────────
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

    // 诊断：打印几个示例
    NSArray *sample = [sBidToExePath allKeys];
    for (int i = 0; i < MIN(5, (int)sample.count); i++) {
        RDLog(@"PathCache sample: %@ → %@", sample[i], sBidToExePath[sample[i]]);
    }
}

// ─── 进程路径→bundleID 反查 ──────────
static NSString *MKBidFromPath(NSString *fullPath) {
    // PathCache 直查
    NSString *bid = sPathToBundleID[fullPath];
    if (bid) return bid;

    // Info.plist 回退
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

    // .app 目录名模糊匹配
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

// ─── 进程枚举（回退策略）──────────────────
static void MKComputeRunningSet() {
    @try {
        int pidBuf[512];
        int bufBytes = sizeof(pidBuf);
        int retBytes = proc_listallpids(pidBuf, bufBytes);

        if (retBytes <= 0) return;

        int numPids = retBytes / sizeof(int);

        static int sProcEntryLogs = 0;
        if (sProcEntryLogs < 3) {
            sProcEntryLogs++;
            RDLog(@"PROC: %d PIDs (ret=%d)", numPids, retBytes);
        }

        // ─── 首次扫描时 dump 所有路径（诊断）──────────
        static int sFullDumpDone = 0;
        if (sFullDumpDone == 0) {
            sFullDumpDone = 1;
            RDLog(@"PROC: === FULL PATH DUMP (first scan) ===");
            int dumpCount = 0;
            for (int i = 0; i < numPids && dumpCount < 80; i++) {
                char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
                if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;
                NSString *p = [NSString stringWithUTF8String:pathBuf];
                if (p.length > 0) {
                    RDLog(@"PROC dump [%d]: pid=%d → %@", dumpCount, pidBuf[i], p);
                    dumpCount++;
                }
            }
            RDLog(@"PROC: === END DUMP (%d paths) ===", dumpCount);
        }

        // ─── 遍历匹配 ──────
        NSMutableSet *procSet = [NSMutableSet set];
        int appProcessCount = 0;

        for (int i = 0; i < numPids; i++) {
            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;

            NSString *fullPath = [NSString stringWithUTF8String:pathBuf];

            BOOL isAppPath = NO;
            if ([fullPath containsString:@"/Bundle/Application/"]) {
                isAppPath = YES;
            } else if ([fullPath containsString:@".app/"]) {
                if (![fullPath containsString:@"/var/jb/"] && ![fullPath hasPrefix:@"/usr/"]) {
                    isAppPath = YES;
                }
            }
            if (!isAppPath) continue;
            appProcessCount++;

            NSString *bid = MKBidFromPath(fullPath);
            if (bid) {
                [procSet addObject:bid];
            } else {
                static int sUnmatchLogs = 0;
                if (sUnmatchLogs < 10) {
                    sUnmatchLogs++;
                    RDLog(@"PROC: UNMATCHED %@", fullPath);
                }
            }
        }

        // 进程枚举只补充，不覆盖
        int supplemented = 0;
        for (NSString *bid in procSet) {
            if (![sRunningSet containsObject:bid]) {
                MKAddToRunningSet(bid);
                supplemented++;
            }
        }

        static int sProcResultLogs = 0;
        if (sProcResultLogs < 5) {
            sProcResultLogs++;
            RDLog(@"PROC result: appProc=%d supplemented=%d runningSet=%lu",
                  appProcessCount, supplemented, (unsigned long)sRunningSet.count);
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
        if (!sInitDone) return;  // ⚠️ 延迟初始化未完成时不渲染

        sCallCount++;
        if (MKIsDisabled()) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
            UIView *label = MKFindLabelView(self);
            if (label) label.hidden = NO;
            return;
        }

        MKConfig *cfg = [MKConfig sharedConfig];
        if (!cfg || !cfg.enabled) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
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

        BOOL running = MKIsAppRunning(bundleID);
        if (!running) {
            [[self viewWithTag:kDotTag] removeFromSuperview];
            if (cfg.position == MKPositionReplaceName) {
                UIView *label = MKFindLabelView(self);
                if (label) label.hidden = NO;
            }
            return;
        }

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
// 延迟初始化（核心修复：15 秒后执行，不阻塞 SpringBoard 启动）
// ====================================================================

static void MKDelayedInit() {
    RDLog(@"DELAYED INIT: starting heavy work...");

    // ─── 步骤 1：路径缓存 ──────
    MKBuildPathCache();

    // ─── 步骤 2：进程枚举初始同步 ──────
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    MKComputeRunningSet();

    RDLog(@"DELAYED INIT: runningSet has %lu items", (unsigned long)sRunningSet.count);

    // ─── 步骤 3：检查 SBMainWorkspace hook 是否已触发 ──────
    // 如果 SBMainWorkspace hook 已经在延迟期间收到了状态变更通知，
    // runningSet 可能已经有内容了。进程枚举只是补充。

    // ─── 标记初始化完成 ──────
    sInitDone = YES;

    RDLog(@"DELAYED INIT: done. sInitDone=YES");
    RDLog(@"runningSet: %@", [[sRunningSet allObjects] componentsJoinedByString:@", "]);

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
    if (self.window && sInitDone) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MKUpdate(self);
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if (sInitDone) MKUpdate(self);
}

%end

// ====================================================================
// Hook — SBMainWorkspace（实时进程状态检测）
// process:stateDidChangeFromState:toState:
// arg1 = 进程对象（有 bundleIdentifier 或 applicationInfo.bundleIdentifier）
// arg3 = 状态对象（有 taskState: 1=Dead, 2=Running, 3=Suspended）
// ====================================================================

%hook SBMainWorkspace

- (void)process:(id)arg1 stateDidChangeFromState:(id)arg2 toState:(id)arg3 {
    %orig;

    @try {
        // ─── 提取 bundleIdentifier ──────────
        NSString *bid = nil;
        if ([arg1 respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            bid = [arg1 performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
        }
        if (!bid && [arg1 respondsToSelector:NSSelectorFromString(@"applicationInfo")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id appInfo = [arg1 performSelector:NSSelectorFromString(@"applicationInfo")];
            if (appInfo && [appInfo respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
                bid = [appInfo performSelector:NSSelectorFromString(@"bundleIdentifier")];
            }
#pragma clang diagnostic pop
        }

        // ─── 提取 taskState ──────────────────
        int newState = 0;
        if ([arg3 respondsToSelector:NSSelectorFromString(@"taskState")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            newState = [[arg3 performSelector:NSSelectorFromString(@"taskState")] intValue];
#pragma clang diagnostic pop
        }
        // taskState 不响应时，尝试描述字符串解析
        if (newState == 0 && arg3) {
            NSString *desc = [arg3 description];
            if ([desc containsString:@"Running"]) newState = kTaskStateRunning;
            else if ([desc containsString:@"Suspended"]) newState = kTaskStateSuspended;
            else if ([desc containsString:@"Dead"] || [desc containsString:@"NotRunning"]) newState = kTaskStateDead;
        }

        static int sHookLogs = 0;
        if (sHookLogs < 50) {
            sHookLogs++;
            RDLog(@"SBWS: %@ state=%d (arg1=%s arg3=%s)",
                  bid ?: @"(nil)", newState,
                  arg1 ? NSStringFromClass([arg1 class]).UTF8String : "nil",
                  arg3 ? NSStringFromClass([arg3 class]).UTF8String : "nil");
        }

        if (!bid.length) return;

        // ─── 更新 runningSet ──────────────
        if (newState == kTaskStateRunning || newState == kTaskStateSuspended) {
            MKAddToRunningSet(bid);
            RDLog(@"SBWS: + %@ (state=%d)", bid, newState);
            if (sInitDone) MKRefreshAllIcons();
        } else if (newState == kTaskStateDead) {
            MKRemoveFromRunningSet(bid);
            RDLog(@"SBWS: - %@ (state=%d)", bid, newState);
            if (sInitDone) MKRefreshAllIcons();
        }

    } @catch (NSException *e) {
        RDLog(@"SBWS exception: %@", e.reason);
    }
}

%end

// ====================================================================
// Hook — SBMainSwitcherController（补充检测入口）
// ====================================================================

%hook SBMainSwitcherController

- (void)_appActivationStateDidChange:(NSNotification *)notification {
    %orig;
    @try {
        NSString *bid = MKBidFromNote(notification);
        if (!bid.length) return;

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
            if (sInitDone) MKRefreshAllIcons();
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
            MKAddToRunningSet(bid);
            RDLog(@"_appActState(SBScene): %@", bid);
            if (sInitDone) MKRefreshAllIcons();
        }
    } @catch (NSException *e) {}
}

%end

// ====================================================================
// 构造函数（v1.4.3 核心修复：只做最轻量工作）
// ====================================================================

%ctor {
    %init;

    NSLog(@"[RunningDotIndicator] v1.4.3 ctor: minimal init (heavy work delayed 15s)");
    RDLog(@"======== v1.4.3 loading (minimal ctor) ========");

    // ⚠️ 紧急开关检查（最轻量，只检查文件是否存在）
    if (MKIsDisabled()) {
        RDLog(@"DISABLED at load; exiting ctor.");
        return;
    }

    // ─── 只注册最轻量的通知（不执行任何重量级操作）──────────
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

    // ─── 生命周期通知（轻量注册，不执行扫描）──────────
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
    };
    [lifecycleActions enumerateKeysAndObjectsUsingBlock:^(NSString *nm, NSString *act, BOOL *_) {
        id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:nm object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note){
            @try {
                NSString *bid = MKBidFromNote(note);
                static int sNoteDetailLogs = 0;
                if (sNoteDetailLogs < 30) {
                    sNoteDetailLogs++;
                    RDLog(@"NOTE: %@ bid=%@", note.name, bid ?: @"(nil)");
                }
                if (!bid) return;
                if ([act isEqualToString:@"add"]) {
                    MKAddToRunningSet(bid);
                    RDLog(@"LIFECYCLE + %@", bid);
                } else {
                    MKRemoveFromRunningSet(bid);
                    RDLog(@"LIFECYCLE - %@", bid);
                }
                if (sInitDone) MKRefreshAllIcons();
            } @catch (NSException *e) {
                RDLog(@"NOTE exception: %@", e.reason);
            }
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }];

    RDLog(@"======== ctor done (heavy work pending) ========");

    // ─── 延迟 15 秒执行重量级初始化 ──────────────────────
    // SpringBoard 启动约需 5-8 秒，15 秒延迟确保它完全加载后才开始扫描
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        MKSafe(^{ MKDelayedInit(); });
    });

    // ─── 定时刷新：每 8 秒（延迟初始化后才生效）───────
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                      dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),  // 首次 20 秒后
                              8 * NSEC_PER_SEC, 1.0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        MKSafe(^{ if (sInitDone) { MKComputeRunningSet(); MKRefreshAllIcons(); } });
    });
    dispatch_resume(timer);
}
