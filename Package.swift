// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyPlanner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MyPlanner", path: "Sources/MyPlanner")
    ]
)
