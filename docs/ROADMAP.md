## Urgent Bug Fixes (Window Constraints & Basic Input)

- [x] Fix Window Resizing & Split-Screen: Remove strict .minSize restrictions on the NSWindow. Ensure the NSImageView (or PDFContentView) has lower compression resistance and hugging priorities so the window can be freely resized below the PDF's native resolution without fighting the layout engine.
- [x] Remove Vim Keybindings: Completely remove the h, j, k, and l keybinds to keep the UX simple and standard for all Mac users.
- [x] Fix Arrow Key Navigation: Ensure the Left and Right (and Up/Down) arrow keys reliably trigger the renderNextPage and renderPreviousPage functions.

## Core Rendering & Gestures (Zooming & Panning)

- [x] Fix Zoom Blurriness (Architectural Fix): Currently, zoom is just scaling the rasterized NSImage, causing blur. Update the PDFContentView so that when Cmd + / Cmd - is pressed, it passes a new zoom scale multiplier directly to the MuPDF C-bridge (fz_scale). The engine must re-rasterize the page at the new DPI to remain crisp.
- [x] Trackpad Gestures (Pinch & Pan): Implement magnify(with:) for pinch-to-zoom (mapping to the new crisp zoom logic) and scrollWheel(with:) for panning around the image when zoomed in.
- [x] Update the Help Guide (?): Correct the help overlay text to accurately reflect Cmd + / Cmd - instead of just + / -.

## UI/UX Enhancements (Toolbar, Navigation & Drop)

- [ ] Top Toolbar Implementation: Add a native macOS NSToolbar to the top of the window housing all utility buttons, keeping the main view uncluttered.
- [ ] Page Index Indicator: Add a simple, non-intrusive page counter (e.g., "14/30") directly into the new toolbar or floating cleanly at the bottom of the window.
- [ ] Drag and Drop Support: Register the main window to accept dragged .pdf files. Implement performDragOperation to capture the file URL and instantly pass it to the MuPDF document loader.
- [ ] Smooth Scrolling vs. Single Page Toggle: Introduce a toggle button in the toolbar. Agent Note: To achieve smooth scrolling without breaking the <30MB memory profile, dynamically render only the visible intersecting pages during the scroll animation, immediately dropping the off-screen page from memory once the animation snaps to the next page.

## Project Architecture (Tabs & Bundling)

- [ ] Multi-Tab Support: Implement native macOS window tabbing (NSWindow.tabbingMode). Agent Note: To maintain low RAM like SumatraPDF, background tabs must only hold the lightweight fz_document pointer, not the heavy rasterized pixel buffer. Drop the pixel buffer of a tab when it loses focus, and quickly re-render it when the user clicks back to it.
- [ ] Migrate to Xcode & App Bundle: Transition the project from a pure Swift Package Manager executable to a standard Xcode .xcodeproj (or .xcworkspace). This is required to properly build a clickable .app bundle, sign the application, and package it into a .dmg.


- [ ] Make common keybinds like ctrl cmd F (for fullscreen) work
- [ ] The inverted colors look better on Skim, find a way to make the black not "too black" and whites not "too whites" like in Skim
- [ ] Crazy idea: add a button that transforms the PDF into Markdown (with Markitdown by microsoft) and, if possible, letting the user choose whether to leave the file in the folder next to the original PDF file or just copy it in the clipboard to paste into AI.
