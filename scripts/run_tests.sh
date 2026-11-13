#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build

swiftc \
    -target x86_64-apple-macosx14.0 \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -parse-as-library \
    Sources/Sketchy/Models/Stroke.swift \
    Sources/Sketchy/Services/CanvasGeometry.swift \
    Sources/Sketchy/Services/ImageCompositor.swift \
    Sources/Sketchy/ViewModels/SketchViewModel.swift \
    Sources/SketchyTests/SketchyTests.swift \
    -o build/SketchyTests

./build/SketchyTests
