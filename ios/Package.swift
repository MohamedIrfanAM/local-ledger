// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalLedgerCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "LedgerCore", targets: ["LedgerCore"])],
    targets: [
        .target(name: "LedgerCore", resources: [.process("Resources")]),
        .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"])
    ]
)
