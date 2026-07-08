//
//  Tweak.x — RunningDotIndicator v1.4.2
//  v1.4.2 核心改动：
//    ✅ Hook SBMainWorkspace.process:stateDidChangeFromState:toState: (实时检测)
//    ✅ SBApplicationController.runningApplications (启动时初始同步)
//    ✅ NSFileManager 扫描替代彻底失败的 LSProxy 缓存
//    ✅ 保留 proc_listallpids 作为终极回退
//    ✅ 生命周期通知作为补充
//  已废弃方案（禁止回退）：
//    ❌ LSApplicationProxy.applicationProxyForIdentifier: (iOS 16 unrecognized selector)
//    ❌ SBApplication.isRunning (iOS 16 不存在)
//    ❌ SBRunningProcessManager/SBAppSwitcher*/SBRecentAppListModel (全部 nil)
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

// SBApplicationController — 管理所有 SBApplication 实例
@interface SBApplicationController : NSObject
+ (id)sharedInstance;
+ (id)sharedInstanceIfExists;
- (id)applicationWithBundleIdentifier:(NSString *)bundleID;
- (NSArray *)allApplications;
- (NSArray *)runningApplications;
@end

// SBApplication — 代表单个应用（iOS 16 仍有 pid、bundleIdentifier）
@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) pid_t pid;
@end

// SBMainWorkspace — iOS 16 进程状态变更入口
@interface SBMainWorkspace : NSObject
@end

// FBApplicationProcess — FrontBoard 进程表示
@interface FBApplicationProcess : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@end

// FBProcessState — 进程状态
@interface FBProcessState : NSObject
@property (nonatomic, readonly) int taskState;  // 1=Dead, 2=Running, 3=Suspended
@end

// FBSSystemService — 通过 bundleID 获取 PID
@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (pid_t)pidForApplication:(NSString *)bundleId;
@end

// ─── 常量 ──────────────────────────────────────────────────
static NSInteger const kDotTag  = 9999;
static NSInteger const kTestTag = 7777;

// ─── taskState 枚举 ──────────────────────────────────────────
static int const kTaskStateDead      = 1;  // 进程已终止
static int const kTaskStateRunning   = 2;  // 进程正在运行（前台）
static int const kTaskStateSuspended = 3;  // 进程已挂起（后台）

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
        if (sCallCount < 5) RDLog(@"EXCEPTION caught: %@", e.reason);
    }
}

// ====================================================================
// 运行状态检测（v1.4.2 — 三层策略：Hook + SBAppCtrl + 进程枚举）
// ====================================================================

// ─── 策略 0：NSFileManager 扫描构建 bundleID↔executablePath 映射 ────
// 替代彻底失败的 LSProxy 缓存（applicationProxyForIdentifier: 不存在）
static void MKBuildPathCache() {
    if (!sBidToExePath) sBidToExePath = [NSMutableDictionary dictionary];
    if (!sPathToBundleID) sPathToBundleID = [NSMutableDictionary dictionary];

    NSFileManager *fm = [NSFileManager defaultManager];
    int added = 0;

    // ─── 扫描 App Store 用户应用 ──────────
    NSArray *scanDirs = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application"
    ];

    for (NSString *baseDir in scanDirs) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:baseDir error:nil];
        if (!uuids) continue;

        for (NSString *uuid in uuids) {
            // 跳过 roothide 前缀目录（.jbroot-XXX），里面是越狱工具不是普通 App
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

    // ─── 扫描系统内置应用 /Applications/ ──────────
    NSArray *sysDirs = @[
        @"/Applications",
        @"/private/var/containers/Bundle/Application"  // 可能还有系统 App 在此
    ];
    for (NSString *sysDir in sysDirs) {
        NSArray *sysApps = [fm contentsOfDirectoryAtPath:sysDir error:nil];
        if (!sysApps) continue;

        for (NSString *item in sysApps) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;

            NSString *appDir = [sysDir stringByAppendingPathComponent:item];
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

    // ─── 尝试从 LSApplicationRecord 取 applicationURL（额外补充）─────
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id ws = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
            if (ws) {
                NSArray *records = [ws performSelector:NSSelectorFromString(@"allInstalledApplications")];
                if (records && records.count > 0) {
                    for (id record in records) {
                        @try {
                            // 尝试从 LSApplicationRecord 获取 applicationURL
                            // applicationURL → NSURL → .app 目录路径
                            NSURL *appURL = nil;
                            if ([record respondsToSelector:NSSelectorFromString(@"applicationURL")]) {
                                appURL = [record performSelector:NSSelectorFromString(@"applicationURL")];
                            }
                            if (!appURL && [record respondsToSelector:NSSelectorFromString(@"bundleURL")]) {
                                appURL = [record performSelector:NSSelectorFromString(@"bundleURL")];
                            }
                            if (!appURL && [record respondsToSelector:NSSelectorFromString(@"installURL")]) {
                                appURL = [record performSelector:NSSelectorFromString(@"installURL")];
                            }
                            if (!appURL) continue;

                            NSString *appDirPath = [appURL path];
                            if (!appDirPath.length || ![appDirPath hasSuffix:@".app"]) continue;

                            // 如果 NSFileManager 扫描已经缓存了此 bid，跳过
                            NSString *bid = nil;
                            if ([record respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
                                bid = [record performSelector:NSSelectorFromString(@"bundleIdentifier")];
                            }
                            if (!bid.length) continue;
                            if (sBidToExePath[bid]) continue;  // 已缓存

                            // 读取 Info.plist 获取 executable name
                            NSString *plistPath = [appDirPath stringByAppendingPathComponent:@"Info.plist"];
                            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                            NSString *exeName = info[@"CFBundleExecutable"];
                            if (!exeName.length) continue;

                            NSString *exePath = [appDirPath stringByAppendingPathComponent:exeName];
                            sBidToExePath[bid] = exePath;
                            sPathToBundleID[exePath] = bid;
                            added++;
                        } @catch (NSException *e) {
                            // 单条异常不中断整体
                        }
                    }
                }
            }
#pragma clang diagnostic pop
        }
    } @catch (NSException *e) {
        RDLog(@"LSRecord fallback exception: %@", e.reason);
    }

    sPathCacheReady = YES;
    RDLog(@"PathCache: cached %d apps via NSFileManager + LSRecord", added);

    // 诊断：打印几个示例
    NSArray *sample = [sBidToExePath allKeys];
    for (int i = 0; i < MIN(5, (int)sample.count); i++) {
        RDLog(@"PathCache sample: %@ → %@", sample[i], sBidToExePath[sample[i]]);
    }
}

// ─── 策略 1：SBApplicationController.runningApplications（启动初始同步）───
static void MKInitRunningFromSBAppCtrl() {
    @try {
        Class ctrlClass = NSClassFromString(@"SBApplicationController");
        if (!ctrlClass) { RDLog(@"SBAppCtrl: class NOT found"); return; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id ctrl = [ctrlClass performSelector:NSSelectorFromString(@"sharedInstance")];
        if (!ctrl) { RDLog(@"SBAppCtrl: sharedInstance nil"); return; }

        // 尝试 runningApplications
        NSArray *running = nil;
        if ([ctrl respondsToSelector:NSSelectorFromString(@"runningApplications")]) {
            running = [ctrl performSelector:NSSelectorFromString(@"runningApplications")];
            RDLog(@"SBAppCtrl: runningApplications returned %lu apps",
                  (unsigned long)(running ? running.count : 0));
        } else {
            RDLog(@"SBAppCtrl: runningApplications NOT available, fallback to allApplications");
            // 回退：遍历 allApplications 并逐个检查
            NSArray *all = [ctrl performSelector:NSSelectorFromString(@"allApplications")];
            if (all) {
                NSMutableArray *filtered = [NSMutableArray array];
                for (id app in all) {
                    // 检查 pid > 0 表示有运行进程
                    pid_t pid = 0;
                    if ([app respondsToSelector:NSSelectorFromString(@"pid")]) {
                        pid = (pid_t)[[app performSelector:NSSelectorFromString(@"pid")] intValue];
                    }
                    if (pid > 0) {
                        [filtered addObject:app];
                    }
                }
                running = filtered;
                RDLog(@"SBAppCtrl: allApplications filter by pid>0 → %lu running",
                      (unsigned long)running.count);
            }
        }
#pragma clang diagnostic pop

        if (!running || !running.count) {
            RDLog(@"SBAppCtrl: no running apps found");
            return;
        }

        // 从 SBApplication 对象提取 bundleIdentifier
        if (!sRunningSet) sRunningSet = [NSMutableSet set];
        int added = 0;
        for (id app in running) {
            NSString *bid = nil;
            if ([app respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                bid = [app performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
            }
            if (bid.length) {
                [sRunningSet addObject:bid];
                added++;
            }
        }
        RDLog(@"SBAppCtrl: added %d bundleIDs to runningSet", added);
        RDLog(@"SBAppCtrl initial: %@", [[sRunningSet allObjects] componentsJoinedByString:@", "]);

    } @catch (NSException *e) {
        RDLog(@"SBAppCtrl exception: %@", e.reason);
    }
}

// ─── 策略 2：Hook SBMainWorkspace（实时检测，最核心）────────────
// 见下方 %hook SBMainWorkspace 部分

// ─── 策略 3：进程枚举回退（proc_listallpids）──────────────────
static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    [sRunningSet removeObject:bid];
}

// 从进程路径提取 bundleID
static NSString *MKBidFromPath(NSString *fullPath) {
    // ─── 方法 1：PathCache 直查 ──────────────
    NSString *bid = sPathToBundleID[fullPath];
    if (bid) return bid;

    // ─── 方法 2：Info.plist 回退 ──────────────
    NSString *appBundlePath = [fullPath stringByDeletingLastPathComponent];
    // 处理 App Extension: .../AppName.app/PlugIns/Ext.appex/Executable
    //                    → 需要向上再跳两层到 AppName.app
    if ([appBundlePath hasSuffix:@".appex"]) {
        appBundlePath = [[appBundlePath stringByDeletingLastPathComponent]
                         stringByDeletingLastPathComponent];  // → .../AppName.app
    }
    if ([appBundlePath hasSuffix:@".app"]) {
        NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *bidFromInfo = info[@"CFBundleIdentifier"];
        if (bidFromInfo) {
            sPathToBundleID[fullPath] = bidFromInfo;
            RDLog(@"PROC: Info.plist fallback: %@", bidFromInfo);
            return bidFromInfo;
        }
    }

    // ─── 方法 3：.app 目录名模糊匹配 ──────────
    NSString *appName = [appBundlePath lastPathComponent];
    if ([appName hasSuffix:@".app"] && sBidToExePath) {
        for (NSString *cachedBid in sBidToExePath) {
            NSString *cachedPath = sBidToExePath[cachedBid];
            if ([cachedPath containsString:appName]) {
                sPathToBundleID[fullPath] = cachedBid;
                RDLog(@"PROC: fuzzy match %@ → %@", appName, cachedBid);
                return cachedBid;
            }
        }
    }

    return nil;
}

static void MKComputeRunningSet() {
    @try {
        int pidBuf[512];
        int bufBytes = sizeof(pidBuf);
        int retBytes = proc_listallpids(pidBuf, bufBytes);

        if (retBytes <= 0) {
            RDLog(@"PROC: proc_listallpids FAILED ret=%d", retBytes);
            return;
        }

        int numPids = retBytes / sizeof(int);

        static int sProcEntryLogs = 0;
        if (sProcEntryLogs < 5) {
            sProcEntryLogs++;
            RDLog(@"PROC: %d total PIDs (ret=%d)", numPids, retBytes);
        }

        // ─── 诊断：首次扫描时 dump 所有路径 ──────────
        static int sFullDumpDone = 0;
        if (sFullDumpDone == 0) {
            sFullDumpDone = 1;
            RDLog(@"PROC: === FULL PATH DUMP (first scan only) ===");
            int dumpCount = 0;
            for (int i = 0; i < numPids && dumpCount < 100; i++) {
                char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
                if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;
                NSString *p = [NSString stringWithUTF8String:pathBuf];
                if (p.length > 0) {
                    RDLog(@"PROC dump [%d]: pid=%d path=%@", dumpCount, pidBuf[i], p);
                    dumpCount++;
                }
            }
            RDLog(@"PROC: === END DUMP (%d paths) ===", dumpCount);
        }

        // ─── 遍历进程路径 → 匹配 App → 反查 bundleID ──────
        NSMutableSet *procSet = [NSMutableSet set];
        int appProcessCount = 0;
        int matchedCount = 0;
        int unmatchedPaths = 0;

        for (int i = 0; i < numPids; i++) {
            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pidBuf[i], pathBuf, sizeof(pathBuf)) <= 0) continue;

            NSString *fullPath = [NSString stringWithUTF8String:pathBuf];

            // 过滤：只关注 App 进程路径
            BOOL isAppPath = NO;
            if ([fullPath containsString:@"/Bundle/Application/"]) {
                isAppPath = YES;
            } else if ([fullPath containsString:@".app/"]) {
                // 放宽过滤：任何包含 .app/ 的路径（包括 /Applications/）
                // 排除 /var/jb/ 和 /usr/ 等系统路径
                if (![fullPath containsString:@"/var/jb/"] &&
                    ![fullPath hasPrefix:@"/usr/"]) {
                    isAppPath = YES;
                }
            }

            if (!isAppPath) continue;
            appProcessCount++;

            NSString *bid = MKBidFromPath(fullPath);

            if (bid) {
                // 如果是 App Extension，映射到父 App 的 bundleID
                // Extension 的 bundleID 格式：parentBundleID.extensionName
                // 我们要显示的是父 App 的指示点
                if ([bid containsString:@"."]) {
                    // 检查是否是已知 App 的 Extension
                    // Extension bundleID 通常是 parent.appName.extName
                    // 我们需要找到父 App 的 bundleID
                    // 简单方法：在 bidToExePath 中查找
                    NSString *parentBid = sBidToExePath[bid];
                    if (parentBid) {
                        // 这是已知 Extension，它的进程说明父 App 在运行
                        // 但 Extension bundleID 和 父 App bundleID 不同
                        // 我们需要从 Extension bundleID 推导父 App bundleID
                        // 目前不做推导，直接用 Extension 的 bundleID
                    }
                }
                [procSet addObject:bid];
                matchedCount++;
            } else {
                unmatchedPaths++;
                static int sUnmatchLogs = 0;
                if (sUnmatchLogs < 10) {
                    sUnmatchLogs++;
                    RDLog(@"PROC: UNMATCHED %@", fullPath);
                }
            }
        }

        // ─── 进程枚举结果不直接覆盖 runningSet，而是作为补充 ──────
        // 主策略（SBMainWorkspace hook + SBAppCtrl）已经维护了 runningSet
        // 进程枚举只补充尚未被 hook 检测到的 App
        int supplemented = 0;
        for (NSString *bid in procSet) {
            if (!sRunningSet || ![sRunningSet containsObject:bid]) {
                MKAddToRunningSet(bid);
                supplemented++;
                RDLog(@"PROC supplement: %@ (not in runningSet)", bid);
            }
        }

        static int sProcResultLogs = 0;
        if (sProcResultLogs < 10) {
            sProcResultLogs++;
            RDLog(@"PROC result: appProc=%d matched=%d unmatched=%d supplemented=%d runningSet=%lu",
                  appProcessCount, matchedCount, unmatchedPaths, supplemented,
                  (unsigned long)sRunningSet.count);
        }

    } @catch (NSException *e) {
        RDLog(@"PROC exception: %@", e.reason);
    }
}

static BOOL MKIsAppRunning(NSString *bundleID) {
    return sRunningSet && [sRunningSet containsObject:bundleID];
}

// ─── 从通知提取 bundleID（保留用于补充）───────────────────────────
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
// Hook — SBIconView
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

// ====================================================================
// Hook — SBMainWorkspace（v1.4.2 核心新增：实时进程状态检测）
// iOS 16 的关键切入点：
//   process:stateDidChangeFromState:toState:
//   arg1 = FBApplicationProcess（有 bundleIdentifier）
//   arg3 = FBProcessState（有 taskState: 1=Dead, 2=Running, 3=Suspended）
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
        // 也可以尝试从 applicationInfo 取
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
        // 如果 taskState 不响应，尝试 rawDescription 或其他属性
        if (newState == 0 && arg3) {
            NSString *desc = [arg3 description];
            RDLog(@"SBWS: state desc: %@", desc);
        }

        static int sHookLogs = 0;
        if (sHookLogs < 50) {
            sHookLogs++;
            RDLog(@"SBWS: %@ state=%d (arg1=%s arg3=%s)",
                  bid ?: @"(nil)", newState,
                  arg1 ? NSStringFromClass([arg1 class]).UTF8String : "nil",
                  arg3 ? NSStringFromClass([arg3 class]).UTF8String : "nil");
        }

        if (!bid.length) {
            RDLog(@"SBWS: no bundleID extracted from arg1 class=%s",
                  arg1 ? NSStringFromClass([arg1 class]).UTF8String : "nil");
            return;
        }

        // ─── 更新 runningSet ──────────────
        // taskState 2=Running, 3=Suspended → 进程还在 → 显示绿点
        // taskState 1=Dead → 进程已杀 → 移除绿点
        if (newState == kTaskStateRunning || newState == kTaskStateSuspended) {
            MKAddToRunningSet(bid);
            RDLog(@"SBWS: + %@ (state=%d)", bid, newState);
            MKRefreshAllIcons();
        } else if (newState == kTaskStateDead) {
            MKRemoveFromRunningSet(bid);
            RDLog(@"SBWS: - %@ (state=%d)", bid, newState);
            MKRefreshAllIcons();
        } else if (newState == 0) {
            // 无法解析 state，不做修改（由 proc enum 或 SBAppCtrl 校准）
            RDLog(@"SBWS: %@ (state unknown, skip)", bid);
        }

    } @catch (NSException *e) {
        RDLog(@"SBWS exception: %@", e.reason);
    }
}

%end

// ====================================================================
// Hook — SBApplication（补充：进程状态变更通知）
// 有些 iOS 版本通过 SBApplication 发送 _noteProcess:didChangeToState:
// ====================================================================

%hook SBApplication

- (void)_noteProcess:(id)process didChangeToState:(id)state {
    %orig;

    @try {
        NSString *bid = nil;
        if ([self respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            bid = [self performSelector:NSSelectorFromString(@"bundleIdentifier")];
#pragma clang diagnostic pop
        }

        int taskState = 0;
        if ([state respondsToSelector:NSSelectorFromString(@"taskState")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            taskState = [[state performSelector:NSSelectorFromString(@"taskState")] intValue];
#pragma clang diagnostic pop
        }

        static int sNoteProcessLogs = 0;
        if (sNoteProcessLogs < 30) {
            sNoteProcessLogs++;
            RDLog(@"SBApp._noteProc: %@ state=%d", bid ?: @"(nil)", taskState);
        }

        if (bid.length) {
            if (taskState == kTaskStateRunning || taskState == kTaskStateSuspended) {
                MKAddToRunningSet(bid);
            } else if (taskState == kTaskStateDead) {
                MKRemoveFromRunningSet(bid);
            }
            MKRefreshAllIcons();
        }
    } @catch (NSException *e) {}
}

%end

// ====================================================================
// Hook — SBMainSwitcherController（保留，作为补充检测入口）
// ====================================================================

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
            MKRefreshAllIcons();
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
            MKRefreshAllIcons();
        }
    } @catch (NSException *e) {}
}

%end

// ====================================================================
// 构造函数
// ====================================================================

%ctor {
    %init;

    NSLog(@"[RunningDotIndicator] v1.4.2 loaded (SBMainWorkspace hook + NSFileManager + SBAppCtrl)");
    RDLog(@"======== v1.4.2 loading ========");
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

    // ─── 步骤 1：NSFileManager 扫描构建路径缓存 ──────
    MKBuildPathCache();

    // ─── 步骤 2：SBApplicationController 初始同步 ──────
    MKInitRunningFromSBAppCtrl();

    // ─── 步骤 3：进程枚举补充 ──────────────────────
    MKComputeRunningSet();

    RDLog(@"Initial scan: %lu items in runningSet", (unsigned long)sRunningSet.count);
    RDLog(@"runningSet: %@", [[sRunningSet allObjects] componentsJoinedByString:@", "]);

    // ─── 定时刷新：每 5 秒 ────────────────────────────
    // 降低频率：SBMainWorkspace hook 已经实时更新
    // 定时器主要用于 proc_enum 补充检测 + 刷新图标
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                      dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                              5 * NSEC_PER_SEC, 1.0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        MKSafe(^{ MKComputeRunningSet(); MKRefreshAllIcons(); });
    });
    dispatch_resume(timer);

    // ─── 生命周期通知（补充）─────────────────────────────
    // 注意：iOS 16 上只有 SBApplicationDidExitNotification 有效
    // launch/add 类通知不再发送，由 SBMainWorkspace hook 替代
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
                if (sNoteDetailLogs < 50) {
                    sNoteDetailLogs++;
                    RDLog(@"NOTE: %@ bid=%@ obj=%s",
                          note.name, bid ?: @"(nil)",
                          note.object ? NSStringFromClass([note.object class]).UTF8String : "nil");
                }
                if (!bid) return;
                if ([act isEqualToString:@"add"]) {
                    MKAddToRunningSet(bid);
                    RDLog(@"LIFECYCLE + %@ → %@", nm, bid);
                } else if ([act isEqualToString:@"remove"]) {
                    MKRemoveFromRunningSet(bid);
                    RDLog(@"LIFECYCLE - %@ → %@", nm, bid);
                }
                MKRefreshAllIcons();
            } @catch (NSException *e) {
                RDLog(@"NOTE exception: %@", e.reason);
            }
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }];

    RDLog(@"======== loaded OK ========");
}
