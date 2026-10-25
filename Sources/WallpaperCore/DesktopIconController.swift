import Foundation

/// 桌面图标显示控制：读写 com.apple.finder 的 CreateDesktop 并重启 Finder 生效。
/// 通过 /usr/bin/defaults 与 /usr/bin/killall 明确执行系统级修改，可完整恢复。
public enum DesktopIconController {
    public enum IconState: Equatable, Sendable {
        case shown
        case hidden
    }

    /// 读取当前 Finder 的 CreateDesktop 值；键不存在视为显示（系统默认）。
    public static func currentState() -> IconState {
        let result = Process.run("/usr/bin/defaults", arguments: ["read", "com.apple.finder", "CreateDesktop"])
        guard result.terminationStatus == 0 else { return .shown }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "0" || value == "false" ? .hidden : .shown
    }

    /// 设置状态并重启 Finder；返回是否成功。
    @discardableResult
    public static func setState(_ state: IconState) -> Bool {
        let value = state == .hidden ? "false" : "true"
        let write = Process.run("/usr/bin/defaults", arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", value])
        guard write.terminationStatus == 0 else { return false }
        // killall Finder 找不到进程时返回非零，属正常情况（Finder 未运行）。
        _ = Process.run("/usr/bin/killall", arguments: ["Finder"])
        return true
    }
}

extension Process {
    /// 同步执行并返回终止状态与标准输出。
    @discardableResult
    static func run(_ executablePath: String, arguments: [String]) -> (terminationStatus: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
