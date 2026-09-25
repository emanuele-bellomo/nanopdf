import AppKit
import CMuPDF
import UniformTypeIdentifiers

// AppDelegate — Handles application lifecycle, window creation, and PDF actions.
//
// Owns the MuPDFDocument and coordinates between the PDFContentView (UI) and
// the rendering engine. All navigation/zoom/darkmode actions are exposed as
// methods that the PDFContentView calls from its keyboard handler.

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    /// The custom content view that displays the PDF and handles keyboard input.
    var contentView: PDFContentView!

    /// The currently loaded MuPDF document (nil if nothing is open).
    var document: MuPDFDocument?

    /// Current zero-based page index.
    var currentPage: Int = 0

    /// Tracks the current rendering task to prevent out-of-order UI updates when scrolling fast.
    private var renderGeneration: Int = 0

    /// Current zoom level (1.0 = 72 DPI, fits the page at native resolution).
    var zoomLevel: Float = 1.0

    /// Whether dark mode (luminance inversion) is active.
    var darkModeEnabled: Bool = false

    /// File path to load once the window is ready (handles openFile: before launch).
    private var pendingFilePath: String?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --- Verify MuPDF linkage works ---
        if let ctx = nanopdf_new_context() {
            let version = String(cString: nanopdf_mupdf_version())
            print("✅ MuPDF loaded successfully — version \(version)")
            fz_drop_context(ctx)
        } else {
            print("❌ Failed to create MuPDF context")
        }

        // --- Create the main window ---
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
        window.title = "NanoPDF"
        window.center()
        window.setFrameAutosaveName("NanoPDFMainWindow")
        window.minSize = NSSize(width: 400, height: 300)

        // --- Create the PDF content view (Task 3.1) ---
        contentView = PDFContentView(frame: windowRect)
        contentView.appDelegate = self
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)

        // --- Set up menus ---
        setupMenuBar()

        NSApp.activate(ignoringOtherApps: true)

        // Load a PDF if one was requested (via CLI arg or openFile: before launch).
        if let pending = pendingFilePath {
            pendingFilePath = nil
            loadDocument(at: pending)
        } else if CommandLine.arguments.count > 1 {
            loadDocument(at: CommandLine.arguments[1])
        } else {
            // Restore previous state if no file was explicitly requested
            restoreState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }

    // Also support opening PDFs via Finder / drag-drop onto dock icon.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // openFile: can be called before applicationDidFinishLaunching.
        // If the window isn't ready yet, stash the path and load it later.
        if contentView != nil {
            loadDocument(at: filename)
        } else {
            pendingFilePath = filename
        }
        return true
    }

    // MARK: - State Restoration

    private func saveState() {
        guard let doc = document else { return }
        let prefs = UserDefaults.standard
        prefs.set(doc.filePath, forKey: "lastDocumentPath")
        prefs.set(currentPage, forKey: "lastPage")
        prefs.set(zoomLevel, forKey: "lastZoom")
        prefs.set(darkModeEnabled, forKey: "lastDarkMode")
    }

    private func restoreState() {
        let prefs = UserDefaults.standard
        guard let lastPath = prefs.string(forKey: "lastDocumentPath"),
              FileManager.default.fileExists(atPath: lastPath) else { return }
        
        // Restore preferences
        darkModeEnabled = prefs.bool(forKey: "lastDarkMode")
        let savedZoom = prefs.float(forKey: "lastZoom")
        zoomLevel = savedZoom > 0 ? savedZoom : 1.0
        
        let savedPage = prefs.integer(forKey: "lastPage")
        
        // Load the document (bypassing default reset)
        loadDocument(at: lastPath, restorePage: savedPage)
    }

    // MARK: - Document Loading

    /// Opens a PDF from the given file path using MuPDFDocument.
    func loadDocument(at path: String, restorePage: Int = 0) {
        // Release the previous document (if any).
        document = nil
        currentPage = restorePage

        guard let doc = MuPDFDocument(path: path) else {
            let alert = NSAlert()
            alert.messageText = "Failed to Open PDF"
            alert.informativeText = "Could not open the file at:\n\(path)"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        document = doc
        renderCurrentPage()
    }

    // MARK: - Rendering (Task 3.3: Retina-aware)

    /// Renders the current page at the current zoom level and dark mode setting.
    /// Accounts for the screen's backing scale factor for crisp Retina rendering.
    /// Performs MuPDF rendering on a background thread to prevent UI hangs.
    func renderCurrentPage() {
        guard let doc = document else { return }

        // Increment generation to discard any currently pending background renders
        renderGeneration += 1
        let currentGen = renderGeneration
        let targetPage = currentPage
        let targetZoom = zoomLevel
        let isDark = darkModeEnabled

        // Task 3.3: Factor in the screen's backing scale for Retina displays.
        let backingScale = Float(window?.screen?.backingScaleFactor
                                  ?? NSScreen.main?.backingScaleFactor ?? 1.0)
        let effectiveZoom = targetZoom * backingScale

        // Task 4.2: Move heavy MuPDF C rendering to a background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cgImage = doc.renderPage(number: targetPage,
                                                zoom: effectiveZoom,
                                                darkMode: isDark) else {
                DispatchQueue.main.async {
                    print("⚠️ AppDelegate: renderPage returned nil for page \(targetPage)")
                }
                return
            }

            // Create an NSImage at logical size (divided by backingScale).
            let logicalWidth  = CGFloat(cgImage.width) / CGFloat(backingScale)
            let logicalHeight = CGFloat(cgImage.height) / CGFloat(backingScale)
            let nsImage = NSImage(cgImage: cgImage,
                                  size: NSSize(width: logicalWidth, height: logicalHeight))

            // Switch back to the main thread to update the UI
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Only update if the user hasn't already switched to another page
                guard self.renderGeneration == currentGen else { return }

                self.contentView.imageView.image = nsImage

                // Update the window title with page info.
                let fileName = URL(fileURLWithPath: doc.filePath).lastPathComponent
                self.window.title = "NanoPDF — \(fileName) — Page \(targetPage + 1)/\(doc.pageCount)"

                // Set the window's represented URL for the proxy icon in the title bar.
                self.window.representedURL = URL(fileURLWithPath: doc.filePath)
            }
        }
    }

    // MARK: - Navigation Actions (called by PDFContentView)

    func goToNextPage() {
        guard let doc = document else { return }
        if currentPage < doc.pageCount - 1 {
            currentPage += 1
            renderCurrentPage()
        }
    }

    func goToPreviousPage() {
        guard document != nil else { return }
        if currentPage > 0 {
            currentPage -= 1
            renderCurrentPage()
        }
    }

    func jumpToPage(_ page: Int) {
        guard let doc = document, page >= 0, page < doc.pageCount else { return }
        currentPage = page
        renderCurrentPage()
    }

    // MARK: - Zoom Actions

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

    // MARK: - Dark Mode (Task 2.3 integration)

    func toggleDarkMode() {
        guard document != nil else { return }
        darkModeEnabled.toggle()
        renderCurrentPage()
        print(darkModeEnabled ? "🌙 Dark mode ON" : "☀️ Dark mode OFF")
    }

    // MARK: - Menu Bar (Task 3.5: Help menu entry)

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu (NanoPDF)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "NanoPDF")
        appMenu.addItem(withTitle: "About NanoPDF",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit NanoPDF",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(openDocument(_:)),
                         keyEquivalent: "o")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(menuZoomIn(_:)),
                         keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(menuZoomOut(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(menuResetZoom(_:)),
                         keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Dark Mode",
                         action: #selector(menuToggleDark(_:)),
                         keyEquivalent: "i")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Go menu
        let goMenuItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        goMenu.addItem(withTitle: "Next Page",
                       action: #selector(menuNextPage(_:)),
                       keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        goMenu.addItem(withTitle: "Previous Page",
                       action: #selector(menuPrevPage(_:)),
                       keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        goMenu.addItem(NSMenuItem.separator())
        let jumpItem = NSMenuItem(title: "Jump to Page…",
                                  action: #selector(menuJumpToPage(_:)),
                                  keyEquivalent: "g")
        jumpItem.keyEquivalentModifierMask = [.command]
        goMenu.addItem(jumpItem)
        goMenuItem.submenu = goMenu
        mainMenu.addItem(goMenuItem)

        // Help menu (Task 3.5: "NanoPDF Shortcuts" entry)
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "NanoPDF Shortcuts",
                         action: #selector(menuShowShortcuts(_:)),
                         keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func openDocument(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.loadDocument(at: url.path)
            }
        }
    }

    @objc private func menuNextPage(_ sender: Any) { goToNextPage() }
    @objc private func menuPrevPage(_ sender: Any) { goToPreviousPage() }
    @objc private func menuZoomIn(_ sender: Any)   { zoomIn() }
    @objc private func menuZoomOut(_ sender: Any)   { zoomOut() }
    @objc private func menuResetZoom(_ sender: Any) { resetZoom() }
    @objc private func menuToggleDark(_ sender: Any) { toggleDarkMode() }

    @objc private func menuJumpToPage(_ sender: Any) {
        contentView.showJumpToPage()
    }

    @objc private func menuShowShortcuts(_ sender: Any) {
        contentView.toggleHelpOverlay()
    }
}
