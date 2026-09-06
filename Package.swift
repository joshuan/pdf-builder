// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PDFBuilder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PDFBuilderCore", targets: ["PDFBuilderCore"]),
        .executable(name: "PDFBuilder", targets: ["PDFBuilder"])
    ],
    targets: [
        .target(
            name: "PDFBuilderCore",
            path: "Sources/PDFBuilderCore"
        ),
        .executableTarget(
            name: "PDFBuilder",
            dependencies: ["PDFBuilderCore"],
            path: "Sources/PDFBuilder"
        ),
        .executableTarget(
            name: "PDFBuilderCoreChecks",
            dependencies: ["PDFBuilderCore"],
            path: "Tests/PDFBuilderCoreChecks"
        )
    ]
)
