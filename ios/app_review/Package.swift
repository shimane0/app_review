// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "app_review",
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(name: "app-review", targets: ["app_review"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "app_review",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
