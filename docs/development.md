# 开发指南

[返回 README](../README.md)

## 项目结构


项目使用一个 Swift 应用模块，按功能和系统职责组织文件，无第三方依赖。

| 目录 | 职责 |
| --- | --- |
| `Sources/main.swift` | 程序入口 |
| `Sources/App/` | 应用生命周期、状态协调、菜单栏和重启 |
| `Sources/Features/History/` | 历史界面、卡片及面板布局参数 |
| `Sources/Features/SequentialPaste/` | 顺序粘贴界面和队列模型 |
| `Sources/Features/Settings/` | 设置界面 |
| `Sources/Services/` | 剪贴板监听、粘贴焦点等待、权限、快捷键配置和 Finder 文件移动 |
| `Sources/Platform/` | 原生窗口、快捷键注册、事件监听和 Finder 焦点检查 |
| `Sources/Models/` | 剪贴板内容的数据结构与格式转换 |
| `Sources/Storage/` | SQLite 历史索引和内容文件存储 |
| `Sources/Preview/` | 图片、视频缩略图和缓存 |
| `Sources/UI/` | 公共视觉样式、工具栏组件和滚动行为 |
| `Sources/Localization/` | 语言选择与界面文案 |
| `Resources/` | 应用 Bundle 配置 |
| `Tests/` | 按职责分组的回归测试与测试入口 |
| `Tools/` | 源文件收集、测试、签名和图标生成工具 |
| `dist/` | 构建生成的应用、DMG 和调试符号 |

`AppController` 连接服务并协调历史、顺序粘贴和设置。服务负责各自的状态和系统操作，通过回调报告结果；原生窗口由 `WindowCoordinator` 管理，界面放在对应的功能目录。

常用修改入口：

- 历史面板的尺寸、搜索栏边距和卡片上下间距：`Sources/Features/History/HistoryLayout.swift`。
- 面板材质、选中颜色：`Sources/UI/PanelStyle.swift`。
- 快捷键默认值与作用范围：`Sources/Platform/Shortcuts/ShortcutSettings.swift`。
- 中英文界面文案：`Sources/Localization/AppText.swift`。
- 应用和菜单栏标志：`Sources/UI/OwnClipIcon.swift`；README 图标位于 `Resources/OwnClip.png`，矢量母版为 `Resources/OwnClip.svg`。`Tools/make-icon.swift` 与应用共用绘制代码，构建时生成完整多尺寸 ICNS。本机完整设计资源和使用规范位于 `Resources/Brand/`，按当前 `.gitignore` 保留为本地素材。

新增 Swift 文件放在对应职责目录即可，构建和测试脚本会递归收集源码。测试排除应用入口，编译其余全部源码，以覆盖文件拆分后的集成关系。测试使用独立剪贴板、临时目录和独立偏好设置，不发送真实粘贴按键。

## 构建

在 macOS 上安装 Xcode 命令行工具。首次构建前初始化固定的本地代码签名证书，然后构建：

```bash
./Tools/setup-signing.sh
./build.sh
```

初始化脚本会生成有效期 10 年的 `OwnClip Local Code Signing` 自签名证书，将证书和私钥导入当前用户的默认钥匙串，并仅为代码签名设置信任；macOS 可能弹出确认窗口。重复运行会复用已有证书，不会重新生成。若已有证书缺少私钥、过期或未受信任，脚本会报错，应修复原证书而不是新建同名证书。可用 `./Tools/setup-signing.sh --check` 只检查配置。

输出为 `dist/OwnClip.app`、`dist/OwnClip-<版本号>-<架构>.dmg` 和 `dist/OwnClip.app.dSYM`。DMG 文件名使用应用 `Info.plist` 中的 `CFBundleShortVersionString` 和目标架构，例如 `dist/OwnClip-1.0.10-arm64.dmg`（Apple Silicon）或 `dist/OwnClip-1.0.10-x86_64.dmg`（Intel）。默认使用当前架构，可通过 `OWNCLIP_ARCH=arm64 ./build.sh` 或 `OWNCLIP_ARCH=x86_64 ./build.sh` 分别构建；两种 DMG 可以并存，`OwnClip.app` 和 `.dSYM` 仍会被后一次构建覆盖。只构建应用和调试符号时可运行 `./build.sh --app-only`。默认使用固定的本地证书；证书不存在或不可用时会停止，不会退回临时签名。也可通过 `OWNCLIP_SIGN_IDENTITY` 指定其他证书的完整名称或 SHA-1 指纹；不接受 `-` 临时签名。发布时按版本和架构保留应用和 `.dSYM`，用 `xcrun dwarfdump --uuid` 核对它们与崩溃报告中的 UUID 一致。

可将同一份签好的安装包用于多台 Mac；每台 Mac 首次安装仍需单独授予权限，之后使用同一签名身份升级。其他电脑只需安装应用，无需导入签名私钥。自签名不等于 Apple Developer ID 或公证，下载后首次打开仍可能需要在系统设置中允许。

请保留钥匙串中的证书和私钥。更换构建电脑时，可通过「钥匙串访问」安全导出为带密码的 `.p12` 并导入新构建电脑，同时恢复代码签名信任；不要将私钥、`.p12` 或密码放进项目或安装包。重新生成同名证书并不是同一个签名身份，会导致重新授权。

运行 `./Tools/smoke-test.sh` 可验证原生剪贴板格式、历史保留和快捷键配置。测试使用独立的剪贴板和临时目录。

正式分发需要在签名机的钥匙串中安装 Developer ID Application 证书及私钥，并用 `xcrun notarytool store-credentials` 配置公证凭据。使用钥匙串中的完整签名身份名称和公证配置名构建：

```bash
OWNCLIP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
OWNCLIP_NOTARY_PROFILE='OwnClip' ./build.sh
```

脚本会启用 Hardened Runtime，签名并提交 DMG，等待 Apple 接受后附加并验证公证票据。正式分发时使用生成的 `dist/OwnClip-<版本号>-<架构>.dmg`。
