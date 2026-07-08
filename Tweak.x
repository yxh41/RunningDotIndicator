//
//  Tweak.x — RunningDotIndicator v1.3.6
//  进程枚举版：通过 proc_listallpids + proc_pidpath 直接查进程表，
//  匹配 /var/containers/Bundle/Application/ 下 App 的 Info.plist → bundleID。
//  进程存在 = 绿点；进程不存在 = 无点。这才是真正意义上的"在运行"。
//  生命周期通知用于即时增删（响应更快），进程枚举用于每 3s 校准。
//  紧急开关：/var/mobile/Documents/rd_disabled 存在则整机不生效。
//

#import <UIKit/UIKit.h>
#import "MKConfig.h"
#import "MKIndicatorDotView.h"
#include <spawn.h>
#include <objc/runtime.h>

// libproc 函数声明（iOS 运行时存在，但 iPhoneOS SDK 不含此头文件，不能 #include <libproc.h>）
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

@interface SBRunningProcessManager : NSObject
+ (id)sharedInstance;
@end

// ─── 常量 ──────────────────────────────────────────────────
static NSInteger const kDotTag  = 9999;
static NSInteger const kTestTag = 7777;

// ─── 全局状态 ─────────────────────────────────────────────
static int   sCallCount   = 0;
static int   sRunningCount = 0;
static NSMutableSet<NSString*> *sRunningSet = nil;  // 当前运行中的 App bundleID 集合(每 3s 进程枚举刷新)
static NSMutableArray *sLifecycleObservers = nil;  // 生命周期通知观察者(防释放)
static NSTimeInterval sDisableTS = 0;  // 紧急开关检查节流时间戳
static BOOL  sDisableChecked = NO;
static BOOL  sDisabled = NO;

// ─── 文件日志（自身已保护）────────────────────────────────
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

// 紧急开关：存在 /var/mobile/Documents/rd_disabled 则整机禁用（方便救机）
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

// 安全包裹：任何回调抛异常都吞掉，绝不拖垮 SpringBoard
static void MKSafe(void (^block)(void)) {
    @try { if (block) block(); }
    @catch (NSException *e) {
        if (sCallCount < 5) RDLog(@"EXCEPTION caught: %@", e.reason);
    }
}

// ====================================================================
// 运行状态检测（全部做 respondsToSelector 校验）
// ====================================================================

// 一次性探测本机真实存在的私有类/方法名（调试用，保留但当前不调用）
__attribute__((unused))
static void MKProbe() {
    static BOOL done = NO;
    if (done) return; done = YES;

    int n = objc_getClassList(NULL, 0);
    if (n <= 0) return;
    Class *buf = (Class *)malloc(sizeof(Class) * n);
    n = objc_getClassList(buf, n);
    NSMutableArray *hits = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        NSString *name = NSStringFromClass(buf[i]);
        if ([name containsString:@"Switcher"] || [name containsString:@"Recent"] ||
            [name containsString:@"Running"] || [name containsString:@"Process"] ||
            [name containsString:@"AppSwitcher"] || [name containsString:@"Workspace"] ||
            [name isEqualToString:@"SBApplication"] ||
            [name isEqualToString:@"SBApplicationController"]) {
            BOOL si = [buf[i] respondsToSelector:@selector(sharedInstance)];
            [hits addObject:[NSString stringWithFormat:@"%@%@", name, si ? @"(+si)" : @""]];
        }
    }
    free(buf);
    RDLog(@"PROBE classes: %@", [hits componentsJoinedByString:@", "]);

    // 显式探测"前台 App 获取方法"是否存在（决定性，避免盲猜方法名）
    Class ctrlC = NSClassFromString(@"SBApplicationController");
    if (ctrlC && [ctrlC respondsToSelector:@selector(sharedInstance)]) {
        NSArray *fg = @[@"frontApplication",@"currentApplication",@"activeApplication",
                        @"foregroundApplication",@"_activeApplication",@"topApplication"];
        NSMutableArray *fr = [NSMutableArray array];
        for (NSString *s in fg) {
            BOOL ok = [ctrlC instancesRespondToSelector:NSSelectorFromString(s)];
            [fr addObject:[NSString stringWithFormat:@"%@=%@", s, ok?@"Y":@"N"]];
        }
        RDLog(@"PROBE front getters: %@", [fr componentsJoinedByString:@", "]);
    } else {
        RDLog(@"PROBE front getters: SBApplicationController unavailable");
    }

    NSArray *kws = @[@"unning",@"uspended",@"rocess",@"pplicationState",@"oreground",
                     @"ackground",@"ctive",@"ecent",@"pplication",@"odel",@"hared",@"pp"];
    NSArray *probeClasses = @[@"SBApplication",@"SBApplicationController",@"SBAppSwitcherModel",
                              @"SBAppSwitcherController",@"SBMainSwitcherController",
                              @"SBRecentAppListModel",@"SBRunningProcessManager"];
    for (NSString *cn in probeClasses) {
        Class c = NSClassFromString(cn);
        if (!c) { RDLog(@"PROBE %@ : NOT FOUND", cn); continue; }
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(c, &mc);
        NSMutableArray *ns = [NSMutableArray array];
        for (unsigned i = 0; i < mc; i++) {
            NSString *m = NSStringFromSelector(method_getName(ms[i]));
            for (NSString *kw in kws) {
                if ([m rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [ns addObject:m]; break;
                }
            }
        }
        free(ms);
        RDLog(@"PROBE %@ : %@", cn, [ns componentsJoinedByString:@", "]);
    }
}

// ====================================================================
// 运行状态检测（v1.3.6 — 进程枚举）
// 通过 proc_listallpids + proc_pidpath 枚举系统所有进程，
// 匹配 /var/containers/Bundle/Application/ 路径下的 App 进程，
// 读取其 Info.plist 获取 CFBundleIdentifier。
// 进程存在 → 绿点；进程不存在 → 无点。无宽限期，纯粹看进程在不在。
// ====================================================================

// 缓存：可执行文件全路径 → bundleID（避免每次读 Info.plist）
static NSMutableDictionary<NSString*, NSString*> *sPathToBundleID = nil;

static void MKAddToRunningSet(NSString *bid) {
    if (!bid.length) return;
    if (!sRunningSet) sRunningSet = [NSMutableSet set];
    [sRunningSet addObject:bid];
}

static void MKRemoveFromRunningSet(NSString *bid) {
    if (!bid.length) return;
    [sRunningSet removeObject:bid];
}

// 每 3 秒：扫描全部进程 → 找出所有用户 App → 更新运行集合
static void MKComputeRunningSet() {
    @try {
        if (!sPathToBundleID) sPathToBundleID = [NSMutableDictionary dictionary];
        NSMutableSet *newSet = [NSMutableSet set];

        int bufSize = proc_listallpids(NULL, 0);
        if (bufSize <= 0) return;
        int *pids = (int *)malloc(bufSize);
        int count = proc_listallpids(pids, bufSize);
        int numPids = count / sizeof(int);   // proc_listallpids 返回字节数

        for (int i = 0; i < numPids; i++) {
            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pids[i], pathBuf, sizeof(pathBuf)) <= 0) continue;

            NSString *fullPath = [NSString stringWithUTF8String:pathBuf];

            // 仅处理用户 App 进程（位于 Bundle/Application 或 /Applications）
            NSRange r = [fullPath rangeOfString:@"/var/containers/Bundle/Application/"];
            if (r.location == NSNotFound) {
                r = [fullPath rangeOfString:@"/Applications/"];
            }
            if (r.location == NSNotFound) continue;

            // 查缓存
            NSString *bid = sPathToBundleID[fullPath];
            if (!bid) {
                // 未缓存 → 读 Info.plist 取 CFBundleIdentifier
                // fullPath 格式: .../UUID/AppName.app/AppName
                NSString *appBundlePath = [fullPath stringByDeletingLastPathComponent];
                NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                bid = info[@"CFBundleIdentifier"];
                if (bid) sPathToBundleID[fullPath] = bid;
            }
            if (bid) [newSet addObject:bid];
        }
        free(pids);

        // 仅当日志量少时打印运行集合（首次和变化时）
        static int sProcLogs = 0;
        static NSSet *sLastProcSet = nil;
        if (sProcLogs < 10 && (!sLastProcSet || ![newSet isEqualToSet:sLastProcSet])) {
            sProcLogs++;
            RDLog(@"PROC enum: %lu running → %@",
                  (unsigned long)newSet.count,
                  [[newSet allObjects] componentsJoinedByString:@", "]);
        }
        sLastProcSet = [newSet copy];
        sRunningSet = newSet;
    } @catch (NSException *e) {
        if (sCallCount < 5) RDLog(@"PROC enum exception: %@", e.reason);
    }
}

// 进程是否存在（核心判定）
static BOOL MKIsAppLit(NSString *bid) {
    return sRunningSet && [sRunningSet containsObject:bid];
}

// 从 SpringBoard 应用生命周期通知中取出 bundleID（全程安全）
static NSString *MKBidFromNote(NSNotification *note) {
    @try {
        id obj = note.object;
        if (obj && [obj respondsToSelector:@selector(bundleIdentifier)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id b = [obj performSelector:@selector(bundleIdentifier)];
#pragma clang diagnostic pop
            if ([b isKindOfClass:[NSString class]]) return b;
        }
        NSDictionary *info = note.userInfo;
        for (id k in info) {
            id v = info[k];
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v containsString:@"."]) return v;
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
            [cls containsString:@"Label"] ||
            [cls containsString:@"label"]) {
            return sv;
        }
    }
    return nil;
}

// ====================================================================
// 主更新函数（全程安全）
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

        // 强制测试点：前 3 个图标画蓝色圆点（确认渲染通，不依赖检测）
        static int sTestDots = 0;
        if (sTestDots < 3 && sCallCount < 50) {
            sTestDots++;
            RDLog(@"TEST DOT #%d on %@", sTestDots, bundleID);
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
        if (sRunLogs < 30) { sRunLogs++; RDLog(@"RUNNING: %@ (call=%d, runCount=%d)", bundleID, sCallCount, sRunningCount); }

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

// 真正的 respring：在 SpringBoard 进程内执行（非沙盒，posix_spawn 可用）
static void MKDoRespring() {
    RDLog(@"RESPRING: executing kill from SpringBoard context");
    pid_t pid;
    const char *shArgs[] = {
        "/bin/sh", "-c",
        "PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH; "
        "sbreload 2>/dev/null || killall -9 SpringBoard 2>/dev/null || killall -9 backboardd 2>/dev/null",
        NULL
    };
    int ret = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)shArgs, NULL);
    RDLog(@"RESPRING: posix_spawn ret=%d pid=%d", ret, pid);
    // 不 waitpid：killall 会结束 SpringBoard 自身，本进程即将退出
}

static void MKRespringCallback(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    MKSafe(^{
        MKDoRespring();
    });
}

// ====================================================================
// Hook
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
// 构造函数
// ====================================================================

%ctor {
    NSLog(@"[RunningDotIndicator] v1.3.6 loaded (process enumeration via proc_listallpids + Info.plist)");
    RDLog(@"======== v1.3.6 loading (process enum, no grace period) ========");
    if (MKIsDisabled()) {
        RDLog(@"DISABLED at load; doing nothing.");
        return;
    }

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        MKPrefsChangedCallback,
        CFSTR("com.mk.runningdotindicator.reload"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    // 注销按钮：设置 App 发通知，由 SpringBoard(非沙盒)执行真正的 kill
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        MKRespringCallback,
        CFSTR("com.mk.runningdotindicator.respring"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    // 定时刷新：每 3 秒计算一次运行集合 + 刷新图标
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                      dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                              3 * NSEC_PER_SEC,
                              1.0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        MKSafe(^{
            MKComputeRunningSet();
            MKRefreshAllIcons();
        });
    });
    dispatch_resume(timer);

    // 应用生命周期通知：启动/恢复 → 即时加入；退出 → 即时移除。
    // 进程枚举每 3s 做全量校准，生命周期提供亚秒级响应速度。
    if (!sLifecycleObservers) sLifecycleObservers = [NSMutableArray array];
    NSDictionary *lifecycleActions = @{
        // 启动/恢复 → 加入运行集合
        @"SBApplicationDidFinishLaunchingNotification": @"add",
        @"SBApplicationDidBecomeActiveNotification":       @"add",
        @"SBApplicationWillResumeNotification":            @"add",
        @"SBApplicationDidResumeNotification":             @"add",
        // 退出/终止 → 从运行集合移除（即时，不等下次进程扫描）
        @"SBApplicationProcessDidExitNotification":        @"remove",
        @"SBApplicationDidExitNotification":               @"remove",
        // 挂起 → 忽略（进程仍存活，留给进程扫描判定）
        @"SBApplicationWillSuspendNotification":           @"ignore",
        @"SBApplicationDidSuspendNotification":            @"ignore",
    };
    [lifecycleActions enumerateKeysAndObjectsUsingBlock:^(NSString *nm, NSString *act, BOOL *_) {
        id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:nm object:nil queue:nil
                    usingBlock:^(NSNotification *note){
            @try {
                NSString *bid = MKBidFromNote(note);
                if (!bid) return;
                if ([act isEqualToString:@"add"]) {
                    MKAddToRunningSet(bid);
                    static int sLCLog = 0;
                    if (sLCLog < 20) { sLCLog++; RDLog(@"LIFECYCLE + %@ → %@", note.name, bid); }
                } else if ([act isEqualToString:@"remove"]) {
                    MKRemoveFromRunningSet(bid);
                    static int sLCRmLog = 0;
                    if (sLCRmLog < 20) { sLCRmLog++; RDLog(@"LIFECYCLE - %@ → %@", note.name, bid); }
                }
            } @catch (NSException *e) {}
        }];
        if (obs) [sLifecycleObservers addObject:obs];
    }];

    RDLog(@"======== loaded OK ========");
}
