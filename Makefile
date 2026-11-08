export ARCHS = arm64 arm64e
# latest = 用 CI 里装好的最新 SDK
export TARGET = iphone:clang:latest:15.0

# 你的环境：Dopamine (roothide) + iOS 16.3 → roothide
export THEOS_PACKAGE_SCHEME = roothide
# 如果以后换回普通 Dopamine/palera1n rootless，换成：
# export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glassify
Glassify_FILES = Tweak.xm
Glassify_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
Glassify_FRAMEWORKS = UIKit Foundation QuartzCore
# substrate 由 tweak.mk 自动链接

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
