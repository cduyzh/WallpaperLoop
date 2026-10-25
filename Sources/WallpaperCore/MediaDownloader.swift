import Foundation

/// 在线视频下载：落到临时文件，由调用方再走正常导入流程复制进库。
public enum MediaDownloader {
    public enum DownloadError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "下载地址没有返回有效响应"
            case .httpStatus(let code): return "下载失败（HTTP \(code)）"
            }
        }
    }

    /// 校验 URL 形态（http/https 且带路径）。
    public static func sanitizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              !url.path.isEmpty else { return nil }
        return url
    }

    /// 下载到临时目录并返回文件 URL。
    @discardableResult
    public static func download(from url: URL) async throws -> URL {
        let (location, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadError.httpStatus(httpResponse.statusCode)
        }
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cduyzh-download-\(UUID().uuidString).\(ext)")
        // URLSession.download 的临时文件默认会被清理，移动后归调用方管理。
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }
}
