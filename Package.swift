// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nimbus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nimbus", targets: ["Nimbus"])],
    targets: [
        .executableTarget(name: "Nimbus", path: "Sources/Nimbus", exclude: ["Info.plist"])
    ]
)
