// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SuperCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
        .executable(name: "CleanerApp", targets: ["CleanerApp"]),
        .executable(name: "CleanerHelper", targets: ["CleanerHelper"]),
        .executable(name: "CoreContractChecks", targets: ["CoreContractChecks"]),
        .executable(name: "supercleaner", targets: ["CleanerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "CleanerCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "CleanerApp", dependencies: ["CleanerCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "CleanerHelper", dependencies: ["CleanerCore"]),
        .executableTarget(name: "CleanerCLI", dependencies: ["CleanerCore"]),
        .executableTarget(name: "CoreContractChecks", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
