// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PostKit",
    // English baseline for the String Catalog (Resources/Localizable.xcstrings). Required once the
    // package carries localized resources; SwiftUI Text in the package now localizes via .module.
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "PostKit", targets: ["PostKit"])
    ],
    targets: [
        .target(
            name: "PostKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PostKitTests",
            dependencies: ["PostKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
