// swift-tools-version:6.2
import PackageDescription
import Foundation
let llgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let package = Package(
  name: "sl",
  platforms: [.macOS(.v14)],
  products: [.library(name: "SLCore", targets: ["SLCore"]), .executable(name: "sl", targets: ["sl"])],
  dependencies: [
    .package(path: "../schicksal"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
  ],
  targets: [
    // header-only C target; the cargo-built static lib (./build-llg.sh -> vendor/llg) is linked via the unsafe flags
    .target(name: "CLlguidance", path: "Sources/CLlguidance", publicHeadersPath: "include",
      linkerSettings: [.unsafeFlags(["-L", llgDir + "/vendor/llg", "-lllguidance"])]),
    .target(name: "SLCore", dependencies: [
      "CLlguidance",
      .product(name: "Schicksal", package: "schicksal"),
      .product(name: "MLXLLM", package: "mlx-swift-lm"),
      .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
      .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
      .product(name: "Tokenizers", package: "swift-transformers"),
    ]),
    .executableTarget(name: "sl", dependencies: ["SLCore"]),
    .testTarget(name: "SLCoreTests", dependencies: ["SLCore"]),
  ],
  swiftLanguageModes: [.v5]
)
