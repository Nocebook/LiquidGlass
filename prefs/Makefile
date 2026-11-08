BUNDLE_NAME = GlassifyPrefs
GlassifyPrefs_FILES = GSPRootListController.m
GlassifyPrefs_FRAMEWORKS = UIKit Foundation
GlassifyPrefs_PRIVATE_FRAMEWORKS = Preferences
GlassifyPrefs_INSTALL_PATH = /Library/PreferenceBundles
GlassifyPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 Preferences"
