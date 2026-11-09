#pragma once

#import <Foundation/Foundation.h>

// 路径约定（roothide / rootless 通用）
// ---------------------------------------------------------------------------
// roothide 的 jbroot() 会把任意绝对路径重定向进隐藏根，连
// /var/mobile/Library/Preferences 也会被改写成
// .jbroot-xxxx/var/mobile/Library/Preferences —— 那里并没有 SpringBoard
// 真正写入的偏好文件。所以本插件：
//   1. 偏好全部走 cfprefsd（CFPreferences），见 AxsLiquidGlassPreferences.h；
//   2. 不读取任何 rootfs 内的资源文件，液态玻璃的高光与描边全部代码绘制。
// 因此不需要链接 libroot，也不需要 include roothide.h。

static inline NSString *axs_liquidglass_resourcePath(NSString *rootfsPath) {
    // 仅作为未来新增资源的统一入口；当前没有调用方。
    return rootfsPath.length > 0 ? rootfsPath : @"";
}
