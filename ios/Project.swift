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
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Kaname",
                "UILaunchScreen": [:],
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "KanameCore"),
                // Statement text extraction is a platform concern (Constitution II): PDFKit
                // is the only PDF engine, and the Rust core never opens a document.
                .sdk(name: "PDFKit", type: .framework),
            ]
        ),
        .target(
            name: "KanameCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "in.beaconbrain.kaname.core",
            deploymentTargets: .iOS("26.0"),
            sources: ["Generated/**"],
            dependencies: [
                .xcframework(path: "Frameworks/KanameCoreFFI.xcframework"),
                // The Rust core's SQLCipher is built with the CommonCrypto backend on
                // Apple (SQLCIPHER_CRYPTO_CC), so the final link needs Security +
                // CoreFoundation. No OpenSSL is linked (Constitution I).
                .sdk(name: "Security", type: .framework),
                .sdk(name: "CoreFoundation", type: .framework),
            ]
        ),
        .target(
            name: "KanameTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "in.beaconbrain.kaname.tests",
            deploymentTargets: .iOS("26.0"),
            sources: ["Tests/**"],
            // The geometry vectors are data, not code: `GeometryFixtureTests` renders each
            // one into a real PDF at test time, so they have to reach the simulator's test
            // bundle. A folder reference keeps them as `geometry/*.json` inside it, which
            // is how `GeometryFixtureLoader` finds them without colliding with any other
            // resource.
            resources: [.folderReference(path: "../fixtures/geometry")],
            dependencies: [
                .target(name: "Kaname"),
                .target(name: "KanameCore"),
            ]
        ),
        .target(
            name: "KanameUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "in.beaconbrain.kaname.uitests",
            deploymentTargets: .iOS("26.0"),
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "Kaname")
            ]
        ),
    ]
)
