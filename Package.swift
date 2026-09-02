// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PokeBattleBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeBattleBar",
            path: "Sources/PokeBattleBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
