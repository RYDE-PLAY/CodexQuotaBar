// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexQuotaBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexQuotaBar", targets: ["CodexQuotaBar"])
    ],
    targets: [
        .target(
            name: "CodexQuotaBarCore",
            path: "Sources/CodexQuotaBarCore"
        ),
        .executableTarget(
            name: "CodexQuotaBar",
            dependencies: ["CodexQuotaBarCore"],
            path: "Sources/CodexQuotaBar"
        ),
        .testTarget(
            name: "CodexQuotaBarCoreTests",
            dependencies: ["CodexQuotaBarCore"],
            path: "Tests/CodexQuotaBarCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
