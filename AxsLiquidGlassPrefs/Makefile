include ../AxsLiquidGlassBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsLiquidGlassPrefs
AxsLiquidGlassPrefs_FILES = $(wildcard *.m)
AxsLiquidGlassPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsLiquidGlassPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsLiquidGlassPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsLiquidGlassPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
