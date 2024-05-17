// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MachOKitObjCSupport",
    products: [
        .library(
            name: "MachOKitObjCSupport",
            targets: ["MachOKitObjCSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/MachOKit.git", from: "0.17.0")
    ],
    targets: [
        .target(
            name: "MachOKitObjCSupport",
            dependencies: [
                "MachOKitObjCSupportC",
                "MachOKit",
            ]
        ),
        .target(
            name: "MachOKitObjCSupportC"
        ),
        .testTarget(
            name: "MachOKitObjCSupportTests",
            dependencies: ["MachOKitObjCSupport"]
        ),
    ]
)
