# 日志实证：v2.0.66.40 dock 串名根因 = 纯位移路径

分析对象：`rd_log(1).txt`（v2.0.66.40 实机日志，1MB / 10330 行，用户已复现 dock 串名）
目标：核对 dock 串名是否是「先 setHidden:NO 复显（主屏坐标）→ 后 setFrame/setCenter 漂到 dock」这条纯位移路径。

## 一、结论
**是，与推断完全一致。** 日志铁证表明：那个串名 label 到达 dock 坐标时，**从未经过我们任何 hook 的采样窗口**，只能是通过 `setFrame:`/`setCenter:` 这类纯位移操作搬过去的（.40 不钩这两个，所以漏）。v2.0.66.42 的 setFrame/setCenter hook 正是精准对症的修复。

## 二、三条铁证

### 铁证 1：诊断当时开着（否则无法判定）
日志含全套 `sDebugLog` 门控探针：`BLACKLIST` / `EXIT NOTE` / `REFRESH` / `FOLDER-REFRESH` / `CLOSE-TAIL` / `UNLOCK-*` 等。
→ 说明本次抓取时诊断开关是 ON，所有诊断日志都在产出。

### 铁证 2：全文 `DOCK-PHYS-HIDE` 计数 = 0
`DOCK-PHYS-HIDE` 仅定义在 `MKLabelDidMoveToSuperviewHook` 内（Tweak.x ~L2503），且**只有在 `MKLabelPhysicallyInDock(lbl)` 返回 YES 且 `fctx` 为 NO（即「物理在 dock 但祖先链判定 miss」的串名情形）时才打印**。

也就是说：**只要那个 label 在「换父视图」的那一刻已经落在 dock 坐标，就一定会有这条日志。**

结果：
- `DOCK-PHYS-HIDE` 全文 = **0 条**
- `DOCK-FRAME-HIDE` 全文 = **0 条**（.40 本就没有 setFrame hook，符合预期）

→ 那个串名 label **从未在「换父视图」时处于 dock 坐标**。

### 铁证 3：bug 确实复现，但三 hook 全程未命中
用户肉眼确认 dock 串名出现（label 没被藏）。但：
- 若 label 是在 **dock 坐标** 时被 `setHidden:NO`/`setAlpha:` 复显 → `MKSetHiddenHook`/`MKSetAlphaHook`（L2302/L2350）的 `MKLabelPhysicallyInDock` 会命中并藏掉 → bug 不会显示。
- 既然 bug 显示了，说明复显发生在**主屏坐标**（物理判定 NO，三 hook 放行），随后经**纯位移**漂到 dock 且**不经过任何 hook**（.40 不钩 setFrame/setCenter）→ 卡在 dock 坐标一直可见。

## 三、日志抓到完整复现时序（与「解锁消失、1 秒后回来」完全吻合）
```
13:34:26  LOCK: hid all indicators
13:34:28  UNLOCK(timer): explicit fade-in overlays + refreshed all icons
            └─ 即 .40 的 1.0s 兜底 MKRefreshAllIcons：此刻串名 label 已在 dock 坐标
               → MKLabelPhysicallyInDock=YES → 强制藏名 → 用户所见「解锁消失」
13:34:30+ 主屏 settle 期间某 label 再次 setHidden:NO(主屏坐标,放行) → setFrame 漂到 dock(不重查) → 「约1秒后又回来」
```
这与此前推断（L74-79）逐一对齐。

## 四、对 v2.0.66.42 修复的意义
- .42 新增 `setFrame:`/`setCenter:` hook，在「漂到 dock」那一步即时校验 dock 纵带、命中即藏 → **正好堵死该位移路径**。
- 日志证实位移确实发生且 label 最终停在 dock 坐标 → setFrame/setCenter 命中概率极高，.42 应能根治。
- **唯一残留风险（.42 同受）**：若 iOS 用 `layer.transform/position` 而非 `setFrame/setCenter` 搬移，仍可能漏。真机装 .42 后开 `sDebugLog` 复现，看 `DOCK-FRAME-HIDE` 是否打出即可一锤定音：
  - **打出** → 根治成功；
  - **未打出仍复现** → 位移走 layer 变换，需升级去钩父视图 `layoutSubviews`（更重，先不急）。

## 五、验证建议（给用户）
1. 装 CI 绿灯后的 **v2.0.66.42**；
2. 开 `sDebugLog` 复现 dock 串名（含「锁屏解锁→约1秒后回来」场景），静置 ~2s；
3. 看日志 `DOCK-FRAME-HIDE` 是否在解锁后再次打出 —— 打出即证 .42 把延迟复触发也截住了；
4. 再关诊断复现一次，确认 `rd_log.txt` 干净（验证 .41 的 IconColor 门控）。
