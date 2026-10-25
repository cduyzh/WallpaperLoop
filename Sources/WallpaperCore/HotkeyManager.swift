import Carbon.HIToolbox
import Foundation

/// 全局快捷键：Carbon RegisterEventHotKey，不依赖辅助功能权限。
/// 必须在主线程创建与销毁。
public final class HotkeyManager: @unchecked Sendable {
    public struct Combo: Equatable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private var combo: Combo?

    public init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit { unregister() }

    /// 注册快捷键；combo 传 nil 表示先解除注册。
    public func register(combo: HotkeyCombo?) {
        unregister()
        guard let combo else { return }
        let carbonModifiers = Self.carbonModifiers(from: combo)
        guard carbonModifiers != 0 else { return }
        self.combo = Combo(keyCode: combo.keyCode, modifiers: carbonModifiers)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x43575A48) /* CWZH */, id: 1)
        guard RegisterEventHotKey(combo.keyCode, carbonModifiers, hotKeyID,
                                  GetApplicationEventTarget(), 0, &ref) == noErr, let ref else { return }
        hotKeyRef = ref
        installHandlerIfNeeded()
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        combo = nil
    }

    public static func carbonModifiers(from combo: HotkeyCombo) -> UInt32 {
        var value: UInt32 = 0
        if combo.commandKey { value |= UInt32(cmdKey) }
        if combo.optionKey { value |= UInt32(optionKey) }
        if combo.controlKey { value |= UInt32(controlKey) }
        if combo.shiftKey { value |= UInt32(shiftKey) }
        return value
    }

    /// 常用键码的可读名称（与系统键盘布局无关的虚拟键）。
    public static func readableLabel(for combo: HotkeyCombo) -> String {
        var parts: [String] = []
        if combo.controlKey { parts.append("⌃") }
        if combo.optionKey { parts.append("⌥") }
        if combo.shiftKey { parts.append("⇧") }
        if combo.commandKey { parts.append("⌘") }
        parts.append(keyName(for: combo.keyCode))
        return parts.joined()
    }

    public static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 35: return "P"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        default: return "键码 \(keyCode)"
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr else {
                return noErr
            }
            // 只响应自己注册的快捷键。
            if hotKeyID.id == 1, hotKeyID.signature == OSType(0x43575A48) {
                DispatchQueue.main.async { manager.handler() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, opaque, &handlerRef)
    }
}
