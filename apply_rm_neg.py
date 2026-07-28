#!/usr/bin/env python3
# v2.0.66.30: 彻底移除 NEG 系列负一屏随机名诊断探针(用户拍板"撤")。
# 删除策略: 行号精确删除(自底向上) + 断言校验起始行 + 残留校验仅针对真实代码引用。
import sys, re

P = "Tweak.x"
lines = open(P, encoding="utf-8").read().split("\n")

# (start, end, 期望起始行含此子串)  —— end 含闭区间
blocks = [
    (2204, 2204, "MKNegContainerScan(UIView *container);"),               # 前向声明
    (2296, 2317, "NSString *txt = MKFindTextDeep(label);"),                # NEG-WIDGET-LABEL 内部诊断(保留外层 if+return 防误藏)
    (2437, 2477, "全 window 树 DFS 所有可见 UILabel"),                      # MKNegativeScreenDump + sNegDumpSeen
    (2479, 2508, "v2.0.66.22: 事件驱动负一屏 dump"),                        # MKNegEventDump + sNegEvtSeen/sNegContSeen
    (2511, 2546, "route A, dump-only): 负一屏/widget 容器级捕获"),          # MKNegContainerScan
    (2548, 2558, "以下 WidgetKit/SpringBoard 类若 iOS16 不存在"),           # %hook WGWidgetWrapperView
    (2560, 2569, "%hook WGWidgetListFooterView"),                          # %hook WGWidgetListFooterView
    (2571, 2576, "%hook WGPlatterHeaderContentView"),                      # %hook WGPlatterHeaderContentView
    (2578, 2587, "%hook SBTodayView"),                                     # %hook SBTodayView
    (2589, 2603, "本机负一屏真实容器是 SBFFocusIsolationView"),             # MKNegScreenContext
    (2604, 2639, "瞬态 setText 探针支持"),                                  # sAppDisplayNames/sAppNamesBuilt/MKViewChain/MKBuildAppNameSet
    (2641, 2653, "%hook SBFFocusIsolationView"),                           # %hook SBFFocusIsolationView
    (2655, 2671, "最终捕获版(彻底无门控)"),                                 # MKLabelInNegScreen
    (2672, 2709, "static NSMutableSet *sNegSetTextSeen = nil;"),           # sNegSetTextSeen/sNegSetTextCount + %hook UILabel
    (2723, 2723, "MKNegativeScreenDump();"),                               # MKScanStrayGeom 内调用
    (2812, 2812, "if (!hidden) MKNegEventDump((UIView *)self);"),         # MKSetHiddenHook 内调用
    (2853, 2853, "if (a > 0.0f) MKNegEventDump((UIView *)self);"),        # MKSetAlphaHook 内调用
]

# 校验起始行
for a, b, exp in blocks:
    if not (1 <= a <= b <= len(lines)):
        print("RANGE ERROR %d-%d (file has %d lines)" % (a, b, len(lines)))
        sys.exit(1)
    if exp not in lines[a - 1]:
        print("START MISMATCH @%d: expected %r, got %r" % (a, exp, lines[a - 1]))
        sys.exit(1)

before = len(lines)
for a, b, exp in sorted(blocks, reverse=True):
    del lines[a - 1:b]
text = "\n".join(lines)

# 版本戳 bump 2.0.66.29 -> 2.0.66.30
n = text.count("2.0.66.29")
text = text.replace("2.0.66.29", "2.0.66.30")
print("removed %d lines; version stamps bumped: %d" % (before - len(lines), n))

# 残留校验: 仅针对真实代码引用(剥离 // 注释与 @"..." 字符串)
stripped = re.sub(r'//[^\n]*', '', text)
stripped = re.sub(r'@"[^"]*"', '""', stripped)
removed = [
    "MKNegContainerScan", "MKNegEventDump", "MKNegativeScreenDump",
    "MKLabelInNegScreen", "MKNegScreenContext", "MKViewChain", "MKBuildAppNameSet",
    "sAppDisplayNames", "sAppNamesBuilt", "sNegDumpSeen", "sNegEvtSeen",
    "sNegContSeen", "sNegSetTextSeen", "sNegSetTextCount",
]
code_refs = [s for s in removed if s in stripped]
if code_refs:
    print("CODE REFS LEFT: %s" % ", ".join(code_refs))
    sys.exit(1)

# 主路径共享 helper 必须仍在
keep = ["MKLabelInDock", "MKIsIconNameLabel", "MKForeignContainerCtx",
        "sLastStrayLabel", "sLastStrayLog", "MKStrayNameProbe", "CTX-HIDE",
        "MKTrueParentIconView", "MKGetCachedBid"]
miss = [s for s in keep if s not in text]
if miss:
    print("MISSING SHARED HELPER: %s" % ", ".join(miss))
    sys.exit(1)

open(P, "w", encoding="utf-8").write(text)
print("OK: Tweak.x NEG probes removed, version -> 2.0.66.30, shared helpers intact")
