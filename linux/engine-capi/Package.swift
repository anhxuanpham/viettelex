// swift-tools-version: 5.9
// libtelexcore — the TelexCore engine exported through a C ABI for the Linux
// frontends (Fcitx5 addon, IBus engine). See linux/docs/LINUX-SPEC.md §2.
//
// Sources/TelexCoreEngine holds SYMLINKS to ../../TelexCore/Sources/TelexCore/*.swift
// (every file except ClientPolicy.swift, the only one importing Foundation), so the
// Linux library compiles the exact engine the Mac/iOS apps ship — no fork, no copy —
// and stays Foundation-free (small, self-contained .so with --static-swift-stdlib).
// `scripts/check-engine-links.sh` fails the build when TelexCore gains a file that is
// not linked here.
//
// viettelex-text-tool — text tools for the selection (Thêm dấu, HOA, thường, …), run by
// the frontends as a CHILD PROCESS like macOS `VietTelex --add-tones`. Sources/TextToolCLI
// symlinks the shared iOS/Keyboard files (TextTools, AddTones + lexicon/LM — the same ones
// the macOS target compiles, see project.yml) and depends on the TelexCore package itself
// (AddTones/SwipeEnglish `import TelexCore`). It uses Foundation, which stays out of the
// engine .so and out of the IM processes.
//
// Build (Linux):  swift build -c release --static-swift-stdlib
//   → .build/release/libtelexcore.so   (C header: include/telexcore.h)
//   → .build/release/viettelex-text-tool
import PackageDescription

let package = Package(
    name: "TelexCoreCAPI",
    // TelexCore declares macOS 13 (only matters for `swift build` on a Mac).
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "telexcore", type: .dynamic, targets: ["TelexCoreC"]),
        .executable(name: "viettelex-text-tool", targets: ["TextToolCLI"]),
    ],
    dependencies: [
        .package(name: "TelexCore", path: "../../TelexCore"),
    ],
    targets: [
        .target(
            name: "TelexCoreEngine",
            path: "Sources/TelexCoreEngine"
        ),
        .target(
            name: "TelexCoreC",
            dependencies: ["TelexCoreEngine"],
            path: "Sources/TelexCoreC",
            linkerSettings: [
                // Export only the vt_* C ABI from the .so (Swift runtime stays private).
                .unsafeFlags(["-Xlinker", "--version-script=\(Context.packageDirectory)/exports.map"],
                             .when(platforms: [.linux])),
            ]
        ),
        .executableTarget(
            name: "TextToolCLI",
            dependencies: [.product(name: "TelexCore", package: "TelexCore")],
            path: "Sources/TextToolCLI",
            swiftSettings: [.define("VIETTELEX_CLI")],
            linkerSettings: [
                // Debian hardening (lintian hardening-no-relro / bindnow).
                .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "relro", "-Xlinker", "-z", "-Xlinker", "now"],
                             .when(platforms: [.linux])),
            ]
        ),
    ]
)
