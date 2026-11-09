#import <UIKit/UIKit.h>
#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassBadge.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassSettings.h"
#import "AxsLiquidGlassSurface.h"

// 系统所有毛玻璃最终都落在两套实现上：
//   1. UIVisualEffectView + _UICustomBlurEffect（App 内、部分系统表面）
//   2. _UIBackdropView + _UIBackdropViewSettings（控制中心 / Dock / 文件夹 / 通知，iOS 15+ 的主力）
// 只挂第 1 条会给人"装了个空包"的错觉，所以两条都要接。
//
// 每个回调都包 @try：在 WidgetRenderer / chronod 这类扩展进程里，一个未捕获的
// Objective-C 异常不是"少个效果"，而是整个进程被杀 → 桌面小组件直接空白。
%group AxsLiquidGlassEffectGroup
%hook UIVisualEffectView

- (id)initWithEffect:(UIVisualEffect *)effect {
    self = %orig;
    if (self) {
        @try {
            [AxsLiquidGlassEffect axs_liquidglass_handleEffectChange:self];
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    return self;
}

- (void)setEffect:(UIVisualEffect *)effect {
    %orig;
    @try {
        [AxsLiquidGlassEffect axs_liquidglass_handleEffectChange:self];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

%end
%end

// layoutSubviews / didMoveToSuperview 是 UIView 的实现，UIVisualEffectView 不一定覆写。
// MSHookMessageEx 对继承方法会把 hook 落到父类上，等于给全系统 UIView 挂钩，所以先查再挂。
%group AxsLiquidGlassLayoutGroup
%hook UIVisualEffectView
- (void)layoutSubviews {
    %orig;
    @try {
        [AxsLiquidGlassEffect axs_liquidglass_layoutTrackedView:self];
    } @catch (NSException *exception) {
        (void)exception;
    }
}
%end
%end

%group AxsLiquidGlassHierarchyGroup
%hook UIVisualEffectView
- (void)didMoveToSuperview {
    %orig;
    @try {
        [AxsLiquidGlassEffect axs_liquidglass_handleHierarchyChange:self];
    } @catch (NSException *exception) {
        (void)exception;
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        AxsLog(@"===== liquid (HL) 注入成功 =====");
        AxsLog(@"进程=%@", [NSProcessInfo processInfo].processName);

        // 自定义 %ctor 后 Logos 不再自动初始化默认组，所有 hook 都必须显式 %init。
        %init(AxsLiquidGlassEffectGroup);

        // 主力路径：系统玻璃的真实参数在 _UIBackdropViewSettings 上。
        [AxsLiquidGlassSettings axs_liquidglass_installHooksIfAvailable];

        @try {
            AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
            AxsLog(@"配置 enabled=%d blur=%.1f sat=%.2f tint=%.2f 描边=%.2f 折射=%.2f 膜=%.2f 高光=%.2f 档位=%ld widget=%ld island=%d",
                   [config axs_liquidglass_isEnabled],
                   [config axs_liquidglass_blurRadius],
                   [config axs_liquidglass_saturation],
                   [config axs_liquidglass_tintAlpha],
                   [config axs_liquidglass_rimStrength],
                   [config axs_liquidglass_meshStrength],
                   [config axs_liquidglass_fillAlpha],
                   [config axs_liquidglass_specularStrength],
                   (long)[config axs_liquidglass_perfMode],
                   (long)[config axs_liquidglass_widgetMode],
                   [config axs_liquidglass_hideIsland]);
        } @catch (NSException *exception) {
            (void)exception;
        }

        // 读取配置快照；这里不写默认值，避免所有进程都去动偏好。
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            @try {
                AxsLog(@"配置变更，刷新已跟踪视图");
                [AxsLiquidGlassEffect axs_liquidglass_refreshTrackedViews];
                [AxsLiquidGlassBackdrop axs_liquidglass_refreshTrackedViews];
                [AxsLiquidGlassBadge axs_liquidglass_refreshAll];
            } @catch (NSException *exception) {
                (void)exception;
            }
        }];

        // Dock / 文件夹在 iOS 16 走 _UIBackdropView，单独补一条只调参数的路径。
        [AxsLiquidGlassBackdrop axs_liquidglass_installHooksIfAvailable];

        // 液态角标：只挂 SpringBoard 的 SBIconBadgeView，钩子内部自带尺寸防呆与
        // @try 包裹，取不到类就整体跳过，不影响上面两条主路径。
        [AxsLiquidGlassBadge axs_liquidglass_installHooksIfAvailable];

        Class effectViewClass = NSClassFromString(@"UIVisualEffectView");
        if (axs_liquidglass_classImplements(effectViewClass, @selector(layoutSubviews))) {
            %init(AxsLiquidGlassLayoutGroup);
        }
        if (axs_liquidglass_classImplements(effectViewClass, @selector(didMoveToSuperview))) {
            %init(AxsLiquidGlassHierarchyGroup);
        }
    }
}
