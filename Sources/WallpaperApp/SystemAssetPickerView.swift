import SwiftUI
import WallpaperCore

/// 系统内置壁纸选择器：列出 macOS 自带的动态壁纸视频，引用或复制加入库。
struct SystemAssetPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear { store.refreshSystemAssets() }
        .alert("导入失败", isPresented: Binding(get: { store.importError != nil }, set: { _ in store.importError = nil })) {
            Button("好") { store.importError = nil }
        } message: {
            Text(store.importError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("系统内置壁纸").font(.headline)
            Text("macOS 自带的动态壁纸视频（/System/Library/Desktop Pictures）。推荐「引用播放」：不复制文件、不占库空间，删除条目也不会影响系统资源。")
                .font(.callout)
                .foregroundStyle(Palette.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        if store.systemAssets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 32))
                    .foregroundStyle(Palette.subtleText)
                Text("未找到系统内置壁纸视频")
                    .font(.headline)
                Text("当前 macOS 版本可能不包含动态壁纸视频，可改用「从 URL 导入」添加在线视频。")
                    .font(.callout)
                    .foregroundStyle(Palette.subtleText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(store.systemAssets) { asset in
                row(asset)
            }
            .listStyle(.inset)
        }
    }

    private func row(_ asset: SystemWallpaperAsset) -> some View {
        let imported = store.importedSystemAssetPaths.contains(asset.url.path)
        return HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).lineLimit(1)
                Text(AppStore.byteCountText(asset.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(Palette.subtleText)
            }
            Spacer()
            if imported {
                Label("已在库中", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(Palette.accent)
            } else {
                Menu {
                    Button("引用播放（推荐，0 空间占用）") {
                        Task { await store.addSystemAsset(asset, storage: .reference) }
                    }
                    Button("复制导入（占 \(AppStore.byteCountText(asset.sizeBytes)) 库空间）") {
                        Task { await store.addSystemAsset(asset, storage: .copy) }
                    }
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            if store.isImporting {
                ProgressView().controlSize(.small)
                Text("正在导入…").font(.caption).foregroundStyle(Palette.subtleText)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

/// URL 导入面板：粘贴直链视频地址，下载后复制入库。
struct URLImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isWorking = false

    private var sanitized: URL? {
        MediaDownloader.sanitizedURL(from: urlText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 URL 导入视频").font(.headline)
            Text("粘贴视频直链（mp4 / mov），下载完成后作为副本加入壁纸库，可在资源管理中删除。")
                .font(.callout)
                .foregroundStyle(Palette.subtleText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://example.com/wallpaper.mp4", text: $urlText)
                .textFieldStyle(.roundedBorder)
            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.downloadDescription ?? "正在下载…")
                        .font(.caption)
                        .foregroundStyle(Palette.subtleText)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    guard let url = sanitized else { return }
                    isWorking = true
                    Task { @MainActor in
                        let success = await store.downloadAndImport(from: url)
                        isWorking = false
                        if success { dismiss() }
                    }
                } label: {
                    Text("下载并导入")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sanitized == nil || isWorking)
            }
        }
        .padding(20)
        .frame(width: 440, height: 210)
        .alert("导入失败", isPresented: Binding(get: { store.importError != nil }, set: { _ in store.importError = nil })) {
            Button("好") { store.importError = nil }
        } message: {
            Text(store.importError ?? "")
        }
    }
}
