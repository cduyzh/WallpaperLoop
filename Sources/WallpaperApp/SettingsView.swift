import AppKit
import SwiftUI
import WallpaperCore

/// 设置：播放、智能暂停、桌面与显示器、启动与快捷键、关于。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                settingsStatusCard
            }

            Section {
                Picker("播放速度", selection: rateBinding) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Text(String(format: "%.2g×", rate)).tag(rate)
                    }
                }
                Toggle("静音", isOn: mutedBinding)
                LabeledContent("音量") {
                    HStack {
                        Slider(value: volumeBinding, in: 0...1)
                        Text(String(format: "%d%%", Int(store.settingsStore.settings.volume * 100)))
                            .monospacedDigit().frame(width: 42)
                    }
                }
                Toggle("切换壁纸时淡入淡出", isOn: crossfadeBinding)
            } header: {
                Text("播放")
            }

            Section {
                Toggle("前台应用全屏时暂停", isOn: fullscreenBinding)
                Toggle("电池供电时暂停", isOn: batteryBinding)
                Toggle("闲置时暂停", isOn: idleEnabledBinding)
                if store.settingsStore.settings.idlePauseMinutes > 0 {
                    Picker("闲置时长", selection: idleMinutesBinding) {
                        ForEach([1, 3, 5, 10, 30], id: \.self) { minutes in
                            Text("\(minutes) 分钟无输入").tag(minutes)
                        }
                    }
                }
                Toggle("屏幕休眠或屏保时暂停", isOn: sleepBinding)
            } header: {
                Text("智能暂停")
            } footer: {
                if let reason = store.engine.activePauseReasons.sorted(by: { $0.rawValue < $1.rawValue }).first {
                    Text("当前已自动暂停：\(reasonText(reason))").foregroundStyle(Palette.accent)
                } else if store.engine.playing {
                    Text("当前正在播放。")
                } else {
                    Text("当前手动暂停中。")
                }
            }

            Section {
                Toggle("隐藏桌面图标", isOn: hideIconsBinding)
                ForEach(currentDisplays(), id: \.displayID) { config in
                    displayRow(config)
                }
            } header: {
                Text("桌面与显示器")
            } footer: {
                Text("隐藏桌面图标会写入 Finder 的 CreateDesktop 设置并重启 Finder，关闭开关即可恢复。")
            }

            Section {
                Toggle("开机启动", isOn: loginBinding)
                Toggle("全局快捷键（切换播放/暂停）", isOn: hotkeyEnabledBinding)
                if store.settingsStore.settings.hotkeyEnabled {
                    Text("快捷键：\(HotkeyManager.readableLabel(for: store.settingsStore.settings.hotkey))")
                        .foregroundStyle(Palette.subtleText)
                }
            } header: {
                Text("启动与快捷键")
            }

            Section {
                AboutView()
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBackground)
        .listRowBackground(Palette.cardBackground)
        .navigationTitle("设置")
        .navigationSubtitle("播放、暂停策略与桌面行为")
    }

    private var settingsStatusCard: some View {
        let reason = store.engine.activePauseReasons.sorted { $0.rawValue < $1.rawValue }.first
        return HStack(spacing: 12) {
            Image(systemName: store.engine.playing ? "play.circle.fill" : "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(store.engine.playing ? Palette.success : Palette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.engine.playing ? "壁纸正在播放" : "壁纸已暂停")
                    .font(.callout.weight(.semibold))
                Text(reason.map { "自动暂停：\(reasonText($0))" } ?? "当前设置会在需要时自动保护性能")
                    .font(.caption)
                    .foregroundStyle(Palette.subtleText)
            }
            Spacer()
            Text(store.engine.playing ? "LIVE" : "PAUSED")
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(store.engine.playing ? Palette.success : Palette.warning)
        }
        .padding(12)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    private func displayRow(_ config: DisplayConfig) -> some View {
        let reference = Binding<WallpaperReference?> {
            store.settingsStore.settings.displays.first { $0.displayID == config.displayID }?.wallpaper
        } set: { value in
            store.settingsStore.update { settings in
                if let index = settings.displays.firstIndex(where: { $0.displayID == config.displayID }) {
                    settings.displays[index].wallpaper = value
                }
            }
        }
        return HStack {
            Toggle(displayName(config.displayID), isOn: enableBinding(config.displayID))
            Spacer()
            Picker("", selection: reference) {
                Text("跟随当前壁纸").tag(WallpaperReference?.none)
                ForEach(allReferences(), id: \.self) { item in
                    Text(store.title(for: item)).tag(WallpaperReference?.some(item))
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .disabled(!store.settingsStore.settings.displays.first { $0.displayID == config.displayID }!.enabled)
        }
    }

    /// 当前连接的屏幕合成设置条目；断开的显示器保留配置不再显示。
    private func currentDisplays() -> [DisplayConfig] {
        let connected = NSScreen.screens.compactMap { WallpaperEngine.displayID(of: $0) }
        var result: [DisplayConfig] = []
        for id in connected {
            if let existing = store.settingsStore.settings.displays.first(where: { $0.displayID == id }) {
                result.append(existing)
            } else {
                result.append(DisplayConfig(displayID: id, enabled: true, wallpaper: nil))
            }
        }
        // 同步一次设置，保证引擎读到的配置覆盖所有已连接屏幕。
        if result != store.settingsStore.settings.displays.filter({ connected.contains($0.displayID) }) {
            let snapshot = result
            store.settingsStore.update { settings in
                settings.displays = snapshot + settings.displays.filter { !connected.contains($0.displayID) }
            }
        }
        return result
    }

    private func displayName(_ id: CGDirectDisplayID) -> String {
        let name: String
        if let screen = NSScreen.screens.first(where: { WallpaperEngine.displayID(of: $0) == id }) {
            name = screen.localizedName
        } else {
            name = "显示器"
        }
        return NSScreen.screens.count > 1 ? name : "\(name)（主屏幕）"
    }

    private func allReferences() -> [WallpaperReference] {
        store.snapshot.media.map { .media($0.id) } + store.snapshot.dynamicWallpapers.map { .dynamicWallpaper($0.id) }
    }

    private func reasonText(_ reason: PauseReason) -> String {
        switch reason {
        case .fullscreen: return "前台应用全屏"
        case .battery: return "电池供电"
        case .idle: return "闲置"
        case .displaySleep: return "屏幕休眠或屏保"
        }
    }

    // MARK: - Bindings

    private var rateBinding: Binding<Double> {
        Binding { store.settingsStore.settings.playbackRate } set: { value in store.settingsStore.update { $0.playbackRate = value } }
    }
    private var mutedBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.muted } set: { value in store.settingsStore.update { $0.muted = value } }
    }
    private var volumeBinding: Binding<Double> {
        Binding { store.settingsStore.settings.volume } set: { value in store.settingsStore.update { $0.volume = value } }
    }
    private var crossfadeBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.crossfade } set: { value in store.settingsStore.update { $0.crossfade = value } }
    }
    private var fullscreenBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.pauseWhenFullscreen } set: { value in store.settingsStore.update { $0.pauseWhenFullscreen = value } }
    }
    private var batteryBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.pauseOnBattery } set: { value in store.settingsStore.update { $0.pauseOnBattery = value } }
    }
    private var idleEnabledBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.idlePauseMinutes > 0 } set: { value in
            store.settingsStore.update { $0.idlePauseMinutes = value ? 5 : 0 }
        }
    }
    private var idleMinutesBinding: Binding<Int> {
        Binding { store.settingsStore.settings.idlePauseMinutes } set: { value in store.settingsStore.update { $0.idlePauseMinutes = value } }
    }
    private var sleepBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.pauseWhenDisplaySleep } set: { value in store.settingsStore.update { $0.pauseWhenDisplaySleep = value } }
    }
    private var hideIconsBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.hideDesktopIcons } set: { value in store.setHideDesktopIcons(value) }
    }
    private var loginBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.launchAtLogin } set: { value in store.setLaunchAtLogin(value) }
    }
    private var hotkeyEnabledBinding: Binding<Bool> {
        Binding { store.settingsStore.settings.hotkeyEnabled } set: { value in
            store.settingsStore.update { $0.hotkeyEnabled = value }
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }

    private func enableBinding(_ displayID: UInt32) -> Binding<Bool> {
        Binding {
            store.settingsStore.settings.displays.first { $0.displayID == displayID }?.enabled ?? true
        } set: { value in
            store.settingsStore.update { settings in
                if let index = settings.displays.firstIndex(where: { $0.displayID == displayID }) {
                    settings.displays[index].enabled = value
                } else {
                    settings.displays.append(DisplayConfig(displayID: displayID, enabled: value))
                }
            }
        }
    }
}

extension Notification.Name {
    static let hotkeySettingsChanged = Notification.Name("cduyzhWallpaper.hotkeySettingsChanged")
}
