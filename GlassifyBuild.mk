# 共享构建参数：根 Makefile 和 prefs 子工程都必须 include 这一份。
#
# 子工程一定要先 include 这个、再 include $(THEOS)/makefiles/common.mk，
# 否则会出现 Theos version mismatch（common.mk [version 0] vs rules.mk [version 1]）。
DEBUG ?= 0
FINALPACKAGE ?= 1

ARCHS = arm64e

# rootless / roothide 都要求 iOS 15+；rootful 保留 14.0 下限
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
TARGET = iphone:clang:16.5:15.0
else
TARGET = iphone:clang:16.5:14.0
endif
