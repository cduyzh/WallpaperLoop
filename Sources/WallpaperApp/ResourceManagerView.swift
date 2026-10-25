import AppKit
import SwiftUI
import WallpaperCore

/// 资源管理：视频 / 图片资源的用量统计、来源、使用状态与删除。
struct ResourceManagerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var deleteTarget: WallpaperMedia?
    @State private var batchTarget: BatchCleanup?
    @State private var statusMessage: String?

    enum BatchCleanup {
        case unusedVideoCopies(items: [WallpaperMedia])
        case orphanThumbnails

        var title: String {
            switch self {
            case .unusedVideoCopies: return "清理未使用的视频副本"
            case .orphanThumbnails: return "清理孤儿缩略图"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCards
                entrySection(title: "视频", items: store.videoEntries)
                entrySection(title: "图片", items: store.imageEntries)
                maintenanceSection
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(20)
        }
        .navigationTitle("资源管理")
        .navigationSubtitle("库内资源、占用与清理")
        .confirmationDialog(deleteDialog.title,
                            isPresented: Binding(get: { deleteTarget != nil || batchTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil; batchTarget = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) { performDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteDialog.message)
        }
    }

    private var libraryPath: String {
        store.library.libraryDirectory.path
    }

    // MARK: - 统计卡片

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            StatCard(title: "视频", value: "\(store.videoEntries.count)",
                     detail: videoSummary, systemImage: "film.stack")
            StatCard(title: "库内副本占用", value: AppStore.byteCountText(store.copiedBytesOnDisk),
                     detail: "缩略图额外占用 \(AppStore.byteCountText(thumbnailBytes))", systemImage: "internaldrive")
            StatCard(title: "引用条目", value: "\(referenceCount)",
                     detail: "直接播放系统等外部文件，不占库空间", systemImage: "link")
        }
    }

    private var videoSummary: String {
        let videos = store.videoEntries
        let bytes = videos.filter { !$0.isReference }.reduce(Int64(0)) { $0 + (store.library.fileSizeBytes(for: $1) ?? 0) }
        return "\(videos.count - referenceCount) 个副本 · 共 \(AppStore.byteCountText(bytes))"
    }

    private var referenceCount: Int {
        store.snapshot.media.filter(\.isReference).count
    }

    private var thumbnailBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: store.thumbnailsDirectory,
                                                                  includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    // MARK: - 条目列表

    @ViewBuilder
    private func entrySection(title: String, items: [WallpaperMedia]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title)（\(items.count)）")
                .font(.headline)
            if items.isEmpty {
                Text("暂无\(title)")
                    .font(.callout)
                    .foregroundStyle(Palette.subtleText)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        entryRow(item)
                    }
                }
            }
        }
    }

    private func entryRow(_ item: WallpaperMedia) -> some View {
        let usages = store.usages(of: item.id)
        return HStack(spacing: 12) {
            MediaThumbnail(media: item, height: 56)
                .frame(width: 88)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1).font(.callout.weight(.medium))
                    if store.isMissing(item) {
                        Label("资源缺失", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("源文件不存在，无法播放")
                    }
                }
                HStack(spacing: 4) {
                    Text(store.originLabel(for: item))
                    Text("·")
                    Text(sizeDetail(item))
                    if let duration = item.durationSeconds, duration > 0 {
                        Text("·")
                        Text(MediaCard.timeString(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.subtleText)
                .lineLimit(1)
                if usages.isEmpty {
                    Text("未被使用")
                        .font(.caption)
                        .foregroundStyle(Palette.subtleText)
                } else {
                    HStack(spacing: 4) {
                        ForEach(usages, id: \.self) { usage in
                            Text(usage)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                revealInFinder(item)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            Button {
                deleteTarget = item
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(10)
        .background(Palette.cardRaised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.border, lineWidth: 1))
    }

    private func sizeDetail(_ item: WallpaperMedia) -> String {
        guard let bytes = store.library.fileSizeBytes(for: item), bytes > 0 else { return "大小未知" }
        return item.isReference ? "外部文件 \(AppStore.byteCountText(bytes))" : AppStore.byteCountText(bytes)
    }

    // MARK: - 维护操作

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("维护")
                .font(.headline)
            HStack(spacing: 10) {
                Button("清理未使用的视频副本") {
                    let items = store.videoEntries.filter { !$0.isReference && store.usages(of: $0.id).isEmpty }
                    guard !items.isEmpty else {
                        statusMessage = "没有未使用的视频副本"
                        return
                    }
                    batchTarget = .unusedVideoCopies(items: items)
                }
                .disabled(store.videoEntries.filter { !$0.isReference }.isEmpty)
                Button("清理孤儿缩略图") {
                    let removed = store.cleanOrphanThumbnails()
                    statusMessage = removed > 0 ? "已清理 \(removed) 个孤儿缩略图" : "没有需要清理的孤儿缩略图"
                }
                Button("打开资源目录") {
                    store.openLibraryInFinder()
                }
                Spacer()
            }
            Text("库目录：\(libraryPath)")
                .font(.caption)
                .foregroundStyle(Palette.subtleText)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 删除流程

    private var deleteDialog: (title: String, message: String) {
        if let item = deleteTarget {
            return deleteDialog(for: item)
        }
        if case .unusedVideoCopies(let items)? = batchTarget {
            let bytes = items.reduce(Int64(0)) { $0 + (store.library.fileSizeBytes(for: $1) ?? 0) }
            return ("清理未使用的视频副本",
                    "将删除 \(items.count) 个视频副本，永久释放 \(AppStore.byteCountText(bytes)) 磁盘空间（含缩略图）。此操作不可恢复。")
        }
        return ("清理孤儿缩略图", "将删除没有对应媒体条目的缩略图文件。")
    }

    private func deleteDialog(for item: WallpaperMedia) -> (title: String, message: String) {
        let usages = store.usages(of: item.id)
        let usageHint = usages.isEmpty ? "" : "该条目当前被：\(usages.joined(separator: "、")) 使用，删除后相关配置会一并清理。"
        if item.isReference {
            return ("删除「\(item.title)」？",
                    "仅从壁纸库移除引用条目，不会删除外部源文件（\(item.sourcePath ?? "")）。\(usageHint)")
        }
        let bytes = store.library.fileSizeBytes(for: item) ?? 0
        return ("删除「\(item.title)」？",
                "将永久删除库内文件（\(AppStore.byteCountText(bytes))）与缩略图，此操作不可恢复。\(usageHint)")
    }

    private func performDelete() {
        if let item = deleteTarget {
            store.remove(reference: .media(item.id))
            statusMessage = "已删除「\(item.title)」"
        } else if case .unusedVideoCopies(let items)? = batchTarget {
            let count = store.removeMedia(ids: items.map(\.id))
            statusMessage = "已清理 \(count) 个未使用的视频副本"
        } else if batchTarget != nil {
            let removed = store.cleanOrphanThumbnails()
            statusMessage = "已清理 \(removed) 个孤儿缩略图"
        }
        deleteTarget = nil
        batchTarget = nil
    }

    private func revealInFinder(_ item: WallpaperMedia) {
        let url = store.library.url(for: item)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// 统计卡片。
private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(Palette.accent)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.subtleText)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.subtleText)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}
