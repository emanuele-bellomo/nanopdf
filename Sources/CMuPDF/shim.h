// NanoPDF — MuPDF C-to-Swift Bridging Header (Shim)
//
// This header exposes the MuPDF C API types and functions to Swift
// through the CMuPDF system library module.
//
// Swift cannot call C function-like macros, so we provide thin inline
// wrapper functions for the macros we need. These compile to zero-cost
// calls since they are static inline.
//
// Key types exposed:
//   fz_context    — MuPDF global state (memory, error handling)
//   fz_document   — An opened document (PDF, EPUB, etc.)
//   fz_page       — A single page within a document
//   fz_pixmap     — A rendered pixel buffer (RGBA)
//   fz_matrix     — 2D affine transform (zoom, rotation)
//   fz_rect       — Bounding rectangle
//   fz_colorspace — Color space descriptor (RGB, CMYK, etc.)

#ifndef CMUPDF_SHIM_H
#define CMUPDF_SHIM_H

// MuPDF core (Fitz engine) — context, geometry, device, pixmap, etc.
#include <mupdf/fitz.h>

// MuPDF PDF-specific API — PDF document, annotations, etc.
#include <mupdf/pdf.h>

// ---------------------------------------------------------------------------
// Swift-callable wrappers for MuPDF macros
// ---------------------------------------------------------------------------

/// Create a new MuPDF context. Wraps the fz_new_context() macro which Swift
/// cannot call directly because it expands to fz_new_context_imp(..., FZ_VERSION).
static inline fz_context *nanopdf_new_context(void) {
    return fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
}

/// Returns the MuPDF version string (e.g. "1.28.4").
/// FZ_VERSION is a preprocessor macro, invisible to Swift.
static inline const char *nanopdf_mupdf_version(void) {
    return FZ_VERSION;
}

/// Wrapper for fz_scale() which may be a macro in some MuPDF versions.
static inline fz_matrix nanopdf_scale(float sx, float sy) {
    return fz_scale(sx, sy);
}

/// Wrapper for fz_bound_page() which may be a macro in some MuPDF versions.
static inline fz_rect nanopdf_bound_page(fz_context *ctx, fz_page *page) {
    return fz_bound_page(ctx, page);
}

/// Wrapper for fz_device_rgb() which is a macro.
static inline fz_colorspace *nanopdf_device_rgb(fz_context *ctx) {
    return fz_device_rgb(ctx);
}

#endif /* CMUPDF_SHIM_H */
