// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "shotX",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "ShotXKit", swiftSettings: strict + [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "shotX", dependencies: ["ShotXKit"], swiftSettings: strict),
        .testTarget(name: "ShotXKitTests", dependencies: ["ShotXKit"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
