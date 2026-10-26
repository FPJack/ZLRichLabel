// swift-tools-version:5.5
//
// Swift Package Manager 支持：
//   Xcode › File › Add Package Dependencies… 输入 https://github.com/FPJack/ZLRichLabel.git
// 或在 Package.swift 中：
//   .package(url: "https://github.com/FPJack/ZLRichLabel.git", from: "3.0.0")
//

import PackageDescription

let package = Package(
    name: "ZLRichLabel",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "ZLRichLabel", targets: ["ZLRichLabel"]),
    ],
    targets: [
        .target(
            name: "ZLRichLabel",
            path: "ZLRichLabel/Classes",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("CoreText"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
