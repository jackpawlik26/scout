// swift-tools-version: 6.2
// ScoutCore: Scout's UI-free logic (file listing, search ranking, visit history).
// Kept separate from the Mac app so an iPhone app or a home server can reuse it later.
import PackageDescription

let package = Package(
    name: "ScoutCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ScoutCore", targets: ["ScoutCore"]),
        .executable(name: "scout", targets: ["ScoutCLI"]),
    ],
    targets: [
        .target(name: "ScoutCore"),
        .executableTarget(name: "ScoutCLI", dependencies: ["ScoutCore"]),
        .testTarget(name: "ScoutCoreTests", dependencies: ["ScoutCore"]),
    ]
)
