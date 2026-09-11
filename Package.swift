// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PulseNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PulseNotchCore",
            targets: ["PulseNotchCore"]
        ),
        .executable(
            name: "PulseNotch",
            targets: ["PulseNotchApp"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.12.0"
        )
    ],
    targets: [
        .target(
            name: "PulseNotchCore"
        ),
        .executableTarget(
            name: "PulseNotchApp",
            dependencies: ["PulseNotchCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PulseNotchApp/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PulseNotchCoreTests",
            dependencies: [
                "PulseNotchCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
