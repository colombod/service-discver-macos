// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServiceDiscovery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ServiceDiscovery", targets: ["ServiceDiscovery"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "DirectoryCore"),
        .executableTarget(name: "ServiceDiscovery", dependencies: ["DirectoryCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DirectoryCoreTests", dependencies: ["DirectoryCore"])
    ],
    swiftLanguageModes: [.v5]
)
