include ../AxsLiquidGlassBuild.mk
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Heli

Heli_FILES = main.m HeliAppDelegate.m HeliRootViewController.m HeliGlass.m HeliRows.m
Heli_CFLAGS = -fobjc-arc -I../Sources -I.
Heli_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
Heli_INSTALL_PATH = /Applications
Heli_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/entitlements.plist
Heli_RESOURCE_FILES = Resources/AppIcon60x60@2x.png Resources/AppIcon60x60@3x.png

include $(THEOS_MAKE_PATH)/application.mk

# Theos 用 ../Resources/Info.plist 生成 bundle；这里再兜一次底：
# 覆盖成自己的 Info.plist、补上桌面图标，并用越狱 entitlements 重签，
# 保证 app 能读写全局的 com.heli.liquid 偏好域。
after-install::
	@set -e; \
	for dir in "$(THEOS_STAGING_DIR)/Applications/Heli.app" \
	           "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/Heli.app"; do \
	  if [ -d "$$dir" ]; then \
	    cp -f "$(THEOS_PROJECT_DIR)/Resources/Info.plist" "$$dir/Info.plist"; \
	    cp -f "$(THEOS_PROJECT_DIR)/Resources/AppIcon60x60@2x.png" "$$dir/" || true; \
	    cp -f "$(THEOS_PROJECT_DIR)/Resources/AppIcon60x60@3x.png" "$$dir/" || true; \
	    if command -v ldid >/dev/null 2>&1; then \
	      ldid -S"$(THEOS_PROJECT_DIR)/entitlements.plist" "$$dir/Heli" || true; \
	    fi; \
	  fi; \
	done
