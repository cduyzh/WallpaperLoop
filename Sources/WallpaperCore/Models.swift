import Foundation

/// 壁纸媒体的类型。
public enum WallpaperKind: String, Codable, Sendable {
    case video
    case image

    public init(fileExtension: String) {
        let ext = fileExtension.lowercased()
        switch ext {
        case "mov", "mp4", "m4v":
            self = .video
        default:
            self = .image
        }
    }
}

/// 媒体入库方式：copy 复制进库目录；reference 引用原路径播放（不占用库空间）。
public enum WallpaperStorage: String, Codable, Sendable {
    case copy
    case reference
}

/// 媒体来源，用于资源管理展示。
public enum WallpaperOrigin: String, Codable, Sendable {
    case imported
    case system
    case downloaded
}

/// 壁纸库中的一个媒体文件（视频或图片）。
public struct WallpaperMedia: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var fileName: String
    public var kind: WallpaperKind
    public var addedAt: Date
    public var durationSeconds: Double?
    public var pixelSize: CGSizeValue?
    /// nil 视为 copy，兼容 0.1.0 的旧索引。
    public var storage: WallpaperStorage?
    public var origin: WallpaperOrigin?
    /// reference 模式下播放的原文件绝对路径。
    public var sourcePath: String?
    /// 入库时的文件字节数；copy 为副本大小，reference 为被引用文件大小。
    public var fileSizeBytes: Int64?

    public init(id: UUID = UUID(), title: String, fileName: String, kind: WallpaperKind,
                addedAt: Date = Date(), durationSeconds: Double? = nil, pixelSize: CGSizeValue? = nil,
                storage: WallpaperStorage = .copy, origin: WallpaperOrigin = .imported,
                sourcePath: String? = nil, fileSizeBytes: Int64? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.kind = kind
        self.addedAt = addedAt
        self.durationSeconds = durationSeconds
        self.pixelSize = pixelSize
        self.storage = storage
        self.origin = origin
        self.sourcePath = sourcePath
        self.fileSizeBytes = fileSizeBytes
    }

    public var isReference: Bool { storage == .reference }
}

/// Codable 友好的 CGSize。
public struct CGSizeValue: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// 动态壁纸的一个时段：从 startMinute（本地时间 0–1439）起使用指定媒体。
public struct DynamicSlot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startMinute: Int
    public var mediaID: UUID

    public init(id: UUID = UUID(), startMinute: Int, mediaID: UUID) {
        self.id = id
        self.startMinute = startMinute
        self.mediaID = mediaID
    }
}

/// 按本地时间切换的动态壁纸。
public struct DynamicWallpaper: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// 必须按 startMinute 升序且不重复；可跨零点回绕。
    public var slots: [DynamicSlot]
    public var addedAt: Date

    public init(id: UUID = UUID(), title: String, slots: [DynamicSlot], addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.slots = slots
        self.addedAt = addedAt
    }
}

/// 壁纸条目的统一引用：媒体或动态壁纸。
public enum WallpaperReference: Codable, Equatable, Hashable, Sendable {
    case media(UUID)
    case dynamicWallpaper(UUID)

    public var id: UUID {
        switch self {
        case .media(let id), .dynamicWallpaper(let id): return id
        }
    }
}

/// 播放列表自动轮换方式。
public enum AutoChangeMode: String, Codable, Sendable {
    case off
    case interval
}

public struct PlaylistSettings: Codable, Equatable, Sendable {
    public var mode: AutoChangeMode
    public var intervalSeconds: Int
    public var order: [WallpaperReference]
    public var shuffle: Bool

    public init(mode: AutoChangeMode = .off, intervalSeconds: Int = 900,
                order: [WallpaperReference] = [], shuffle: Bool = false) {
        self.mode = mode
        self.intervalSeconds = intervalSeconds
        self.order = order
        self.shuffle = shuffle
    }
}

/// 全局快捷键组合。
public struct HotkeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var optionKey: Bool
    public var commandKey: Bool
    public var controlKey: Bool
    public var shiftKey: Bool

    public init(keyCode: UInt32, optionKey: Bool = true, commandKey: Bool = true,
                controlKey: Bool = false, shiftKey: Bool = false) {
        self.keyCode = keyCode
        self.optionKey = optionKey
        self.commandKey = commandKey
        self.controlKey = controlKey
        self.shiftKey = shiftKey
    }

    /// 默认 ⌥⌘P（切换播放/暂停）。
    public static let defaultToggle = HotkeyCombo(keyCode: 35)
}

/// 单块显示器的壁纸配置。
public struct DisplayConfig: Codable, Equatable, Identifiable, Sendable {
    public var displayID: UInt32
    public var enabled: Bool
    /// nil 表示跟随主显示器使用当前壁纸。
    public var wallpaper: WallpaperReference?

    public var id: UInt32 { displayID }

    public init(displayID: UInt32, enabled: Bool = true, wallpaper: WallpaperReference? = nil) {
        self.displayID = displayID
        self.enabled = enabled
        self.wallpaper = wallpaper
    }
}

/// 应用设置。持久化到 UserDefaults（标准域，键前缀 wallpaper.）。
public struct AppSettings: Codable, Equatable, Sendable {
    public var muted: Bool
    public var volume: Double
    public var playbackRate: Double
    public var pauseWhenFullscreen: Bool
    public var pauseOnBattery: Bool
    /// 0 表示不启用闲置暂停。
    public var idlePauseMinutes: Int
    public var pauseWhenDisplaySleep: Bool
    public var crossfade: Bool
    public var hideDesktopIcons: Bool
    public var launchAtLogin: Bool
    public var hotkeyEnabled: Bool
    public var hotkey: HotkeyCombo
    public var playlist: PlaylistSettings
    /// 主壁纸（未按显示器指定时使用）。
    public var currentWallpaper: WallpaperReference?
    public var displays: [DisplayConfig]

    public init() {
        muted = true
        volume = 0.5
        playbackRate = 1.0
        pauseWhenFullscreen = true
        pauseOnBattery = false
        idlePauseMinutes = 0
        pauseWhenDisplaySleep = true
        crossfade = true
        hideDesktopIcons = false
        launchAtLogin = false
        hotkeyEnabled = true
        hotkey = .defaultToggle
        playlist = PlaylistSettings()
        currentWallpaper = nil
        displays = []
    }
}

/// 引发自动暂停的原因。
public enum PauseReason: String, Codable, CaseIterable, Sendable {
    case fullscreen
    case battery
    case idle
    case displaySleep
}
