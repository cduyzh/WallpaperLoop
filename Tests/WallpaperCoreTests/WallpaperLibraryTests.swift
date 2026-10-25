import XCTest
@testable import WallpaperCore

final class WallpaperLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSourceFile(name: String, content: String = "demo") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testImportCopiesFileAndPersistsIndex() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let source = try makeSourceFile(name: "sunset.mp4")
        let item = try library.importMedia(at: source, kind: .video, durationSeconds: 12)
        XCTAssertEqual(item.kind, .video)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: item).path))
        // 重新加载后仍能找到。
        let reloaded = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        XCTAssertEqual(reloaded.media(withID: item.id), item)
    }

    func testRemoveMediaDeletesFileAndPrunesDynamicSlots() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let first = try library.importMedia(at: makeSourceFile(name: "a.png"), kind: .image)
        let second = try library.importMedia(at: makeSourceFile(name: "b.png"), kind: .image)
        try library.addDynamicWallpaper(DynamicWallpaper(
            title: "日夜",
            slots: [DynamicSlot(startMinute: 420, mediaID: first.id),
                    DynamicSlot(startMinute: 1140, mediaID: second.id)]
        ))
        let firstFile = library.url(for: first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFile.path))

        try library.remove(reference: .media(first.id))
        XCTAssertNil(library.media(withID: first.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstFile.path))
        // 只剩一个时段的动态壁纸保留该时段。
        let dynamic = library.currentSnapshot().dynamicWallpapers
        XCTAssertEqual(dynamic.count, 1)
        XCTAssertEqual(dynamic[0].slots.map(\.mediaID), [second.id])
    }

    func testRemoveLastSlotMediaRemovesDynamicWallpaper() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let item = try library.importMedia(at: makeSourceFile(name: "only.png"), kind: .image)
        try library.addDynamicWallpaper(DynamicWallpaper(title: "单时段", slots: [DynamicSlot(startMinute: 0, mediaID: item.id)]))
        try library.remove(reference: .media(item.id))
        XCTAssertTrue(library.currentSnapshot().dynamicWallpapers.isEmpty)
    }

    func testAddDynamicRejectsMissingMedia() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        XCTAssertThrowsError(try library.addDynamicWallpaper(
            DynamicWallpaper(title: "坏引用", slots: [DynamicSlot(startMinute: 0, mediaID: UUID())])
        ))
    }

    func testCorruptedIndexDropsInvalidEntries() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let item = try library.importMedia(at: makeSourceFile(name: "x.png"), kind: .image)
        // 手工注入引用缺失时段与重复媒体，重新加载应清理。
        var snapshot = library.currentSnapshot()
        let duplicate = WallpaperMedia(id: item.id, title: "重复", fileName: item.fileName, kind: .image)
        snapshot.media.append(duplicate)
        snapshot.dynamicWallpapers.append(DynamicWallpaper(title: "空引用", slots: [DynamicSlot(startMinute: 10, mediaID: UUID())]))
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent("lib/library.json"))
        let reloaded = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        XCTAssertEqual(reloaded.currentSnapshot().media.count, 1)
        XCTAssertTrue(reloaded.currentSnapshot().dynamicWallpapers.isEmpty)
    }

    func testRename() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let item = try library.importMedia(at: makeSourceFile(name: "old.png"), kind: .image)
        try library.rename(reference: .media(item.id), title: "新名字")
        XCTAssertEqual(library.media(withID: item.id)?.title, "新名字")
    }

    // MARK: - 引用导入

    func testReferenceImportDoesNotCopyAndRemoveKeepsSource() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let source = try makeSourceFile(name: "system-tahoe.mov", content: "video-bytes")
        let item = try library.importMedia(at: source, kind: .video, storage: .reference, origin: .system)

        XCTAssertTrue(item.isReference)
        // 引用条目不在库目录生成副本。
        let libraryFile = library.libraryDirectory.appendingPathComponent(item.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryFile.path))
        XCTAssertEqual(library.url(for: item), source)
        XCTAssertEqual(library.location(for: item), .externalReference(source))
        XCTAssertEqual(library.fileSizeBytes(for: item), Int64("video-bytes".utf8.count))

        // 删除引用条目绝不触碰源文件。
        try library.remove(reference: .media(item.id))
        XCTAssertNil(library.media(withID: item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testLocationDetectsMissingReferenceSource() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let source = try makeSourceFile(name: "gone.mov", content: "video-bytes")
        let item = try library.importMedia(at: source, kind: .video, storage: .reference)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(library.location(for: item), nil)
    }

    func testCopyImportRecordsFileSize() throws {
        let library = WallpaperLibrary(directory: directory.appendingPathComponent("lib"))
        let item = try library.importMedia(at: makeSourceFile(name: "clip.mp4", content: "12345"), kind: .video)
        XCTAssertFalse(item.isReference)
        XCTAssertEqual(library.fileSizeBytes(for: item), Int64("12345".utf8.count))
    }

    /// 0.1.0 的索引没有 storage 字段：解码为 nil 并按 copy 条目处理。
    func testLegacyIndexWithoutStorageDecodesAsCopy() throws {
        let json = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"旧条目","fileName":"a.mp4","kind":"video","addedAt":700000000.0}"#
        let item = try JSONDecoder().decode(WallpaperMedia.self, from: Data(json.utf8))
        XCTAssertNil(item.storage)
        XCTAssertFalse(item.isReference)
    }
}
