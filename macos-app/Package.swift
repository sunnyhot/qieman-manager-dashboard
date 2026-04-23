// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QiemanDashboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QiemanDashboard",
            path: ".",
            exclude: ["Package.swift"]
        )
    ]
)
