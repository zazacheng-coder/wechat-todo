// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WeChatTodo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WeChatTodo", targets: ["WeChatTodo"])
    ],
    targets: [
        .executableTarget(
            name: "WeChatTodo",
            path: "Sources/WeChatTodo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
