#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build

swiftc \
    -target x86_64-apple-macosx14.0 \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -parse-as-library \
    Sources/SketchPad/Models/Stroke.swift \
    Sources/SketchPad/Services/CanvasGeometry.swift \
    Sources/SketchPad/Services/ImageCompositor.swift \
    Sources/SketchPad/ViewModels/SketchViewModel.swift \
    Sources/SketchPadTests/SketchPadTests.swift \
    -o build/SketchPadTests

./build/SketchPadTests
