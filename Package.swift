// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PrimeSieve",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PrimeSieve", targets: ["PrimeSieveApp"]),
        .executable(name: "primesieve-cli", targets: ["PrimeSieveCLI"])
    ],
    targets: [
        .target(name: "PrimeSieveCore", resources: [.copy("Resources/Workers")]),
        .executableTarget(name: "PrimeSieveApp", dependencies: ["PrimeSieveCore"]),
        .executableTarget(name: "PrimeSieveCLI", dependencies: ["PrimeSieveCore"]),
        .testTarget(name: "PrimeSieveCoreTests", dependencies: ["PrimeSieveCore"]),
        .testTarget(name: "PrimeSieveAppTests", dependencies: ["PrimeSieveApp", "PrimeSieveCore"])
    ]
)
