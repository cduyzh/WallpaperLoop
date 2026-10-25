import AppKit
import AVFoundation
import CoreGraphics
import Foundation

/// 媒体检查：视频时长、像素尺寸与缩略图。
public enum MediaInspection {
    /// 读取视频时长与自然尺寸；同步等待有限时间。
    public static func inspectVideo(url: URL, timeout: TimeInterval = 5) async -> (duration: Double, size: CGSizeValue)? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            var size = CGSizeValue(width: 0, height: 0)
            if let track = tracks.first {
                let natural = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                let transformed = CGSize(width: abs(natural.width * preferredTransform.a + natural.height * preferredTransform.c),
                                         height: abs(natural.width * preferredTransform.b + natural.height * preferredTransform.d))
                size = CGSizeValue(width: transformed.width, height: transformed.height)
            }
            return (CMTimeGetSeconds(duration), size)
        } catch {
            return nil
        }
    }

    /// 图片像素尺寸。
    public static func imageSize(url: URL) -> CGSizeValue? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Double,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Double else {
            return nil
        }
        return CGSizeValue(width: width, height: height)
    }

    /// 生成缩略图并写为 JPEG；视频取首帧，图片按比例缩放。
    public static func writeThumbnail(source: URL, kind: WallpaperKind, destination: URL,
                                      maxPixel: CGFloat = 480) throws {
        let image: NSImage
        switch kind {
        case .video:
            let asset = AVURLAsset(url: source)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            let time = CMTimeMake(value: 1, timescale: 10)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            image = NSImage(cgImage: cgImage, size: .zero)
        case .image:
            guard let data = try? Data(contentsOf: source),
                  let loaded = NSImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            image = loaded
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try jpeg.write(to: destination, options: .atomic)
    }
}
