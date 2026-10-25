import AVFoundation
import AppKit
import Combine
import Foundation
import WallpaperCore

/// 壁纸引擎：协调每屏窗口、播放状态、智能暂停、播放列表与动态壁纸时段切换。
@MainActor
final class WallpaperEngine: ObservableObject {
    @Published private(set) var userPaused = false
    @Published private(set) var activePauseReasons: Set<PauseReason> = []
    @Published private(set) var currentWallpaper: WallpaperReference?
    @Published private(set) var playing: Bool = false
    @Published private(set) var slotMediaID: UUID?
    @Published private(set) var slotEndsAt: Date?

    private let library: WallpaperLibrary
    private let settingsStore: SettingsStore
    private let systemState: SystemStateMonitor
    private let powerMonitor: PowerMonitor
    private var surfaces: [CGDirectDisplayID: WallpaperSurface] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var playlistIndex: Int?
    private var playlistTimer: Timer?
    private var slotTimer: Timer?
    private var screenSanityTimer: Timer?

    init(library: WallpaperLibrary, settingsStore: SettingsStore,
         systemState: SystemStateMonitor = SystemStateMonitor(), powerMonitor: PowerMonitor = PowerMonitor()) {
        self.library = library
        self.settingsStore = settingsStore
        self.systemState = systemState
        self.powerMonitor = powerMonitor
        currentWallpaper = settingsStore.settings.currentWallpaper
    }

    func start() {
        rebuildSurfaces()
        presentCurrentWallpaper(animated: false)
        observeInputs()
        syncScreenObservers()
        refreshPlaybackState()
        scheduleTimers()
    }

    func shutdown() {
        playlistTimer?.invalidate()
        slotTimer?.invalidate()
        screenSanityTimer?.invalidate()
        for surface in surfaces.values { surface.stopPlayback() }
        surfaces.values.forEach { $0.window.orderOut(nil) }
        surfaces.removeAll()
    }

    // MARK: - 对外动作

    func togglePause() {
        userPaused.toggle()
        refreshPlaybackState()
    }

    func setPaused(_ paused: Bool) {
        userPaused = paused
        refreshPlaybackState()
    }

    /// 设置当前壁纸并立即呈现。
    func play(wallpaper: WallpaperReference) {
        settingsStore.update { $0.currentWallpaper = wallpaper }
        currentWallpaper = wallpaper
        playlistIndex = playlistIndex(of: wallpaper)
        presentCurrentWallpaper(animated: true)
        scheduleTimers()
    }

    /// 播放列表下一个（无播放列表则按库顺序）。
    func playNext() {
        let order = settingsStore.settings.playlist.order
        if order.isEmpty {
            playNextFromLibrary()
            return
        }
        let index = PlaylistScheduler.nextIndex(after: playlistIndex, count: order.count,
                                                shuffle: settingsStore.settings.playlist.shuffle, seed: UInt64(Date().timeIntervalSince1970))
        guard let index else { return }
        playlistIndex = index
        let reference = order[index]
        settingsStore.update { $0.currentWallpaper = reference }
        currentWallpaper = reference
        presentCurrentWallpaper(animated: true)
    }

    private func playNextFromLibrary() {
        let snapshot = library.currentSnapshot()
        let all: [WallpaperReference] = snapshot.media.map { .media($0.id) } + snapshot.dynamicWallpapers.map { .dynamicWallpaper($0.id) }
        guard !all.isEmpty else { return }
        let currentIndex = currentWallpaper.flatMap { all.firstIndex(of: $0) }
        let index = PlaylistScheduler.nextIndex(after: currentIndex, count: all.count, shuffle: false, seed: 0)
        if let index, all.indices.contains(index) {
            play(wallpaper: all[index])
        } else {
            play(wallpaper: all[0])
        }
    }

    private func playlistIndex(of reference: WallpaperReference) -> Int? {
        settingsStore.settings.playlist.order.firstIndex(of: reference)
    }

    // MARK: - 屏幕管理

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// 当前每屏应呈现的媒体；nil 表示该屏不启用。
    private func intendedMedia(forDisplay displayID: CGDirectDisplayID) -> WallpaperSurface.Media? {
        let settings = settingsStore.settings
        let config = settings.displays.first { $0.displayID == displayID }
        if let config, !config.enabled { return nil }
        let reference = (config?.wallpaper ?? settings.currentWallpaper) ?? settings.currentWallpaper
        guard let reference else { return nil }
        return resolveMedia(for: reference)
    }

    /// 引用 → 当前应显示的媒体（动态壁纸取当前时段）；源文件缺失时返回 nil（该屏回退系统壁纸）。
    private func resolveMedia(for reference: WallpaperReference) -> WallpaperSurface.Media? {
        switch reference {
        case .media(let id):
            guard let item = library.media(withID: id),
                  library.location(for: item) != nil else { return nil }
            return WallpaperSurface.Media(url: library.url(for: item), kind: item.kind, startAt: 0)
        case .dynamicWallpaper(let id):
            guard let dynamic = library.dynamicWallpaper(withID: id),
                  let slot = PlaylistScheduler.activeSlot(at: Date(), slots: dynamic.slots),
                  let item = library.media(withID: slot.mediaID),
                  library.location(for: item) != nil else { return nil }
            slotMediaID = slot.mediaID
            slotEndsAt = PlaylistScheduler.nextTransition(after: Date(), slots: dynamic.slots)
            return WallpaperSurface.Media(url: library.url(for: item), kind: item.kind, startAt: 0)
        }
    }

    private func rebuildSurfaces() {
        let screens = NSScreen.screens
        var liveIDs = Set<CGDirectDisplayID>()
        for screen in screens {
            guard let id = Self.displayID(of: screen) else { continue }
            liveIDs.insert(id)
            if let existing = surfaces[id] {
                existing.syncFrame(with: screen)
            } else {
                surfaces[id] = WallpaperSurface(screen: screen, displayID: id)
            }
        }
        for (id, surface) in surfaces where !liveIDs.contains(id) {
            surface.stopPlayback()
            surface.window.orderOut(nil)
            surfaces.removeValue(forKey: id)
        }
        presentCurrentWallpaper(animated: false)
    }

    private func presentCurrentWallpaper(animated: Bool) {
        let crossfade = animated && settingsStore.settings.crossfade
        for (id, surface) in surfaces {
            if let media = intendedMedia(forDisplay: id) {
                surface.window.orderFrontRegardless()
                surface.present(media, crossfade: crossfade)
            } else {
                surface.window.orderOut(nil)
                surface.stopPlayback()
            }
        }
        refreshPlaybackState()
    }

    private func syncScreenObservers() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // 屏幕热插拔后几何信息短暂不稳定，稍候再重建。
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.rebuildSurfaces()
            }
        }
        screenSanityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verifyScreenGeometry() }
        }
    }

    /// 分辨率或缩放变化不触发屏幕列表通知，低频比对几何兜底。
    private func verifyScreenGeometry() {
        for screen in NSScreen.screens {
            guard let id = Self.displayID(of: screen) else { continue }
            if let surface = surfaces[id], surface.screenFrame != screen.frame {
                surface.syncFrame(with: screen)
            }
        }
    }

    // MARK: - 输入订阅

    private func observeInputs() {
        settingsStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSettingsChange() }
            .store(in: &cancellables)

        systemState.$frontmostIsFullscreen
            .combineLatest(systemState.$idleSeconds, systemState.$displayAsleep, powerMonitor.$isOnBattery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPauseReasons() }
            .store(in: &cancellables)

        systemState.$idleSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPauseReasons() }
            .store(in: &cancellables)
    }

    private func handleSettingsChange() {
        presentCurrentWallpaper(animated: true)
        refreshPlaybackState()
        scheduleTimers()
    }

    // MARK: - 暂停策略

    private func refreshPauseReasons() {
        let settings = settingsStore.settings
        var reasons: Set<PauseReason> = []
        if settings.pauseWhenFullscreen, systemState.frontmostIsFullscreen { reasons.insert(.fullscreen) }
        if settings.pauseOnBattery, powerMonitor.isOnBattery { reasons.insert(.battery) }
        if settings.idlePauseMinutes > 0,
           systemState.idleSeconds >= Double(settings.idlePauseMinutes * 60) { reasons.insert(.idle) }
        if settings.pauseWhenDisplaySleep, systemState.displayAsleep { reasons.insert(.displaySleep) }
        activePauseReasons = reasons
        refreshPlaybackState()
    }

    private func refreshPlaybackState() {
        let next = !userPaused && activePauseReasons.isEmpty
        playing = next
        let settings = settingsStore.settings
        for surface in surfaces.values {
            surface.applyPlayback(playing: next, rate: settings.playbackRate,
                                  muted: settings.muted, volume: settings.volume)
        }
    }

    // MARK: - 定时器

    private func scheduleTimers() {
        schedulePlaylistTimer()
        scheduleSlotTimer()
    }

    private func schedulePlaylistTimer() {
        playlistTimer?.invalidate()
        let settings = settingsStore.settings
        guard settings.playlist.mode == .interval, !settings.playlist.order.isEmpty,
              settings.playlist.intervalSeconds >= 10 else { return }
        playlistTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.playlist.intervalSeconds),
                                             repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
                self?.schedulePlaylistTimer()
            }
        }
    }

    /// 动态壁纸：到下一个时段边界重呈现；播放列表：按间隔轮换。
    private func scheduleSlotTimer() {
        slotTimer?.invalidate()
        guard case .dynamicWallpaper(let id)? = currentWallpaper,
              let dynamic = library.dynamicWallpaper(withID: id),
              let next = PlaylistScheduler.nextTransition(after: Date(), slots: dynamic.slots) else { return }
        let interval = max(1, next.timeIntervalSince(Date()))
        slotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.presentCurrentWallpaper(animated: true)
                self?.scheduleSlotTimer()
            }
        }
    }
}
