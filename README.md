# liquid (HL)

越狱插件，把系统毛玻璃重做成液态玻璃质感：更厚的模糊、更高的饱和度、一层左上斜向高光加一圈边缘折射线。

- 包名 `com.heli.liquid`
- 目标设备：**iPhone 14 Pro（A16）/ iOS 16.3 / 隐根越狱**
- 打包方案：`THEOS_PACKAGE_SCHEME = rootless`（设备 rootfs 只读，roothide 布局装不进），产物 `iphoneos-arm64`
- 注入：SpringBoard、MediaRemoteUI、chronod、WidgetRenderer(默认/CarPlay)、ClockAngel
- 设置面板：`设置 → liquid (HL)`

## roothide 适配（这一版的重点）

roothide 和 rootless 长得像，但根目录不是固定的 `/var/jb`，而是随机命名的 `.jbroot-xxxx`。这带来一个很容易翻车的点：

`jbroot("/var/mobile/Library/Preferences/xxx.plist")` 会把**用户偏好路径也重定向进隐藏根**，而 SpringBoard 真正写入的偏好仍在真实根的 `/var/mobile/...`。直接读文件 → 永远读到空值 → 面板改了没反应。

所以这一版做了三件事：

1. **偏好全部走 cfprefsd**：`CFPreferencesCopyMultiple` / `CFPreferencesSetAppValue`，由系统按 domain 寻址，和根前缀彻底解耦。rootful / rootless / roothide 行为一致。
2. **不链接 libroot、不 include `roothide.h`**：本插件不读取任何 rootfs 内的资源文件，高光与描边全部代码绘制，所以没有路径需要解析。少一个依赖就少一处 roothide 差异。
3. **deb 布局**：`layout/Library/...` 由 Theos 在 roothide scheme 下打成 `var/jb/...`，安装时由 roothide 的 dpkg 重定向到真实 `.jbroot`，不需要手写前缀。

## 实现路线

系统里绝大多数毛玻璃是 `UIVisualEffectView` 在渲染。所以没有逐个去 hook 控制中心、Dock、文件夹这些具体类，只在两个点上动手：

1. `-[UIVisualEffectView setEffect:]`：把系统 `UIBlurEffect` 换成私有类 `_UICustomBlurEffect`，单独设半径、饱和度、染色。这一步只改参数，不碰视图层级，风险最低。
2. `layoutSubviews` / `didMoveToSuperview`：只在系统类自己实现了这两个方法时才挂（`axs_liquidglass_classImplements` 检查）。`MSHookMessageEx` 对继承来的方法会把 hook 落到父类上，直接写 `%hook UIVisualEffectView - (void)layoutSubviews` 等于给全系统 `UIView` 挂钩。

高光是两个 `CALayer`：斜向 `CAGradientLayer` 做反射光，`CAShapeLayer` 描一圈 1pt 白边做边缘折光，`zPosition` 抬到内容之上，不接管触摸。

私有类拿不到时不写空效果，退回 `UIBlurEffectStyleSystemUltraThinMaterial`，宁可没有质感也不让界面变透明。

### iOS 16 的 Dock / 文件夹

这两块在 16.x 上不是 `UIVisualEffectView`，而是私有 `_UIBackdropView`（内部自己画 `CABackdropLayer`）。只挂 `UIVisualEffectView` 会漏掉它们，所以额外补了一条保守路径：

- 只对父链里出现 `dock` / `folder` / `homescreen` / `iconlist` 的 `_UIBackdropView` 生效
- 只调 `setBlurRadius:` / `setSaturationDeltaFactor:`，**不加任何子视图或子层**（这类视图内部结构脆弱，叠层容易直接白块）
- 私有 setter 探测不到就整体跳过，不退回 KVC 硬写
- hook 仍然只挂类自己实现的方法，不污染 `UIView`

## 小组件兼容（重点）

### 先纠正一个判断

之前我把小组件白屏归因于"叠加子层导致快照归档失败"。对照实际排查记录，这个判断不准确。真机上 `WidgetRenderer` / `chronod` 的限制是**资源限制**：

| 约束 | 实际值 |
|---|---|
| 进程内存 | 30~50MB，超了直接被 jetsam 杀掉 |
| 渲染窗口 | 8~10 秒，超时进程终止 |
| 图片解码 | 最大崩溃源，大图 `addImage` 能瞬间撑爆 |
| 模糊半径 | 直接决定 backdrop 采样缓冲区大小 |

进程被杀 → 桌面那块就是空白，且**没有任何 UI 提示**。所以策略不是"禁止加图层"，而是"把每个改动压到内存预算里"。

### 四档，默认第二档

| 模式 | 行为 | 内存增量 | 适用 |
|---|---|---|---|
| 0 完全跳过 | 小组件进程里什么都不做 | 0 | 出问题时的兜底 |
| 1 仅调参数 | 只改模糊半径/饱和度 | 小 | 最保守 |
| **2 边缘折光（默认）** | 参数 + `layer.borderWidth` 描边 | **≈0，不新增图层** | 日常 |
| 3 完整效果（实验） | 参数 + `CAGradientLayer` 高光 | 每视图 +2 个图层 | 确认设备撑得住再开 |

默认档之所以能做到"有效果又几乎不可能白屏"，是因为描边用的是 `CALayer` 自带的 `borderWidth` / `borderColor`，不是新增子层：不占额外缓冲区、不进新增合成层，只是绘制属性。

### 三道硬保护

1. **半径上限**：小组件进程里模糊半径强制 `min(用户值, 28)`、饱和度 `min(1.5)`、乳白 `min(0.06)`。主屏默认 46，在 widget 里采样缓冲区太大，是内存超限的主要来源之一。
2. **不延迟**：主屏那条路径会在下一个 runloop 补一次重试，小组件里**全部改成同步**。8~10 秒的窗口里，多等一个 runloop 就可能赶不上出快照，表现就是"点了没反应"。
3. **异常吃掉**：每个 hook 回调都包 `@try/@catch`。在扩展进程里未捕获的 Objective-C 异常不是"少个效果"，是整个进程被杀。

再加一层跳过列表：逗号分隔的包名子串，默认 `autonavi,amap`（高德系，家人地图在内）。命中即跳过该小组件，不看模式。匹配靠沿 superview 链 KVC 探测 `extensionBundleIdentifier` / `containerBundleIdentifier` / `widgetIdentifier` / `bundleIdentifier`，探不到就当作不命中，不会崩。

想把家人地图也上效果，把 `autonavi,amap` 从跳过列表里删掉即可——建议先停在模式 2 观察一轮，别直接上模式 3。

### 白屏了怎么定位

不要靠猜。装完在 Mac 上看 Console，过滤 `WidgetRenderer` 和 `jetsam`：

- 日志里有 `memorystatus` / `jetsam` 记录 → 确认是内存超限，退到模式 1 或 0
- 进程在渲染中途消失、没有崩溃栈 → 超时或被杀
- 有 `NSException` 栈 → 是插件抛异常，把栈发我

`AxsLiquidGlassWidgets.xm` 在小组件进程里额外做一件事：配置重载时先把残留图层摘干净再按新配置重铺，避免从模式 3 切回模式 2 后还留着高光层。


## 下载与安装

源地址（推荐，能收到更新）：<https://nocebook.github.io/heli/>

直装：<https://github.com/Nocebook/LiquidGlass/releases/latest>

iPhone 上装（roothide / Sileo）：

**走源**
1. Sileo → 源 → 右上角 `+` → 粘贴 `https://nocebook.github.io/heli/`
2. 提示「未签名」时选继续添加
3. 进 Heli 源，点 `liquid (HL)` → 获取

**走单个 deb**
1. Safari 打开 Releases 链接，点最新 Release 里的 `.deb`
2. 下载完点它，选「用 Sileo 打开」（没弹窗就去「文件」App 里找到它点开）
3. Sileo 里点「获取」→ 安装 → Restart SpringBoard

包内 `Architecture` 必须是 `iphoneos-arm64`。theos 的 roothide scheme 默认会写成
`iphoneos-arm64e`，那样 dpkg 会判架构不匹配直接拒绝安装，所以 CI 在打包后重写这个字段。

## 自己构建

本地（需 roothide 版 Theos + iOS 16.5 SDK）：

```sh
sh build.sh roothide      # 不传参数时默认也是 roothide
sh build.sh all           # 需要时一次出 rootful / rootless / roothide
```

云端：推到 `main` 即触发，Actions 用 `roothide/theos` 在 `macos-14` 上构建并发布 Release，版本号 `5.2.0-<run_number>`。

产物在 Release 里，也可以在 Actions 的 Artifacts 里拿。

## 真机验收清单（iPhone 14 Pro / 16.3 / roothide）

装完先 respring，然后按顺序看：

1. 设置里出现入口，打开"启用插件"，**退出设置再进一次，确认开关状态还在**（这一条直接验证 cfprefsd 那条路径通不通）
2. 控制中心、通知中心有更厚的模糊
3. Dock 和文件夹背景有变化（走 `_UIBackdropView` 那条备份路径）
4. 桌面放一个天气小组件 + 一个地图小组件：两者都能正常渲染，且卡片边缘有细白描边（模式 2 生效的标志）
5. 反复下拉通知中心、左右翻页十几轮，小组件不闪白、不消失（内存压力测试）
6. 旋转屏幕，高光跟着变尺寸
7. 关掉"启用插件"，模糊回到系统原样（不需要注销）

第 4 步不通过就把"小组件处理"往下调一档，再逐项排查是不是某个具体组件的问题。第 5 步出现闪白，说明模式 2 的描边加在了过大的视图上，先降到模式 1 确认，再把组件包名填进跳过列表。第 3 步不通过说明 16.3 的 `_UIBackdropView` 不认 `setBlurRadius:`，需要按真机 dump 的类结构再改。

## 已知限制

- 这不是真正的折射。iOS 26 的液态玻璃靠 `UIGlassEffect` 做实时折射，越狱环境在旧系统上拿不到；这里做的是"厚模糊 + 高光 + 边缘折光"的近似，视觉接近，物理上不是。
- 默认只注入系统 UI 进程。App 内的模态/弹窗不在注入范围（改 `AxsLiquidGlass.plist` 的 Bundles 可以加，但会影响第三方 App 稳定性，不默认开）。
- 依赖私有类 `_UICustomBlurEffect` 与 `_UIBackdropView`。系统改结构时会自动降级，不会崩但效果会少一块。
- 静态检查通过不等于编译通过，编译通过不等于真机正常。当前工程未在本机编译过（Windows 无 Theos/SDK），第一次构建请以 Actions 日志为准。
