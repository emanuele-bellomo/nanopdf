# NanoPDF Development Notes

## Documentation & Useful Links
- [official Swift book](https://docs.swift.org)
- [Hacking with Swift (macOS)](https://www.hackingwithswift.com)
- [Apple Developer Documentation](https://developer.apple.com/documentation)

---

## Task Progress Summary

### 1. 🛠️ Agent 1: The Build System & Environment Architect
**Status:** Completed ✅

*   **Task 1.1: Dependency Management**
    *   Verified Homebrew MuPDF installation at `/opt/homebrew/opt/mupdf`.
    *   Located header include path: `/opt/homebrew/opt/mupdf/include`
    *   Located library path: `/opt/homebrew/opt/mupdf/lib/libmupdf.dylib`

*   **Task 1.2: Xcode Project Setup**
    *   Created `Package.swift` using Swift Package Manager (SPM) for clean macOS app targeting and C library linkage.
    *   Configured `CMuPDF` system library target and `NanoPDF` executable target.
    *   Added linker settings (`-lmupdf`, rpath setup) targeting Homebrew lib paths.
    *   Created AppKit bootstrap files in `Sources/NanoPDF/` (`main.swift`, `AppDelegate.swift`).
    *   Removed initial SwiftUI/Playground template files (`MyApp.swift`, `ContentView.swift`).

*   **Task 1.3: Bridging Header**
    *   Created module map (`Sources/CMuPDF/module.modulemap`) exposing the C module `CMuPDF`.
    *   Created shim header (`Sources/CMuPDF/shim.h`) importing `<mupdf/fitz.h>` and `<mupdf/pdf.h>`.
    *   Added `static inline` C wrapper functions (`nanopdf_new_context`, `nanopdf_mupdf_version`, `nanopdf_scale`, `nanopdf_bound_page`, `nanopdf_device_rgb`) to wrap C preprocessor macros incompatible with direct Swift invocation.
    *   Verified build & runtime execution (`✅ MuPDF loaded successfully — version 1.28.4`).

---

### 2. 🧠 Agent 2: The Core Engine (C-Swift Interop) Developer
**Status:** Completed ✅

*   **Task 2.1: Context & Document Management**
    *   Created `MuPDFDocument` class (`Sources/NanoPDF/MuPDFDocument.swift`) wrapping the MuPDF C engine.
    *   `init?(path:)` — creates `fz_context` (via `nanopdf_new_context()`), registers document handlers, opens the PDF with `fz_open_document()`, and caches `pageCount`.
    *   Returns `nil` on failure (context creation failure or unopenable file), cleaning up any partially allocated resources.
    *   `deinit` — calls `fz_drop_document()` then `fz_drop_context()` for leak-free teardown via ARC.
    *   Uses typed Swift pointers (`UnsafeMutablePointer<fz_context>`, `UnsafeMutablePointer<fz_document>`) — not `OpaquePointer` — since Swift imports C struct pointers as typed pointers.

*   **Task 2.2: Page Rendering (The Core Logic)**
    *   Implemented `renderPage(number:zoom:darkMode:) -> CGImage?`.
    *   Pipeline: `fz_load_page` → `fz_new_pixmap_from_page` (convenience function that handles draw device creation internally) → pixel data copy → `CGDataProvider` → `CGImage`.
    *   `defer` blocks ensure `fz_drop_page` and `fz_drop_pixmap` always run, even on early exit.
    *   Pixel data is **copied** into a Swift-managed buffer so the `CGImage` is independent of MuPDF resources — this allows immediate deallocation of the pixmap.
    *   The `CGDataProvider` release callback frees the copied buffer when the `CGImage` is deallocated by ARC.
    *   Updated `AppDelegate` to wire up rendering: `loadDocument(at:)`, `renderCurrentPage()`, Retina-aware zoom (`backingScaleFactor`), page info in title bar, and CLI argument loading.

*   **Task 2.3: Dark Mode Implementation**
    *   Integrated into `renderPage()`: when `darkMode: true`, calls `fz_invert_pixmap_luminance()` on the pixmap before CGImage conversion.
    *   `fz_invert_pixmap_luminance` inverts luminance while preserving hue/saturation — superior to raw RGB inversion for colored content.
    *   Dark mode is toggled via `AppDelegate.darkModeEnabled` (Agent 3 will bind this to the `i` key).

*   **Verification:**
    *   Build: zero warnings, zero errors (`swift build -Xcc -I/opt/homebrew/opt/mupdf/include`).
    *   Runtime: successfully opened and rendered both a hand-crafted test PDF (2 pages) and a real-world PDF (`python-cheatsheet.pdf`, 3 pages).
    *   Output: `✅ MuPDF loaded successfully — version 1.28.4` + `📖 MuPDFDocument: Opened ... — N pages`.

---

### 3. 🖥️ Agent 3: The AppKit UI & UX Engineer
**Status:** Completed ✅

*   **Task 3.1: The Viewport**
    *   Created a custom `NSView` subclass named `PDFContentView` (`Sources/NanoPDF/PDFContentView.swift`).
    *   Configured an `NSImageView` inside it with `.scaleProportionallyUpOrDown` scaling to display the rendered `CGImage`.
    *   Assigned `PDFContentView` as the main window's `contentView`.

*   **Task 3.2: Keyboard Event Handling**
    *   Overrode `keyDown(with:)` and `performKeyEquivalent(with:)` in `PDFContentView`.
    *   Implemented navigation mappings: Space, Right/Down Arrows, and Vim `j`/`l` for Next Page; Left/Up Arrows, and Vim `h`/`k` for Previous Page.
    *   Implemented zoom mappings: `+`/`=` (In), `-` (Out), and `0` (Reset).
    *   Mapped `i` to toggle dark mode.
    *   Key events trigger corresponding actions exposed in `AppDelegate` (`goToNextPage()`, `zoomIn()`, etc.).

*   **Task 3.3: Retina Display Optimization**
    *   Updated `renderCurrentPage()` in `AppDelegate` to capture the window's `backingScaleFactor`.
    *   Passed `effectiveZoom` (zoom * scale factor) to the renderer to generate a crisp 2x image.
    *   Instantiated the final `NSImage` at the logical (1x) size so macOS renders it flawlessly on Retina displays.

*   **Task 3.4: Jump to Page (`Cmd + G`)**
    *   Added a hidden `NSTextField` overlay centered at the top of the viewport.
    *   Triggered by `Cmd + G`.
    *   Implemented `NSTextFieldDelegate` to parse 1-based page input on `Enter`, convert to a 0-based index, and command `AppDelegate` to switch pages. `Escape` cancels the prompt.

*   **Task 3.5: Discoverable Shortcuts & Hardware Guide**
    *   Created an `NSVisualEffectView` overlay acting as a shortcut cheatsheet.
    *   Accessible via three methods: Native Menu Bar ("Help" -> "NanoPDF Shortcuts"), Floating `?` button (bottom right), and the `?` hotkey.

*   **Verification:**
    *   Resolved a race condition where `application(_:openFile:)` crashed if called before `applicationDidFinishLaunching` (by deferring CLI loading).
    *   Build succeeded cleanly.
    *   Successfully rendered large PDFs (e.g., 528 pages) with full keyboard navigation and UI overlay functionality.

---

### 4. 🕵️ Agent 4: The Profiling & QA Specialist
**Status:** Completed ✅

*   **Task 4.1: Memory Auditing**
    *   Conducted rigorous code review on the memory model and verified actual runtime footprint behavior.
    *   Discovered and patched a semantic memory deallocation flaw in `MuPDFDocument.swift`: `CGDataProvider`'s `releaseData` callback previously attempted to `deinitialize(count: 1)` on a dynamically sized pixel buffer. Corrected it to cleanly `deallocate()` the entire allocated `UnsafeMutablePointer<UInt8>` block to guarantee no gradual memory leaks.
    *   Confirmed memory footprint stays remarkably flat over extended usage sessions.

*   **Task 4.2: CPU & Threading**
    *   Refactored `renderCurrentPage()` in `AppDelegate.swift` to offload heavy `libmupdf` C-engine page generation tasks to `DispatchQueue.global(qos: .userInitiated)`.
    *   Ensured UI stays 100% responsive during rapid page turns, eliminating main-thread hanging.
    *   Implemented a `renderGeneration` tracking mechanism. When users scroll through pages incredibly quickly, intermediate (older) background render tasks are safely discarded when they finish, preventing out-of-order frames from overriding the target page view on the main thread.
