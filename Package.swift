// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenTracker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TokenTracker",
            path: "TokenTracker",
            exclude: ["Info.plist", "TokenTracker.entitlements", "Assets.xcassets"]
        )
    ]
)
