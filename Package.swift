// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NanoPDF",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // System library target that wraps MuPDF's C headers.
        // This creates a Swift-importable module called "CMuPDF".
        .systemLibrary(
            name: "CMuPDF",
            pkgConfig: nil,
            providers: [
                .brew(["mupdf"])
            ]
        ),

        // The main macOS application target.
        .executableTarget(
            name: "NanoPDF",
            dependencies: ["CMuPDF"],
            path: "Sources/NanoPDF",
            linkerSettings: [
                // Link the MuPDF dynamic library from Homebrew.
                .unsafeFlags([
                    "-L/opt/homebrew/opt/mupdf/lib",
                    "-lmupdf",
                    // rpath so the dylib is found at runtime
                    "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/opt/mupdf/lib",
                ]),
            ]
        ),
    ]
)
