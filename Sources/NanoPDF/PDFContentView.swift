import AppKit

// PDFContentView — The main viewport for NanoPDF.
//
// A custom NSView that hosts the rendered PDF page image and handles all
// keyboard input. It is the first responder for the window, routing key
// events to the AppDelegate for page navigation, zoom, and dark mode.
//
// Trackpad zoom is implemented with a two-phase approach for smooth feel:
//   1. During gesture (.changed): GPU-accelerated CALayer scale transform for
//      instant, zero-cost visual feedback — no MuPDF re-render.
//   2. On gesture end (.ended): commit the new zoom level and trigger a single
//      MuPDF re-rasterization at the correct DPI.

// MARK: - CenteredClipView

/// NSClipView subclass that centers the document view when it is smaller
/// than the visible area — standard macOS pattern for PDF/image viewers.
private class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docFrame = doc.frame

        if rect.width > docFrame.width {
            rect.origin.x = floor((docFrame.width - rect.width) / 2)
        }
        if rect.height > docFrame.height {
            rect.origin.y = floor((docFrame.height - rect.height) / 2)
        }
        return rect
    }
}

// MARK: - PDFContentView

class PDFContentView: NSView {

    // MARK: - Subviews

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// Displays the rendered PDF page CGImage.
    /// wantsLayer = true is required for smooth CALayer transforms during pinch.
    let imageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleNone   // Frame is managed manually to match render size
        iv.imageAlignment = .alignCenter
        iv.wantsLayer = true           // Enables GPU-accelerated layer transforms
        iv.translatesAutoresizingMaskIntoConstraints = true  // frame-based layout
        return iv
    }()

    /// Semi-transparent help button pinned to the bottom-right corner.
    private let helpButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.image = NSImage(systemSymbolName: "questionmark.circle",
                            accessibilityDescription: "Keyboard Shortcuts")
        btn.imageScaling = .scaleProportionallyUpOrDown
        btn.isBordered = false
        btn.alphaValue = 0.4
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.toolTip = "Keyboard Shortcuts (?)"
        return btn
    }()

    /// The Jump-to-Page text field overlay.
    private let jumpField: NSTextField = {
        let tf = NSTextField()
        tf.placeholderString = "Go to page…"
        tf.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        tf.alignment = .center
        tf.bezelStyle = .roundedBezel
        tf.focusRingType = .none
        tf.isHidden = true
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    /// The shortcuts/help overlay.
    private let helpOverlay: NSVisualEffectView = {
        let vev = NSVisualEffectView()
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        vev.wantsLayer = true
        vev.layer?.cornerRadius = 14
        vev.isHidden = true
        vev.translatesAutoresizingMaskIntoConstraints = false
        return vev
    }()

    /// Back-reference to the per-tab controller for triggering navigation/zoom actions.
    weak var windowController: PDFWindowController?

    // MARK: - Pinch gesture state

    /// Zoom level captured at gesture start — used to compute the final level.
    private var pinchStartZoom: Float = 1.0
    /// Cumulative visual scale factor accumulated during the current gesture.
    private var pinchScale: CGFloat = 1.0

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        // Replace NSScrollView's default clip view with the centered variant.
        let clip = CenteredClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip

        // Set imageView as the document view ONCE — never re-assign later.
        scrollView.documentView = imageView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Help button — bottom-right corner
        helpButton.target = self
        helpButton.action = #selector(toggleHelpOverlay)
        addSubview(helpButton)
        NSLayoutConstraint.activate([
            helpButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            helpButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            helpButton.widthAnchor.constraint(equalToConstant: 28),
            helpButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Jump-to-Page field
        jumpField.delegate = self
        addSubview(jumpField)
        NSLayoutConstraint.activate([
            jumpField.centerXAnchor.constraint(equalTo: centerXAnchor),
            jumpField.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            jumpField.widthAnchor.constraint(equalToConstant: 180),
            jumpField.heightAnchor.constraint(equalToConstant: 30),
        ])

        // Help overlay
        addSubview(helpOverlay)
        setupHelpContent()
        NSLayoutConstraint.activate([
            helpOverlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            helpOverlay.centerYAnchor.constraint(equalTo: centerYAnchor),
            helpOverlay.widthAnchor.constraint(equalToConstant: 420),
            helpOverlay.heightAnchor.constraint(equalToConstant: 400),
        ])
    }

    // MARK: - Image Update

    /// Called by AppDelegate after each MuPDF render completes.
    /// Sets the image and sizes the document view to match so the scroll
    /// view knows its scrollable extent. Never re-assigns documentView.
    func setPageImage(_ image: NSImage) {
        // 1. Capture the visible center as a fraction of the CURRENT document
        //    BEFORE we change the frame. clipBounds in AppKit/NSScrollView gives
        //    the scroll origin, so midX/midY is the center of the visible area
        //    in document coordinates. Dividing by the old doc size normalizes it.
        let clipBounds = scrollView.contentView.bounds
        let oldDocSize = imageView.frame.size
        let focalX: CGFloat = oldDocSize.width  > 0 ? max(0, min(1, clipBounds.midX / oldDocSize.width))  : 0.5
        let focalY: CGFloat = oldDocSize.height > 0 ? max(0, min(1, clipBounds.midY / oldDocSize.height)) : 0.5

        // 2. Atomically clear the pinch layer transform and swap the image.
        //    Single CATransaction = zero intermediate frames = no flash.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.layer?.setAffineTransform(.identity)
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.size)
        CATransaction.commit()

        // 3. Tell the scroll view the content size changed.
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // 4. Re-position the scroll so the same fraction of the document is
        //    visible in the center. Only needed when the document is larger
        //    than the viewport; CenteredClipView handles the smaller case.
        let newDocSize = image.size
        let clipSize = scrollView.contentView.frame.size
        if newDocSize.width > clipSize.width || newDocSize.height > clipSize.height {
            let targetX = focalX * newDocSize.width  - clipSize.width  / 2
            let targetY = focalY * newDocSize.height - clipSize.height / 2
            let scrollX = max(0, min(newDocSize.width  - clipSize.width,  targetX))
            let scrollY = max(0, min(newDocSize.height - clipSize.height, targetY))
            scrollView.contentView.scroll(to: NSPoint(x: scrollX, y: scrollY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Help Overlay Content

    private func setupHelpContent() {
        let lines: [(String, String)] = [
            ("→  /  ↓  /  Space", "Next Page"),
            ("←  /  ↑", "Previous Page"),
            ("⌘+  /  ⌘=", "Zoom In"),
            ("⌘-", "Zoom Out"),
            ("⌘0", "Reset Zoom"),
            ("Pinch  /  Scroll", "Zoom & Pan"),
            ("i", "Toggle Dark Mode"),
            ("⌘G", "Jump to Page"),
            ("⌘O", "Open PDF"),
            ("?", "Toggle This Guide"),
            ("⌘Q", "Quit"),
        ]

        let title = NSTextField(labelWithString: "NanoPDF — Keyboard Shortcuts")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "Single-page PDF reader · Ultra-low memory footprint")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (key, desc) in lines {
            stack.addArrangedSubview(createShortcutRow(key: key, description: desc))
        }

        helpOverlay.addSubview(title)
        helpOverlay.addSubview(subtitle)
        helpOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: helpOverlay.topAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: helpOverlay.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.centerXAnchor.constraint(equalTo: helpOverlay.centerXAnchor),

            stack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: helpOverlay.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: helpOverlay.trailingAnchor, constant: -30),
        ])
    }

    private func createShortcutRow(key: String, description: String) -> NSView {
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        keyLabel.textColor = .labelColor
        keyLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .right
        descLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [keyLabel, descLabel])
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return row
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    // MARK: - Keyboard Event Handling

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        // ⌘G — Jump to Page
        if chars == "g" && modifiers.contains(.command) {
            showJumpToPage()
            return
        }

        // Arrow keys — macOS sets .function and .numericPad on arrow events.
        if modifiers.subtracting([.shift, .function, .numericPad]).isEmpty {
            switch event.keyCode {
            case 124, 125:
                windowController?.goToNextPage(); return
            case 123, 126:
                windowController?.goToPreviousPage(); return
            default:
                break
            }
        }

        let hasNonShiftModifiers = !modifiers.subtracting(.shift).isEmpty
        if hasNonShiftModifiers {
            super.keyDown(with: event)
            return
        }

        switch chars {
        case " ":   windowController?.goToNextPage()
        case "i":   windowController?.toggleDarkMode()
        case "?":   toggleHelpOverlay()
        default:    super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if chars == "g" && modifiers.contains(.command) {
            showJumpToPage(); return true
        }
        if modifiers.contains(.command) && (chars == "+" || chars == "=") {
            windowController?.zoomIn(); return true
        }
        if modifiers.contains(.command) && chars == "-" {
            windowController?.zoomOut(); return true
        }
        if modifiers.contains(.command) && chars == "0" {
            windowController?.resetZoom(); return true
        }

        // Arrow keys
        if modifiers.subtracting([.shift, .function, .numericPad]).isEmpty {
            switch event.keyCode {
            case 124, 125:
                windowController?.goToNextPage(); return true
            case 123, 126:
                windowController?.goToPreviousPage(); return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Trackpad Gestures

    /// Pinch-to-zoom — smooth two-phase approach:
    ///   .began/.changed → instant GPU layer transform, zero CPU cost
    ///   .ended          → commit zoom level, one MuPDF re-render
    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            pinchStartZoom = windowController?.zoomLevel ?? 1.0
            pinchScale = 1.0

        case .changed:
            pinchScale *= (1.0 + event.magnification)
            let s = max(0.1, min(8.0, pinchScale))

            // Build a transform that scales around the CENTER of the visible
            // viewport rather than the layer's origin (which is bottom-left).
            // Formula: translate(cx,cy) · scale(s) · translate(-cx,-cy)
            // In matrix form: [s, 0, cx*(1-s)]
            //                 [0, s, cy*(1-s)]
            //                 [0, 0, 1       ]
            let clipBounds = scrollView.contentView.bounds
            let cx = clipBounds.midX
            let cy = clipBounds.midY
            imageView.layer?.setAffineTransform(
                CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                  tx: cx * (1 - s),
                                  ty: cy * (1 - s))
            )

        case .ended, .cancelled:
            // Commit the final zoom level and trigger exactly one crisp re-render.
            // Do NOT clear the layer transform here — keeping the scaled preview
            // visible until the new image is ready prevents the flash.
            let finalZoom = pinchStartZoom * Float(pinchScale)
            windowController?.zoomLevel = max(0.25, min(5.0, finalZoom))
            windowController?.renderCurrentPage()
            pinchScale = 1.0

        default:
            break
        }
    }

    /// Two-finger pan — forward to the scroll view for panning when zoomed in.
    override func scrollWheel(with event: NSEvent) {
        let zoom = windowController?.zoomLevel ?? 1.0
        if zoom > 1.05 {
            scrollView.scrollWheel(with: event)
        }
        // At zoom ≤ 1.0, swallow the event — no continuous page scrolling.
    }

    // MARK: - Jump to Page

    func showJumpToPage() {
        guard windowController?.document != nil else { return }
        if !helpOverlay.isHidden { helpOverlay.isHidden = true }
        jumpField.isHidden = false
        jumpField.stringValue = ""
        window?.makeFirstResponder(jumpField)
    }

    func dismissJumpToPage() {
        jumpField.isHidden = true
        window?.makeFirstResponder(self)
    }

    // MARK: - Help Overlay Toggle

    @objc func toggleHelpOverlay() {
        if !jumpField.isHidden { dismissJumpToPage() }
        helpOverlay.isHidden.toggle()
        if !helpOverlay.isHidden {
            helpOverlay.superview?.addSubview(helpOverlay, positioned: .above, relativeTo: nil)
        }
    }
}

// MARK: - NSTextFieldDelegate (Jump to Page)

extension PDFContentView: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            let text = jumpField.stringValue.trimmingCharacters(in: .whitespaces)
            if let pageNum = Int(text), let doc = windowController?.document {
                let targetPage = pageNum - 1
                if targetPage >= 0 && targetPage < doc.pageCount {
                    windowController?.jumpToPage(targetPage)
                } else {
                    NSSound.beep()
                }
            } else {
                NSSound.beep()
            }
            dismissJumpToPage()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            dismissJumpToPage()
            return true
        }
        return false
    }
}
