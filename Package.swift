// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppTabs",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppTabsCore", targets: ["AppTabsCore"]),
        .executable(name: "AppTabs", targets: ["AppTabs"]),
        .executable(name: "AppTabsCoreTests", targets: ["AppTabsCoreTests"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppTabsCore",
            path: "Sources/AppTabsCore"
        ),
        .executableTarget(
            name: "AppTabs",
            dependencies: ["AppTabsCore"],
            path: "Sources/AppTabs"
        ),
        // CLT has no XCTest / Swift Testing module, so tests are a plain
        // executable assertion harness: run with `swift run AppTabsCoreTests`.
        .executableTarget(
            name: "AppTabsCoreTests",
            dependencies: ["AppTabsCore"],
            path: "Tests/AppTabsCoreTests"
        ),
    ]
)
