# AI Agents Collaboration Plan: Minimalist macOS MuPDF Reader

This document outlines the development plan for building a highly optimized PDF reader for Apple Silicon (macOS) utilizing Swift and the MuPDF C library. The goal is to recreate a "SumatraPDF-like" experience on macOS with an ultra-low memory footprint even with multiple tabs open, to avoid Preview's or Skim's heavy memory increase with multiple PDFs open.

## The First AI Draft and AI Usage

The current project is for the most part AI Generated, so you, AI Agent, should talk to me, the developer, like I don't know much about the project's or MuPDF's practical structure and filesystem. I, however, know Swift and C and many other programming languages, so don't be afraid to use technical language, but explain key concepts (like what a specific function or variable does) with simple words.

I decided I will not leave AI access to edit files from now on, and I'll use it simply for research, tips, and guidance, so your job is not to code for me but to help me code, since this is my first real software engineering project and I'm a solo developer.

## Core Requirements & Features
- **Native Apple Silicon:** No Rosetta/Intel bloat.
- **Engine:** `MuPDF` (C library) bridged to Swift.
- **UI:** AppKit
- **Features (need priority reorganizing):**
  - Open PDF files.
  - Instant page flipping and scrolling (choice).
  - Zoom In / Zoom Out.
  - Dark Mode (color matrix inversion).
  - Print PDF, using AppKit's NSPrintOperation with CGPDFDocument
  - Jump to Page
  - Keybindings: Arrow keys, Control - Command - F (fullscreen toggle), Control - Tab (change tab), Command - C (copy text), Command - F (find text), Command - P (print PDF), i (invert colors)
