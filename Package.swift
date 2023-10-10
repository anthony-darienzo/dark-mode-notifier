// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "dark-mode-notifier",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "http://github.com/jdfergason/swift-toml", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/ianpartridge/swift-log-syslog.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", .upToNextMajor(from: "0.2.2")),
        .package(url: "https://github.com/Adorkable/swift-log-format-and-pipe", .upToNextMajor(from: "0.1.1")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "dark-mode-notifier",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LoggingOSLog", package: "swift-log-oslog"),
                .product(name: "LoggingFormatAndPipe", package: "swift-log-format-and-pipe"),
                .product(name: "Toml", package: "swift-toml"),
            ]
        ),
    ]
)
