# 共享构建参数：根 Makefile 和 prefs 子工程都必须 include 这一份。
#
# 子工程一定要先 include 这个、再 include $(THEOS)/makefiles/common.mk，
# 否则会出现 Theos version mismatch（common.mk [version 0] vs rules.mk [version 1]）。
DEBUG ?= 0
FINALPACKAGE ?= 1

# 只编 arm64，不要 arm64e。
# L1ghtmann 工具链产出的 arm64e 切片 ABI 与 A16 不一致，dyld 映射后
# objc readClass 会 SIGBUS（崩溃日志：map_images_nolock -> readClass），
# 表现为 SpringBoard 安全模式 / 设置面板一打开就闪退。
# arm64 二进制在 arm64e 设备上原生运行，代价只是不走指针认证。
ARCHS = arm64

# rootless / roothide 都要求 iOS 15+；rootful 保留 14.0 下限
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
TARGET = iphone:clang:16.5:15.0
else
TARGET = iphone:clang:16.5:14.0
endif
