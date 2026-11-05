# 完美液态玻璃 (LiquidGlass)

越狱插件，把系统毛玻璃重做成液态玻璃质感：更厚的模糊、更高的饱和度、一层左上斜向高光加一圈边缘折射线。

- 包名 `com.axs.liquidglass`，rootless 布局（`/var/jb`）
- 注入：SpringBoard、MediaRemoteUI、chronod、WidgetRenderer(默认/CarPlay)、ClockAngel
- 设置面板：`设置 → 完美液态玻璃`

## 实现路线

系统里所有毛玻璃最终都是 `UIVisualEffectView` 在渲染。所以没有逐个去 hook 控制中心、Dock、文件夹这些具体类，只在两个点上动手：

1. `-[UIVisualEffectView setEffect:]`：把系统 `UIBlurEffect` 换成私有类 `_UICustomBlurEffect`，单独设半径、饱和度、染色。这一步只改参数，不碰视图层级，风险最低。
2. `layoutSubviews` / `didMoveToSuperview`：只在系统类自己实现了这两个方法时才挂（`axs_liquidglass_classImplements` 检查）。`MSHookMessageEx` 对继承来的方法会把 hook 落到父类上，直接写 `%hook UIVisualEffectView - (void)layoutSubviews` 等于给全系统 `UIView` 挂钩。

高光是两个 `CALayer`：斜向 `CAGradientLayer` 做反射光，`CAShapeLayer` 描一圈 1pt 白边做边缘折光，`zPosition` 抬到内容之上，不接管触摸。

私有类拿不到时不写空效果，退回 `UIBlurEffectStyleSystemUltraThinMaterial`，宁可没有质感也不让界面变透明。

## 小组件兼容（重点）

地图类小组件（家人地图、系统地图）不再显示，根因通常不是模糊参数，而是**自绘图层**：小组件跑在 `chronod` / `WidgetRenderer` / `ClockAngel` 里，渲染结果要归档成快照，往这些视图上叠子层会让归档失败，桌面就空一块。

所以默认策略是分级的：

| 模式 | 行为 | 适用 |
|---|---|---|
| 完全跳过 | 小组件进程里什么都不做 | 出问题时的兜底 |
| 仅调参数（默认） | 只改模糊半径/饱和度，不加任何图层 | 日常 |
| 完整效果 | 参数 + 高光层 | 确定没问题再开 |

再加一层跳过列表：逗号分隔的包名子串，默认 `autonavi,amap`（高德系，家人地图在内）。命中即跳过该小组件，不看模式。匹配靠沿 superview 链 KVC 探测 `extensionBundleIdentifier` / `containerBundleIdentifier` / `widgetIdentifier` / `bundleIdentifier`，探不到就当作不命中，不会崩。

`AxsLiquidGlassWidgets.xm` 在小组件进程里额外做了件事：配置重载时主动把可能残留的高光层摘掉，避免从"完整效果"切回"仅调参数"后还留着旧图层。

## 构建

本地（需 Theos + iOS 16.5 SDK）：

```sh
sh build.sh rootless
```

云端（默认路径）：推到 GitHub 的 `main`，Actions 用 `roothide/theos` 在 `macos-14` 上构建并发布 Release，包版本 `5.2.0-<run_number>`。

```sh
git remote add origin git@github.com:<你的账号>/LiquidGlass.git
git push -u origin main
```

产物在 Release 里，也可以在 Actions 的 Artifacts 里拿。

## 真机验收清单

装完先 respring，然后按顺序看：

1. 设置里出现入口，打开"启用插件"
2. 控制中心、Dock、文件夹有更厚的模糊
3. 通知中心/横幅正常，不透明、不白屏
4. 桌面放一个天气小组件 + 一个地图小组件，确认都能正常渲染
5. 旋转屏幕，高光跟着变尺寸
6. 关掉"启用插件"，模糊立刻回到系统原样（不需要注销）

第 4 步不通过就把"小组件处理"调成"完全跳过"，再逐项排查是不是某个具体组件的问题。

## 已知限制

- 这不是真正的折射。iOS 26 的液态玻璃靠 `UIGlassEffect` 做实时折射，越狱环境在旧系统上拿不到；这里做的是"厚模糊 + 高光 + 边缘折光"的近似，视觉接近，物理上不是。
- 默认只注入系统 UI 进程。App 内的模态/弹窗不在注入范围（改 `AxsLiquidGlass.plist` 的 Bundles 可以加，但会影响第三方 App 稳定性，不默认开）。
- 依赖私有类 `_UICustomBlurEffect`。系统哪天改了这个类，会自动降级到系统材质，不会崩但也没有玻璃效果。
- 静态检查通过不等于编译通过，编译通过不等于真机正常。当前工程未在本机编译过（Windows 无 Theos/SDK），第一次构建请以 Actions 日志为准。
