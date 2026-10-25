import AppKit
import CoreGraphics
import Foundation

/// 系统状态监测：全屏前台应用、用户闲置、屏幕睡眠/唤醒与屏保。
public final class SystemStateMonitor: @unchecked Sendable, ObservableObject {
    /// CGWindowList 抓到的窗口快照（纯数据，便于测试）。
    public struct WindowSnapshot: Equatable, Sendable {
        public var ownerPID: Int
        public var layer: Int
        public var bounds: CGRect
        public var isOnscreen: Bool

        public init(ownerPID: Int, layer: Int, bounds: CGRect, isOnscreen: Bool) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.bounds = bounds
            self.isOnscreen = isOnscreen
        }
    }

    @Published public private(set) var frontmostIsFullscreen: Bool
    @Published public private(set) var idleSeconds: TimeInterval
    @Published public private(set) var displayAsleep: Bool

    /// 检测间隔：闲置与全屏共用低频轮询，事件触发即时刷新。
    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    public init(pollInterval: TimeInterval = 10) {
        frontmostIsFullscreen = false
        idleSeconds = 0
        displayAsleep = false
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refreshFullscreen()
            self?.refreshIdle()
        }
        installObservers()
        refreshIdle()
    }

    deinit {
        pollTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    // MARK: - 全屏检测

    /// 前台应用是否在任一屏幕上有全屏窗口。
    /// 判据：普通层级（0）的在屏窗口完全覆盖某块屏幕（含菜单栏区域）。
    /// 只读取窗口几何与进程信息，不读取窗口内容，无需屏幕录制权限。
    public static func evaluateFullscreen(windows: [WindowSnapshot], frontmostPID: Int?, screens: [CGRect]) -> Bool {
        guard let pid = frontmostPID, !screens.isEmpty else { return false }
        for window in windows where window.ownerPID == pid && window.layer == 0 && window.isOnscreen {
            for screen in screens {
                // 全屏窗口覆盖整块屏幕（含菜单栏高度），允许 1 点误差。
                if window.bounds.minX <= screen.minX + 1, window.bounds.minY <= screen.minY + 1,
                   window.bounds.maxX >= screen.maxX - 1, window.bounds.maxY >= screen.maxY - 1 {
                    return true
                }
            }
        }
        return false
    }

    public func refreshFullscreen() {
        let frontmost = NSWorkspace.shared.frontmostApplication.flatMap { app in Int(exactly: app.processIdentifier) }
        let snapshots = Self.captureWindows()
        let screens = NSScreen.screens.map(\.frame)
        let result = Self.evaluateFullscreen(windows: snapshots, frontmostPID: frontmost, screens: screens)
        if result != frontmostIsFullscreen { frontmostIsFullscreen = result }
    }

    /// CGWindowList 在无屏幕录制权限时依旧返回几何与进程信息（窗口名除外）。
    private static func captureWindows() -> [WindowSnapshot] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else { return nil }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            return WindowSnapshot(ownerPID: pid, layer: layer,
                                  bounds: CGRect(x: x, y: y, width: width, height: height),
                                  isOnscreen: true)
        }
    }

    // MARK: - 闲置检测

    /// 距上次输入事件的秒数（合并会话）。无需辅助功能权限。
    public static func readIdleSeconds() -> TimeInterval {
        // 传入非法事件类型时系统返回所有输入类型的最近值，这是公开认可的用法。
        guard let anyType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    public func refreshIdle() {
        let seconds = Self.readIdleSeconds()
        if abs(seconds - idleSeconds) > 0.5 { idleSeconds = seconds }
    }

    // MARK: - 事件订阅

    private func installObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let main = OperationQueue.main
        for name: Notification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
        ] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: main) { [weak self] _ in
                // 切换瞬间窗口层级可能未稳定，稍作延迟再判定。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refreshFullscreen() }
            })
        }
        for name: Notification.Name in [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: main) { [weak self] notification in
                self?.displayAsleep = notification.name == NSWorkspace.screensDidSleepNotification
            })
        }
        // 屏保启动/停止走分布式通知。
        for name in ["com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            distributedObservers.append(DistributedNotificationCenter.default()
                .addObserver(forName: Notification.Name(name), object: nil, queue: main) { [weak self] notification in
                    let started = notification.name.rawValue == "com.apple.screensaver.didstart"
                    self?.displayAsleep = started
                })
        }
    }
}
