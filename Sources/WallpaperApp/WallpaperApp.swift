import AppKit
import SwiftUI
import WallpaperCore

@main
struct WallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // 维护命令（无头模式）：--seed-system-wallpapers / --import-url <url>，执行完即退出，不进入 UI。
        if MaintenanceCLI.runIfNeeded() {
            exit(0)
        }
    }

    var body: some Scene {
        Window("WallpaperLoop", id: "main") {
            ContentView()
                .environmentObject(delegate.store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { NotificationCenter.default.post(name: .navigateSettings, object: nil) }
                    .keyboardShortcut(",")
                Button("资源管理…") { NotificationCenter.default.post(name: .navigateResources, object: nil) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name { static let navigateSettings = Notification.Name("cduyzhWallpaper.navigateSettings") }

/// 无头维护命令：供脚本批量导入资源，不启动界面、不依赖主线程。
enum MaintenanceCLI {
    static var wantsCLI: Bool {
        CommandLine.arguments.contains("--seed-system-wallpapers") || CommandLine.arguments.contains("--import-url")
    }

    /// 执行维护命令并返回 true（无命令时返回 false 继续正常启动）。
    static func runIfNeeded() -> Bool {
        guard wantsCLI else { return false }
        perform()
        return true
    }

    private static func perform() {
        let library = WallpaperLibrary(directory: WallpaperLibrary.defaultDirectory())
        let thumbnailsDirectory = library.libraryDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        if CommandLine.arguments.contains("--seed-system-wallpapers") {
            seedSystemWallpapers(library: library, thumbnailsDirectory: thumbnailsDirectory)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--import-url"), index + 1 < CommandLine.arguments.count {
            importFromURL(raw: CommandLine.arguments[index + 1], library: library, thumbnailsDirectory: thumbnailsDirectory)
        }
        print("库内现有 \(library.currentSnapshot().media.count) 个媒体条目：\(library.libraryDirectory.path)")
    }

    private static func seedSystemWallpapers(library: WallpaperLibrary, thumbnailsDirectory: URL) {
        let assets = SystemWallpaperAssets.scan()
        guard !assets.isEmpty else {
            print("未找到系统内置壁纸视频（/System/Library/Desktop Pictures/.wallpapers）")
            return
        }
        let existing = Set(library.currentSnapshot().media.compactMap { $0.isReference ? $0.sourcePath : nil })
        for asset in assets where !existing.contains(asset.url.path) {
            let inspected: (duration: Double, size: CGSizeValue)? = waitFor {
                await MediaInspection.inspectVideo(url: asset.url)
            } ?? nil
            do {
                let item = try library.importMedia(at: asset.url, kind: .video,
                                                   durationSeconds: inspected?.duration, pixelSize: inspected?.size,
                                                   storage: .reference, origin: .system)
                try? MediaInspection.writeThumbnail(source: asset.url, kind: .video,
                                                    destination: thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg"))
                print("已引用：\(asset.name)（\(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))，不占库空间）")
            } catch {
                print("导入失败：\(asset.name)：\(error.localizedDescription)")
            }
        }
    }

    private static func importFromURL(raw: String, library: WallpaperLibrary, thumbnailsDirectory: URL) {
        guard let url = MediaDownloader.sanitizedURL(from: raw) else {
            print("无效的 URL：\(raw)")
            return
        }
        guard let file = waitFor({ try await MediaDownloader.download(from: url) }) else {
            print("下载失败：\(url.absoluteString)")
            return
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let inspected: (duration: Double, size: CGSizeValue)? = waitFor {
            await MediaInspection.inspectVideo(url: file)
        } ?? nil
        do {
            let item = try library.importMedia(at: file, kind: .video,
                                               durationSeconds: inspected?.duration, pixelSize: inspected?.size,
                                               storage: .copy, origin: .downloaded)
            try? MediaInspection.writeThumbnail(source: library.url(for: item), kind: .video,
                                                destination: thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg"))
            // 临时文件名不可读，按原始 URL 文件名重命名。
            let originalName = url.deletingPathExtension().lastPathComponent
            if !originalName.isEmpty {
                try? library.rename(reference: .media(item.id), title: originalName)
            }
            print("已导入：\(originalName.isEmpty ? item.title : originalName)（\(ByteCountFormatter.string(fromByteCount: library.fileSizeBytes(for: item) ?? 0, countStyle: .file))）")
        } catch {
            print("导入失败：\(url.absoluteString)：\(error.localizedDescription)")
        }
    }

    /// 在后台线程等待一个 async 调用完成（CLI 无主线程 run loop，需显式桥接）；抛错时返回 nil。
    private static func waitFor<T>(_ body: @escaping @Sendable () async throws -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        Task {
            do { result = try await body() } catch { result = nil }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 引擎与库由委托持有，启动即就绪，不依赖主窗口出现。
    let store = AppStore()
    private var statusItem: NSStatusItem?
    private var hotkey: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        installStatusItem()
        installHotkey()
        // 启动即弹出主窗口；关闭窗口后应用继续常驻菜单栏。
        openMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 主窗口关闭后继续常驻菜单栏。
        false
    }

    /// 应用已在运行时再次启动（Spotlight / Finder / open）：把主窗口拉回前台。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.engine.shutdown()
        // 若因本应用隐藏了桌面图标，退出前恢复显示。
        if store.settingsStore.settings.hideDesktopIcons {
            store.setHideDesktopIcons(false)
        }
    }

    // MARK: - 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "WallpaperLoop")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let playing = store.engine.playing

        let playItem = NSMenuItem(title: playing ? "暂停壁纸" : "播放壁纸",
                                  action: #selector(togglePause), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        let nextItem = NSMenuItem(title: "下一个壁纸", action: #selector(playNext), keyEquivalent: "")
        nextItem.target = self
        nextItem.isEnabled = store.snapshot.media.count + store.snapshot.dynamicWallpapers.count > 1
        menu.addItem(nextItem)

        let muteItem = NSMenuItem(title: store.settingsStore.settings.muted ? "取消静音" : "静音",
                                  action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)

        menu.addItem(.separator())

        let windowItem = NSMenuItem(title: "打开壁纸库…", action: #selector(openMain), keyEquivalent: "")
        windowItem.target = self
        menu.addItem(windowItem)

        let iconItem = NSMenuItem(title: store.settingsStore.settings.hideDesktopIcons ? "显示桌面图标" : "隐藏桌面图标",
                                  action: #selector(toggleDesktopIcons), keyEquivalent: "")
        iconItem.target = self
        menu.addItem(iconItem)

        let loginItem = NSMenuItem(title: store.settingsStore.settings.launchAtLogin ? "关闭开机启动" : "开机启动",
                                   action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        if let reasons = store.engine.activePauseReasons.sorted(by: { $0.rawValue < $1.rawValue }).first {
            let label: String
            switch reasons {
            case .fullscreen: label = "已自动暂停：前台应用全屏"
            case .battery: label = "已自动暂停：电池供电"
            case .idle: label = "已自动暂停：闲置"
            case .displaySleep: label = "已自动暂停：屏幕休眠或屏保"
            }
            let stateItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
            menu.addItem(.separator())
        }
        let quitItem = NSMenuItem(title: "退出 WallpaperLoop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func togglePause() {
        store.engine.togglePause()
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    @objc private func playNext() {
        store.engine.playNext()
    }

    @objc private func toggleMute() {
        store.settingsStore.update { $0.muted.toggle() }
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    @objc private func openMain() {
        openMainWindow()
    }

    @objc private func toggleDesktopIcons() {
        let store = store
        let next = !store.settingsStore.settings.hideDesktopIcons
        store.setHideDesktopIcons(next)
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    @objc private func toggleLogin() {
        let store = store
        store.setLaunchAtLogin(!store.settingsStore.settings.launchAtLogin)
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func openMainWindow() {
        // SwiftUI Window 场景创建的窗口：按标题或场景 id 匹配（隐藏标题栏不影响 title 属性）。
        let mainWindow = NSApp.windows.first { window in
            window.level == .normal
                && (window.title == "WallpaperLoop" || window.identifier?.rawValue == "main")
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 快捷键

    private func installHotkey() {
        let manager = HotkeyManager { [weak self] in
            self?.togglePause()
        }
        let settings = store.settingsStore.settings
        manager.register(combo: settings.hotkeyEnabled ? settings.hotkey : nil)
        hotkey = manager
        NotificationCenter.default.addObserver(forName: .hotkeySettingsChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let settings = self.store.settingsStore.settings
                self.hotkey?.register(combo: settings.hotkeyEnabled ? settings.hotkey : nil)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
