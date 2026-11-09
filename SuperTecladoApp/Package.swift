// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Super Teclado",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .iOSApplication(
            name: "Super Teclado",
            targets: ["AppModule"],
            displayVersion: "2.9.7",
            bundleVersion: "39",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
