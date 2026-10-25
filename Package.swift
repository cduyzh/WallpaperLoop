// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cduyzhDynamicWallpapaer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "cduyzhDynamicWallpapaer", targets: ["WallpaperApp"])],
    dependencies: [],
    targets: [
        .target(name: "WallpaperCore", path: "Sources/WallpaperCore"),
        .executableTarget(name: "WallpaperApp", dependencies: ["WallpaperCore"], path: "Sources/WallpaperApp"),
        .testTarget(name: "WallpaperCoreTests", dependencies: ["WallpaperCore"], path: "Tests/WallpaperCoreTests")
    ]
)
