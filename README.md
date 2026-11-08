# Glassify

给越狱 iOS 用的**液态玻璃效果框架**：通知角标 / Dock / 文件夹 / 控制中心，带设置面板和视图树调试。

> 独立实现，仓库里没有 Liquidify 的任何二进制或反编译产物。视觉效果用系统公开 API（`UIVisualEffectView` + Core Animation）重写。

## 适配环境

| 项 | 值 |
|---|---|
| 设备 | iPhone 14 Pro（A16，arm64e） |
| 系统 | iOS 16.3 |
| 越狱 | Dopamine（roothide 3.0.13） |
| 打包 | `THEOS_PACKAGE_SCHEME = roothide` |

换回普通 rootless 越狱只需改 `Makefile` 里那一行。

## 这一版有什么

- **通知角标玻璃**：`SBIconBadgeView` 里插一层超薄材质模糊，原红色底板调淡，玻璃透出壁纸，加 1px 高光描边和弹入手感
- Dock 玻璃（`SBDockView`）
- 文件夹背景玻璃（`SBFolderControllerBackgroundView`）
- 控制中心玻璃（`CCUIModularControlCenterOverlayViewController`）
- 设置面板：总开关、圆角、三个位置独立开关、角标三项参数、视图树调试

三个角标参数：

| 参数 | 默认 | 作用 |
|---|---|---|
| 角标玻璃 | 开 | 总开关 |
| 原底板不透明度 | 0.15 | 越低越透；数字看不清就往上调 |
| 保留角标颜色 | 开 | 用原红色做 30% 染色；关掉是纯玻璃 |
| 未读呼吸动画 | 开 | 玻璃层 1.5s 轻微放大 + 高光提亮，可随时关掉 |

## 呼吸动画的实现

- 只动**玻璃层**（scale 1.0 ⇄ 1.045）和高光透明度，数字本身不移动，所以不会看着晃
- `CABasicAnimation` 交渲染进程跑，autoreverse 无限循环，**不占 CPU、不占主线程**
- 开关是实时的：改完发通知，已经在屏幕上的角标立刻加/撤动画，不用重启
- 尊重系统「减弱动态效果」：开了无障碍里的 Reduce Motion 就自动不动
- 关掉动画时会清掉动画并把 transform 复位，不会留下一个被放大的角标

## 角标玻璃的实现思路

角标只有 18–20pt，直接上折射滤镜会糊成一坨，所以取的是"薄玻璃"路线：

1. 往 `SBIconBadgeView` 的 `index 0` 插一个 `GSBadgeGlassView`
2. 里面是 `UIBlurEffectStyleSystemUltraThinMaterial` + 角标原色 30% 染色 + 上亮下暗的高光渐变
3. 把原底板（非 UILabel 的子视图）alpha 调到 0.15，玻璃才透得出来
4. 圆角按 `高度 / 2` 走，描边 1px 白 42%
5. 首次出现时 0.72 → 1.0 的弹簧动画

逻辑全在 [Tweak.xm](Tweak.xm) 的 `GSDecorateBadge`。

## 跑通（5 步）

### 1. 换名字

一条命令搞定（把 `yourname` 换成你的 GitHub 用户名，全小写）：

```bash
bash scripts/rename.sh yourname
```

Windows 用这个：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\rename.ps1 yourname
```

脚本只改 `control`、`Tweak.xm`、`prefs/GSPRootListController.m`、`LICENSE` 四个文件，不会碰别的。bundle id 装上去之后别再改。

### 2. 建一个空仓库

去 https://github.com/new 建 **public** 空仓库，名字 `glassify`，**不要**勾 README / .gitignore / LICENSE（勾了会冲突）。

### 3. 一键发布

在你自己的终端里（需要能出网，会弹浏览器让你登录 GitHub）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 你的用户名
```

它会做完：换包名 → 提交 → 配远端 → 推送，最后打印源地址。

手动版等价于：

```bash
git remote add origin https://github.com/你的用户名/glassify.git
git push -u origin main
```

### 4. 等 Actions 出包

自动流程：装 Theos（含 roothide 支持）→ `make package` → 生成 apt 源 → 推 `gh-pages`。

### 5. 开 Pages

`Settings → Pages → Deploy from a branch → gh-pages / root`。

### 5. 手机装

Sileo 添加 `https://YOURNAME.github.io/glassify/`，安装 Glassify，注销。

## 效果不对时怎么查

设置里打开「调试：导出视图树」，重进桌面 / 控制中心，`idevicesyslog | grep Glassify`：

```
[Glassify] hooks: badge=yes dock=yes folder=yes controlCenter=yes
[Glassify] badge SBIconBadgeView (18x18)
```

| 现象 | 原因 | 处理 |
|---|---|---|
| `badge=no` | 类名变了 | 把 `objc_getClass` 附近的日志发我 |
| 没日志也没效果 | 没装成功 / 没注销 | 确认 Sileo 里版本号是 0.3.0，重装后注销 |
| 数字被盖住 | 玻璃插在了文字上面 | 发我视图树，我改插入层级 |
| 数字看不清 | 底板太透 | 「原底板不透明度」调到 0.4 |
| 掉帧 | 角标太多，模糊层重 | 同上，或先只开角标关掉 Dock |

## 已知限制

- 本机（Windows，无 WSL 发行版、无 Theos）**编译不了**，第一次真实编译在 GitHub Actions，红了贴日志我改。
- 只覆盖 `SBIconBadgeView`；锁屏/通知中心的数字不是它，需要另做。
- iOS 16.3 的私有类名已按公开资料对齐，仍需真机日志确认。
- roothide 的路径是随机的，靠 Theos 的 roothide 打包处理，别手动改 layout 里的路径。

## 下一步可以加

1. 角标跟随 App 图标主色（不是统一红）
2. 角标数字字体/字重
3. 呼吸节奏可调（慢/标准/快）
4. 锁屏通知的玻璃
5. 预设：清透 / 磨砂 / 高对比

## License

MIT。
