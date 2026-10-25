import AVFoundation
import AppKit
import CoreGraphics
import WallpaperCore


/// 一块屏幕上的壁纸窗口：无边框、位于桌面层级（图标之下、系统壁纸之上）、
/// 加入所有空间、不参与鼠标交互。内容为视频播放层或图片层，支持双层淡入淡出。
@MainActor
final class WallpaperSurface: NSObject, NSWindowDelegate {
    struct Media: Equatable {
        let url: URL
        let kind: WallpaperKind
        let startAt: Double
    }

    let displayID: CGDirectDisplayID
    private(set) var screenFrame: CGRect
    let window: NSWindow
    private let contentView: WallpaperContentView

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.screenFrame = screen.frame
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        // 桌面层级：与系统壁纸同层（CGWindowLevelForKey(.desktopWindow) == -2147483623），
        // 桌面图标层比它高一级，因此窗口自然位于图标之下。
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.title = ""
        window.animationBehavior = .none
        let content = WallpaperContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        self.window = window
        self.contentView = content
        super.init()
        window.delegate = self
        window.orderFrontRegardless()
    }

    func syncFrame(with screen: NSScreen) {
        guard screen.frame != screenFrame else { return }
        screenFrame = screen.frame
        window.setFrame(screen.frame, display: true)
        contentView.setFrameSize(screen.frame.size)
    }

    var currentMedia: Media? { contentView.currentMedia }

    /// 切换媒体；crossfade 为 false 时立即替换（首次显示）。
    func present(_ media: Media, crossfade: Bool, duration: TimeInterval = 0.7) {
        contentView.transition(to: media, crossfade: crossfade, duration: duration)
    }

    func applyPlayback(playing: Bool, rate: Double, muted: Bool, volume: Double) {
        contentView.applyPlayback(playing: playing, rate: rate, muted: muted, volume: volume)
    }

    func stopPlayback() {
        contentView.stopPlayback()
    }
}

/// 层托管内容视图：维护当前媒体层，切换时叠层淡入后移除旧层。
@MainActor
final class WallpaperContentView: NSView {
    private(set) var currentMedia: WallpaperSurface.Media?
    private var activePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var mediaLayer: CALayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("不支持 XIB 初始化") }

    func transition(to media: WallpaperSurface.Media, crossfade: Bool, duration: TimeInterval) {
        guard media != currentMedia else {
            // 同一媒体（例如动态壁纸回到同一时段）只需确保播放状态正确。
            return
        }
        let oldLayer = mediaLayer
        let oldPlayer = activePlayer
        let oldLooper = looper

        let layer = makeLayer(for: media)
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        mediaLayer = layer

        if crossfade, let oldLayer {
            layer.opacity = 0
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setCompletionBlock { [weak oldLayer] in
                oldLayer?.removeFromSuperlayer()
            }
            layer.opacity = 1
            CATransaction.commit()
            cleanup(player: oldPlayer, looper: oldLooper, delay: duration)
        } else {
            oldLayer?.removeFromSuperlayer()
            cleanup(player: oldPlayer, looper: oldLooper, delay: 0)
        }
        currentMedia = media
    }

    private func makeLayer(for media: WallpaperSurface.Media) -> CALayer {
        switch media.kind {
        case .video:
            let item = AVPlayerItem(url: media.url)
            item.preferredForwardBufferDuration = 3
            let player = AVQueuePlayer()
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: item)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            activePlayer = player
            self.looper = looper
            // 播放状态由 applyPlayback 统一下发；先以 0 速率就绪。
            player.rate = 0
            player.seek(to: .init(seconds: media.startAt, preferredTimescale: 600))
            return playerLayer
        case .image:
            if let imageSource = CGImageSourceCreateWithURL(media.url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                let imageLayer = CALayer()
                imageLayer.contents = cgImage
                imageLayer.contentsGravity = .resizeAspectFill
                return imageLayer
            }
            let fallback = CALayer()
            fallback.backgroundColor = NSColor.black.cgColor
            return fallback
        }
    }

    func applyPlayback(playing: Bool, rate: Double, muted: Bool, volume: Double) {
        guard let player = activePlayer else { return }
        player.isMuted = muted
        player.volume = Float(volume)
        if playing {
            player.playImmediately(atRate: Float(rate))
        } else {
            player.pause()
        }
    }

    func stopPlayback() {
        activePlayer?.pause()
    }

    override func layout() {
        super.layout()
        mediaLayer?.frame = bounds
        if let sublayers = layer?.sublayers {
            for sublayer in sublayers { sublayer.frame = bounds }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mediaLayer?.contentsScale = window?.backingScaleFactor ?? 2
        if let sublayers = layer?.sublayers {
            for sublayer in sublayers { sublayer.contentsScale = window?.backingScaleFactor ?? 2 }
        }
    }

    /// 延迟释放旧播放器，保证淡出动画期间画面仍有内容。
    private func cleanup(player: AVQueuePlayer?, looper: AVPlayerLooper?, delay: TimeInterval) {
        guard player != nil || looper != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) { [weak player, weak looper] in
            looper?.disableLooping()
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}
