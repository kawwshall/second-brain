// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mahdi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mahdi", targets: ["Mahdi"])],
    targets: [
        .target(name: "MahdiCore"),
        .executableTarget(name: "Mahdi", dependencies: ["MahdiCore"]),
        .executableTarget(name: "MahdiChecks", dependencies: ["MahdiCore"], path: "Tests/MahdiChecks")
    ],
    swiftLanguageModes: [.v5]
)
