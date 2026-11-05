DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsLiquidGlassBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsLiquidGlass
AxsLiquidGlass_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsLiquidGlass_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsLiquidGlass_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
AxsLiquidGlass_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsLiquidGlassPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
