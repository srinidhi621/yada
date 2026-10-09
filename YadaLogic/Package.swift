// swift-tools-version: 6.0
// Portable logic only. The Mac app is still built from Yada.xcodeproj.
import PackageDescription

let package = Package(
    name: "YadaLogic",
    targets: [
        .target(
            name: "YadaLogic",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "YadaLogicTests",
            dependencies: ["YadaLogic"],
            path: "Tests/YadaLogicTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
