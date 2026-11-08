# 共享构建参数：根 Makefile 和 prefs 子工程都必须 include 这一份。
#
# 子工程一定要先 include 这个、再 include $(THEOS)/makefiles/common.mk，
# 否则会出现 Theos version mismatch（common.mk [version 0] vs rules.mk [version 1]）。
DEBUG ?= 0
FINALPACKAGE ?= 1

# 必须是 arm64e：SpringBoard / 设置这些都是 arm64e 进程，
# 只接受 arm64e 的 dylib 和 bundle（纯 arm64 会被 dlopen 以
# "incompatible architecture (have 'arm64', need 'arm64e')" 拒绝）。
# 之前的 SIGBUS 不是架构选错，而是 Linux 工具链编出的 arm64e ABI 有问题，
# 所以 CI 改用 macOS runner + Xcode SDK。
ARCHS = arm64 arm64e

# latest = 用 Xcode 自带的最新 iOS SDK
TARGET = iphone:clang:latest:15.0
