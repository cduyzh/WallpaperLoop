import AppKit
import Combine
import Foundation
import SwiftUI
import WallpaperCore

/// 应用状态中枢：壁纸库 + 设置 + 引擎的桥接，供 SwiftUI 使用。
@MainActor
final class AppStore: ObservableObject {
    let library: WallpaperLibrary
    let settingsStore: SettingsStore
    let engine: WallpaperEngine

    @Published private(set) var snapshot = WallpaperLibrary.Snapshot()
    @Published var importError: String?
    @Published var isImporting = false
    /// 引擎状态变化计数，驱动侧栏状态行刷新。
    @Published private(set) var engineRevision = 0
    @Published private(set) var systemAssets: [SystemWallpaperAsset] = []
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadDescription: String?

    var thumbnailsDirectory: URL {
        library.libraryDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    private var cancellables: Set<AnyCancellable> = []

    init(library: WallpaperLibrary = WallpaperLibrary(directory: WallpaperLibrary.defaultDirectory()),
         settingsStore: SettingsStore = SettingsStore()) {
        self.library = library
        self.settingsStore = settingsStore
        self.engine = WallpaperEngine(library: library, settingsStore: settingsStore)
        snapshot = library.currentSnapshot()
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.engineRevision += 1 }
            .store(in: &cancellables)
    }

    func start() {
        engine.start()
        reconcileSettings()
        syncDesktopIconsToSetting()
    }

    func reloadSnapshot() {
        snapshot = library.currentSnapshot()
        reconcileSettings()
    }

    /// 清理设置中指向已删除条目的引用。
    private func reconcileSettings() {
        settingsStore.pruneReferences(validMedia: Set(snapshot.media.map(\.id)),
                                      validDynamic: Set(snapshot.dynamicWallpapers.map(\.id)))
    }

    // MARK: - 导入

    func importMedia(from urls: [URL], storage: WallpaperStorage = .copy,
                     origin: WallpaperOrigin = .imported) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        importError = nil
        defer { isImporting = false }
        for url in urls {
            await importSingleMedia(url: url, storage: storage, origin: origin)
        }
        reloadSnapshot()
    }

    private func importSingleMedia(url: URL, storage: WallpaperStorage, origin: WallpaperOrigin) async {
        let kind = WallpaperKind(fileExtension: url.pathExtension)
        do {
            var duration: Double?
            var pixelSize: CGSizeValue?
            if kind == .video, let info = await MediaInspection.inspectVideo(url: url) {
                duration = info.duration
                pixelSize = info.size
            } else if kind == .image {
                pixelSize = MediaInspection.imageSize(url: url)
            }
            let item = try library.importMedia(at: url, kind: kind,
                                               durationSeconds: duration, pixelSize: pixelSize,
                                               storage: storage, origin: origin)
            writeThumbnail(for: item, kind: kind)
        } catch {
            importError = "导入「\(url.lastPathComponent)」失败：\(error.localizedDescription)"
        }
    }

    private func writeThumbnail(for item: WallpaperMedia, kind: WallpaperKind) {
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? MediaInspection.writeThumbnail(source: library.url(for: item), kind: kind,
                                            destination: thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg"))
    }

    // MARK: - 系统内置壁纸

    func refreshSystemAssets() {
        systemAssets = SystemWallpaperAssets.scan()
    }

    /// 已按引用方式加入库中的系统视频路径。
    var importedSystemAssetPaths: Set<String> {
        Set(snapshot.media.compactMap { $0.isReference ? $0.sourcePath : nil })
    }

    func addSystemAsset(_ asset: SystemWallpaperAsset, storage: WallpaperStorage) async {
        await importMedia(from: [asset.url], storage: storage, origin: .system)
    }

    // MARK: - 在线视频导入

    /// 下载在线视频并复制入库；返回是否成功（失败时已写入 importError）。
    func downloadAndImport(from url: URL) async -> Bool {
        isDownloading = true
        downloadDescription = url.host.map { "正在从 \($0) 下载…" } ?? "正在下载…"
        defer {
            isDownloading = false
            downloadDescription = nil
        }
        do {
            let file = try await MediaDownloader.download(from: url)
            await importMedia(from: [file], storage: .copy, origin: .downloaded)
            try? FileManager.default.removeItem(at: file)
            // 临时文件名不可读，按原始 URL 文件名重命名。
            let originalName = url.deletingPathExtension().lastPathComponent
            if importError == nil, !originalName.isEmpty,
               let imported = snapshot.media.last(where: { $0.origin == .downloaded }) {
                rename(reference: .media(imported.id), title: originalName)
            }
            return importError == nil
        } catch {
            importError = "下载「\(url.absoluteString)」失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 删除与清理

    /// 移除条目：删除索引与库内副本文件，并清理对应缩略图；引用条目绝不触碰源文件。
    func remove(reference: WallpaperReference) {
        var thumbnailName: String?
        if case .media(let id) = reference {
            thumbnailName = "\(id.uuidString).jpg"
        }
        do {
            try library.remove(reference: reference)
        } catch {
            importError = "移除失败：\(error.localizedDescription)"
        }
        if let thumbnailName {
            try? FileManager.default.removeItem(at: thumbnailsDirectory.appendingPathComponent(thumbnailName))
        }
        reloadSnapshot()
    }

    func rename(reference: WallpaperReference, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? library.rename(reference: reference, title: trimmed)
        reloadSnapshot()
    }

    /// 删除指定的一批媒体条目，返回成功数量。
    @discardableResult
    func removeMedia(ids: [UUID]) -> Int {
        var removed = 0
        for id in ids {
            guard snapshot.media.contains(where: { $0.id == id }) else { continue }
            remove(reference: .media(id))
            removed += 1
        }
        return removed
    }

    /// 清理没有对应媒体条目的孤儿缩略图。
    func cleanOrphanThumbnails() -> Int {
        let validIDs = Set(snapshot.media.map { $0.id.uuidString })
        let files = (try? FileManager.default.contentsOfDirectory(at: thumbnailsDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for file in files where file.pathExtension.lowercased() == "jpg" {
            if validIDs.contains(file.deletingPathExtension().lastPathComponent) { continue }
            try? FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    func openLibraryInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: library.libraryDirectory.path)
    }

    // MARK: - 资源统计

    /// 库内副本占用（缩略图除外）。
    var copiedBytesOnDisk: Int64 {
        snapshot.media
            .filter { !$0.isReference }
            .reduce(0) { $0 + (library.fileSizeBytes(for: $1) ?? 0) }
    }

    /// 视频条目（资源管理页主对象）。
    var videoEntries: [WallpaperMedia] {
        snapshot.media.filter { $0.kind == .video }
    }

    var imageEntries: [WallpaperMedia] {
        snapshot.media.filter { $0.kind == .image }
    }

    /// 条目的使用场景；未被使用时可安全删除。
    func usages(of mediaID: UUID) -> [String] {
        var usages: [String] = []
        if settingsStore.settings.currentWallpaper == .media(mediaID) { usages.append("当前壁纸") }
        if settingsStore.settings.playlist.order.contains(.media(mediaID)) { usages.append("播放列表") }
        for dynamic in snapshot.dynamicWallpapers where dynamic.slots.contains(where: { $0.mediaID == mediaID }) {
            usages.append("动态壁纸「\(dynamic.title)」")
        }
        if usedOnDisplay(mediaID: mediaID) { usages.append("显示器独立壁纸") }
        return usages
    }

    /// 每屏指定壁纸是否使用了该媒体。
    func usedOnDisplay(mediaID: UUID) -> Bool {
        settingsStore.settings.displays.contains {
            if case .media(let id)? = $0.wallpaper { return id == mediaID }
            return false
        }
    }

    func isMissing(_ media: WallpaperMedia) -> Bool {
        library.location(for: media) == nil
    }

    // MARK: - 展示辅助

    func thumbnailURL(for media: WallpaperMedia) -> URL? {
        let url = thumbnailsDirectory.appendingPathComponent("\(media.id.uuidString).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func title(for reference: WallpaperReference) -> String {
        switch reference {
        case .media(let id): return snapshot.media.first { $0.id == id }?.title ?? "缺失媒体"
        case .dynamicWallpaper(let id): return snapshot.dynamicWallpapers.first { $0.id == id }?.title ?? "缺失动态壁纸"
        }
    }

    func mediaTitle(id: UUID) -> String {
        snapshot.media.first { $0.id == id }?.title ?? "缺失媒体"
    }

    static func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 条目来源标签。
    func originLabel(for media: WallpaperMedia) -> String {
        let storage = media.isReference ? "引用" : "副本"
        switch media.origin {
        case .system: return "系统内置 · \(storage)"
        case .downloaded: return "在线下载 · \(storage)"
        case .imported, .none: return "本地导入 · \(storage)"
        }
    }

    // MARK: - 桌面图标

    private func syncDesktopIconsToSetting() {
        let expected: DesktopIconController.IconState = settingsStore.settings.hideDesktopIcons ? .hidden : .shown
        guard DesktopIconController.currentState() != expected else { return }
        _ = DesktopIconController.setState(expected)
    }

    func setHideDesktopIcons(_ hidden: Bool) {
        settingsStore.update { $0.hideDesktopIcons = hidden }
        _ = DesktopIconController.setState(hidden ? .hidden : .shown)
    }

    // MARK: - 登录项

    var launchAtLogin: Bool {
        LoginItem.isRegistered
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if LoginItem.setEnabled(enabled) {
            settingsStore.update { $0.launchAtLogin = enabled }
        }
    }
}
