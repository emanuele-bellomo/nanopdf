# NanoPDF Development Notes

## Documentation & Useful Links
- [official Swift book](https://docs.swift.org)
- [Hacking with Swift (macOS)](https://www.hackingwithswift.com)
- [Apple Developer Documentation](https://developer.apple.com/documentation)

---

# The Process Model: Iterative & Incremental (via Kanban)

Do not try to build the whole app at once (Waterfall). Use an Iterative approach where you build a core foundation, then add features in cycles.

- **Iteration 1 (Minimum Viable Product)**: Get the C-Swift bridge working. Successfully render a single PDF page into an NSView. Ignore scrolling, zooming, or UI polish.

- **Iteration 2 (Pagination & Memory)**: Implement scrolling and multiple pages. This is where you introduce lazy-loading to keep RAM below your 100MB target.

- **Iteration 3 (UX & Features)**: Add tabs, a table of contents sidebar, keyboard shortcuts, and zooming.

# DevOps & Tooling for a Solo Dev

- **Version Control (Git)**: Use Feature Branching. Keep your main branch stable. When you want to add tabs, create a feature/tabs branch, build it, and merge it back.

- **CI/CD (Continuous Integration)**: Set up GitHub Actions. Write a simple YAML script that automatically builds your Swift project every time you push code. This proves to your professors that you understand modern DevOps pipelines.

- **Testing**: Write unit tests for your C-Swift bridging header. You don't need to write automated tests for every UI button, but testing that the MuPDF engine successfully returns page counts or text strings without memory leaks is crucial.

***Pro-Tip for your Thesis***: Start documenting your memory benchmarks on day one. A chart in your thesis showing your app consuming 85MB while Preview consumes 1.2GB for the exact same document will guarantee an excellent grade.

---

# AI Draft Code Analysis: Issues & Solutions

The first AI generated draft suffers from severe instability and massive RAM consumption. The AI wrote clean and elegant Swift UI code, but made critical architectural errors when integrating the MuPDF C engine. Here are the three main culprits:

### RAM Explosion: The Zoom Bomb
This is why the app consumes hundreds of megabytes instead of the 30MB promised in the AI's comments.
*   In `MuPDFDocument.swift`, the AI uses the convenience function `fz_new_pixmap_from_page` to generate pixels[cite: 6]. This function always allocates memory for the *entire* page[cite: 6].
*   In `PDFContentView.swift`, the maximum zoom level is capped at `5.0`[cite: 7].
*   If you zoom in 5x, the area (and thus the stored pixels) grows quadratically. A single page that takes 15MB at normal size will balloon to almost 400MB in RAM.
*   **How SumatraPDF does it:** Instead of using `_from_page`, optimized readers use a bounding box (`fz_rect`) to tell MuPDF: *"Render ONLY the 800x600 pixel rectangle that the user is currently viewing on the screen."*

### Hidden Memory Leaks: Asynchronous Queues
The AI implemented a subtle logic flaw that saturates RAM during fast navigation.
*   In `PDFWindowController.swift`, inside `renderCurrentPage()`, every time the page changes, a new rendering thread is spawned[cite: 8].
*   The AI tried to manage stale renders by incrementing a `renderGeneration` counter[cite: 8]. When the background thread finishes, it checks if the current generation matches the saved one; if not, it simply discards the calculated image without updating the UI (`self.contentView.setPageImage(nsImage)`)[cite: 8].
*   **The problem:** The heavy C operation is never *cancelled*; its result is just thrown away at the end! If you press the "Next Page" arrow 10 times in quick succession, the app launches 10 concurrent background rendering operations[cite: 8]. Each allocates tens of megabytes of pixels in parallel before Swift can clean up the memory.

### The Verdict
The prototype isn't garbage. The whole AppKit scaffolding (keyboard shortcuts, tab management, windows) written by the AI is excellent and very useful[cite: 4, 7, 8]. 

The real engineering work (and perfect material for a university thesis) will be to tear down `MuPDFDocument.swift`[cite: 6] and `shim.h`[cite: 9] and rebuild them professionally: implementing C mutexes for the context, calculating viewport clipping during zoom, and actively cancelling background processes when the user turns pages too quickly.
