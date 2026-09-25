import AppKit

// NanoPDF — Minimalist macOS PDF reader powered by MuPDF.
//
// This is the application entry point. We use a traditional AppKit lifecycle
// (NSApplication + NSApplicationDelegate) instead of SwiftUI's App protocol
// because we need fine-grained control over NSWindow, keyboard events,
// and the MuPDF C engine integration.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
