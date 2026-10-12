import AppKit
import CMuPDF
import UniformTypeIdentifiers

// AppDelegate — Thin application coordinator for NanoPDF.
//
// Manages the collection of PDFWindowControllers (one per tab), sets up the
// global menu bar, and routes menu actions to whichever tab is currently active.
// Per-tab state (document, page, zoom, dark mode, rendering) lives entirely in
// PDFWindowController.

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Tab Registry

    private var windowControllers: [PDFWindowController] = []

    /// The controller for the window that currently has main/key focus.
    var activeController: PDFWindowController? {
        if let main = NSApp.mainWindow {
            return windowControllers.first { $0.window === main }
        }
        return windowControllers.first
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Verify MuPDF linkage.
        if let ctx = nanopdf_new_context() {
            let version = String(cString: nanopdf_mupdf_version())
            print("✅ MuPDF loaded — version \(version)")
            fz_drop_context(ctx)
        } else {
            print("❌ Failed to create MuPDF context")
        }

        // Set app icon.
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        } else if let localIcon = NSImage(contentsOfFile: "AppIcon.icns")
                                  ?? NSImage(contentsOfFile: "img/logo.png") {
            NSApp.applicationIconImage = localIcon
        }

        // Build the menu bar before creating any windows.
        setupMenuBar()

        // Create the first tab.
        let first = makeWindowController()
        first.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Load a file if one was passed via CLI or Finder before launch.
        if CommandLine.arguments.count > 1 {
            first.loadDocument(at: CommandLine.arguments[1])
        } else {
            restoreState(into: first)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }

    /// Finder double-click / Dock drag-drop (single file).
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if let active = activeController, active.document == nil {
            active.loadDocument(at: filename)
        } else {
            openNewTab(withFile: filename)
        }
        return true
    }

    /// Finder / Dock drag-drop (multiple files).
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for (i, path) in filenames.enumerated() {
            if i == 0, let active = activeController, active.document == nil {
                active.loadDocument(at: path)
            } else {
                openNewTab(withFile: path)
            }
        }
    }

    // MARK: - State Restoration

    private func saveState() {
        guard let wc = activeController ?? windowControllers.first,
              let doc = wc.document else { return }
        let p = UserDefaults.standard
        p.set(doc.filePath, forKey: "lastDocumentPath")
        p.set(wc.currentPage,     forKey: "lastPage")
        p.set(wc.zoomLevel,       forKey: "lastZoom")
        p.set(wc.darkModeEnabled, forKey: "lastDarkMode")
    }

    private func restoreState(into wc: PDFWindowController) {
        let p = UserDefaults.standard
        guard let path = p.string(forKey: "lastDocumentPath"),
              FileManager.default.fileExists(atPath: path) else { return }
        wc.darkModeEnabled = p.bool(forKey: "lastDarkMode")
        let savedZoom = p.float(forKey: "lastZoom")
        wc.zoomLevel = savedZoom > 0 ? savedZoom : 1.0
        wc.loadDocument(at: path, restorePage: p.integer(forKey: "lastPage"))
    }

    // MARK: - Tab Management

    /// Create a new PDFWindowController, register it, and return it.
    @discardableResult
    func makeWindowController() -> PDFWindowController {
        let wc = PDFWindowController()
        wc.appDelegate = self
        wc.setup()
        windowControllers.append(wc)
        return wc
    }

    /// Create a new tab and attach it to the current window's tab group.
    @discardableResult
    func openNewTab() -> PDFWindowController {
        let wc = makeWindowController()
        // addTabbedWindow joins the new window into the existing tab bar.
        if let existing = NSApp.keyWindow ?? windowControllers.first?.window {
            existing.addTabbedWindow(wc.window, ordered: .above)
        }
        wc.window.makeKeyAndOrderFront(nil)
        return wc
    }

    /// Create a new tab and immediately load a PDF into it.
    @discardableResult
    func openNewTab(withFile path: String) -> PDFWindowController {
        let wc = openNewTab()
        wc.loadDocument(at: path)
        return wc
    }

    func removeWindowController(_ wc: PDFWindowController) {
        windowControllers.removeAll { $0 === wc }
    }

    /// Called by the system when the user clicks the "+" button in the tab bar
    /// or uses the system "New Tab" keyboard shortcut.
    @objc func newWindowForTab(_ sender: Any?) {
        openNewTab()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // ── App ────────────────────────────────────────────────────────────
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "NanoPDF")
        appMenu.addItem(withTitle: "About NanoPDF",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit NanoPDF",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // ── File ───────────────────────────────────────────────────────────
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(menuOpen(_:)),
                         keyEquivalent: "o")
        let newTabItem = NSMenuItem(title: "New Tab",
                                    action: #selector(menuNewTab(_:)),
                                    keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(newTabItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ── View ───────────────────────────────────────────────────────────
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let zoomInItem = NSMenuItem(title: "Zoom In",
                                    action: #selector(menuZoomIn(_:)),
                                    keyEquivalent: "+")
        zoomInItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out",
                                     action: #selector(menuZoomOut(_:)),
                                     keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomOutItem)

        let actualSizeItem = NSMenuItem(title: "Actual Size",
                                        action: #selector(menuResetZoom(_:)),
                                        keyEquivalent: "0")
        actualSizeItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(actualSizeItem)

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Dark Mode",
                         action: #selector(menuToggleDark(_:)),
                         keyEquivalent: "i")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // ── Go ─────────────────────────────────────────────────────────────
        let goMenuItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        // No arrow key equivalents here — handled in PDFContentView.performKeyEquivalent.
        goMenu.addItem(withTitle: "Next Page",
                       action: #selector(menuNextPage(_:)),
                       keyEquivalent: "")
        goMenu.addItem(withTitle: "Previous Page",
                       action: #selector(menuPrevPage(_:)),
                       keyEquivalent: "")
        goMenu.addItem(.separator())
        let jumpItem = NSMenuItem(title: "Jump to Page…",
                                  action: #selector(menuJumpToPage(_:)),
                                  keyEquivalent: "g")
        jumpItem.keyEquivalentModifierMask = [.command]
        goMenu.addItem(jumpItem)
        goMenuItem.submenu = goMenu
        mainMenu.addItem(goMenuItem)

        // ── Window ─────────────────────────────────────────────────────────
        // Registering a Window menu enables the system tab bar controls
        // (next/previous tab, merge all windows) automatically.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Select Next Tab",
                           action: #selector(NSWindow.selectNextTab(_:)),
                           keyEquivalent: "\t")  // Ctrl+Tab handled by system
        windowMenu.addItem(withTitle: "Select Previous Tab",
                           action: #selector(NSWindow.selectPreviousTab(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Merge All Windows",
                           action: #selector(NSWindow.mergeAllWindows(_:)),
                           keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu       // lets macOS manage window list entries
        mainMenu.addItem(windowMenuItem)

        // ── Help ───────────────────────────────────────────────────────────
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "NanoPDF Shortcuts",
                         action: #selector(menuShowShortcuts(_:)),
                         keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions (all routed to the active tab)

    @objc private func menuOpen(_ sender: Any)           { activeController?.showOpenPanel() }
    @objc private func menuNewTab(_ sender: Any)          { openNewTab() }
    @objc private func menuNextPage(_ sender: Any)        { activeController?.goToNextPage() }
    @objc private func menuPrevPage(_ sender: Any)        { activeController?.goToPreviousPage() }
    @objc private func menuZoomIn(_ sender: Any)          { activeController?.zoomIn() }
    @objc private func menuZoomOut(_ sender: Any)         { activeController?.zoomOut() }
    @objc private func menuResetZoom(_ sender: Any)       { activeController?.resetZoom() }
    @objc private func menuToggleDark(_ sender: Any)      { activeController?.toggleDarkMode() }

    @objc private func menuJumpToPage(_ sender: Any) {
        activeController?.contentView.showJumpToPage()
    }

    @objc private func menuShowShortcuts(_ sender: Any) {
        activeController?.contentView.toggleHelpOverlay()
    }
}
