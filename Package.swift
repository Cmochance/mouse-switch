// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MouseSwitch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MouseSwitch", targets: ["MouseSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "MouseSwitch",
            path: "Sources/MouseSwitch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
