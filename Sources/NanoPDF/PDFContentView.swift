import AppKit

// PDFContentView — The main viewport for NanoPDF.
//
// A custom NSView that hosts the rendered PDF page image and handles all
// keyboard input. It is the first responder for the window, routing key
// events to the AppDelegate for page navigation, zoom, and dark mode.
//
// Tasks implemented:
//   3.1 — The Viewport (NSImageView display)
//   3.2 — Keyboard Event Handling (arrows, vim, zoom, dark mode)
//   3.4 — Jump to Page (⌘G overlay)
//   3.5 — Discoverable Shortcuts overlay (? key, help button)

class PDFContentView: NSView {

    // MARK: - Subviews

    /// Displays the rendered PDF page CGImage.
    let imageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    /// Semi-transparent help button pinned to the bottom-right corner (Task 3.5).
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

    /// The Jump-to-Page text field overlay (Task 3.4).
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

    /// The shortcuts/help overlay (Task 3.5).
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

    /// Back-reference to the app delegate for triggering actions.
    weak var appDelegate: AppDelegate?

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
        // --- Image view (Task 3.1) ---
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // --- Help button, bottom-right corner (Task 3.5) ---
        helpButton.target = self
        helpButton.action = #selector(toggleHelpOverlay)
        addSubview(helpButton)
        NSLayoutConstraint.activate([
            helpButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            helpButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            helpButton.widthAnchor.constraint(equalToConstant: 28),
            helpButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // --- Jump-to-Page field (Task 3.4) ---
        jumpField.delegate = self
        addSubview(jumpField)
        NSLayoutConstraint.activate([
            jumpField.centerXAnchor.constraint(equalTo: centerXAnchor),
            jumpField.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            jumpField.widthAnchor.constraint(equalToConstant: 180),
            jumpField.heightAnchor.constraint(equalToConstant: 30),
        ])

        // --- Help overlay (Task 3.5) ---
        addSubview(helpOverlay)
        setupHelpContent()
        NSLayoutConstraint.activate([
            helpOverlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            helpOverlay.centerYAnchor.constraint(equalTo: centerYAnchor),
            helpOverlay.widthAnchor.constraint(equalToConstant: 420),
            helpOverlay.heightAnchor.constraint(equalToConstant: 380),
        ])
    }

    // MARK: - Help Overlay Content (Task 3.5)

    private func setupHelpContent() {
        let lines: [(String, String)] = [
            ("→  /  l  /  j  /  Space", "Next Page"),
            ("←  /  h  /  k", "Previous Page"),
            ("+  /  =", "Zoom In"),
            ("-", "Zoom Out"),
            ("0", "Reset Zoom (Fit)"),
            ("i", "Toggle Dark Mode"),
            ("⌘G", "Jump to Page"),
            ("⌘O", "Open PDF"),
            ("?", "Toggle This Guide"),
            ("⌘Q", "Quit"),
        ]

        // Title
        let title = NSTextField(labelWithString: "NanoPDF — Keyboard Shortcuts")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Single-page PDF reader · Ultra-low memory footprint")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        // Stack of key bindings
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (key, desc) in lines {
            let row = createShortcutRow(key: key, description: desc)
            stack.addArrangedSubview(row)
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

    // MARK: - First Responder (required for keyDown)

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    // MARK: - Task 3.2: Keyboard Event Handling

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘G — Jump to Page (Task 3.4)
        if chars == "g" && modifiers.contains(.command) {
            showJumpToPage()
            return
        }

        // Ignore other modified keys (except shift for ? and +)
        // Allow shift through for characters like ? and +
        let hasNonShiftModifiers = modifiers.subtracting(.shift).isEmpty == false
        if hasNonShiftModifiers {
            super.keyDown(with: event)
            return
        }

        switch chars {
        // --- Navigation ---
        case " ":   // Space → next page
            appDelegate?.goToNextPage()

        // --- Zoom ---
        case "+", "=":
            appDelegate?.zoomIn()
        case "-":
            appDelegate?.zoomOut()
        case "0":
            appDelegate?.resetZoom()

        // --- Dark Mode ---
        case "i":
            appDelegate?.toggleDarkMode()

        // --- Help Overlay (Task 3.5) ---
        case "?":
            toggleHelpOverlay()

        // --- Vim & Arrow keys ---
        default:
            // Check special keys (arrows) via key codes
            switch event.keyCode {
            case 124, 125:  // Right Arrow, Down Arrow
                appDelegate?.goToNextPage()
            case 123, 126:  // Left Arrow, Up Arrow
                appDelegate?.goToPreviousPage()
            default:
                // Vim bindings by character
                switch chars {
                case "j", "l":
                    appDelegate?.goToNextPage()
                case "k", "h":
                    appDelegate?.goToPreviousPage()
                default:
                    super.keyDown(with: event)
                }
            }
        }
    }

    // Suppress the system beep for keys we handle.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Claim ⌘G so it doesn't beep
        if chars == "g" && modifiers.contains(.command) {
            showJumpToPage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Task 3.4: Jump to Page

    func showJumpToPage() {
        guard appDelegate?.document != nil else { return }

        // If the help overlay is showing, dismiss it first.
        if !helpOverlay.isHidden {
            helpOverlay.isHidden = true
        }

        jumpField.isHidden = false
        jumpField.stringValue = ""
        window?.makeFirstResponder(jumpField)
    }

    func dismissJumpToPage() {
        jumpField.isHidden = true
        window?.makeFirstResponder(self)
    }

    // MARK: - Task 3.5: Help Overlay Toggle

    @objc func toggleHelpOverlay() {
        // If the jump field is active, dismiss it first.
        if !jumpField.isHidden {
            dismissJumpToPage()
        }

        helpOverlay.isHidden.toggle()

        // If we just showed the overlay, bring it to front.
        if !helpOverlay.isHidden {
            helpOverlay.superview?.addSubview(helpOverlay, positioned: .above, relativeTo: nil)
        }
    }
}

// MARK: - NSTextFieldDelegate (Jump to Page input)

extension PDFContentView: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // User pressed Enter — validate and jump.
            let text = jumpField.stringValue.trimmingCharacters(in: .whitespaces)
            if let pageNum = Int(text), let doc = appDelegate?.document {
                // User enters 1-based page numbers, convert to 0-based.
                let targetPage = pageNum - 1
                if targetPage >= 0 && targetPage < doc.pageCount {
                    appDelegate?.jumpToPage(targetPage)
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
            // User pressed Escape — dismiss without jumping.
            dismissJumpToPage()
            return true
        }

        return false
    }
}
