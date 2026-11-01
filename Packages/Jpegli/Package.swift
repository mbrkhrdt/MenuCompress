// swift-tools-version: 5.9
import PackageDescription

// jpegli (google/jpegli) as a prebuilt static library, behind a tiny C API that Swift can call.
// Rebuild the library and vendored headers with build-jpegli.sh.
let package = Package(
    name: "Jpegli",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CJpegli", targets: ["CJpegli"]),
    ],
    targets: [
        .binaryTarget(name: "JpegliLibrary", path: "Jpegli.xcframework"),
        .target(
            name: "CJpegli",
            dependencies: ["JpegliLibrary"],
            cxxSettings: [.headerSearchPath("vendor")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
