import Foundation

/// 壁纸库：媒体文件与动态壁纸的索引，落盘为应用支持目录中的 library.json。
/// 媒体文件复制进库目录，删除条目时同步删除文件。
public final class WallpaperLibrary: @unchecked Sendable {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var media: [WallpaperMedia]
        public var dynamicWallpapers: [DynamicWallpaper]
        public var version: Int

        public init(media: [WallpaperMedia] = [], dynamicWallpapers: [DynamicWallpaper] = [], version: Int = 1) {
            self.media = media
            self.dynamicWallpapers = dynamicWallpapers
            self.version = version
        }
    }

    public enum LibraryError: LocalizedError {
        case duplicateID
        case mediaNotFound(UUID)
        case fileCopyFailed(String)
        case invalidSlotMedia
        case referenceSourceMissing(String)

        public var errorDescription: String? {
            switch self {
            case .duplicateID: return "壁纸库中存在重复条目"
            case .mediaNotFound(let id): return "壁纸库中找不到媒体 \(id)"
            case .fileCopyFailed(let name): return "复制媒体文件失败：\(name)"
            case .invalidSlotMedia: return "动态壁纸时段引用了不存在的媒体"
            case .referenceSourceMissing(let name): return "引用的源文件不存在：\(name)"
            }
        }
    }

    /// 媒体解析结果：播放用 URL 与所在位置。
    public enum MediaLocation: Equatable, Sendable {
        /// 库目录中的副本。
        case libraryFile
        /// 库外引用的原文件（如系统内置壁纸）。
        case externalReference(URL)
    }

    public let libraryDirectory: URL
    private let queue = DispatchQueue(label: "com.cduyzh.dynamic-wallpaper.library")
    private var snapshot: Snapshot
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    public init(directory: URL) {
        libraryDirectory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        snapshot = Snapshot()
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL()),
           let loaded = try? decoder.decode(Snapshot.self, from: data) {
            snapshot = Self.validated(loaded)
        }
    }

    /// 便捷入口：Application Support/cduyzhDynamicWallpapaer/Library。
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("cduyzhDynamicWallpapaer/Library", isDirectory: true)
    }

    public func url(for media: WallpaperMedia) -> URL {
        if media.isReference, let path = media.sourcePath {
            return URL(fileURLWithPath: path)
        }
        return libraryDirectory.appendingPathComponent(media.fileName)
    }

    /// 媒体文件当前位置；reference 源文件被移动或删除时返回 nil。
    public func location(for media: WallpaperMedia) -> MediaLocation? {
        if media.isReference, let path = media.sourcePath {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? .externalReference(url) : nil
        }
        let url = libraryDirectory.appendingPathComponent(media.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? .libraryFile : nil
    }

    /// 媒体文件字节数；文件缺失时回退到入库时记录的大小。
    public func fileSizeBytes(for media: WallpaperMedia) -> Int64? {
        if let size = media.fileSizeBytes { return size }
        let url: URL
        if media.isReference, let path = media.sourcePath {
            url = URL(fileURLWithPath: path)
        } else {
            url = libraryDirectory.appendingPathComponent(media.fileName)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64
    }

    public func media(withID id: UUID) -> WallpaperMedia? {
        queue.sync { snapshot.media.first { $0.id == id } }
    }

    public func dynamicWallpaper(withID id: UUID) -> DynamicWallpaper? {
        queue.sync { snapshot.dynamicWallpapers.first { $0.id == id } }
    }

    public func currentSnapshot() -> Snapshot {
        queue.sync { snapshot }
    }

    /// 导入一个媒体文件。mode 为 copy 时复制进库目录；reference 时只记录原路径，不复制任何字节。
    @discardableResult
    public func importMedia(at sourceURL: URL, kind: WallpaperKind,
                            durationSeconds: Double? = nil, pixelSize: CGSizeValue? = nil,
                            storage: WallpaperStorage = .copy, origin: WallpaperOrigin = .imported) throws -> WallpaperMedia {
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = fileAttributes?[.size] as? Int64
        let item: WallpaperMedia
        switch storage {
        case .copy:
            let ext = sourceURL.pathExtension.isEmpty ? (kind == .video ? "mp4" : "png") : sourceURL.pathExtension
            item = WallpaperMedia(
                title: sourceURL.deletingPathExtension().lastPathComponent,
                fileName: "\(UUID().uuidString).\(ext)",
                kind: kind,
                durationSeconds: durationSeconds,
                pixelSize: pixelSize,
                storage: .copy,
                origin: origin,
                fileSizeBytes: fileSize
            )
            let destination = url(for: item)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                throw LibraryError.fileCopyFailed(sourceURL.lastPathComponent)
            }
        case .reference:
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw LibraryError.referenceSourceMissing(sourceURL.lastPathComponent)
            }
            item = WallpaperMedia(
                title: sourceURL.deletingPathExtension().lastPathComponent,
                fileName: sourceURL.lastPathComponent,
                kind: kind,
                durationSeconds: durationSeconds,
                pixelSize: pixelSize,
                storage: .reference,
                origin: origin,
                sourcePath: sourceURL.path,
                fileSizeBytes: fileSize
            )
        }
        var pending: Snapshot?
        queue.sync {
            var next = snapshot
            next.media.append(item)
            pending = next
        }
        if let next = pending { try commit(next) }
        return item
    }

    @discardableResult
    public func addDynamicWallpaper(_ wallpaper: DynamicWallpaper) throws -> DynamicWallpaper {
        for slot in wallpaper.slots where media(withID: slot.mediaID) == nil {
            throw LibraryError.invalidSlotMedia
        }
        var pending: Snapshot?
        queue.sync {
            var next = snapshot
            next.dynamicWallpapers.removeAll { $0.id == wallpaper.id }
            next.dynamicWallpapers.append(wallpaper)
            pending = next
        }
        if let next = pending { try commit(next) }
        return wallpaper
    }

    public func remove(reference: WallpaperReference) throws {
        var pending: Snapshot?
        queue.sync {
            var next = snapshot
            switch reference {
            case .media(let id):
                guard let index = next.media.firstIndex(where: { $0.id == id }) else { return }
                let item = next.media.remove(at: index)
                // 同步清理引用该媒体的动态壁纸时段，空时段的动态壁纸一并移除。
                var kept: [DynamicWallpaper] = []
                for var wallpaper in next.dynamicWallpapers {
                    wallpaper.slots.removeAll { $0.mediaID == id }
                    if !wallpaper.slots.isEmpty { kept.append(wallpaper) }
                }
                next.dynamicWallpapers = kept
                pending = next
                // 出队后再删文件，保证索引与磁盘一致；引用条目只删索引，绝不触碰源文件。
                if !item.isReference {
                    try? FileManager.default.removeItem(at: libraryDirectory.appendingPathComponent(item.fileName))
                }
            case .dynamicWallpaper(let id):
                next.dynamicWallpapers.removeAll { $0.id == id }
                pending = next
            }
        }
        if let next = pending { try commit(next) }
    }

    public func rename(reference: WallpaperReference, title: String) throws {
        var pending: Snapshot?
        queue.sync {
            var next = snapshot
            switch reference {
            case .media(let id):
                guard let index = next.media.firstIndex(where: { $0.id == id }) else { return }
                next.media[index].title = title
            case .dynamicWallpaper(let id):
                guard let index = next.dynamicWallpapers.firstIndex(where: { $0.id == id }) else { return }
                next.dynamicWallpapers[index].title = title
            }
            pending = next
        }
        if let next = pending { try commit(next) }
    }

    private func commit(_ next: Snapshot) throws {
        let data = try encoder.encode(next)
        try data.write(to: indexURL(), options: .atomic)
        queue.sync { snapshot = next }
    }

    private func indexURL() -> URL {
        libraryDirectory.appendingPathComponent("library.json")
    }

    /// 落盘数据兜底校验：去除重复 ID 与引用缺失的时段。
    private static func validated(_ raw: Snapshot) -> Snapshot {
        var media: [WallpaperMedia] = []
        var seen = Set<UUID>()
        for item in raw.media where !seen.contains(item.id) {
            seen.insert(item.id)
            media.append(item)
        }
        let dynamicWallpapers = raw.dynamicWallpapers.compactMap { wallpaper -> DynamicWallpaper? in
            let slots = wallpaper.slots.filter { seen.contains($0.mediaID) }
            guard !slots.isEmpty else { return nil }
            var sorted = slots.sorted { $0.startMinute < $1.startMinute }
            // 去除同分钟重复，仅保留第一条。
            var unique: [DynamicSlot] = []
            for slot in sorted where unique.last?.startMinute != slot.startMinute {
                unique.append(slot)
            }
            sorted = unique
            return DynamicWallpaper(id: wallpaper.id, title: wallpaper.title, slots: sorted, addedAt: wallpaper.addedAt)
        }
        return Snapshot(media: media, dynamicWallpapers: dynamicWallpapers, version: raw.version)
    }
}
