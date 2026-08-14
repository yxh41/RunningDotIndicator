# RunningDotIndicator 全代码核对报告（v2.0.66.42）

核对时间：2026-08-03 | 基线：v2.0.66.42（commit `3929927`，本地领先 origin 5 提交未推）

## 结论
**未发现编译错误、逻辑 bug、递归死循环或内存泄漏。** 本次重点核验了 v2.0.66.42 新增的 `setFrame:`/`setCenter:` 位移拦截 hook（之前唯一未过 CI 验证的改动），并通盘复核了版本号一致性与 `-Werror` 风险面。

---

## 一、v2.0.66.42 新增 hook 逐项核验

### 1. `MKSetFrameHook` / `MKSetCenterHook`（Tweak.x L2370 / L2388）
| 检查项 | 结果 |
|---|---|
| orig 解析 | `MKResolveOrigIMP(...)` 调用签名与全部既有 hook 完全一致（已验证函数），双字典查找正确 |
| 递归守卫 | `orig != MKSetFrameHook` —— orig 恒为 superclass 实现，绝不等于本 hook，无自递归 |
| 异常防护 | 外层 `%orig` 与内层判定均 `@try/@catch` 包裹，异常仅 `RDLog` 不崩溃 |
| 零分配早退 | `if (lbl.hidden || lbl.alpha <= 0.01f) return;` 已藏/不可见直接返回，不爬层级 |
| 校验时序 | `MKLabelPhysicallyInDock` 在 `%orig` 应用新 frame **之后**调用 → 查的是搬到位后的 dock 坐标 ✓ |
| 诊断门控 | `DOCK-FRAME-HIDE` 被 `if (sDebugLog)` 包裹，诊断关零输出 |

### 2. 安装逻辑（Tweak.x L2707–L2749）
| 检查项 | 结果 |
|---|---|
| 钩得上 | 本类重写 setFrame: → `class_replaceMethod` 取旧 IMP；继承来的 → `class_addMethod` 强制挂 override（避免 `method_setImplementation` 钩不上继承方法的缺陷） |
| orig 取值 | 两分支 orig 均非 NULL，正确存入 NSString + CF 双字典 |
| 类型编码 | `method_getTypeEncoding(mf/supMf)` 按是否重写分别取对 |
| `sup` 作用域 | `Class sup = class_getSuperclass(cls)` 在 L2655 声明，位于安装块之前，作用域内 ✓ |
| 幂等早退 | 放宽成"四 hook 全装才 return"；`MKHookOneLabelClass` 每类仅调一次（L2836 循环），即便某类未重写 setHidden 被跳过也不影响 setFrame 安装 |

---

## 二、全局一致性核验
- **版本号三处一致**：`control` / `Preferences/Resources/Root.plist` / `Tweak.x` RDBUILD 横幅 均为 `2.0.66.42` ✓
- **`-Werror` 风险面**（CI 强制警告即错误）：
  - RDLog 串无字面 `%`、无嵌入 ASCII 直引号（仅 `%@` + 全角书名号注释）✓
  - 无 forward-class 强制 cast ✓
  - 无非常量静态初始化（CGRectZero 类问题）✓
  - 两新 hook 均被安装，无 `unused-function` ✓

---

## 三、已知残留风险（非新 bug，属既有物理判定同风险类）
- 新 hook 把 dock 物理判定的检查频率从"显隐变化时才查"提升到"每帧位移都查"。**滚动瞬态**下若某 home 网格 label 的 midY 短暂落入 dock 纵带，会被误藏一帧；但下一 `setHidden`/`setAlpha`/`MKUpdate` 即复原（home 网格底排稳态不与 dock 带重叠，无稳态回归）。
- 若系统用 `layer.transform/position` 直接搬移（完全不调 `setFrame:`/`setCenter:`），此版仍可能漏——需真机开 `sDebugLog` 看 `DOCK-FRAME-HIDE` 是否触发以坐实；若漏则升级钩父视图 `layoutSubviews`（更重，先不急）。

---

## 四、待办
1. 需推送 5 个积压提交（含 `.42`）触发 CI 验证；旧 PAT 建议 revoke。
2. 真机验证：先 `sDebugLog=ON` 复现 dock 串名并确认 `DOCK-FRAME-HIDE` 打出 → 再关诊断确认 `rd_log.txt` 干净。
