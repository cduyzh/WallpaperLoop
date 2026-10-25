import SwiftUI
import WallpaperCore

/// 播放列表：把轮换规则和播放顺序放在同一条清晰的操作路径上。
struct PlaylistView: View {
    @EnvironmentObject private var store: AppStore

    private var settings: PlaylistSettings { store.settingsStore.settings.playlist }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                playbackSettings
                orderSection
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.pageBackground)
        .navigationTitle("播放列表")
        .navigationSubtitle(playlistSubtitle)
    }

    private var playlistSubtitle: String {
        if settings.order.isEmpty { return "还没有加入壁纸" }
        let mode = settings.mode == .interval ? "自动轮换已开启" : "手动切换"
        return "\(settings.order.count) 项 · \(mode)"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("让桌面按你的节奏变化")
                    .font(.title2.weight(.semibold))
                Text("把喜欢的壁纸排成一组，按间隔自动切换，或随时手动播放下一张。")
                    .font(.callout)
                    .foregroundStyle(Palette.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                NotificationCenter.default.post(name: .navigateLibrary, object: nil)
            } label: {
                Label("去壁纸库添加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Palette.accent.opacity(0.15), Palette.cardBackground.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.accent.opacity(0.17), lineWidth: 1))
    }

    private var playbackSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("轮换规则", subtitle: "决定播放列表何时自动前进")
            HStack(spacing: 12) {
                settingTile(title: "自动轮换", systemImage: "timer") {
                    Picker("自动轮换", selection: modeBinding) {
                        Text("关闭").tag(AutoChangeMode.off)
                        Text("按间隔").tag(AutoChangeMode.interval)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if settings.mode == .interval {
                    settingTile(title: "切换间隔", systemImage: "clock") {
                        Picker("轮换间隔", selection: intervalBinding) {
                            ForEach([5, 10, 15, 30, 60, 120, 300], id: \.self) { minutes in
                                Text(label(minutes)).tag(minutes)
                            }
                        }
                        .labelsHidden()
                    }
                }
                settingTile(title: "播放顺序", systemImage: settings.shuffle ? "shuffle" : "list.number") {
                    Toggle("随机顺序", isOn: shuffleBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .padding(18)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
    }

    private func settingTile<Content: View>(title: String, systemImage: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.subtleText)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panelBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("播放顺序", subtitle: settings.order.isEmpty ? "从壁纸库加入媒体或动态壁纸" : "使用箭头调整顺序，当前播放项会自动高亮")
            if settings.order.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(Palette.accent.opacity(0.8))
                    Text("播放列表还是空的")
                        .font(.headline)
                    Text("在壁纸库卡片上点击“加入播放列表”，就能在这里统一管理。")
                        .font(.callout)
                        .foregroundStyle(Palette.subtleText)
                        .multilineTextAlignment(.center)
                    Button("打开壁纸库") {
                        NotificationCenter.default.post(name: .navigateLibrary, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settings.order.enumerated()), id: \.offset) { index, reference in
                        playlistRow(index: index, reference: reference)
                        if index < settings.order.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Palette.cardRaised, in: RoundedRectangle(cornerRadius: 11))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                Button("清空播放列表", role: .destructive) {
                    store.settingsStore.update { $0.playlist.order = [] }
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
    }

    private func playlistRow(index: Int, reference: WallpaperReference) -> some View {
        let isCurrent = store.engine.currentWallpaper == reference
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isCurrent ? Palette.accent : Palette.subtleText)
                .frame(width: 22, alignment: .trailing)
            Image(systemName: isCurrent ? "play.circle.fill" : "rectangle.fill")
                .foregroundStyle(isCurrent ? Palette.accent : Palette.subtleText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title(for: reference))
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if isCurrent {
                    Text(store.engine.playing ? "正在播放" : "已暂停")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                }
            }
            Spacer(minLength: 8)
            Button { move(index, delta: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("上移")
            Button { move(index, delta: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == settings.order.count - 1)
            .help("下移")
            Button {
                store.settingsStore.update { $0.playlist.order.remove(at: index) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("从播放列表移除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isCurrent ? Palette.accentSoft : .clear)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(Palette.subtleText)
        }
    }

    private var modeBinding: Binding<AutoChangeMode> {
        Binding {
            settings.mode
        } set: { value in
            store.settingsStore.update { $0.playlist.mode = value }
        }
    }

    private var intervalBinding: Binding<Int> {
        Binding {
            let minutes = (settings.intervalSeconds + 59) / 60
            return [5, 10, 15, 30, 60, 120, 300].min { abs($0 - minutes) < abs($1 - minutes) } ?? 15
        } set: { minutes in
            store.settingsStore.update { $0.playlist.intervalSeconds = minutes * 60 }
        }
    }

    private var shuffleBinding: Binding<Bool> {
        Binding {
            settings.shuffle
        } set: { value in
            store.settingsStore.update { $0.playlist.shuffle = value }
        }
    }

    private func label(_ minutes: Int) -> String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }

    private func move(_ index: Int, delta: Int) {
        store.settingsStore.update { settings in
            let target = index + delta
            guard settings.playlist.order.indices.contains(index),
                  settings.playlist.order.indices.contains(target) else { return }
            settings.playlist.order.swapAt(index, target)
        }
    }
}
