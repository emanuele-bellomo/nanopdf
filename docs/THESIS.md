# Key Technical Chapters for Your Thesis
ARC vs. Manual Reference Counting Bridge
The Problem: Swift relies on Automatic Reference Counting (ARC), while MuPDF relies on explicit C reference management using fz_keep_* and fz_drop_* functions.
The Thesis Value: You can detail how you designed Swift wrappers (RAII pattern) around C pointers so that when a Swift object deinitializes (deinit), it deterministically frees C memory without leaking or causing use-after-free crashes.
Multi-threading and Context Isolation
The Problem: An fz_context cannot be safely modified by multiple threads at once. If your background thread renders a page while your main thread fetches page info on the same context, the app will crash.
The Thesis Value: You must use fz_clone_context to create thread-safe context handles for background queues. Documenting how you handle thread isolation across Swift's Concurrency / GCD system makes for a strong systems-programming chapter.
Viewport Culling & Cache Eviction (The 100MB Challenge)
The Problem: A single 4K uncompressed fz_pixmap can consume 30–50MB of raw RAM. Keeping 5 pages pre-rendered in memory instantly breaches your target budget.
The Thesis Value: You can design and document a custom Cache Eviction policy (such as LRU - Least Recently Used) that automatically drops fz_pixmap instances as soon as pages scroll out of the viewport.
Empirical Benchmarking & Memory Profiling
The Thesis Value: Academic advisors love empirical data. You can run automated tests using Xcode Instruments (Allocations, Leaks, and Time Profiler) comparing NanoPDF against Apple Preview and Skim on identical 1,000-page PDFs, providing clear graphs of CPU utilization, thread contention, and memory allocation curves.
