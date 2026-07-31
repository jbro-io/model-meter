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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .executableTarget(
            name: "ModelMeter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ModelMeter",
            resources: [
                .copy("Resources/Brand")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
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
