include ../HeliBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HeliPrefs
HeliPrefs_FILES = HLPRootListController.m
HeliPrefs_CFLAGS = -fobjc-arc
HeliPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
HeliPrefs_PRIVATE_FRAMEWORKS = Preferences
HeliPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
