#import <UIKit/UIKit.h>
#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassGuard.h"
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
        // 第一件事永远是看门狗：它决定这次启动要不要装 Hook、装多少。
        // 必须排在所有 %init 之前 —— 一旦崩在这里，本次启动还剩什么都没意义。
        NSInteger guard = AxsLiquidGlassGuardBeginLaunch();
        AxsLog(@"===== liquid (HL) 注入成功（启动保护等级 %ld）=====", (long)guard);
        AxsLog(@"进程=%@", [NSProcessInfo processInfo].processName);

        if (guard >= 2) {
            // 上一次带效果的启动崩了，而且降级到"只改模糊"也没救回来。
            // 这次一个 Hook 都不装，保证机器能用；用户可以在面板里解除。
            AxsLog(@"启动保护：本次启动不加载任何 Hook（等于未安装）");
            AxsLiquidGlassGuardScheduleHeartbeat();
            return;
        }

        // 配置单例必须在装 Hook 之前建好：Hook 回调里第一次碰到它的话，
        // 初始化（读 cfprefsd、迁移默认值）就发生在某个系统布局回调中间，
        // 既拖慢启动，也容易和 cfprefsd 抢锁。先建好，回调里只剩纯读。
        [AxsLiquidGlassConfig axs_liquidglass_shared];
        AxsLiquidGlassGuardNoteStage(@"配置就绪");

        // 自定义 %ctor 后 Logos 不再自动初始化默认组，所有 hook 都必须显式 %init。
        %init(AxsLiquidGlassEffectGroup);

        // 主力路径：系统玻璃的真实参数在 _UIBackdropViewSettings 上。
        @try {
            [AxsLiquidGlassSettings axs_liquidglass_installHooksIfAvailable];
        } @catch (NSException *exception) {
            AxsLog(@"settings 挂载异常：%@", exception.reason);
        }

        @try {
            const AxsLiquidGlassParams *params = AxsLiquidGlassParamsGet();
            AxsLog(@"配置 enabled=%d blur=%.1f sat=%.2f tint=%.2f 描边=%.2f 折射=%.2f 膜=%.2f 高光=%.2f 档位=%ld 生效档=%ld 低电量=%d widget=%ld island=%d",
                   params->enabled,
                   params->blurRadius,
                   params->saturation,
                   params->tintAlpha,
                   params->rimStrength,
                   params->meshStrength,
                   params->fillAlpha,
                   params->specularStrength,
                   (long)[[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_perfMode],
                   (long)params->perfMode,
                   (int)params->lowPower,
                   (long)params->widgetMode,
                   params->islandGlass);
        } @catch (NSException *exception) {
            (void)exception;
        }

        // 读取配置快照；这里不写默认值，避免所有进程都去动偏好。
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            @try {
                AxsLog(@"配置变更，刷新已跟踪视图");
                [AxsLiquidGlassEffect axs_liquidglass_refreshTrackedViews];
                [AxsLiquidGlassBackdrop axs_liquidglass_refreshTrackedViews];
            } @catch (NSException *exception) {
                (void)exception;
            }
        }];

        // Dock / 文件夹在 iOS 16 走 _UIBackdropView，单独补一条只调参数的路径。
        @try {
            [AxsLiquidGlassBackdrop axs_liquidglass_installHooksIfAvailable];
        } @catch (NSException *exception) {
            AxsLog(@"backdrop 挂载异常：%@", exception.reason);
        }

        Class effectViewClass = NSClassFromString(@"UIVisualEffectView");
        @try {
            if (axs_liquidglass_classImplements(effectViewClass, @selector(layoutSubviews))) {
                %init(AxsLiquidGlassLayoutGroup);
            }
            if (axs_liquidglass_classImplements(effectViewClass, @selector(didMoveToSuperview))) {
                %init(AxsLiquidGlassHierarchyGroup);
            }
        } @catch (NSException *exception) {
            AxsLog(@"UIVisualEffectView 挂载异常：%@", exception.reason);
        }

        AxsLiquidGlassGuardNoteStage(@"Hook 安装完成");
        // 跑满 20 秒没出事，就把这次启动记成"好的"，下次不再降级。
        AxsLiquidGlassGuardScheduleHeartbeat();
    }
}
