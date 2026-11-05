include ../AxsLiquidGlassBuild.mk
# 注入型组件（tweak / PreferenceBundle）必须是 arm64e，因为 SpringBoard、
# Preferences.app 都是 arm64e 进程，加载不了 arm64。但桌面 App 本身是
# 独立进程，保持 arm64 更稳（arm64e 应用对签名更挑剔，容易点不开）。
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Heli

Heli_FILES = main.m HeliAppDelegate.m HeliRootViewController.m HeliGlass.m HeliRows.m
Heli_CFLAGS = -fobjc-arc -I../Sources -I.
Heli_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
Heli_INSTALL_PATH = /Applications
# $(THEOS_PROJECT_DIR) 在子工程里指向顶层仓库，取 CURDIR 才是 App/ 自己。
Heli_CODESIGN_FLAGS = -S$(CURDIR)/entitlements.plist
Heli_RESOURCE_FILES = Resources/AppIcon60x60@2x.png Resources/AppIcon60x60@3x.png

include $(THEOS_MAKE_PATH)/application.mk

# Theos 用 Resources/Info.plist 生成 bundle；这里再兜一次底：
# 覆盖成自己的 Info.plist、补上桌面图标，并用越狱 entitlements 重签，
# 保证 app 能读写全局的 com.heli.liquid 偏好域。
after-install::
	@set -e; \
	for dir in "$(THEOS_STAGING_DIR)/Applications/Heli.app" \
	           "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/Heli.app"; do \
	  if [ -d "$$dir" ]; then \
	    cp -f "$(CURDIR)/Resources/Info.plist" "$$dir/Info.plist"; \
	    cp -f "$(CURDIR)/Resources/AppIcon60x60@2x.png" "$$dir/" || true; \
	    cp -f "$(CURDIR)/Resources/AppIcon60x60@3x.png" "$$dir/" || true; \
	    if command -v ldid >/dev/null 2>&1; then \
	      ldid -S"$(CURDIR)/entitlements.plist" "$$dir/Heli" || true; \
	    fi; \
	    echo ">> Heli.app staged at $$dir"; \
	    ls -la "$$dir"; \
	  fi; \
	done
