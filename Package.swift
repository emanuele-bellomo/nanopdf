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
        .target(
            name: "CMuPDF",
            path: "Sources/CMuPDF",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/mupdf/include"])
            ]
        ),

        // The main macOS application target.
        .executableTarget(
            name: "NanoPDF",
            dependencies: ["CMuPDF"],
            path: "Sources/NanoPDF",
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])
            ],
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
