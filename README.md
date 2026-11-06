# liquid (HL)

越狱插件，把系统毛玻璃重做成液态玻璃质感：更厚的模糊、更高的饱和度、一层左上斜向高光加一圈边缘折射线。

- 包名 `com.heli.liquid`
- 目标设备：**iPhone 14 Pro（A16）/ iOS 16.3 / 隐根越狱**
- 打包方案：`THEOS_PACKAGE_SCHEME = roothide`（隐根专用，dylib 过 roothide patcher），打包后重定位进 `var/jb`，产物 `iphoneos-arm64`
- 注入：SpringBoard、MediaRemoteUI、chronod、WidgetRenderer(默认/CarPlay)、ClockAngel
- 设置入口：**桌面 `liquid` 图标** + **设置 → liquid (HL)**，两处读写同一个 cfg 域

## 两个设置入口

roothide 的隐藏根会随机改名（`.jbroot-xxxx`），Settings.app 又是系统进程，PreferenceLoader 扫不扫得到 `/var/jb/Library/PreferenceLoader/Preferences` 完全看那台机器上装的是哪个版本的 bootstrap。**所以这一版不再赌 Settings 入口**：

| 入口 | 依赖 | 说明 |
|---|---|---|
| 桌面 `liquid` 图标（主） | 只需 `uicache` | 独立 App，一定打得开；postinst 装完自动 uicache + 注销一次 |
| 设置 → liquid (HL) | PreferenceLoader | 走标准 PreferenceBundle，机器上能扫到就出现 |

两边写的是同一个 `com.heli.liquid` 偏好域，改哪边都一样，**改完即时生效，不用注销**（写入后发 Darwin 通知，插件收到就重载并刷新已经在屏幕上的模糊视图）。

App 的内容：总开关、模糊半径、色彩饱和度、乳白浓度、边缘高光、主屏/控制中心/通知/键盘四个范围开关、隐藏灵动岛、小组件四档强度 + 跳过列表、恢复默认、重启桌面。

## 隐藏灵动岛

iOS 16 的灵动岛在 SpringBoard 里由 `SBIslandContainerView` 承载，个别小版本还会出现 `SBIslandChromeView` / `_SBIslandView`。实现是逐个探测类名，存在才挂 hook（不存在整组跳过，非灵动岛机型不留空 hook），把 `alpha` 压到 0 并关掉触摸：

- 只在 SpringBoard 进程生效（tweak 的 Filter 里本来就只有桌面进程）
- 关掉开关立刻把 `alpha` 还原成 1，不用注销
- 再加一层兜底：配置变更时遍历所有 window，类名里带 `Island` 的视图一律处理。私有类改名了也还能命中


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

## 功耗控制（7.1.0 重点）

液态玻璃的观感全部由 GPU 侧的实时合成换来，所以"耗电"不是玄学，而是几笔能算清的账。7.1.0 逐项做了压缩：

| 项 | 旧 | 新 | 为什么 |
| --- | --- | --- | --- |
| 默认模糊半径 | 120 | 88 | 高斯模糊的采样面积随半径平方增长。系统原生就是 46，120 相当于 2.6 倍核；88 只降了观感上的"厚"，GPU 那侧少了近一半工作量 |
| 网格段数 | 12 / 10 / 8 | 10 / 8 / 6 | 折射带只有 5%~22% 宽，段数降到 8/6 后形状几乎看不出差别，面数少 40%~55% |
| 每块玻璃的图层 | 膜 + 底阴影 + 高光 + 描边 + 遮罩 = 5 | 膜（含底阴影）+ 高光 + 描边 + 遮罩 = 4 | 膜和底阴影本来就是同一条竖直渐变，合成成一条色标后少一层、少一遍全幅 alpha 混合 |
| 省电档的图层 | 仍建高光层（透明） | 连层都不建 | 一整幅径向渐变在任何界面上都是一次实打实的合成 |
| 灵动岛刷新 | 1.2s 固定轮询 + 每轮重设网格 | 接管容器 `layoutSubviews`，事件驱动；轮询退到 2.5s 兜底、找不到容器时 6s | 旧版每 1.2 秒就提交一次 CA 事务重设 `meshTransform`，一天几万次多余重绘，设备也进不了深睡 |
| 每帧签名比较 | 拼 `NSString` | `NSData` + `memcmp` | `layoutSubviews` 是逐帧回调，拼字符串会持续产生临时对象 |
| 键盘判定 | 每帧往上走 12 层做类名小写 | 结果缓存在视图上，换父级时失效 | App 里每一个背景模糊都"不是键盘"，每帧重算纯属浪费 |
| 窗口扫描 | 全部窗口各递归 5 层 | 先按类名筛出 `*Aperture*` 窗口，只扫那一棵 | 桌面常驻窗口十几个，每个几百视图 |
| 第三方 App 的模糊 | 全进程改写（每个 App 的导航栏/键盘都抬到配置值） | 默认只改 SpringBoard，App 内保持系统原值（面板可开） | `_UIBackdropViewSettings` 的 setter 是全进程生效的，App 里滚动时每帧重算更大高斯核，这是待机以外最明显的耗电 |

另外新增 **低电量模式自动省电**（默认开）：系统进入低电量模式时按省电档渲染（不挂折射网格、去掉镜面高光、膜压淡一半），退出后自动恢复，不用注销。实现上是监听 `NSProcessInfoPowerStateDidChangeNotification`，把档位压进配置快照，渲染路径读的都是"已经算过降档"的 `perfMode`。

想要更强的效果，面板里往上拉就行 —— 但 150 以上会明显发热，这是半径的平方关系决定的，不是实现问题。

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

## 隐根（roothide）构建链路

这里有个容易踩的坑，记一下免得以后再翻：**roothide scheme 编出来的包不能直接发**。

| 环节 | 现象 | 处理 |
|---|---|---|
| 编译 | `THEOS_PACKAGE_SCHEME=roothide` 时 Theos 会跑 roothide patcher，dylib 的 install name 与 substrate 依赖被改写成 `@loader_path/.jbroot/...` | 保留，这正是隐根能加载的关键 |
| 打包 | roothide scheme **不设** `THEOS_PACKAGE_INSTALL_PREFIX`，产物是 rootfs 绝对路径（`/Library`、`/Applications`） | `tools/relocate_to_jbroot.py` 统一挪进 `var/jb` |
| 安装 | 不重定位会报 `error creating directory './rootfs/Library/...': Read-only file system` | 重定位后装进可写的 `var` 分区 |
| 校验 | 任何越界路径都会让安装失败 | `tools/check_deb_paths.py` 硬校验，越界即中断构建 |

对比两种 scheme 编出来的 dylib：

```
rootless：ID @rpath/AxsLiquidGlass.dylib
          RPATH /var/jb/usr/lib                    ← 隐根上 /var/jb 不存在，加载失败
roothide：ID @loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/AxsLiquidGlass.dylib
          LOAD @loader_path/.jbroot/usr/lib/libsubstrate.dylib   ← 由 roothide 解析到真实隐藏根
```

`postinst` / `postrm` 也要注意：隐根下 `/var/jb` 只是兼容链接，真实根是
`/var/containers/Bundle/Application/.jbroot-*`，脚本里依次探 `JBROOT`、`/var/jb`、`.jbroot-*`。

## 自己构建

本地（需 roothide 版 Theos + iOS 16.5 SDK）：

```sh
sh build.sh roothide      # 不传参数时默认也是 roothide
sh build.sh all           # 需要时一次出 rootful / rootless / roothide
```

云端：推到 `main` 即触发，Actions 用 `roothide/theos` 在 `macos-14` 上构建并发布 Release，版本号 `6.1.0-<run_number>`。

产物在 Release 里，也可以在 Actions 的 Artifacts 里拿。

## 真机验收清单（iPhone 14 Pro / 16.3 / roothide）

装完先 respring，然后按顺序看：

0. **桌面出现 `liquid` 图标**（没出现就是 uicache 没跑到，见下面兜底）
1. 设置里出现入口，打开"启用插件"，**退出设置再进一次，确认开关状态还在**（这一条直接验证 cfprefsd 那条路径通不通）
2. 控制中心、通知中心有更厚的模糊
3. Dock 和文件夹背景有变化（走 `_UIBackdropView` 那条备份路径）
4. 桌面放一个天气小组件 + 一个地图小组件：两者都能正常渲染，且卡片边缘有细白描边（模式 2 生效的标志）
5. 反复下拉通知中心、左右翻页十几轮，小组件不闪白、不消失（内存压力测试）
6. 旋转屏幕，高光跟着变尺寸
7. 关掉"启用插件"，模糊回到系统原样（不需要注销）
8. 打开"隐藏灵动岛"，灵动岛整块消失；关掉立刻回来

第 4 步不通过就把"小组件处理"往下调一档，再逐项排查是不是某个具体组件的问题。第 5 步出现闪白，说明模式 2 的描边加在了过大的视图上，先降到模式 1 确认，再把组件包名填进跳过列表。第 3 步不通过说明 16.3 的 `_UIBackdropView` 不认 `setBlurRadius:`，需要按真机 dump 的类结构再改。

桌面图标没出来（第 0 步）：
1. 先看设置里有没有 `liquid (HL)`，有的话直接从那儿进，功能完全一样
2. 都没有就用 Filza 打开 `/var/jb/Applications/`，确认 `Heli.app` 在不在；在的话手动点开一次
3. 还是没有：`uicache -p /var/jb/Applications/Heli.app` 再注销一次


## 已知限制

- 这不是真正的折射。iOS 26 的液态玻璃靠 `UIGlassEffect` 做实时折射，越狱环境在旧系统上拿不到；这里做的是"厚模糊 + 高光 + 边缘折光"的近似，视觉接近，物理上不是。
- 默认只注入系统 UI 进程。App 内的模态/弹窗不在注入范围（改 `AxsLiquidGlass.plist` 的 Bundles 可以加，但会影响第三方 App 稳定性，不默认开）。
- 依赖私有类 `_UICustomBlurEffect` 与 `_UIBackdropView`。系统改结构时会自动降级，不会崩但效果会少一块。
- 静态检查通过不等于编译通过，编译通过不等于真机正常。当前工程未在本机编译过（Windows 无 Theos/SDK），第一次构建请以 Actions 日志为准。
