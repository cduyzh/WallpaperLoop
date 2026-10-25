import Foundation

/// macOS 系统内置的动态壁纸视频（/System/Library/Desktop Pictures 下的 .mov）。
public struct SystemWallpaperAsset: Identifiable, Equatable, Sendable {
    public let name: String
    public let url: URL
    public let sizeBytes: Int64

    public var id: String { url.path }
}

/// 扫描系统内置壁纸视频目录。目录结构随 macOS 版本变化，因此做两层递归。
public enum SystemWallpaperAssets {
    /// 默认根目录：系统壁纸包（隐藏目录，含各版本内置的 .mov 动态壁纸）。
    public static let defaultRoot: URL = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers")

    public static func scan(root: URL = SystemWallpaperAssets.defaultRoot) -> [SystemWallpaperAsset] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        var assets: [SystemWallpaperAsset] = []
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                options: [.skipsPackageDescendants])
        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.pathExtension.lowercased() == "mov" else { continue }
            let name = candidate.deletingPathExtension().lastPathComponent
            // 缩略图与预览素材不是壁纸本体。
            guard !name.lowercased().contains("thumbnail") else { continue }
            guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size > 0 else { continue }
            assets.append(SystemWallpaperAsset(name: name, url: candidate, sizeBytes: Int64(size)))
        }
        return assets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
