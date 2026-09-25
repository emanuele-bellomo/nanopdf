import AppKit
import CMuPDF
import CoreGraphics

// MuPDFDocument — Wraps the MuPDF C engine in a safe Swift class.
//
// Owns the fz_context and fz_document pointers, managing their lifecycle
// through Swift's init/deinit. Only one page's pixel data is alive at a time,
// enforcing the ~30 MB memory ceiling.
//
// Usage:
//   let doc = MuPDFDocument(path: "/path/to/file.pdf")
//   let image = doc?.renderPage(number: 0, zoom: 1.5, darkMode: false)

final class MuPDFDocument {

    // MARK: - Private MuPDF State

    /// MuPDF global context — owns allocators, error handlers, font cache.
    private let ctx: UnsafeMutablePointer<fz_context>

    /// The opened PDF document handle.
    private let doc: UnsafeMutablePointer<fz_document>

    /// Total number of pages in the document (cached on open).
    let pageCount: Int

    /// The filesystem path this document was opened from.
    let filePath: String

    // MARK: - Task 2.1: Initialization & Document Management

    /// Opens a PDF file at the given path.
    ///
    /// Returns nil if the MuPDF context cannot be created or the file
    /// cannot be opened (wrong format, missing file, etc.).
    ///
    /// - Parameter path: Absolute filesystem path to the PDF file.
    init?(path: String) {
        self.filePath = path

        // Create the MuPDF context with default store size.
        guard let context = nanopdf_new_context() else {
            print("❌ MuPDFDocument: Failed to create fz_context")
            return nil
        }
        self.ctx = context

        // Register the default document handlers (PDF, EPUB, etc.).
        fz_register_document_handlers(ctx)

        // Open the document.
        guard let document = fz_open_document(ctx, path) else {
            print("❌ MuPDFDocument: Failed to open document at \(path)")
            fz_drop_context(ctx)
            return nil
        }
        self.doc = document

        // Cache the page count.
        self.pageCount = Int(fz_count_pages(ctx, doc))
        print("📖 MuPDFDocument: Opened \(path) — \(pageCount) pages")
    }

    /// Safe teardown: drop document first, then the context.
    deinit {
        fz_drop_document(ctx, doc)
        fz_drop_context(ctx)
        print("🗑️ MuPDFDocument: Released resources for \(filePath)")
    }

    // MARK: - Task 2.2: Page Rendering

    /// Renders a single page to a CGImage.
    ///
    /// This is the core rendering pipeline. It loads the page, renders it to
    /// a MuPDF pixmap (RGBA pixel buffer), converts it to a CGImage, then
    /// immediately drops all MuPDF resources to keep memory flat.
    ///
    /// - Parameters:
    ///   - number: Zero-based page index (0 ..< pageCount).
    ///   - zoom: Scale factor (1.0 = 72 DPI, 2.0 = 144 DPI for Retina).
    ///   - darkMode: If true, applies luminance inversion for dark reading.
    /// - Returns: A CGImage of the rendered page, or nil on failure.
    func renderPage(number: Int, zoom: Float, darkMode: Bool) -> CGImage? {
        guard number >= 0 && number < pageCount else {
            print("⚠️ MuPDFDocument: Page \(number) out of range (0..<\(pageCount))")
            return nil
        }

        // --- Step 1: Load the page ---
        guard let page = fz_load_page(ctx, doc, Int32(number)) else {
            print("❌ MuPDFDocument: Failed to load page \(number)")
            return nil
        }
        // Ensure the page is always dropped, even if we bail out early.
        defer { fz_drop_page(ctx, page) }

        // --- Step 2: Compute the transform matrix ---
        // fz_new_pixmap_from_page handles page bounds internally,
        // so we only need the zoom transform.
        let transform = nanopdf_scale(zoom, zoom)

        // --- Step 3: Create a pixmap and render ---
        // fz_new_pixmap_from_page is a convenience function that:
        //   1. Allocates a pixmap sized to fit the page at the given transform
        //   2. Creates a draw device targeting that pixmap
        //   3. Runs the page through the device
        //   4. Cleans up the device
        //   5. Returns the filled pixmap
        guard let pixmap = fz_new_pixmap_from_page(ctx, page, transform,
                                                    nanopdf_device_rgb(ctx),
                                                    Int32(1)) else {
            print("❌ MuPDFDocument: Failed to render page \(number) to pixmap")
            return nil
        }
        // Ensure the pixmap is always dropped after we create the CGImage.
        defer { fz_drop_pixmap(ctx, pixmap) }

        // --- Step 4 (Task 2.3): Apply dark mode if requested ---
        if darkMode {
            // fz_invert_pixmap_luminance inverts the luminance channel while
            // preserving hue/saturation — much better than raw RGB inversion
            // for documents with colored diagrams or images.
            fz_invert_pixmap_luminance(ctx, pixmap)
        }

        // --- Step 5: Convert pixmap to CGImage ---
        let width  = Int(fz_pixmap_width(ctx, pixmap))
        let height = Int(fz_pixmap_height(ctx, pixmap))
        let stride = Int(fz_pixmap_stride(ctx, pixmap))
        let n      = Int(fz_pixmap_components(ctx, pixmap))  // Should be 4 (RGBA)

        guard let samples = fz_pixmap_samples(ctx, pixmap) else {
            print("❌ MuPDFDocument: Pixmap has no sample data")
            return nil
        }

        // Copy the pixel data so the CGImage owns it independently.
        // This lets us safely fz_drop_pixmap in the defer block above.
        let dataSize = height * stride
        let dataCopy = UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        dataCopy.initialize(from: samples, count: dataSize)

        // Create a data provider that will free the copied buffer when
        // the CGImage is deallocated.
        guard let provider = CGDataProvider(dataInfo: dataCopy,
                                             data: dataCopy,
                                             size: dataSize,
                                             releaseData: { info, _, _ in
            guard let ptr = info else { return }
            // UInt8 is a trivial type, so we don't strictly need to deinitialize,
            // but if we do, it must be the full count. Here we simply deallocate.
            ptr.assumingMemoryBound(to: UInt8.self).deallocate()
        }) else {
            dataCopy.deallocate()
            print("❌ MuPDFDocument: Failed to create CGDataProvider")
            return nil
        }

        // Construct the CGImage. MuPDF produces RGBA with premultiplied alpha.
        let bitsPerComponent = 8
        let bitsPerPixel = n * 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ]

        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )

        // At this point:
        //   - The CGImage owns a copy of the pixel data (via dataCopy + provider).
        //   - The defer blocks will now run:
        //     1. fz_drop_pixmap(ctx, pixmap)  — frees MuPDF's pixel buffer
        //     2. fz_drop_page(ctx, page)      — frees the page structures
        // Memory stays flat: only one CGImage is alive at a time (the caller
        // replaces the old one, which gets deallocated by ARC).

        return image
    }
}
