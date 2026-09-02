// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nimbus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nimbus", targets: ["Nimbus"])],
    targets: [
        .executableTarget(
            name: "Nimbus",
            path: "Sources/Nimbus",
            exclude: ["Info.plist"],
            // Declared so `swift build` doesn't treat them as stray files. The
            // icon only takes effect in the `.app` the Xcode project builds —
            // `swift build` produces a bare executable with no bundle to carry
            // it — so the code falls back to an SF Symbol when it isn't found.
            resources: [.copy("Resources")]
        )
    ]
)
