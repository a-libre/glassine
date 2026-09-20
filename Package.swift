// swift-tools-version:5.9
import PackageDescription

// The direct download updates itself with Sparkle. The App Store flavor has
// no updater of its own — the store is its updater — so `build.sh --appstore`
// sets GLASSINE_APPSTORE and Sparkle is left out of that build entirely: not
// linked, not in the bundle. The package is still resolved either way, so
// Package.resolved does not churn between flavors.
let appStore = Context.environment["GLASSINE_APPSTORE"] != nil

let package = Package(
    name: "Glassine",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Glassine",
            dependencies: appStore ? [] : [.product(name: "Sparkle", package: "Sparkle")],
            // One module, two folders: Shared is the code every platform compiles,
            // Mac is the AppKit shell. Sources/iOS is the UIKit shell; it is built
            // by the iOS project (ios/project.yml), never by this package.
            path: "Sources",
            exclude: ["iOS"],
            sources: ["Shared", "Mac"]
        )
    ]
)
