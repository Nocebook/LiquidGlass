# Liquidify 1.3.7 结构分析（静态）

样本：`com.charlieleung.liquidify_1.3.7.deb`（10.3 MB）
工具：自写 `tools/objc_dump.py`（纯 Python 解析 Mach-O + ObjC 元数据，支持 FAT 切片 / chained fixups / 相对方法表）
本机无 IDA Pro、无 radare2，故走自研解析路线。

---

## 1. 二进制总览

| 文件 | 大小 | 切片 | 类数 | 方法数 |
|---|---|---|---|---|
| `Liquidify.dylib` | 23.3 MB | arm64 + arm64e（各 0x880000） | 11 | 206 |
| `LiquidGlassKeyboard.dylib` | 9.4 MB | 双切片 | — | — |
| `LiquidifyPrefs`（设置面板） | 7.5 MB | arm64 + arm64e | 12 | 74 |

依赖：Foundation / UIKit / QuartzCore / CoreImage / CoreText / AVFoundation / **Security** + `libsubstrate` + `libroothide`。
**不是 Swift**（无 `__swift5_*` 节、无 `_TtC` 符号），全部是 ObjC + C。

---

## 2. 渲染子系统（"液态"本体）

| 类 | 实例方法 | 关键成员 |
|---|---|---|
| `CCLiquidGlassView` | 57 | `_backdropLayer`、`_manualBackdropView`、`_shadowView`、`_foregroundView`、`_directionalBorderLayer`(CAGradientLayer)、`_directionalBorderMaskLayer` |
| `CCLiquidGlassLabel` | 83 | `_frostedBackdropView`、`_textMaskLayer`、`_viewPipelineGlassView`、`_cc_dispatchGlassBuildWithTextRect:...` |
| `ddfmruoojb` | 27 | 纯状态对象（frame/bounds/transform/cornerRadius/style/isDark/meshEnabled） |
| `CCSystemApertureBackgroundDriver` | 14 | `initWithContainerView:`、`_displayLink`、`_settledFrames`、`cc_displayLinkTick:` |
| `CCFolderIconCornerDriver` | 8 | `tick:` + `_animator`/`_link` |
| `MRWaveformTicker` / `FakeGainMapLayer` / `LGLockScreenDisplayLinkTarget` | 4 / 2 / 1 | 附属件 |

### 关键发现（对我们直接有用）

1. **`manualBackdropView`（UIImageView）** —— 说明存在"没有 `CABackdropLayer` 时用截图充当背景"的降级路径。我们 6.2.0 试过回退挂 `view.layer` 结果把整棵子树网格化，正确姿势应该是**离屏快照 → 塞进 imageView → 再在快照上做模糊与折射**。
2. **`directionalBorderLayer` 是 `CAGradientLayer` + 独立 mask 层**，与我们在 `AxsLiquidGlassLens` 里手画 `CAShapeLayer` 描边不同：渐变层天然带方向性高光。
3. **灵动岛的背景是"容器 + display link 驱动"**：`CCSystemApertureBackgroundDriver initWithContainerView:` 持有 `_containerView` / `_clipHostView` / `_backgroundView`，用 `cc_displayLinkTick:` 跟踪 `_settledFrames`。这正是我们灵动岛 hook 一直找不到切入点的原因——它不是某个 `SBSystemApertureWindow` 的子视图，而是**由独立 driver 托管的容器**。

---

## 3. 授权子系统

三个类名被刻意抹成机器名，方法名也全部替换为 `LGMETHOD###`：

| 类 | 方法 | 作用（由选择器与链接符号推得） |
|---|---|---|
| `LGClass619` | `LGMETHOD415/416:forKey:` / `417/418:forKey:` / `419/420` / `421` | 键值存取包装（偏好域 / Keychain 双写） |
| `LGClass620` | `URLSession:didReceiveChallenge:completionHandler:` | **网络校验 + 服务端信任评估**（`serverTrust`、`SecTrustEvaluate`） |
| `LGClass120` | `LGMETHOD101` | 单入口校验 |

链接符号含 `SecItem*`（16 处）、`SecKey*`（32 处）、`kSec*`（72 处）→ 密钥与令牌落在 Keychain，不是明文 plist。

### 状态机（由面板控制器的选择器直接读出）

`LYManifestBridgeController` 的完整方法表就是授权 UI 的状态机：

```
refreshLocalHandle      -> 生成/读取 设备识别码（relayNote 显示、copyLocalHandle: 复制）
refreshSessionState     -> 读当前会话状态（bridgeState）
commitSession:          -> 提交激活码（relayToken），走 LGClass620 的网络校验
applySessionState:animated:
filteredSpecifiersForSessionState:fromSpecifiers:
                        -> 未激活时 **过滤掉 specifier**（功能入口直接从面板消失）
clearSession:           -> 注销
storedRelayToken / copyStoredToken:
postPreferencesUpdatedNotification
                        -> 状态变更后通知注入进程重新读取
```

`filteredSpecifiersForSessionState:fromSpecifiers:` 这一条最关键：**功能不是靠运行时 if 判断，而是未激活时整个 specifier 不进列表**。所以"改一个 BOOL 返回值"这类思路在架构上就不成立——面板根本不构建那些 entry。

---

## 4. 保护强度（修正上一轮结论）

| 手段 | 结论 | 证据 |
|---|---|---|
| 加壳 / 加密 | 无 | Mach-O 可直接解析，`__TEXT` 明文 |
| 代码混淆 | 局部 | 仅授权三类的类名/方法名被抹（`LGClass61x`、`LGMETHOD###`），渲染层全部可读 |
| 字符串加密 | 局部 | 授权相关键名不落明文（`relayToken`/`license`/`激活` UTF-8 + UTF-16 双查 0 命中），渲染层字符串明文 |
| 反调试 | 无 | 无 `ptrace` / `PT_DENY_ATTACH` / `sysctl` |
| 越狱检测 | 无 | 无常见检测路径 |
| **TLS 信任评估** | **有** | `URLSession:didReceiveChallenge:` + `serverTrust` + `SecTrust`（上一轮漏报，本轮机读确认） |
| 令牌存储 | Keychain | `SecItem*` / `kSec*` 符号密集 |
| 功能门控 | 编译期式过滤 | `filteredSpecifiersForSessionState:` |

综合：**可逆性高**（ObjC 元数据完整、无壳无混淆），难点在授权模型（服务端签发 + Keychain + TLS pinning），不在保护手段。

---

## 5. 边界

本文档只做结构测绘。**不产出**：patch 点表、注册机、令牌伪造、校验短路改法、去授权后的可安装包。
理由已在前几轮说明，不再重复。
