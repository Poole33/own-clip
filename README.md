<div align="center">

# OwnClip

**免费开源，轻量、克制、原生的 macOS 剪贴板工具。**

让复制、剪切和粘贴更顺手。

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-Native-F05138?style=flat-square&logo=swift&logoColor=white)
![Dependencies](https://img.shields.io/badge/Dependencies-0-307A59?style=flat-square)
[![Release](https://img.shields.io/github/v/release/Poole33/own-clip?style=flat-square)](https://github.com/Poole33/own-clip/releases/latest)

[下载最新版本](https://github.com/Poole33/own-clip/releases/latest) · [设计理念](#设计理念) · [功能](#功能) · [安装](#安装) · [使用指南](docs/usage.md) · [开发指南](docs/development.md)

</div>

## 为什么做 OwnClip

我试过不少同类产品，却一直没找到一款足够轻量、功能克制，专注剪贴板，又能同时满足**文件/文字剪切、顺序粘贴和剪贴板历史**这三个需求的工具。

找回刚才复制的一段文字，把几条内容依次填进表单，或把 Finder 里的文件剪切到另一个文件夹，都是我每天反复遇到的场景。

于是有了 OwnClip。它围绕这些高频操作，补上几个顺手的小功能，保持小巧，也保持专注。常驻菜单栏，按下快捷键就能呼出，用完回到手头的工作。

> 如果在使用的某一瞬间，你觉得“这本来就是 macOS 的功能”，OwnClip 就做对了。

## 设计理念

- **免费开源。** 免费下载和使用，源代码公开，欢迎查看实现、反馈问题和参与贡献。
- **轻量。** 使用 Swift、AppKit 和 SwiftUI，直接调用系统框架，零第三方依赖，让应用保持小巧。
- **做减法。** 功能取舍围绕复制、剪切和粘贴，保持清晰的使用范围。
- **高频优先。** 每个新功能都应解决日常反复遇到的问题；增加功能前，先考虑能否把现有操作做得更顺手。
- **原生体验。** 使用系统窗口材质、选中颜色和标准键盘操作，跟随浅色与深色外观，也尊重系统的“降低透明度”设置，不花里胡哨，尽量给你原生般的体验。

**应用本体约 0.8 MB。** 本机已安装的 OwnClip 1.0.9 应用包（`OwnClip.app`）内文件合计 791,621 字节，实测于 2026-11-19；体积会随版本、架构及签名方式变化。

## 功能

### 找回刚才复制的内容

按 `⌘⇧V` 打开剪贴板历史，搜索并选中需要的内容，按 `Return` 直接粘贴到原来的应用。支持文本、富文本、图片和文件等剪贴板内容；需要去掉文字格式时，按 `⌘Return` 粘贴为纯文本。

历史提供屏幕底部长条和浮动列表两种展示方式，可在设置中切换。

### 连续复制，依次粘贴

按 `⌘⇧C` 打开顺序粘贴，再连续复制多条内容。回到目标应用，按 `⌘V` 逐条粘贴，适合填写表单、整理资料等重复操作。

支持“用后移除”和“循环使用”，也可以反转顺序，或从历史中添加条目。关闭顺序粘贴后，`⌘V` 恢复普通粘贴。

### 在 Finder 中剪切文件

在设置中开启文件剪切后，选中文件按 `⌘X`，进入目标文件夹按 `⌘V`，由 Finder 完成移动。

这项功能默认关闭；文本和文件名编辑沿用系统原生的剪切操作。

## 安装

需要 **macOS 14 或更高版本**。现有安装包面向 Apple Silicon；构建脚本支持按当前 Mac 架构编译，也可通过 `OWNCLIP_ARCH` 指定 `arm64` 或 `x86_64`。

从 [GitHub Releases](https://github.com/Poole33/own-clip/releases/latest) 下载最新版本，或[直接下载 OwnClip.dmg](https://github.com/Poole33/own-clip/releases/latest/download/OwnClip.dmg)。

1. 打开 `OwnClip.dmg`，将 `OwnClip.app` 拖入“应用程序”。
2. 启动 OwnClip，按提示在“系统设置 → 隐私与安全性”中授予自动粘贴所需权限。
3. 如系统提示访问剪贴板或启用输入监控，按引导完成授权。

当前发布版本使用本地自签名，未经 Apple 公证，首次打开时可能需要在“隐私与安全性”中确认打开。授权未生效等问题见[使用指南](docs/usage.md)。

## 常用快捷键

| 操作 | 默认快捷键 | 生效范围 |
| --- | --- | --- |
| 打开剪贴板历史 | `⌘⇧V` | 全局 |
| 打开顺序粘贴 | `⌘⇧C` | 全局 |
| 粘贴选中条目 | `Return` | 历史面板 |
| 粘贴为纯文本 | `⌘Return` | 历史面板 |
| 粘贴当前结果的第 1–10 条 | `⌘1` 至 `⌘0` | 历史面板 |
| 粘贴下一条 | `⌘V` | 顺序粘贴启用时 |
| 关闭当前窗口 | `Esc` / `⌘W` | OwnClip 窗口 |
| 标记文件待移动 / 移动到目标目录 | `⌘X` / `⌘V` | Finder 文件剪切启用时 |

可在“设置 → 快捷键”中修改快捷键；`Esc` 和 `⌘W` 保留为标准窗口操作。语言支持简体中文、English 和跟随系统，登录时自动启动可按需开启。

## 本地存储

剪贴板历史保存在这台 Mac 上，无需账户或联网服务。

- 存储位置：`~/Library/Application Support/OwnClip`。
- 默认保留 **1 天**，可在设置中调整为 **1–7 天**，也可手动清空。
- Finder 文件和视频记录保留原文件引用；直接复制的图片、视频数据保存在本机。引用的原文件不可访问时，会提示无法使用。

## 从源码构建

在 macOS 上安装 Xcode 命令行工具后，在项目根目录运行：

```bash
./Tools/setup-signing.sh
./build.sh
```

首次初始化会将固定的本地签名证书及私钥导入当前用户钥匙串，并设置代码签名信任，过程中可能出现系统确认窗口。后续构建复用同一签名身份。

构建产物为 `dist/OwnClip.app`、`dist/OwnClip.dmg` 和 `dist/OwnClip.app.dSYM`。只构建应用与调试符号可使用 `./build.sh --app-only`。

运行回归检查：

```bash
./Tools/smoke-test.sh
```

项目结构、签名迁移与 Developer ID 公证分发说明见[开发指南](docs/development.md)。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Poole33/own-clip/issues) 反馈问题或提出建议。报告问题时，请附上 macOS 版本、OwnClip 版本和复现步骤。

提出新功能时，也请描述你在什么场景下、以多高的频率遇到这个问题。OwnClip 会持续围绕轻量、常用和原生体验做取舍。
