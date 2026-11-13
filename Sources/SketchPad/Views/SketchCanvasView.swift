import AppKit
import SwiftUI

struct SketchCanvasView: View {
    @Bindable var viewModel: SketchViewModel
    @State private var hoverLocation: CGPoint?
    @State private var dragStartPan: CGSize?
    @State private var gestureStartZoom: CGFloat?
    @State private var cropDragStart: CGPoint?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let baseRect = CanvasGeometry.aspectFitRect(
                imageSize: viewModel.imagePixelSize,
                in: geometry.size
            )
            let zoomedW = baseRect.width * viewModel.zoomScale
            let zoomedH = baseRect.height * viewModel.zoomScale
            let imageRect = CGRect(
                x: geometry.size.width * 0.5 - zoomedW * 0.5 + viewModel.panOffset.width,
                y: geometry.size.height * 0.5 - zoomedH * 0.5 + viewModel.panOffset.height,
                width: zoomedW,
                height: zoomedH
            )
            let imageScaleFactor = viewModel.imagePixelSize.width / max(imageRect.width, 1)

            ZStack {
                if let displayImage = viewModel.displayBaseImage ?? viewModel.baseImage,
                   imageRect.width > 0, imageRect.height > 0 {
                    // Base image (with live pixelations baked in)
                    Image(nsImage: displayImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)

                    // Isolated annotation layer so `.destinationOut` erases only annotations
                    Canvas { context, size in
                        let scaleX = size.width / max(viewModel.imagePixelSize.width, 1)
                        let scaleY = size.height / max(viewModel.imagePixelSize.height, 1)

                        let allStrokes = viewModel.strokes + (viewModel.activeStroke.map { [$0] } ?? [])
                        for stroke in allStrokes {
                            drawPreviewAnnotation(stroke, in: &context, scaleX: scaleX, scaleY: scaleY)
                        }
                    }
                    .compositingGroup()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasSpace"))
                            .onChanged { value in
                                if viewModel.isCropMode {
                                    handleCropDragChanged(value, imageRect: imageRect)
                                    return
                                }

                                let optionHeld = NSEvent.modifierFlags.contains(.option)
                                if viewModel.isPanMode || optionHeld {
                                    if dragStartPan == nil {
                                        dragStartPan = viewModel.panOffset
                                    }
                                    if let start = dragStartPan {
                                        viewModel.panOffset = CGSize(
                                            width: start.width + value.translation.width,
                                            height: start.height + value.translation.height
                                        )
                                    }
                                    return
                                }

                                let imagePoint = CanvasGeometry.viewToImage(
                                    point: value.location,
                                    imageRect: imageRect,
                                    imageSize: viewModel.imagePixelSize
                                )
                                if viewModel.activeStroke == nil {
                                    viewModel.beginStroke(at: imagePoint, imageScaleFactor: imageScaleFactor)
                                } else {
                                    let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                                    viewModel.continueStroke(to: imagePoint, isShiftPressed: shiftHeld)
                                }
                            }
                            .onEnded { _ in
                                if viewModel.isCropMode {
                                    cropDragStart = nil
                                    return
                                }
                                if dragStartPan != nil {
                                    dragStartPan = nil
                                    return
                                }
                                viewModel.endStroke()
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = imageRect.contains(location) ? location : nil
                        case .ended:
                            hoverLocation = nil
                        }
                    }

                    // Crop overlay when Crop mode is active
                    if viewModel.isCropMode, let cropRect = viewModel.cropRect {
                        cropOverlay(cropRect: cropRect, imageRect: imageRect)
                    }

                    // Inline text input overlay when placing a Text Callout
                    if let pendingPoint = viewModel.pendingTextPoint {
                        let viewPos = CanvasGeometry.imageToView(
                            point: pendingPoint,
                            imageRect: imageRect,
                            imageSize: viewModel.imagePixelSize
                        )
                        TextField("Type callout…", text: $viewModel.pendingTextDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(width: 220)
                            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            )
                            .shadow(radius: 6)
                            .focused($isTextFieldFocused)
                            .onAppear { isTextFieldFocused = true }
                            .onSubmit { viewModel.commitPendingText() }
                            .onExitCommand { viewModel.cancelPendingText() }
                            .position(
                                x: min(max(viewPos.x + 110, 120), geometry.size.width - 120),
                                y: min(max(viewPos.y, 30), geometry.size.height - 30)
                            )
                    }

                    // Brush cursor preview ring
                    if let hoverLocation,
                       !viewModel.isCropMode,
                       !viewModel.isPanMode,
                       [.pen, .highlighter, .eraser].contains(viewModel.selectedTool) {
                        let diameter = viewModel.selectedTool == .highlighter
                            ? max(8, viewModel.brushSize * 2.4)
                            : max(4, viewModel.brushSize)
                        Circle()
                            .strokeBorder(
                                viewModel.selectedTool == .eraser
                                    ? Color.white.opacity(0.9)
                                    : viewModel.selectedColor.swiftUIColor,
                                lineWidth: 1.5
                            )
                            .background(
                                Circle()
                                    .stroke(Color.black.opacity(0.45), lineWidth: 0.75)
                            )
                            .frame(width: diameter, height: diameter)
                            .position(hoverLocation)
                            .allowsHitTesting(false)
                    }
                }
            }
            .coordinateSpace(name: "canvasSpace")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        if gestureStartZoom == nil {
                            gestureStartZoom = viewModel.zoomScale
                        }
                        if let start = gestureStartZoom {
                            viewModel.zoomScale = min(max(start * value.magnification, 0.25), 5.0)
                        }
                    }
                    .onEnded { _ in
                        gestureStartZoom = nil
                    }
            )
        }
    }

    // MARK: - Live Canvas Annotation Rendering

    private func drawPreviewAnnotation(
        _ stroke: Stroke,
        in context: inout GraphicsContext,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        guard !stroke.points.isEmpty else { return }

        switch stroke.tool {
        case .pen:
            guard let swiftUIPath = scaledPath(CanvasGeometry.smoothedPath(for: stroke.points), scaleX: scaleX, scaleY: scaleY) else { return }
            let style = StrokeStyle(lineWidth: stroke.lineWidth * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.blendMode = .normal
                layer.stroke(swiftUIPath, with: .color(stroke.color.swiftUIColor), style: style)
            }

        case .highlighter:
            guard let swiftUIPath = scaledPath(CanvasGeometry.smoothedPath(for: stroke.points), scaleX: scaleX, scaleY: scaleY) else { return }
            let style = StrokeStyle(lineWidth: stroke.lineWidth * 2.4 * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.blendMode = .normal
                layer.stroke(swiftUIPath, with: .color(stroke.color.withAlpha(0.38).swiftUIColor), style: style)
            }

        case .eraser:
            guard let swiftUIPath = scaledPath(CanvasGeometry.smoothedPath(for: stroke.points), scaleX: scaleX, scaleY: scaleY) else { return }
            let style = StrokeStyle(lineWidth: stroke.lineWidth * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.blendMode = .destinationOut
                layer.stroke(swiftUIPath, with: .color(.black), style: style)
            }

        case .rectangle:
            guard stroke.points.count >= 2 else { return }
            let p0 = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let p1 = CGPoint(x: stroke.points[1].x * scaleX, y: stroke.points[1].y * scaleY)
            let rect = CanvasGeometry.rect(from: p0, to: p1)
            let style = StrokeStyle(lineWidth: stroke.lineWidth * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.stroke(Path(rect), with: .color(stroke.color.swiftUIColor), style: style)
            }

        case .ellipse:
            guard stroke.points.count >= 2 else { return }
            let p0 = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let p1 = CGPoint(x: stroke.points[1].x * scaleX, y: stroke.points[1].y * scaleY)
            let rect = CanvasGeometry.rect(from: p0, to: p1)
            let style = StrokeStyle(lineWidth: stroke.lineWidth * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.stroke(Path(ellipseIn: rect), with: .color(stroke.color.swiftUIColor), style: style)
            }

        case .arrow:
            guard stroke.points.count >= 2 else { return }
            let p0 = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let p1 = CGPoint(x: stroke.points[1].x * scaleX, y: stroke.points[1].y * scaleY)
            let arrowCG = CanvasGeometry.arrowPath(from: p0, to: p1, lineWidth: stroke.lineWidth * scaleX)
            let style = StrokeStyle(lineWidth: stroke.lineWidth * scaleX, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.stroke(Path(arrowCG), with: .color(stroke.color.swiftUIColor), style: style)
            }

        case .pixelate:
            // Only draw dashed selection preview while actively dragging
            guard stroke.id == viewModel.activeStroke?.id, stroke.points.count >= 2 else { return }
            let p0 = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let p1 = CGPoint(x: stroke.points[1].x * scaleX, y: stroke.points[1].y * scaleY)
            let rect = CanvasGeometry.rect(from: p0, to: p1)
            context.stroke(
                Path(rect),
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )

        case .text:
            guard let text = stroke.text, !text.isEmpty else { return }
            let origin = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let fontSize = max(16, stroke.lineWidth * 3.0) * scaleX
            let resolvedText = context.resolve(
                Text(text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(stroke.color.swiftUIColor)
            )
            let textSize = resolvedText.measure(in: CGSize(width: 2000, height: 1000))
            let padX = fontSize * 0.45
            let padY = fontSize * 0.25
            let pillRect = CGRect(
                x: origin.x,
                y: origin.y,
                width: textSize.width + padX * 2,
                height: textSize.height + padY * 2
            )
            let isLightText = (stroke.color.red + stroke.color.green + stroke.color.blue) / 3.0 > 0.65
            let bgColor = isLightText ? Color.black.opacity(0.72) : Color.white.opacity(0.85)
            context.fill(
                Path(roundedRect: pillRect, cornerRadius: fontSize * 0.35),
                with: .color(bgColor)
            )
            context.draw(
                resolvedText,
                at: CGPoint(x: pillRect.minX + padX, y: pillRect.minY + padY),
                anchor: .topLeading
            )

        case .stepBadge:
            let center = CGPoint(x: stroke.points[0].x * scaleX, y: stroke.points[0].y * scaleY)
            let number = stroke.badgeNumber ?? 1
            let diameter = max(28, stroke.lineWidth * 4.0) * scaleX
            let circleRect = CGRect(
                x: center.x - diameter * 0.5,
                y: center.y - diameter * 0.5,
                width: diameter,
                height: diameter
            )
            let circlePath = Path(ellipseIn: circleRect)
            context.fill(circlePath, with: .color(stroke.color.swiftUIColor))
            context.stroke(circlePath, with: .color(.white), lineWidth: max(1.5, diameter * 0.08))

            let isLightFill = (stroke.color.red * 0.299 + stroke.color.green * 0.587 + stroke.color.blue * 0.114) > 0.72
            let resolvedNum = context.resolve(
                Text("\(number)")
                    .font(.system(size: diameter * 0.52, weight: .bold))
                    .foregroundColor(isLightFill ? .black : .white)
            )
            context.draw(resolvedNum, at: center, anchor: .center)

        case .eyedropper:
            break
        }
    }

    private func scaledPath(_ cgPath: CGPath, scaleX: CGFloat, scaleY: CGFloat) -> Path? {
        var transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        guard let copy = cgPath.copy(using: &transform) else { return nil }
        return Path(copy)
    }

    // MARK: - Crop Helpers

    private func handleCropDragChanged(_ value: DragGesture.Value, imageRect: CGRect) {
        let current = CanvasGeometry.viewToImage(
            point: value.location,
            imageRect: imageRect,
            imageSize: viewModel.imagePixelSize
        )
        if cropDragStart == nil {
            cropDragStart = current
        }
        if let start = cropDragStart {
            viewModel.cropRect = CanvasGeometry.rect(from: start, to: current)
        }
    }

    @ViewBuilder
    private func cropOverlay(cropRect: CGRect, imageRect: CGRect) -> some View {
        let topLeft = CanvasGeometry.imageToView(
            point: cropRect.origin,
            imageRect: imageRect,
            imageSize: viewModel.imagePixelSize
        )
        let bottomRight = CanvasGeometry.imageToView(
            point: CGPoint(x: cropRect.maxX, y: cropRect.maxY),
            imageRect: imageRect,
            imageSize: viewModel.imagePixelSize
        )
        let viewCropRect = CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: max(4, bottomRight.x - topLeft.x),
            height: max(4, bottomRight.y - topLeft.y)
        )

        ZStack(alignment: .top) {
            Path { path in
                path.addRect(imageRect)
                path.addRect(viewCropRect)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2))
                .frame(width: viewCropRect.width, height: viewCropRect.height)
                .position(x: viewCropRect.midX, y: viewCropRect.midY)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                Text("Drag on image to select crop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { viewModel.cancelCrop() }
                    .buttonStyle(.bordered)
                Button("Apply Crop") { viewModel.applyCrop() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial, in: Capsule())
            .shadow(radius: 8)
            .padding(.top, 12)
        }
    }
}
