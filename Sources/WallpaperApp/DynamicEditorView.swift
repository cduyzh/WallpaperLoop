import SwiftUI
import WallpaperCore

/// 动态壁纸编辑器：创建或编辑按时间切换的时段方案。
struct DynamicEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// nil 为新建；非 nil 为编辑该动态壁纸（保留 id 与添加时间）。
    let editTarget: DynamicWallpaper?

    @State private var title = ""
    @State private var slots: [DynamicSlot] = []
    @State private var didLoad = false

    init(editTarget: DynamicWallpaper? = nil) {
        self.editTarget = editTarget
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if slots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.sunmax").font(.system(size: 30)).foregroundStyle(Palette.subtleText)
                    Text("添加时段：例如 07:00 用日出、19:00 用夜景").foregroundStyle(Palette.subtleText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($slots) { $slot in
                        slotRow($slot)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(width: 500, height: 450)
        .onAppear { loadTarget() }
    }

    private func loadTarget() {
        guard !didLoad else { return }
        didLoad = true
        if let editTarget {
            title = editTarget.title
            slots = editTarget.slots
        } else {
            title = "时间动态壁纸"
            addDefaultSlots()
        }
    }

    private var header: some View {
        HStack {
            TextField("名称", text: $title).textFieldStyle(.roundedBorder)
            Button {
                withAnimation { slots.append(DynamicSlot(startMinute: nextSlotMinute(), mediaID: store.snapshot.media.first?.id ?? UUID())) }
            } label: {
                Label("添加时段", systemImage: "plus")
            }
            .disabled(store.snapshot.media.isEmpty)
        }
        .padding(12)
    }

    private func slotRow(_ slot: Binding<DynamicSlot>) -> some View {
        HStack(spacing: 12) {
            DatePicker("", selection: bindingTime(for: slot), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(width: 100)
            Picker("", selection: slot.mediaID) {
                ForEach(store.snapshot.media) { media in
                    Text(media.title).tag(media.id)
                }
            }
            .labelsHidden()
            Button {
                slots.removeAll { $0.id == slot.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Text("时段按本地时间生效，跨零点自动回绕").font(.caption).foregroundStyle(Palette.subtleText)
            Spacer()
            Button("取消") { dismiss() }
            Button(editTarget == nil ? "创建" : "保存") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(slots.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    /// DatePicker 与 startMinute（当日分钟）互转。
    private func bindingTime(for slot: Binding<DynamicSlot>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: slot.wrappedValue.startMinute / 60,
                                   minute: slot.wrappedValue.startMinute % 60,
                                   second: 0, of: Date()) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            slot.wrappedValue.startMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private func nextSlotMinute() -> Int {
        let last = slots.map(\.startMinute).max() ?? -360
        return min(1439, last + 360)
    }

    private func addDefaultSlots() {
        guard slots.isEmpty, !store.snapshot.media.isEmpty else { return }
        slots = [
            DynamicSlot(startMinute: 7 * 60, mediaID: store.snapshot.media[0].id),
            DynamicSlot(startMinute: 19 * 60, mediaID: store.snapshot.media[min(1, store.snapshot.media.count - 1)].id),
        ]
    }

    private func save() {
        var wallpaper = editTarget ?? DynamicWallpaper(title: "", slots: [])
        wallpaper.title = title.trimmingCharacters(in: .whitespaces)
        wallpaper.slots = slots
        do {
            try store.library.addDynamicWallpaper(wallpaper)
            store.reloadSnapshot()
            dismiss()
        } catch {
            store.importError = "保存动态壁纸失败：\(error.localizedDescription)"
        }
    }
}
