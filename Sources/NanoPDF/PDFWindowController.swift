import AppKit
import CMuPDF
import UniformTypeIdentifiers

// PDFWindowController — Owns a single tab/window in NanoPDF.
//
// Encapsulates all per-tab state: the NSWindow, PDFContentView, MuPDFDocument,
// current page, zoom level and dark-mode flag.
//
// Low-memory model (SumatraPDF-style):
//   • Background tab  → only the lightweight fz_document pointer is kept alive.
//     The rendered pixel buffer (NSImage) is dropped when the window loses main status.
//   • Foreground tab  → one page is rendered and displayed.
//     The previous page's image is released immediately upon page turn.

final class PDFWindowController: NSObject {

    // MARK: - Window & View

    private(set) var window: NSWindow!
    private(set) var contentView: PDFContentView!

    // MARK: - Document State

    var document: MuPDFDocument?
    var currentPage: Int = 0
    var zoomLevel: Float = 1.0
    var darkModeEnabled: Bool = false

    /// Monotonic counter used to discard stale background renders.
    private var renderGeneration: Int = 0

    /// Back-reference to the app delegate (for tab management).
    weak var appDelegate: AppDelegate?

    // MARK: - Setup

    func setup() {
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let windowRect = NSRect(
            x: screenRect.midX - 400,
            y: screenRect.midY - 350,
            width: 800,
            height: 700
        )

        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "NanoPDF"
        window.center()
        // Enable native macOS tabbing — the system provides the tab bar automatically.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NanoPDFTabGroup"
        window.delegate = self

        contentView = PDFContentView(frame: windowRect)
        contentView.windowController = self
        window.contentView = contentView
        window.makeFirstResponder(contentView)
    }

    // MARK: - Document Loading

    func loadDocument(at path: String, restorePage: Int = 0) {
        document = nil
        currentPage = restorePage

        guard let doc = MuPDFDocument(path: path) else {
            let alert = NSAlert()
            alert.messageText = "Failed to Open PDF"
            alert.informativeText = "Could not open:\n\(path)"
            alert.alertStyle = .warning
            if let w = window {
                alert.beginSheetModal(for: w, completionHandler: nil)
            }
            return
        }

        document = doc

        // Set the title immediately so the tab bar shows the filename even
        // before the background render completes. The render callback will
        // overwrite with the more detailed "Page X/Y" title.
        let name = URL(fileURLWithPath: path).lastPathComponent
        window.title = "NanoPDF — \(name)"
        window.representedURL = URL(fileURLWithPath: path)

        renderCurrentPage()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        // Use app-modal (runModal) instead of sheet-modal. Sheet-modal panels
        // create ghost tabs and stuck Cancel buttons when new windows/tabs are
        // spawned from inside the completion handler.
        let response = panel.runModal()
        guard response == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        // First file: load into this tab if it has no document yet.
        let first = urls[0]
        if document == nil {
            loadDocument(at: first.path)
        } else {
            appDelegate?.openNewTab(withFile: first.path)
        }

        // Every additional file gets its own new tab.
        for url in urls.dropFirst() {
            appDelegate?.openNewTab(withFile: url.path)
        }
    }

    // MARK: - Rendering

    func renderCurrentPage() {
        guard let doc = document else { return }

        renderGeneration += 1
        let gen = renderGeneration
        let page = currentPage
        let zoom = zoomLevel
        let dark = darkModeEnabled
        let scale = Float(window?.screen?.backingScaleFactor
                          ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        let effectiveZoom = zoom * scale

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // MuPDF's fz_context is NOT thread-safe. Each background render
            // must use its own cloned context to avoid concurrent access
            // crashes inside libmupdf (e.g. in fz_free / freetype).
            guard let cgImage = doc.renderPageThreadSafe(
                number: page, zoom: effectiveZoom, darkMode: dark
            ) else {
                return
            }

            let logW = CGFloat(cgImage.width)  / CGFloat(scale)
            let logH = CGFloat(cgImage.height) / CGFloat(scale)
            let nsImage = NSImage(cgImage: cgImage,
                                  size: NSSize(width: logW, height: logH))

            DispatchQueue.main.async {
                guard let self = self, self.renderGeneration == gen else { return }
                self.contentView.setPageImage(nsImage)
                let name = URL(fileURLWithPath: doc.filePath).lastPathComponent
                self.window.title = "NanoPDF — \(name) — Page \(page + 1)/\(doc.pageCount)"
                self.window.representedURL = URL(fileURLWithPath: doc.filePath)
            }
        }
    }

    // MARK: - Navigation

    func goToNextPage() {
        guard let doc = document, currentPage < doc.pageCount - 1 else { return }
        currentPage += 1
        renderCurrentPage()
    }

    func goToPreviousPage() {
        guard document != nil, currentPage > 0 else { return }
        currentPage -= 1
        renderCurrentPage()
    }

    func jumpToPage(_ page: Int) {
        guard let doc = document, page >= 0, page < doc.pageCount else { return }
        currentPage = page
        renderCurrentPage()
    }

    // MARK: - Zoom

    func zoomIn() {
        guard document != nil else { return }
        zoomLevel = min(zoomLevel + 0.25, 5.0)
        renderCurrentPage()
    }

    func zoomOut() {
        guard document != nil else { return }
        zoomLevel = max(zoomLevel - 0.25, 0.25)
        renderCurrentPage()
    }

    func resetZoom() {
        guard document != nil else { return }
        zoomLevel = 1.0
        renderCurrentPage()
    }

    // MARK: - Dark Mode

    func toggleDarkMode() {
        guard document != nil else { return }
        darkModeEnabled.toggle()
        renderCurrentPage()
    }
}

// MARK: - NSWindowDelegate

extension PDFWindowController: NSWindowDelegate {

    /// Tab became active → re-render if the pixel buffer was dropped in background.
    func windowDidBecomeMain(_ notification: Notification) {
        window.makeFirstResponder(contentView)
        if document != nil && contentView.imageView.image == nil {
            renderCurrentPage()
        }
    }

    /// Tab went to background → cancel in-flight renders and drop the pixel buffer.
    /// The fz_document pointer (document) stays alive — it's a few KB at most.
    func windowDidResignMain(_ notification: Notification) {
        // Bump generation so any in-flight background render is silently discarded.
        renderGeneration += 1
        // Drop the pixel buffer on the next run-loop tick to avoid flashing
        // during the tab-switch animation.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, NSApp.mainWindow !== self.window else { return }
            self.contentView.imageView.image = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Immediately cancel any in-flight background renders so the closure
        // can't call back into a half-torn-down controller.
        renderGeneration += 1

        // Drop the MuPDF document synchronously — its fz_context and fz_document
        // contain C pointers that must be freed while the object is still valid.
        document = nil

        // Sever the delegate link so macOS doesn't send further notifications
        // to a deallocating controller.
        window.delegate = nil

        // Defer removal from the registry so the controller stays alive until
        // after windowWillClose returns (ARC won't dealloc mid-method).
        let ref = self
        DispatchQueue.main.async {
            ref.appDelegate?.removeWindowController(ref)
        }
    }
}
