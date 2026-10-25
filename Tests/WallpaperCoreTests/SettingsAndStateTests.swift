import Carbon.HIToolbox
import XCTest
@testable import WallpaperCore

final class SettingsAndStateTests: XCTestCase {
    func testSettingsCodableRoundTrip() throws {
        var settings = AppSettings()
        settings.updateForTest { current in
            current.volume = 0.8
            current.pauseOnBattery = true
            current.idlePauseMinutes = 10
            current.playlist.mode = .interval
            current.playlist.intervalSeconds = 600
            current.playlist.order = [.media(UUID()), .dynamicWallpaper(UUID())]
        }
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testPruneReferencesRemovesStaleEntries() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let keepMedia = UUID()
        let keepDynamic = UUID()
        store.update { current in
            current.currentWallpaper = .media(keepMedia)
            current.playlist.order = [.media(keepMedia), .media(UUID()), .dynamicWallpaper(keepDynamic)]
            current.displays = [DisplayConfig(displayID: 1, enabled: true, wallpaper: .dynamicWallpaper(UUID()))]
        }
        store.pruneReferences(validMedia: [keepMedia], validDynamic: [keepDynamic])
        XCTAssertEqual(store.settings.playlist.order, [.media(keepMedia), .dynamicWallpaper(keepDynamic)])
        XCTAssertEqual(store.settings.currentWallpaper, .media(keepMedia))
        XCTAssertNil(store.settings.displays.first?.wallpaper)
    }

    func testWallpaperKindFromExtension() {
        XCTAssertEqual(WallpaperKind(fileExtension: "MP4"), .video)
        XCTAssertEqual(WallpaperKind(fileExtension: "mov"), .video)
        XCTAssertEqual(WallpaperKind(fileExtension: "m4v"), .video)
        XCTAssertEqual(WallpaperKind(fileExtension: "png"), .image)
        XCTAssertEqual(WallpaperKind(fileExtension: "heic"), .image)
        XCTAssertEqual(WallpaperKind(fileExtension: "jpg"), .image)
    }

    func testFullscreenEvaluation() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pid = 4242
        // 全屏窗口：普通层级，覆盖整屏。
        let fullscreen = SystemStateMonitor.WindowSnapshot(
            ownerPID: pid, layer: 0,
            bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isOnscreen: true)
        XCTAssertTrue(SystemStateMonitor.evaluateFullscreen(windows: [fullscreen], frontmostPID: pid, screens: [screen]))

        // 普通窗口：不覆盖整屏。
        let normal = SystemStateMonitor.WindowSnapshot(
            ownerPID: pid, layer: 0,
            bounds: CGRect(x: 0, y: 50, width: 1200, height: 800), isOnscreen: true)
        XCTAssertFalse(SystemStateMonitor.evaluateFullscreen(windows: [normal], frontmostPID: pid, screens: [screen]))

        // 覆盖整屏但不是普通层级（例如本应用自己的桌面层窗口）不算全屏。
        let desktopLayer = SystemStateMonitor.WindowSnapshot(
            ownerPID: pid, layer: -2147483623,
            bounds: screen, isOnscreen: true)
        XCTAssertFalse(SystemStateMonitor.evaluateFullscreen(windows: [desktopLayer], frontmostPID: pid, screens: [screen]))

        // 别的应用的窗口不算。
        XCTAssertFalse(SystemStateMonitor.evaluateFullscreen(windows: [fullscreen], frontmostPID: 999, screens: [screen]))
    }

    func testHotkeyCarbonModifiers() {
        XCTAssertEqual(HotkeyManager.carbonModifiers(from: .defaultToggle), UInt32(cmdKey | optionKey))
        let none = HotkeyCombo(keyCode: 35, optionKey: false, commandKey: false)
        XCTAssertEqual(HotkeyManager.carbonModifiers(from: none), 0)
    }

    func testHotkeyReadableLabel() {
        XCTAssertTrue(HotkeyManager.readableLabel(for: .defaultToggle).hasSuffix("P"))
    }
}

extension AppSettings {
    /// 测试辅助：直接变换设置。
    mutating func updateForTest(_ transform: (inout AppSettings) -> Void) {
        transform(&self)
    }
}
