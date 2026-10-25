import Foundation
import ServiceManagement

/// 登录项：macOS 13+ 的 SMAppService 注册本应用。
public enum LoginItem {
    public static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回是否处于期望状态；失败时返回 false 并保留系统错误可查询。
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已注册"
        case .requiresApproval: return "需要用户在系统设置中批准"
        case .notRegistered: return "未注册"
        case .notFound: return "未找到"
        @unknown default: return "未知状态"
        }
    }
}
