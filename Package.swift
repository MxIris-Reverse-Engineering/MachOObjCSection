// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MachOObjCSection",
    products: [
        .library(
            name: "MachOObjCSection",
            targets: ["MachOObjCSection"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/MachOKit.git", exact: "0.21.1"),
        .package(url: "https://github.com/p-x9/swift-objc-dump.git", exact: "0.1.0")
    ],
    targets: [
        .target(
            name: "MachOObjCSection",
            dependencies: [
                "MachOObjCSectionC",
                "MachOKit",
                .product(name: "ObjCDump", package: "swift-objc-dump")
            ]
        ),
        .target(
            name: "MachOObjCSectionC"
        ),
        .testTarget(
            name: "MachOObjCSectionTests",
            dependencies: ["MachOObjCSection"]
        ),
    ]
)
