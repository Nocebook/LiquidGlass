# Glassify（接管 LiquidGlass 仓库）

iOS 越狱插件：**通知角标液态玻璃 + 未读呼吸动画**，外加 Dock / 文件夹 / 控制中心玻璃。

这一版是**整体替换**：老项目里的模糊改写、折射网格、灵动岛驱动、启动看门狗、参数快照全部移除，只保留三层能跑的实现。包名沿用 `com.heli.liquid`，所以旧版能直接覆盖升级，不会装出两个插件。

## 适配环境

| 项 | 值 |
|---|---|
| 设备 | iPhone 14 Pro（A16 / arm64e） |
| 系统 | iOS 16.3 |
| 越狱 | RootHide（Dopamine roothide 3.0.13） |
| 打包 | roothide scheme + CI 里改 `iphoneos-arm64` + 挪 `/var/jb` + xz 重打包 |

## 8.0.0 做了什么

| 模块 | 实现 | 开关 |
|---|---|---|
| 通知角标玻璃 | `SBIconBadgeView` 插超薄模糊层，原底板 alpha 降到 0.15，原色 30% 染色 | 角标玻璃 |
| 未读呼吸动画 | 玻璃层 1.0⇄1.045 + 高光 0.55⇄1.0，1.5s，CA 驱动，尊重「减弱动态效果」 | 未读呼吸动画 |
| Dock | `SBDockView` 插玻璃层 | Dock |
| 文件夹背景 | `SBFolderControllerBackgroundView` | 文件夹背景 |
| 控制中心 | `CCUIModularControlCenterOverlayViewController` | 控制中心 |
| 调试 | 导出视图树到日志 | 调试：导出视图树 |

角标参数：原底板不透明度（0–1，默认 0.15）、保留角标颜色（默认开）。

设计原则：**找不到类就跳过，绝不挂系统类的 `layoutSubviews` 做全局改写**——这正是上一版卡安全模式、白屏、掉帧的来源。

## 仓库结构与构建

```
Makefile                        roothide scheme / arm64e / iOS 16.5 SDK
control                         com.heli.liquid, 8.0.0
Tweak.xm                        全部插件逻辑（角标 / 呼吸 / 三处容器 / 调试）
prefs/                          设置面板（PSListController）
layout/                         注入过滤器 + PreferenceLoader 入口
tools/relocate_to_jbroot.py     rootfs 布局 → /var/jb
tools/check_deb_paths.py        校验没有 /var/jb 之外的路径
scripts/replace_repo.ps1        覆盖远端 main（带 tag 备份）
.github/workflows/build.yml     推上去自动出包 + Release
```

CI 里有四个坑，都是照着你上一版验证过的做法抄的，别删：

1. **ldid**：noble 源里没有这个包，必须从 ProcursusTeam 下静态二进制
2. **工具链**：Linux 上要 L1ghtmann 的 `iOSToolchain-x86_64`，光 clone theos 编不了
3. **架构**：theos 写成 `iphoneos-arm64e`，Sileo 判不兼容，要改回 `iphoneos-arm64`
4. **布局**：roothide scheme 出的是 rootfs 路径，RootHide 装不进，要挪 `/var/jb`

## 怎么覆盖上去

先确认本地仓库是干净的，然后在**你自己的** PowerShell 里跑：

```powershell
cd "D:\Users\Administrator\Documents\deepseek-harness\default-workspace\glassify"
powershell -ExecutionPolicy Bypass -File scripts\replace_repo.ps1
```

它会：先把远端 `main` 存成 tag `legacy-7.4.0` → 再强制推送本地 `main`。

后悔了随时回滚：

```powershell
git push --force origin legacy-7.4.0:main
```

推完 Actions 自动出包，Release 里就是新 deb。

## 装上之后

1. Sileo 里版本应该是 `8.0.0-<构建号>`，比 `7.4.0` 高，直接升级
2. 装完在包管理器的「重启」按钮里重启 SpringBoard（**不会自动杀**）
3. 设置里会出现 Glassify 面板
4. 给微信发条消息，回桌面看角标：应该有玻璃底 + 呼吸动画
5. 不对就看日志：设置里开「调试：导出视图树」，`idevicesyslog | grep Glassify`

```
[Glassify] hooks: badge=yes dock=yes folder=yes controlCenter=yes
[Glassify] badge SBIconBadgeView (18x18)
```

## 已知取舍

- 老版的「系统级模糊改写 / 边缘折射 / 灵动岛」没有保留。那些是它不稳定的根因，先不要。
- 只覆盖 `SBIconBadgeView`，锁屏和通知中心的数字是别的类，需要另做。
- 本机（Windows，无 WSL 发行版、无 Theos）编不了，首次真实编译在 Actions。

## 下一步候选

1. 角标跟随 App 图标主色
2. 呼吸节奏滑条（0.8 / 1.5 / 2.5s）
3. 角标数字字体/字重
4. 锁屏通知玻璃

## License

MIT。
