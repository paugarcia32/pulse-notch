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
        ),
        .executable(
            name: "PulseNotchClaudeBridge",
            targets: ["PulseNotchClaudeBridge"]
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
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PulseNotchApp/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "PulseNotchClaudeBridge"
        ),
        .testTarget(
            name: "PulseNotchCoreTests",
            dependencies: [
                "PulseNotchCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "PulseNotchAppTests",
            dependencies: [
                "PulseNotchApp",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
