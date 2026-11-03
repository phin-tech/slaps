// swift-tools-version: 6.0
import PackageDescription

// SlapsKit holds everything that isn't UI, so `swift test` covers it headless. The app (project.yml) links it
// as a local package; Sparkle is an Xcode-only dependency and stays out of here.
let package = Package(
    name: "Slaps",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlapsKit", targets: ["SlapsKit"]),
    ],
    targets: [
        .target(name: "SlapsKit"),
        .testTarget(name: "SlapsKitTests", dependencies: ["SlapsKit"]),
    ]
)
