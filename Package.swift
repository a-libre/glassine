// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glassine",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Glassine",
            path: "Sources/Glassine"
        )
    ]
)
