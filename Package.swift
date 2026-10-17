// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nimbus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nimbus", targets: ["Nimbus"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Nimbus",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "libwebp", package: "libwebp-Xcode")
            ],
            path: "Sources/Nimbus",
            exclude: ["Info.plist", "Nimbus.entitlements"],
            // Declared so `swift build` doesn't treat them as stray files. The
            // icon only takes effect in the `.app` the Xcode project builds —
            // `swift build` produces a bare executable with no bundle to carry
            // it — so the code falls back to an SF Symbol when it isn't found.
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/TrayIcon.png"),
                .copy("Resources/ffmpeg")
            ]
        )
    ]
)
