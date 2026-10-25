import Foundation

/// 设置存储：UserDefaults（标准域）持久化 AppSettings，变更时发出通知。
public final class SettingsStore: @unchecked Sendable, ObservableObject {
    private static let storageKey = "wallpaper.settings"
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.cduyzh.dynamic-wallpaper.settings")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published public private(set) var settings: AppSettings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let loaded = try? decoder.decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings()
        }
    }

    public func update(_ transform: (inout AppSettings) -> Void) {
        var next = settings
        transform(&next)
        let data: Data?
        do { data = try encoder.encode(next) } catch { data = nil }
        if let data {
            // 先写盘再广播，读回的一定是已持久化的值。
            defaults.set(data, forKey: Self.storageKey)
        }
        queue.sync { settings = next }
        objectWillChange.send()
    }

    /// 兼容旧版本的清理：移除指向已删除媒体的当前壁纸引用。
    public func pruneReferences(validMedia: Set<UUID>, validDynamic: Set<UUID>) {
        update { current in
            current.playlist.order.removeAll { reference in
                switch reference {
                case .media(let id): return !validMedia.contains(id)
                case .dynamicWallpaper(let id): return !validDynamic.contains(id)
                }
            }
            if let wallpaper = current.currentWallpaper {
                let valid: Bool
                switch wallpaper {
                case .media(let id): valid = validMedia.contains(id)
                case .dynamicWallpaper(let id): valid = validDynamic.contains(id)
                }
                if !valid { current.currentWallpaper = nil }
            }
            for index in current.displays.indices {
                if let wallpaper = current.displays[index].wallpaper {
                    let valid: Bool
                    switch wallpaper {
                    case .media(let id): valid = validMedia.contains(id)
                    case .dynamicWallpaper(let id): valid = validDynamic.contains(id)
                    }
                    if !valid { current.displays[index].wallpaper = nil }
                }
            }
        }
    }
}
