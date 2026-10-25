# WallpaperLoop

A native macOS dynamic wallpaper app: looping video, static images, and time-based dynamic wallpapers on every display's desktop layer.

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://github.com/cduyzh/WallpaperLoop)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white)](https://github.com/cduyzh/WallpaperLoop)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Author cduyzh](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)

**English** · [简体中文](README.zh-CN.md)

WallpaperLoop plays looping videos, static images, or time-based dynamic wallpapers directly on your desktop — below the desktop icons, above the system wallpaper, visible on every Space. It is built with SwiftUI and AppKit, requires macOS 14 or later, and has zero third-party dependencies. Smart pause, playlists, multi-display support, and a resident menu bar item keep everything under control.

## Features

- **Video wallpapers** — seamless looping via `AVQueuePlayer` + `AVPlayerLooper`, with 0.5–2× playback speed, volume control, and mute (muted by default).
- **Image wallpapers** — static images displayed edge to edge on each screen.
- **Time-based dynamic wallpapers** — map several media items from your library to local time slots (e.g. 07:00 sunrise, 19:00 night scene) with automatic switching and midnight wraparound.
- **Desktop-level rendering** — borderless windows placed at `CGWindowLevelForKey(.desktopWindow)`, below the desktop icons and above the system wallpaper, visible on all Spaces and click-through.
- **Smart pause** — automatically pauses when the frontmost app is fullscreen, on battery power, after a configurable idle period (1–30 minutes), or when the display sleeps or the screensaver starts; playback resumes automatically afterwards.
- **Playlists** — auto-rotation on a configurable interval, sequential or shuffled, freely mixing media items and dynamic wallpapers.
- **Crossfade transitions** — new wallpaper fades in while the old one fades out on switch (optional).
- **Multi-display** — enable/disable each screen independently, with an independent wallpaper per screen or a single wallpaper following the current one; hot-plug and resolution changes are handled automatically.
- **Hide desktop icons** — one toggle writes Finder's `CreateDesktop` preference and relaunches Finder; icons are restored automatically when the app quits.
- **Global hotkey** — toggle play/pause via Carbon `RegisterEventHotKey` (default ⌥⌘P) without any accessibility permission.
- **Menu bar app** — `LSUIElement` app resident in the menu bar with playback controls, next item, mute, hide icon, launch-at-login, and quit.
- **Launch at login** — registered as a login item through `SMAppService`.
- **Wallpaper library** — import mp4 / mov / m4v videos and common image formats, copied into the app support directory for unified management, with thumbnails, rename, and remove; type filter, name search, and card hover actions included.
- **Built-in system wallpapers** — browse the dynamic wallpaper videos that ship with macOS (`/System/Library/Desktop Pictures`, e.g. Tahoe Day, Sonoma) and add them by reference (no file copying) or as duplicated copies.
- **Online video import** — paste a direct mp4 / mov URL and the downloaded file joins your library as a copy.
- **Headless maintenance commands** — `--seed-system-wallpapers` and `--import-url <url>` for scripted batch imports (see below).
- **Storage management** — byte accounting of library copies vs. references; per-item deletion (copies delete the library file, references never touch the source file); one-click cleanup of unused video copies and orphan thumbnails; open the resource folder.
- **Dynamic wallpaper editor** — schedules are re-editable at any time; items whose source file was moved or deleted externally are marked "missing source", and playback automatically falls back to the system wallpaper.
- **Version and history** — the app shows the current version, build number, and full local update history, with automatic consistency checks between the root `Info.plist` and `Resources/ReleaseHistory.json`.

## How It Works

- **Desktop window rendering** — every connected screen gets its own borderless, click-through window at `CGWindowLevelForKey(.desktopWindow)` (−2147483623), which sits above the system wallpaper but below the desktop-icon layer (−2147483622), so your wallpaper never covers icons or desktop files. The windows follow all Spaces, and hot-plug and resolution changes are handled automatically. The system wallpaper itself is never modified — quitting the app simply reveals it again.
- **Playback** — videos loop through `AVQueuePlayer` + `AVPlayerLooper`; speed changes go through `AVPlayer.playImmediately(atRate:)`; crossfades are opacity animations between two layers inside the wallpaper window.
- **Time-based dynamic wallpapers** — library media are mapped to local time slots with automatic switching and midnight wraparound, combining Apple's time-based dynamic wallpaper concepts with common ideas from open-source dynamic wallpaper projects.
- **Smart pause triggers** — frontmost app going fullscreen, switching to battery power, idle for the configured minutes, display sleep, or screensaver. Playback resumes automatically once the condition clears. Fullscreen detection only reads window geometry, level, and process info from `CGWindowList` — never window contents — so no screen-recording permission is needed.

## Headless Commands

For scripted batch imports without opening the UI, run the app binary from Terminal (adjust the path if you installed the app elsewhere):

```bash
/Applications/cduyzhDynamicWallpapaer.app/Contents/MacOS/cduyzhDynamicWallpapaer --seed-system-wallpapers
/Applications/cduyzhDynamicWallpapaer.app/Contents/MacOS/cduyzhDynamicWallpapaer --import-url https://example.com/wallpaper.mp4
```

`--seed-system-wallpapers` adds the built-in macOS wallpapers by reference; `--import-url <url>` downloads the given direct mp4 / mov link into the library as a copy.

## Download and Install

1. Download the latest DMG from the [Releases](https://github.com/cduyzh/WallpaperLoop/releases) page.
2. Open the DMG and drag **WallpaperLoop** (`cduyzhDynamicWallpapaer.app`) to `Applications`.
3. The first time, right-click the app in `Applications` and choose **Open** (the app currently uses local ad-hoc signing and is not notarized, so Gatekeeper asks for explicit confirmation once).

After launching, the main window opens automatically; closing it keeps the app resident in the menu bar.

## Build from Source

Requires Xcode or Command Line Tools (Swift 5.9+) on macOS 14 or later.

```bash
git clone https://github.com/cduyzh/WallpaperLoop.git
cd WallpaperLoop
./build_app.sh
```

## Version History

The current version is **0.2.1** (build 3), defined by the root `Info.plist` and kept consistent with `Resources/ReleaseHistory.json`. See [CHANGELOG.md](CHANGELOG.md) for the full history.

## Privacy

All media and settings stay on your Mac. Library copies live in the app's Application Support folder and nothing is uploaded. The only network access is the online import feature, which downloads exactly the mp4 / mov URL you paste. There is no analytics or telemetry.

## License

Released under the [MIT License](LICENSE).

## Author

**cduyzh**

- GitHub: <https://github.com/cduyzh>
- Website: <https://www.cduyzh.top>
- Goal: <https://www.cduyzh.top/goal>
