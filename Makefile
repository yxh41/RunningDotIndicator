# =============================================================================
#  RunningDotIndicator - 在桌面 App 图标旁为运行中的 App 添加可自定义指示点
#  适用于 iOS 15 ~ 16 (rootful / rootless / roothide, arm64 / arm64e)
#  构建环境: macOS / Linux + Theos + iPhoneOS16.x SDK
# =============================================================================

# 目标: SDK 16.5, 最低部署版本 15.0(向上兼容 iOS 16)
TARGET := iphone:clang:16.5:15.0

# 包类型: rootful / rootless(默认) / roothide
# rootful  → Architecture=iphoneos-arm,    装到 /
# rootless → Architecture=iphoneos-arm64,  装到 /var/jb/
# roothide → Architecture=iphoneos-arm64e, 装到 /var/jb/
PACK_TYPE ?= rootless

ifeq ($(PACK_TYPE),rootful)
    THEOS_PACKAGE_SCHEME =
else
    THEOS_PACKAGE_SCHEME = rootless
endif

# roothide: 由 GitHub Actions 在构建后通过 dpkg-deb 重打包生成,
# 不在 Makefile 层面处理 (Theos 会强制覆盖 Architecture 字段)

ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RunningDotIndicator

RunningDotIndicator_FILES = \
	Tweak.x \
	MKConfig.m \
	MKIndicatorDotView.m

RunningDotIndicator_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RunningDotIndicator_FRAMEWORKS = UIKit Foundation
RunningDotIndicator_PRIVATE_FRAMEWORKS = SpringBoard

# MobileSubstrate 注入目标: 必须明确声明
RunningDotIndicator_FILTER_BUNDLES = com.apple.springboard

include $(THEOS_MAKE_PATH)/tweak.mk

# 偏好设置子工程
SUBPROJECTS = Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
