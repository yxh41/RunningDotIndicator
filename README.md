# RunningDotIndicator

> iOS 16 越狱插件：在桌面 App 图标旁为**运行中**的 App 名称添加可自定义的指示点。

## 功能

- 检测桌面 App 是否运行（前台或仍在多任务后台），在其名称旁显示一个指示点
- **显示范围可切换**：
  - 全部运行中（默认）—— 所有在多任务中的 App 都显示
  - 仅前台运行 —— 只显示曾到过前台的 App，纯后台服务（音乐播放、天气刷新等）不显示
- 完全可自定义：
  - **颜色**：13 种预设色 + **自定义十六进制颜色**（输入 `#FF6B00`，优先于预设）
  - **形状**：圆形 / 方形 / 三角形 / 菱形 / 五角星 / 心形
  - **大小**：3–14pt 滑块
  - **位置**：名称左侧 / 名称右侧
  - **不透明度**：0.1–1.0
- 修改设置后**即时生效**，无需注销
- 设置入口出现在系统「设置」App 中

## 运行环境

| 项 | 要求 |
|---|---|
| 系统 | iOS 15.0 ~ 16.x（主要面向 iOS 16） |
| 越狱 | Dopamine（A12–A15，rootless）或 palera1n（A11，rootless）|
| 依赖 | `mobilesubstrate`、`preferenceloader` |
| 架构 | `arm64` + `arm64e` |
| 打包 | rootless（`/var/jb` 前缀） |

> 当前为 rootless 方案。若使用 rootful 越狱，把根目录 `Makefile` 中 `THEOS_PACKAGE_SCHEME = rootless` 删除即可。

## 工程结构

```
RunningDotIndicator/
├── Makefile                          # 根 Makefile（tweak + prefs 聚合）
├── control                           # Debian 包元信息
├── RunningDotIndicator.plist         # 注入过滤器（仅 SpringBoard）
├── Tweak.x                          # 核心 hook：SBIconView + 运行检测
├── MKConfig.h / .m                  # 偏好读取单例
├── MKIndicatorDotView.h / .m        # 自绘指示点视图（6 种形状）
├── Preferences/
│   ├── Makefile                     # 偏好 Bundle Makefile
│   ├── RunningDotIndicatorPrefs.plist
│   ├── MKRootListController.h / .m  # 设置页控制器
│   └── Resources/Root.plist         # 设置项规格
└── layout/
    └── Library/PreferenceLoader/Preferences/
        └── RunningDotIndicator.plist  # 设置入口
```

## 构建方法（需 macOS / Linux）

本工程基于 [Theos](https://theos.dev)，需在 macOS 或 Linux 上编译（Windows 无法直接编译 iOS 越狱插件）。

### 1. 安装 Theos

```bash
# 参考官方文档 https://theos.dev/docs/installation
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

### 2. 安装 SDK

下载 `iPhoneOS16.5.sdk` 放到 `$THEOS/sdks/`：

```bash
# 示例
git clone --recursive https://github.com/theos/sdks.git $THEOS/sdks
# 或手动放入 iPhoneOS16.5.sdk
```

> 若只有其它版本 SDK，可把根 `Makefile` 中 `TARGET := iphone:clang:16.5:15.0` 的 SDK 版本改成你已有的（如 `15.5`）。

### 3. 编译

```bash
cd RunningDotIndicator
make package FINALPACKAGE=1
```

产物在 `packages/com.mk.runningdotindicator_1.0.0_iphoneos-arm64.deb`。

### 4. 安装到设备

**方式 A — Sileo / Zebra 直接安装 deb**

把 `.deb` 传到手机，用 Sileo/Zebra 打开安装。

**方式 B — SSH 命令安装**

```bash
scp packages/com.mk.runningdotindicator_1.0.0_iphoneos-arm64.deb mobile@<设备IP>:/var/mobile/
ssh mobile@<设备IP> "sudo dpkg -i /var/mobile/com.mk.runningdotindicator_1.0.0_iphoneos-arm64.deb"
```

**方式 C — Theos 直接安装（设备需配 SSH）**

```bash
make install THEOS_DEVICE_IP=<设备IP> THEOS_DEVICE_PORT=22
```

安装后 Sileo 会自动注销（respring），桌面即生效。

## 使用

1. 打开系统「设置」→ 滑到底部 →「运行指示点」
2. 开启开关
3. 选择显示范围：全部运行中 / 仅前台运行
4. 选择颜色（预设或自定义十六进制）/ 形状 / 大小 / 位置 / 不透明度
5. 返回桌面即可看到运行中的 App 旁出现指示点
6. 启动 / 退出 App 时指示点自动出现 / 消失

## 实现原理

### 运行中 App 检测

- 启动时通过 `SBMainWorkspace` 的 `runningApplicationContexts` 拉取当前运行 App 列表
- 监听 `SBApplicationDidLaunchNotification` / `SBApplicationDidExitNotification` 等通知实时增删
- 每 5 秒从 workspace 重新校准一次（防止 respring 后漏接通知）

### 前台 App 检测（foregroundOnly 模式）

- 维护独立的 `MKForegroundAppIDs` 集合
- 监听 `SBApplicationDidActivateNotification` / `SBApplicationDidForegroundNotification`，App 进入前台时加入集合
- App 完全退出时从集合移除（切到后台不移除，保持显示）
- `foregroundOnly = YES` 时，指示点只对 `MKForegroundAppIDs` 中的 App 显示

### 颜色解析

- 预设颜色存 `color` 键，自定义颜色存 `customColor` 键
- `MKConfig.color` 优先读 `customColor`，为空时回退到 `color`
- `colorFromHex:` 支持 `#RRGGBB` / `#RGB` / `RRGGBB` / `0xRRGGBB` 多种格式

### 指示点绘制

- hook `SBIconView -layoutSubviews`
- 取图标 `bundleIdentifier`，判断是否在运行集合中
- 在图标标签视图（类名含 `Label`）的左/右侧放置 `MKIndicatorDotView`
- `MKIndicatorDotView` 用 CoreGraphics 绘制 6 种形状

### 设置实时刷新

- 设置页每个项带 `PostNotification = com.mk.runningdotindicator.reload`
- Tweak 监听该 Darwin 通知，收到后重新读取配置并刷新所有 `SBIconView`

## 自定义扩展

- **加预设颜色**：在 `Root.plist` 颜色项的 `validTitles` / `validValues` 里加一组
- **加新形状**：在 `MKShape` 枚举加值，在 `MKIndicatorDotView -drawRect:` 加 `case` 绘制
- **改检测逻辑**：修改 `Tweak.x` 中运行集合 / 前台集合的维护逻辑

## 已知限制

- 仅注入 SpringBoard，因此只在桌面生效（不影响 App 资源库、文件夹内等由其它进程渲染的场景）
- 系统更新后若 `SBIconView` / `SBMainWorkspace` 私有 API 变动，可能需适配（代码用 KVC 容错，已尽量降低耦合）

## 免责声明

仅用于合法的越狱研究与个人定制。越狱可能影响设备安全与保修，请自行评估风险。
