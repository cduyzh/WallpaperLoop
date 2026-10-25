import AppKit
import SwiftUI
import WallpaperCore

enum Palette {
    static let accent = Color(red: 0.30, green: 0.42, blue: 0.95)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .underPageBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardRaised = Color(nsColor: .textBackgroundColor)
    static let border = Color.primary.opacity(0.10)
    static let accentSoft = accent.opacity(0.12)
    static let success = Color.green
    static let warning = Color.orange
    static let subtleText = Color.secondary
}

/// 主窗口：侧栏（资料库 / 管理）+ 详情页。
struct ContentView: View {
    enum Page: String, Hashable {
        case library = "壁纸库"
        case playlist = "播放列表"
        case resources = "资源管理"
        case settings = "设置"
    }

    @EnvironmentObject private var store: AppStore
    @State private var page: Page = .library

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarBrand
                List(selection: $page) {
                    Section("资料库") {
                        Label("壁纸库", systemImage: "photo.on.rectangle.angled").tag(Page.library)
                        Label("播放列表", systemImage: "list.bullet.rectangle").tag(Page.playlist)
                    }
                    Section("管理") {
                        Label("资源管理", systemImage: "archivebox").tag(Page.resources)
                        Label("设置", systemImage: "gearshape").tag(Page.settings)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }
            .background(Palette.panelBackground)
            .navigationSplitViewColumnWidth(min: 218, ideal: 238)
            .safeAreaInset(edge: .bottom) { nowPlayingCard }
        } detail: {
            Group {
                switch page {
                case .library: LibraryView()
                case .playlist: PlaylistView()
                case .resources: ResourceManagerView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.pageBackground)
        }
        .navigationTitle("WallpaperLoop")
        .tint(Palette.accent)
        .onReceive(NotificationCenter.default.publisher(for: .navigateSettings)) { _ in
            page = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateLibrary)) { _ in
            page = .library
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateResources)) { _ in
            page = .resources
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 30, height: 30)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("WallpaperLoop")
                    .font(.headline)
                Text("桌面场景管理")
                    .font(.caption)
                    .foregroundStyle(Palette.subtleText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// 引擎实时状态（engineRevision 驱动刷新），同时提供最常用的播放控制。
    private var nowPlayingCard: some View {
        let _ = store.engineRevision
        let reference = store.engine.currentWallpaper
        let title = reference.map { store.title(for: $0) } ?? "还没有选择壁纸"
        let detail = reference == nil ? "从壁纸库选择一个场景开始" : statusText

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("当前壁纸")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.subtleText)
                    .textCase(.uppercase)
                Spacer()
                if reference != nil {
                    Text(store.engine.playing ? "LIVE" : "PAUSED")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(statusColor)
                }
            }
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.subtleText)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    store.engine.togglePause()
                } label: {
                    Label(store.engine.playing ? "暂停" : "播放",
                          systemImage: store.engine.playing ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(reference == nil)

                Button {
                    store.engine.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("下一个壁纸")
                .disabled(reference == nil)
            }
        }
        .padding(14)
        .modifier(WallpaperGlassSurface(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        if !store.engine.activePauseReasons.isEmpty { return .orange }
        return store.engine.playing ? .green : .secondary
    }

    private var statusText: String {
        if store.engine.playing { return "正在播放" }
        if let reason = store.engine.activePauseReasons.sorted(by: { $0.rawValue < $1.rawValue }).first {
            return "已自动暂停：\(reasonLabel(reason))"
        }
        return "已暂停"
    }

    private func reasonLabel(_ reason: PauseReason) -> String {
        switch reason {
        case .fullscreen: return "前台应用全屏"
        case .battery: return "电池供电"
        case .idle: return "闲置"
        case .displaySleep: return "屏幕休眠"
        }
    }
}

extension Notification.Name {
    static let navigateResources = Notification.Name("cduyzhWallpaper.navigateResources")
    static let navigateLibrary = Notification.Name("cduyzhWallpaper.navigateLibrary")
}
