import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers
import WallpaperCore

/// 壁纸库：媒体卡片网格 + 动态壁纸 + 多来源导入（文件 / 系统内置 / 在线 URL）。
struct LibraryView: View {
    enum Filter: String, CaseIterable, Hashable {
        case all = "全部"
        case video = "视频"
        case image = "图片"
        case dynamic = "动态壁纸"
    }

    @EnvironmentObject private var store: AppStore
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var editingWallpaper: DynamicWallpaper?
    @State private var isShowingDynamicEditor = false
    @State private var isShowingSystemPicker = false
    @State private var isShowingURLImport = false
    @State private var renamingReference: WallpaperReference?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    private var filteredMedia: [WallpaperMedia] {
        store.snapshot.media.filter { item in
            let kindMatch: Bool
            switch filter {
            case .all, .dynamic: kindMatch = true
            case .video: kindMatch = item.kind == .video
            case .image: kindMatch = item.kind == .image
            }
            return kindMatch && matches(item.title)
        }
    }

    private var filteredDynamic: [DynamicWallpaper] {
        guard filter == .all || filter == .dynamic else { return [] }
        return store.snapshot.dynamicWallpapers.filter { matches($0.title) }
    }

    private func matches(_ title: String) -> Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || title.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                libraryHero
                if filteredMedia.isEmpty && filteredDynamic.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredDynamic) { wallpaper in
                            DynamicCard(wallpaper: wallpaper,
                                        onEdit: { editingWallpaper = wallpaper; isShowingDynamicEditor = true })
                                .contextMenu { cardMenu(.dynamicWallpaper(wallpaper.id)) }
                        }
                        ForEach(filteredMedia) { media in
                            MediaCard(media: media)
                                .contextMenu { cardMenu(.media(media.id)) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .top) { toolbar }
        .navigationTitle("壁纸库")
        .navigationSubtitle(importSubtitle)
        .sheet(isPresented: $isShowingSystemPicker) { SystemAssetPickerView() }
        .sheet(isPresented: $isShowingURLImport) { URLImportView() }
        .sheet(isPresented: $isShowingDynamicEditor) {
            DynamicEditorView(editTarget: editingWallpaper)
        }
        .alert("导入失败", isPresented: Binding(get: { store.importError != nil }, set: { _ in store.importError = nil })) {
            Button("好") { store.importError = nil }
        } message: {
            Text(store.importError ?? "")
        }
        .sheet(isPresented: Binding(get: { renamingReference != nil }, set: { if !$0 { renamingReference = nil } })) {
            renameSheet
        }
    }

    private var importSubtitle: String {
        let media = store.snapshot.media.count
        let dynamic = store.snapshot.dynamicWallpapers.count
        guard media + dynamic > 0 else { return "空" }
        return "\(media) 个媒体 · \(dynamic) 个动态壁纸"
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("导入本地视频 / 图片…") { openImportPanel() }
                Button("浏览系统内置壁纸…") {
                    store.refreshSystemAssets()
                    isShowingSystemPicker = true
                }
                Button("从 URL 导入视频…") { isShowingURLImport = true }
            } label: {
                Label("导入素材", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(store.isImporting)

            Button {
                editingWallpaper = nil
                isShowingDynamicEditor = true
            } label: {
                Label("新建动态", systemImage: "clock.badge.sunmax")
            }
            .buttonStyle(.bordered)
            .disabled(store.snapshot.media.isEmpty || store.isImporting)

            Spacer(minLength: 14)

            Picker("筛选", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 246)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.subtleText)
                TextField("搜索名称…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
            .frame(width: 178)

            if store.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .help("正在导入…")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }


    private var libraryHero: some View {
        let reference = store.engine.currentWallpaper
        let title = reference.map { store.title(for: $0) } ?? "选择一个场景，让桌面动起来"
        let subtitle = reference == nil ? "把视频、图片和时间段编排在一起，随时切换桌面氛围。" : store.engine.playing ? "正在播放 · 双击任意卡片即可切换" : "已暂停 · 继续播放即可恢复桌面场景"
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("桌面场景")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .textCase(.uppercase)
                    if reference != nil {
                        Circle().fill(store.engine.playing ? Palette.success : Palette.warning).frame(width: 7, height: 7)
                        Text(store.engine.playing ? "播放中" : "已暂停")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.subtleText)
                    }
                }
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Palette.subtleText)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(store.snapshot.media.count + store.snapshot.dynamicWallpapers.count) 个场景")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.subtleText)
                HStack(spacing: 8) {
                    Button {
                        store.engine.togglePause()
                    } label: {
                        Label(store.engine.playing ? "暂停" : "播放",
                              systemImage: store.engine.playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(reference == nil)
                    Button {
                        store.engine.playNext()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("下一个壁纸")
                    .disabled(reference == nil)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Palette.accent.opacity(0.16), Palette.cardBackground.opacity(0.92)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.accent.opacity(0.18), lineWidth: 1))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent.opacity(0.7))
            Text(hasAnyContent ? "没有匹配的结果" : "壁纸库为空")
                .font(.title3.weight(.medium))
            Text(hasAnyContent ? "换个关键词或筛选条件试试。" : "从三种来源添加视频壁纸，右键卡片即可设为壁纸。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.subtleText)
            if !hasAnyContent {
                HStack(spacing: 10) {
                    Button("导入本地文件") { openImportPanel() }
                        .buttonStyle(.borderedProminent)
                    Button("浏览系统内置壁纸") {
                        store.refreshSystemAssets()
                        isShowingSystemPicker = true
                    }
                    Button("从 URL 导入") { isShowingURLImport = true }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(34)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
    }

    private var hasAnyContent: Bool {
        !store.snapshot.media.isEmpty || !store.snapshot.dynamicWallpapers.isEmpty
    }

    // MARK: - 动作

    private func cardMenu(_ reference: WallpaperReference) -> some View {
        Group {
            Button("设为壁纸") { store.engine.play(wallpaper: reference) }
            if case .dynamicWallpaper = reference {
                Button("编辑时段…") {
                    if let wallpaper = store.snapshot.dynamicWallpapers.first(where: { $0.id == reference.id }) {
                        editingWallpaper = wallpaper
                        isShowingDynamicEditor = true
                    }
                }
            }
            Divider()
            Button("重命名…") {
                renameText = store.title(for: reference)
                renamingReference = reference
            }
            if store.settingsStore.settings.playlist.order.contains(reference) {
                Button("从播放列表移除") {
                    store.settingsStore.update { settings in
                        settings.playlist.order.removeAll { $0 == reference }
                    }
                }
            } else {
                Button("加入播放列表") {
                    store.settingsStore.update { settings in
                        settings.playlist.order.append(reference)
                    }
                }
            }
            Divider()
            if case .media(let id) = reference {
                Button("在资源管理中查看…") {
                    NotificationCenter.default.post(name: .navigateResources, object: nil)
                    _ = id
                }
            }
            Button("移除…", role: .destructive) { store.remove(reference: reference) }
        }
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "选择视频或图片文件"
        panel.allowedContentTypes = [
            UTType.quickTimeMovie, UTType.mpeg4Movie, UTType.movie,
            UTType.png, UTType.jpeg, UTType.heic, UTType.image,
        ]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        Task { await store.importMedia(from: panel.urls) }
    }

    private var renameSheet: some View {
        VStack(spacing: 12) {
            Text("重命名").font(.headline)
            TextField("名称", text: $renameText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { renamingReference = nil }
                Button("确定") {
                    if let reference = renamingReference {
                        store.rename(reference: reference, title: renameText)
                    }
                    renamingReference = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

// MARK: - 卡片

/// 媒体卡片：缩略图 + 悬浮操作 + 状态徽标。
struct MediaCard: View {
    @EnvironmentObject private var store: AppStore
    let media: WallpaperMedia
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaThumbnail(media: media)
                .overlay {
                    if isHovering { hoverOverlay.transition(.opacity) }
                }
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Label(store.engine.playing ? "正在播放" : "已暂停", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Palette.accent, in: Capsule())
                            .padding(8)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
                }
            footer
        }
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? Palette.accent : Palette.border, lineWidth: isCurrent ? 2 : 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0.04), radius: isHovering ? 12 : 4, y: 4)
        .onTapGesture(count: 2) { store.engine.play(wallpaper: .media(media.id)) }
    }

    private var isCurrent: Bool {
        store.settingsStore.settings.currentWallpaper == .media(media.id)
    }

    private var hoverOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            HStack {
                Button {
                    store.engine.play(wallpaper: .media(media.id))
                } label: {
                    Label("设为壁纸", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Spacer()
                Button {
                    let reference = WallpaperReference.media(media.id)
                    store.settingsStore.update { settings in
                        if settings.playlist.order.contains(reference) {
                            settings.playlist.order.removeAll { $0 == reference }
                        } else {
                            settings.playlist.order.append(reference)
                        }
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("加入 / 移出播放列表")
                .accessibilityLabel("加入或移出播放列表")
            }
            .padding(8)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(media.title).lineLimit(1)
                Spacer(minLength: 4)
                if store.isMissing(media) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("源文件不存在，无法播放")
                }
            }
            .font(.callout)
            HStack(spacing: 4) {
                Text(store.originLabel(for: media))
                Text("·")
                Text(sizeText(for: media))
                if let usage = primaryUsage {
                    Text("·")
                    Text(usage).foregroundStyle(Palette.accent)
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(Palette.subtleText)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var primaryUsage: String? {
        store.usages(of: media.id).first
    }

    private func sizeText(for media: WallpaperMedia) -> String {
        guard let bytes = store.library.fileSizeBytes(for: media), bytes > 0 else { return "大小未知" }
        return AppStore.byteCountText(bytes)
    }
}

/// 动态壁纸卡片。
struct DynamicCard: View {
    @EnvironmentObject private var store: AppStore
    let wallpaper: DynamicWallpaper
    var onEdit: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.65), .orange.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "clock.badge.sunmax").font(.system(size: 34)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isHovering { editOverlay.transition(.opacity) }
            }
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Palette.accent)
                        .padding(8)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
            }
            .padding(10)
            VStack(alignment: .leading, spacing: 3) {
                Text(wallpaper.title).lineLimit(1).font(.callout)
                Text("\(wallpaper.slots.count) 个时段 · \(slotSummary)")
                    .font(.caption).foregroundStyle(Palette.subtleText).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? Palette.accent : Palette.border, lineWidth: isCurrent ? 2 : 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0.04), radius: isHovering ? 12 : 4, y: 4)
        .onTapGesture(count: 2) { store.engine.play(wallpaper: .dynamicWallpaper(wallpaper.id)) }
    }

    private var isCurrent: Bool {
        store.settingsStore.settings.currentWallpaper == .dynamicWallpaper(wallpaper.id)
    }

    private var slotSummary: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let times = wallpaper.slots
            .compactMap { Calendar.current.date(bySettingHour: $0.startMinute / 60, minute: $0.startMinute % 60, second: 0, of: Date()) }
            .sorted()
            .map { formatter.string(from: $0) }
        return times.joined(separator: " / ")
    }

    private var editOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            Button {
                onEdit?()
            } label: {
                Label("编辑时段", systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }
}

/// 缩略图容器：16:9，媒体库与资源管理共用。
struct MediaThumbnail: View {
    @EnvironmentObject private var store: AppStore
    let media: WallpaperMedia
    var height: CGFloat = 170

    var body: some View {
        ZStack {
            if let url = store.thumbnailURL(for: media), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Palette.accent.opacity(0.12))
                    Image(systemName: media.kind == .video ? "film" : "photo")
                        .font(.title).foregroundStyle(Palette.accent.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomLeading) { badges }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 6) {
            if media.kind == .video, let duration = media.durationSeconds, duration > 0 {
                Text(MediaCard.timeString(duration)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .font(.caption2).foregroundStyle(.white)
            }
        }
        .padding(6)
    }
}

extension MediaCard {
    static func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
