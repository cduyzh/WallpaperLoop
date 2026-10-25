import SwiftUI

/// 关于：真实版本、构建号、构建时间、来源摘要与安装状态。
struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledRow("产品", value: "WallpaperLoop（cduyzhDynamicWallpapaer）")
            LabeledRow("版本", value: version)
            LabeledRow("构建", value: build)
            if let date = info("CDUYZHBuildDate") {
                LabeledRow("构建时间", value: date)
            }
            if let revision = info("CDUYZHSourceRevision") {
                LabeledRow("来源", value: revision)
            }
            if let hash = info("CDUYZHSourceHash") {
                LabeledRow("来源摘要", value: String(hash.prefix(16)) + "…")
            }
            LabeledRow("安装位置", value: Bundle.main.bundlePath)
        }
        .padding(.vertical, 2)
    }

    private var version: String { info("CFBundleShortVersionString") ?? "未知" }
    private var build: String { info("CFBundleVersion") ?? "未知" }

    private func info(_ key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.subtleText).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }
}
