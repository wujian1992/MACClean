// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MACClean",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MACClean", targets: ["MACClean"])
    ],
    targets: [
        .executableTarget(
            name: "MACClean",
            path: "Sources/MACClean"
        )
    ]
)

