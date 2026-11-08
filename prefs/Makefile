include ../GlassifyBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlassifyPrefs
GlassifyPrefs_FILES = GSPRootListController.m
GlassifyPrefs_CFLAGS = -fobjc-arc
GlassifyPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
GlassifyPrefs_PRIVATE_FRAMEWORKS = Preferences
GlassifyPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
