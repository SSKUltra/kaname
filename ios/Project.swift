import ProjectDescription

// Tuist 4.x project manifest. Generated project/workspace are git-ignored;
// run `tuist generate` (or `make ios-gen`) to produce Kaname.xcworkspace.
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
            sources: ["Sources/**"]
            // P1: add the KanameCore.xcframework (UniFFI bindings over the Rust core)
            // here as a binary dependency.
        ),
        .target(
            name: "KanameTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "in.beaconbrain.kaname.tests",
            deploymentTargets: .iOS("18.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "Kaname")]
        ),
    ]
)
