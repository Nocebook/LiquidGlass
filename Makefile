# 目标设备：iPhone 14 Pro（A16 / arm64e）/ iOS 16.3 / RootHide（Dopamine roothide）
#
# 用 roothide scheme 出包，CI 里再统一做三件事：
#   1) Architecture 改回 iphoneos-arm64（theos 会写成 arm64e，Sileo 判不兼容）
#   2) 所有 rootfs 路径挪进 /var/jb（RootHide 的 rootfs 只读，装不进）
#   3) 用 xz 重打包（Linux 新版 dpkg 默认 zstd，设备端不一定认）

export THEOS_PACKAGE_SCHEME = roothide

include GlassifyBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glassify
Glassify_FILES = Tweak.xm
Glassify_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
Glassify_FRAMEWORKS = UIKit Foundation QuartzCore
# substrate 由 tweak.mk 自动链接

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# 安装/卸载都不自动杀 SpringBoard，重启交给包管理器的按钮
