import Foundation
import IOKit.ps

/// 电池供电状态：IOKit 电源源读取 + 电源变化回调 + 低频轮询兜底。
public final class PowerMonitor: @unchecked Sendable, ObservableObject {
    @Published public private(set) var isOnBattery: Bool

    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?

    public init() {
        isOnBattery = Self.readIsOnBattery()
        // IOPS 回调不携带对象上下文，用桥接引用（本进程内全局唯一电源监测）。
        Self.active = self
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { PowerMonitor.active?.refresh() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        pollTimer?.invalidate()
        if Self.active === self { Self.active = nil }
    }

    fileprivate func refresh() {
        let next = Self.readIsOnBattery()
        if next != isOnBattery { isOnBattery = next }
    }

    /// 直接读取当前供电状态；无电池设备（台式机）恒为 false。
    public static func readIsOnBattery() -> Bool {
        // IOPSCopy* 遵循 Create 规则（takeRetainedValue）；
        // IOPSGetPowerSourceDescription 遵循 Get 规则，返回内部字典，必须 takeUnretainedValue。
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String else { continue }
            if state == kIOPSBatteryPowerValue {
                return true
            }
        }
        return false
    }

    private static weak var active: PowerMonitor?
}
