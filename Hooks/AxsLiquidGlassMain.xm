#import <UIKit/UIKit.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassRim.h"
#import "AxsLiquidGlassSurface.h"

// 系统所有毛玻璃最终都落在 UIVisualEffectView 上，从这一层切入
// 比逐个 hook 控制中心/文件夹/Dock 稳，也不会漏掉新系统新增的表面。
// setEffect: 是 UIVisualEffectView 自己实现的方法，挂在这里不会牵连其他 UIView。
%hook UIVisualEffectView

- (void)setEffect:(UIVisualEffect *)effect {
    %orig;
    [AxsLiquidGlassEffect axs_liquidglass_handleEffectChange:self];
}

%end

// layoutSubviews / didMoveToSuperview 是 UIView 的实现，UIVisualEffectView 不一定覆写。
// MSHookMessageEx 对继承方法会把 hook 落到父类上，等于给全系统 UIView 挂钩，所以先查再挂。
%group AxsLiquidGlassLayoutGroup
%hook UIVisualEffectView
- (void)layoutSubviews {
    %orig;
    [AxsLiquidGlassEffect axs_liquidglass_layoutTrackedView:self];
}
%end
%end

%group AxsLiquidGlassHierarchyGroup
%hook UIVisualEffectView
- (void)didMoveToSuperview {
    %orig;
    [AxsLiquidGlassEffect axs_liquidglass_handleHierarchyChange:self];
}
%end
%end

%ctor {
    @autoreleasepool {
        // 读取配置快照；这里不写默认值，避免所有进程都去动偏好文件。
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            [AxsLiquidGlassEffect axs_liquidglass_refreshTrackedViews];
        }];

        Class effectViewClass = NSClassFromString(@"UIVisualEffectView");
        if (axs_liquidglass_classImplements(effectViewClass, @selector(layoutSubviews))) {
            %init(AxsLiquidGlassLayoutGroup);
        }
        if (axs_liquidglass_classImplements(effectViewClass, @selector(didMoveToSuperview))) {
            %init(AxsLiquidGlassHierarchyGroup);
        }
    }
}
