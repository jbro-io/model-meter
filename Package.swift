// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ModelMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ModelMeter", targets: ["ModelMeter"])
    ],
    targets: [
        .executableTarget(
            name: "ModelMeter",
            path: "Sources/ModelMeter",
            resources: [
                .copy("Resources/Brand")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ModelMeterTests",
            dependencies: ["ModelMeter"],
            path: "Tests/ModelMeterTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
