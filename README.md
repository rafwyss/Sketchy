# SketchPad

A lightweight, native macOS image sketching and annotation app built with SwiftUI and AppKit.

## Features

- **Flexible Input**: Paste from clipboard (`⌘V`), drag & drop an image, open a file (`⌘O`), or start with a blank canvas (`⌘N`).
- **Annotation Tools**:
  - **Pen** & **Highlighter** (translucent marker)
  - **Non-destructive Eraser** (erases annotations without erasing the underlying image)
  - **Shapes**: Arrow, Rectangle, Circle/Ellipse (hold `⇧ Shift` to snap)
  - **Text Callouts** & auto-incrementing **Step Badges**
  - **Blur / Pixelate** redaction tool
  - **Eyedropper** to sample colors directly from the image
- **Image Adjustments & Navigation**: Rotate 90° (`⌘R`), Crop, Pan (`⌥` + drag or Pan mode), and Zoom (`⌘+` / `⌘-` / `⌘0` / trackpad pinch).
- **Full-Resolution Output**: Copy annotated image to clipboard (`⌘C`) or save as PNG / JPEG (`⌘S`).

## Build & Run

Requires macOS 14+ and Swift (Xcode Command Line Tools).

```bash
# Run unit tests
./scripts/run_tests.sh

# Build, sign, and install to /Applications/SketchPad.app
./scripts/build_app.sh

# Launch
open /Applications/SketchPad.app
```
