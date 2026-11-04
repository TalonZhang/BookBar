// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BookBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BookBar", targets: ["BookBar"])],
    targets: [
        .systemLibrary(name: "CZlib"),
        .executableTarget(name: "BookBar", dependencies: ["CZlib"])
    ],
    swiftLanguageModes: [.v5]
)
