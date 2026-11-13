import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Central state and I/O coordinator for SketchPad.
@MainActor
@Observable
public final class SketchViewModel {
    public var baseImage: NSImage?
    public var displayBaseImage: NSImage?
    public var imagePixelSize: CGSize = .zero
    public var strokes: [Stroke] = []
    public var redoStack: [Stroke] = []
    public var activeStroke: Stroke?

    public var selectedTool: ToolType = .pen {
        didSet {
            if selectedTool != .eyedropper {
                lastDrawingTool = selectedTool
            }
        }
    }
    private var lastDrawingTool: ToolType = .pen
    public var selectedColor: StrokeColor = StrokeColor.presets[0].color
    /// Brush diameter in view points; scaled into image-pixel coordinates when drawing.
    public var brushSize: CGFloat = 8.0

    // Text input state
    public var pendingTextPoint: CGPoint?
    public var pendingTextScaleFactor: CGFloat = 1.0
    public var pendingTextDraft: String = ""

    // Crop & Zoom/Pan state
    public var isCropMode: Bool = false
    public var cropRect: CGRect?
    public var zoomScale: CGFloat = 1.0
    public var panOffset: CGSize = .zero
    public var isPanMode: Bool = false

    public var isDropTargeted: Bool = false
    public var toastMessage: String?

    private var toastDismissTask: Task<Void, Never>?

    public init() {}

    public var hasImage: Bool { baseImage != nil }
    public var canUndo: Bool { !strokes.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var canClear: Bool { !strokes.isEmpty }

    public var nextBadgeNumber: Int {
        (strokes.compactMap(\.badgeNumber).max() ?? 0) + 1
    }

    // MARK: - Image Loading

    public func setImage(_ image: NSImage, sourceDescription: String? = nil) {
        let size = ImageCompositor.pixelSize(of: image)
        guard size.width > 0, size.height > 0 else { return }
        baseImage = image
        imagePixelSize = size
        strokes.removeAll()
        redoStack.removeAll()
        activeStroke = nil
        pendingTextPoint = nil
        isCropMode = false
        cropRect = nil
        resetZoom()
        refreshDisplayBaseImage()
        if let sourceDescription {
            showToast(sourceDescription)
        }
    }

    public func createBlankCanvas(width: Int = 1600, height: Int = 1000) {
        let blank = ImageCompositor.makeBlankCanvas(width: width, height: height, color: .white)
        setImage(blank, sourceDescription: "New blank canvas (\(width)×\(height))")
    }

    public func removeImage() {
        guard baseImage != nil else { return }
        baseImage = nil
        displayBaseImage = nil
        imagePixelSize = .zero
        strokes.removeAll()
        redoStack.removeAll()
        activeStroke = nil
        pendingTextPoint = nil
        isCropMode = false
        cropRect = nil
        resetZoom()
        showToast("Removed image")
    }

    public func loadImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            showToast("Could not load image")
            return
        }
        setImage(image, sourceDescription: "Loaded \(url.lastPathComponent)")
    }

    public func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .gif, .webP]

        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    public func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            setImage(image, sourceDescription: "Pasted from clipboard")
            return
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                setImage(image, sourceDescription: "Pasted from clipboard")
                return
            }
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let url = urls.first {
            loadImage(from: url)
            return
        }

        showToast("No image found in clipboard")
    }

    public func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = if let data = item as? Data {
                    URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    self.loadImage(from: url)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    self.setImage(image, sourceDescription: "Loaded dropped image")
                }
            }
            return true
        }

        return false
    }

    // MARK: - Sketching & Annotations

    public func beginStroke(at imagePoint: CGPoint, imageScaleFactor: CGFloat) {
        let pixelLineWidth = max(1.0, brushSize * imageScaleFactor)

        switch selectedTool {
        case .eyedropper:
            sampleEyedropper(at: imagePoint)
            return
        case .stepBadge:
            addStepBadge(at: imagePoint, lineWidth: pixelLineWidth)
            return
        case .text:
            pendingTextPoint = imagePoint
            pendingTextScaleFactor = imageScaleFactor
            pendingTextDraft = ""
            return
        case .arrow, .rectangle, .ellipse, .pixelate:
            activeStroke = Stroke(
                points: [imagePoint, imagePoint],
                color: selectedColor,
                lineWidth: pixelLineWidth,
                tool: selectedTool
            )
        case .pen, .highlighter, .eraser:
            activeStroke = Stroke(
                points: [imagePoint],
                color: selectedColor,
                lineWidth: pixelLineWidth,
                tool: selectedTool
            )
        }
    }

    public func continueStroke(to imagePoint: CGPoint, isShiftPressed: Bool = false) {
        guard let current = activeStroke else { return }

        switch current.tool {
        case .arrow, .rectangle, .ellipse, .pixelate:
            guard let start = current.points.first else { return }
            let endPoint = isShiftPressed
                ? CanvasGeometry.snappedEndPoint(from: start, to: imagePoint, tool: current.tool)
                : imagePoint
            activeStroke?.points = [start, endPoint]

        case .pen, .highlighter, .eraser:
            if let last = current.points.last {
                let dx = imagePoint.x - last.x
                let dy = imagePoint.y - last.y
                if (dx * dx + dy * dy) < 0.5 { return }
            }
            activeStroke?.points.append(imagePoint)

        case .text, .stepBadge, .eyedropper:
            break
        }
    }

    public func endStroke() {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        guard !stroke.points.isEmpty else { return }

        // Ignore zero-size shape/pixelate drags
        if [.arrow, .rectangle, .ellipse, .pixelate].contains(stroke.tool), stroke.points.count >= 2 {
            let dist = hypot(stroke.points[1].x - stroke.points[0].x, stroke.points[1].y - stroke.points[0].y)
            if dist < 2.0 { return }
        }

        strokes.append(stroke)
        redoStack.removeAll()
        if stroke.tool == .pixelate {
            refreshDisplayBaseImage()
        }
    }

    public func commitPendingText() {
        let trimmed = pendingTextDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let point = pendingTextPoint, !trimmed.isEmpty else {
            pendingTextPoint = nil
            pendingTextDraft = ""
            return
        }
        let pixelLineWidth = max(1.0, brushSize * pendingTextScaleFactor)
        let stroke = Stroke(
            points: [point],
            color: selectedColor,
            lineWidth: pixelLineWidth,
            tool: .text,
            text: trimmed
        )
        strokes.append(stroke)
        redoStack.removeAll()
        pendingTextPoint = nil
        pendingTextDraft = ""
    }

    public func cancelPendingText() {
        pendingTextPoint = nil
        pendingTextDraft = ""
    }

    private func addStepBadge(at imagePoint: CGPoint, lineWidth: CGFloat) {
        let stroke = Stroke(
            points: [imagePoint],
            color: selectedColor,
            lineWidth: lineWidth,
            tool: .stepBadge,
            badgeNumber: nextBadgeNumber
        )
        strokes.append(stroke)
        redoStack.removeAll()
    }

    public func sampleEyedropper(at imagePoint: CGPoint) {
        let target = displayBaseImage ?? baseImage
        guard let target, let sampled = ImageCompositor.sampleColor(in: target, at: imagePoint) else {
            return
        }
        selectedColor = sampled
        let restoreTool = (lastDrawingTool == .eraser || lastDrawingTool == .pixelate) ? .pen : lastDrawingTool
        selectedTool = restoreTool
        showToast("Sampled color")
    }

    public func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
        if last.tool == .pixelate {
            refreshDisplayBaseImage()
        }
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        strokes.append(next)
        if next.tool == .pixelate {
            refreshDisplayBaseImage()
        }
    }

    public func clearStrokes() {
        guard !strokes.isEmpty else { return }
        strokes.removeAll()
        redoStack.removeAll()
        refreshDisplayBaseImage()
        showToast("Cleared annotations")
    }

    // MARK: - Crop & Rotate

    public func rotateClockwise() {
        guard let baseImage,
              let rotated = ImageCompositor.rotateClockwise(baseImage) else {
            return
        }
        let oldSize = imagePixelSize
        strokes = strokes.map { stroke in
            var copy = stroke
            copy.points = stroke.points.map { CanvasGeometry.rotatePointClockwise($0, originalSize: oldSize) }
            return copy
        }
        redoStack.removeAll()
        self.baseImage = rotated
        self.imagePixelSize = ImageCompositor.pixelSize(of: rotated)
        isCropMode = false
        cropRect = nil
        refreshDisplayBaseImage()
        showToast("Rotated 90°")
    }

    public func toggleCropMode() {
        guard hasImage else { return }
        if isCropMode {
            cancelCrop()
        } else {
            let marginX = imagePixelSize.width * 0.1
            let marginY = imagePixelSize.height * 0.1
            cropRect = CGRect(
                x: marginX,
                y: marginY,
                width: max(20, imagePixelSize.width - marginX * 2),
                height: max(20, imagePixelSize.height - marginY * 2)
            )
            isCropMode = true
        }
    }

    public func applyCrop() {
        guard let baseImage, let cropRect,
              let cropped = ImageCompositor.crop(baseImage, to: cropRect) else {
            cancelCrop()
            return
        }
        let normalizedRect = cropRect.integral
        strokes = strokes.map { stroke in
            var copy = stroke
            copy.points = stroke.points.map { CanvasGeometry.translatePointForCrop($0, cropRect: normalizedRect) }
            return copy
        }
        redoStack.removeAll()
        self.baseImage = cropped
        self.imagePixelSize = ImageCompositor.pixelSize(of: cropped)
        self.isCropMode = false
        self.cropRect = nil
        resetZoom()
        refreshDisplayBaseImage()
        showToast("Cropped to \(Int(imagePixelSize.width))×\(Int(imagePixelSize.height))")
    }

    public func cancelCrop() {
        isCropMode = false
        cropRect = nil
    }

    // MARK: - Zoom & Pan

    public func zoomIn() {
        zoomScale = min(5.0, (zoomScale * 1.25 * 100).rounded() / 100)
    }

    public func zoomOut() {
        zoomScale = max(0.25, (zoomScale / 1.25 * 100).rounded() / 100)
        if zoomScale <= 1.0 {
            panOffset = .zero
        }
    }

    public func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
    }

    // MARK: - Export

    public func renderCompositeImage() -> NSImage? {
        guard let baseImage else { return nil }
        return ImageCompositor.renderComposite(baseImage: baseImage, strokes: strokes)
    }

    public func copyToClipboard() {
        guard let composite = renderCompositeImage() else {
            showToast("Nothing to copy")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wrote = false
        if let pngData = ImageCompositor.encode(composite, format: .png) {
            pasteboard.setData(pngData, forType: .png)
            wrote = true
        }
        if let tiffData = composite.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            wrote = true
        }

        showToast(wrote ? "Copied to clipboard" : "Failed to copy image")
    }

    public func saveToFile() {
        guard let composite = renderCompositeImage() else {
            showToast("Nothing to save")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Sketched Image"
        panel.nameFieldStringValue = "sketched-image.png"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let ext = url.pathExtension.lowercased()
            let format: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
            guard let data = ImageCompositor.encode(composite, format: format) else {
                showToast("Failed to encode image")
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                showToast("Saved \(url.lastPathComponent)")
            } catch {
                showToast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    public func refreshDisplayBaseImage() {
        guard let baseImage else {
            displayBaseImage = nil
            return
        }
        displayBaseImage = ImageCompositor.renderBaseWithPixelations(baseImage: baseImage, annotations: strokes) ?? baseImage
    }

    public func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled {
                self.toastMessage = nil
            }
        }
    }
}
