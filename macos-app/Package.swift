// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OSCRCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OSCRCompanion", targets: ["OSCRCompanion"])
    ],
    targets: [
        .target(
            name: "CSerialBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "OSCRCompanion",
            dependencies: ["CSerialBridge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OSCRCompanionTests",
            dependencies: ["OSCRCompanion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
