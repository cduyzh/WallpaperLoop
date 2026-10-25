# WallpaperLoop（动态壁纸）

原生 macOS 动态壁纸应用：在每块屏幕的桌面层级播放循环视频、静态图片与按本地时间自动切换的动态壁纸。

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://github.com/cduyzh/WallpaperLoop)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white)](https://github.com/cduyzh/WallpaperLoop)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Author cduyzh](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)

[English](README.md) · **简体中文**

WallpaperLoop 直接在桌面上播放循环视频、静态图片或按时间切换的动态壁纸——位于桌面图标之下、系统壁纸之上，在所有空间可见。应用基于 SwiftUI 与 AppKit 构建，要求 macOS 14 或更新版本，无任何第三方依赖。智能暂停、播放列表、多显示器支持与常驻菜单栏让一切尽在掌控。

## 特性

- **视频壁纸** — `AVQueuePlayer` + `AVPlayerLooper` 无缝循环；0.5–2 倍速、音量与静音（默认静音）。
- **图片壁纸** — 静态图片按屏幕铺满显示。
- **时间型动态壁纸** — 把库内多个媒体编排为本地时间时段（例如 07:00 日出、19:00 夜景），自动切换，跨零点回绕。
- **桌面层渲染** — 无边框窗口置于 `CGWindowLevelForKey(.desktopWindow)`，位于桌面图标之下、系统壁纸之上，随所有空间显示且不拦截鼠标。
- **智能暂停** — 前台应用全屏、电池供电、闲置指定分钟（1–30）、屏幕休眠或屏保时自动暂停，恢复后自动继续播放。
- **播放列表** — 按间隔自动轮换，顺序或随机；库内任意媒体与动态壁纸可自由混排。
- **切换过渡** — 新壁纸淡入、旧壁纸淡出（可关闭）。
- **多显示器** — 每块屏幕独立启用/停用，可指定独立壁纸或跟随当前壁纸；热插拔与分辨率变化自动处理。
- **隐藏桌面图标** — 一键写入 Finder 的 `CreateDesktop` 并重启 Finder；退出应用时自动恢复显示。
- **全局快捷键** — Carbon `RegisterEventHotKey` 切换播放/暂停（默认 ⌥⌘P），无需辅助功能权限。
- **菜单栏应用** — `LSUIElement` 常驻菜单栏：播放控制、下一张、静音、隐藏图标、开机启动与退出。
- **开机启动** — 通过 `SMAppService` 注册登录项。
- **壁纸库** — 导入 mp4 / mov / m4v 视频与常见图片格式，复制到应用支持目录统一管理；生成缩略图、重命名与移除；支持类型筛选、名称搜索与卡片悬浮操作。
- **系统内置壁纸** — 浏览 macOS 自带的动态壁纸视频（`/System/Library/Desktop Pictures`，如 Tahoe Day、Sonoma），可按「引用」加入库（不复制文件）或复制为副本。
- **在线视频导入** — 粘贴 mp4 / mov 直链，下载后作为副本入库。
- **无头维护命令** — `--seed-system-wallpapers` 与 `--import-url <url>`，供脚本批量导入（见下文）。
- **资源管理** — 库内副本与引用条目的字节统计；逐项删除（副本删除库内文件，引用条目绝不触碰源文件）；一键清理未使用的视频副本与孤儿缩略图；打开资源目录。
- **动态壁纸编辑** — 时段方案可随时重新编辑；源文件被外部移动/删除的条目标记「资源缺失」，播放时自动回退系统壁纸。
- **版本与历史** — 应用内展示当前版本、构建号与完整本地更新历史；根 `Info.plist` 与 `Resources/ReleaseHistory.json` 自动校验一致。

## 工作原理

- **桌面层窗口渲染** — 每块连接的屏幕各有一个无边框、不拦截鼠标的窗口，置于 `CGWindowLevelForKey(.desktopWindow)`（−2147483623），位于系统壁纸之上、桌面图标层（−2147483622）之下，因此壁纸永远不会盖住图标与桌面文件。窗口随所有空间显示，热插拔与分辨率变化自动处理。系统壁纸本身不会被修改——退出应用即恢复显示。
- **播放** — 视频经 `AVQueuePlayer` + `AVPlayerLooper` 循环；倍速通过 `AVPlayer.playImmediately(atRate:)` 下发；切换淡入淡出在壁纸窗口内以双层透明度动画完成。
- **时间型动态壁纸** — 把库内媒体映射到本地时间时段，自动切换并跨零点回绕；结合 Apple 时间型动态壁纸概念与开源动态壁纸项目的通用思路。
- **智能暂停触发条件** — 前台应用全屏、切换到电池供电、闲置达到设定分钟数、屏幕休眠或屏保。条件解除后自动恢复播放。全屏检测只读取 `CGWindowList` 的窗口几何、层级与进程信息，绝不读取窗口内容，因此无需屏幕录制权限。

## 无头命令

脚本批量导入资源时，可在终端直接运行应用二进制，不打开界面（路径按实际安装位置调整）：

```bash
/Applications/cduyzhDynamicWallpapaer.app/Contents/MacOS/cduyzhDynamicWallpapaer --seed-system-wallpapers
/Applications/cduyzhDynamicWallpapaer.app/Contents/MacOS/cduyzhDynamicWallpapaer --import-url https://example.com/wallpaper.mp4
```

`--seed-system-wallpapers` 以「引用」方式加入 macOS 自带壁纸；`--import-url <url>` 下载指定的 mp4 / mov 直链并作为副本入库。

## 下载与安装

1. 在 [Releases](https://github.com/cduyzh/WallpaperLoop/releases) 页面下载最新的 DMG。
2. 打开 DMG，把 **WallpaperLoop**（`cduyzhDynamicWallpapaer.app`）拖入 `Applications`。
3. 首次使用时，在 `Applications` 中右键点按应用并选择「打开」（应用目前使用本地 ad-hoc 签名且未公证，Gatekeeper 会要求确认一次）。

启动后主窗口自动弹出；关闭窗口后应用仍常驻菜单栏。

## 从源码构建

需要 macOS 14 或更新版本，以及 Xcode 或 Command Line Tools（Swift 5.9+）。

```bash
git clone https://github.com/cduyzh/WallpaperLoop.git
cd WallpaperLoop
./build_app.sh
```

## 版本历史

当前版本为 **0.2.1**（构建 3），由根目录 `Info.plist` 定义，并与 `Resources/ReleaseHistory.json` 保持一致。完整历史见 [CHANGELOG.md](CHANGELOG.md)。

## 隐私

所有媒体与设置都保留在你的 Mac 上。库内副本保存在应用的应用支持目录中，不上传任何内容。唯一的网络访问是在线导入功能，且只下载你粘贴的 mp4 / mov 直链。无任何统计上报。

## 许可证

以 [MIT License](LICENSE) 发布。

## 作者

**cduyzh**

- GitHub：<https://github.com/cduyzh>
- 网站：<https://www.cduyzh.top>
- 目标页：<https://www.cduyzh.top/goal>
