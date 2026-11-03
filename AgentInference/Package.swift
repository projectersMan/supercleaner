// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentInference",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentInference", targets: ["AgentInference"])],
    dependencies: [.package(url: "https://github.com/maralski/gemma-embed-swift.git", exact: "0.4.1")],
    targets: [.executableTarget(name: "AgentInference", dependencies: [.product(name: "GemmaEmbed", package: "gemma-embed-swift")])]
)
