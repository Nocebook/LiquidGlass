DEBUG = 0
FINALPACKAGE = 1

# 目标设备：iPhone 14 Pro / iOS 16.3 / roothide（隐藏根）。
# roothide 与 rootless 都要求 iOS 15+；rootful 保留 14.0 下限。
# build.sh 会用命令行变量覆盖这里，直接 make 时默认出 roothide 包。
THEOS_PACKAGE_SCHEME ?= roothide

ARCHS = arm64

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsLiquidGlassBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsLiquidGlass
AxsLiquidGlass_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsLiquidGlass_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsLiquidGlass_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
AxsLiquidGlass_LIBRARIES = substrate

# 本插件不读取任何 rootfs 内文件，路径全部交给系统与 cfprefsd，
# 因此 roothide 下不需要链接 libroot，也不必 include roothide.h。
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsLiquidGlassPrefs
SUBPROJECTS += App
include $(THEOS_MAKE_PATH)/aggregate.mk
