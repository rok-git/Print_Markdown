// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PrintMarkdown",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "print-markdown", targets: ["PrintMarkdown"])
    ],
    targets: [
        .executableTarget(name: "PrintMarkdown")
    ]
)
