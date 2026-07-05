import ProjectDescription

// Tuist 4.x project manifest. Generated project/workspace are git-ignored;
// run `tuist generate` (or `make ios-gen`) to produce Kaname.xcworkspace.
//
// The Rust engine is consumed through the `KanameCore` framework target, whose sole
// source is the UniFFI-generated `Generated/kaname_core.swift`; it links the prebuilt
// `Frameworks/KanameCoreFFI.xcframework` (built by `make core-xcframework`). Both the
// generated Swift and the xcframework are git-ignored build artifacts.
let project = Project(
    name: "Kaname",
    targets: [
        .target(
            name: "Kaname",
            destinations: .iOS,
            product: .app,
            bundleId: "in.beaconbrain.kaname",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Kaname",
                "UILaunchScreen": [:],
            ]),
            sources: ["Sources/**"],
            dependencies: [.target(name: "KanameCore")]
        ),
        .target(
            name: "KanameCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "in.beaconbrain.kaname.core",
            deploymentTargets: .iOS("18.0"),
            sources: ["Generated/**"],
            dependencies: [
                .xcframework(path: "Frameworks/KanameCoreFFI.xcframework"),
            ]
        ),
        .target(
            name: "KanameTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "in.beaconbrain.kaname.tests",
            deploymentTargets: .iOS("18.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Kaname"),
                .target(name: "KanameCore"),
            ]
        ),
    ]
)
