// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Feather",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Feather", targets: ["Feather"])],
  targets: [
    .target(name: "FeatherCore"),
    .executableTarget(
      name: "Feather", dependencies: ["FeatherCore"], resources: [.process("Resources")]),
    .testTarget(name: "FeatherCoreTests", dependencies: ["FeatherCore"]),
    .testTarget(name: "FeatherAppTests", dependencies: ["Feather", "FeatherCore"]),
  ]
)
