import XCTest
@testable import WallpaperCore

final class SystemWallpaperAssetsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("system-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(relative: String, size: Int = 10) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
    }

    func testScanFindsNestedMovAndSkipsThumbnailsAndHeic() throws {
        try makeFile(relative: "Tahoe Day/Tahoe Day.mov", size: 30)
        try makeFile(relative: "Sonoma/Sonoma Graphic Light Landscape.mov", size: 20)
        try makeFile(relative: "Sonoma Horizon/Thumbnail.heic")
        try makeFile(relative: "Sonoma Horizon/Sonoma Horizon Thumbnail.png")
        try makeFile(relative: "Some Preview.mov", size: 0) // 空文件跳过

        let assets = SystemWallpaperAssets.scan(root: root)
        XCTAssertEqual(assets.map(\.name).sorted(), ["Sonoma Graphic Light Landscape", "Tahoe Day"])
        XCTAssertEqual(assets.first { $0.name == "Tahoe Day" }?.sizeBytes, 30)
    }

    func testScanMissingRootReturnsEmpty() {
        let assets = SystemWallpaperAssets.scan(root: root.appendingPathComponent("不存在"))
        XCTAssertTrue(assets.isEmpty)
    }
}
