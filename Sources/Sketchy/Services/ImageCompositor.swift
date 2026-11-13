import AppKit
import CoreGraphics

/// Renders the base image, pixelation redactions, and non-destructive annotation layer at full resolution.
public enum ImageCompositor {
    /// Returns the true pixel dimensions of an `NSImage`.
    public static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    /// Creates a solid blank canvas image of the requested pixel dimensions.
    public static func makeBlankCanvas(width: Int = 1600, height: Int = 1000, color: NSColor = .white) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    /// Samples the sRGB pixel color at a top-left image-pixel coordinate.
    public static func sampleColor(in image: NSImage, at pixelPoint: CGPoint) -> StrokeColor? {
        let size = pixelSize(of: image)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        let x = min(max(Int(pixelPoint.x.rounded(.down)), 0), width - 1)
        let y = min(max(Int(pixelPoint.y.rounded(.down)), 0), height - 1)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return StrokeColor(nsColor: color)
    }

    /// Rotates `image` 90 degrees clockwise at exact pixel resolution.
    public static func rotateClockwise(_ image: NSImage) -> NSImage? {
        let size = pixelSize(of: image)
        let oldW = Int(size.width.rounded())
        let oldH = Int(size.height.rounded())
        guard oldW > 0, oldH > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: oldH,
                  height: oldW,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        // Rotate -90 deg around origin, then translate into (oldH x oldW)
        ctx.translateBy(x: 0, y: CGFloat(oldW))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: oldW, height: oldH))

        guard let rotatedCG = ctx.makeImage() else { return nil }
        return nsImage(from: rotatedCG, width: oldH, height: oldW)
    }

    /// Crops `image` to `pixelRect` (in top-left image-pixel coordinates).
    public static func crop(_ image: NSImage, to pixelRect: CGRect) -> NSImage? {
        let size = pixelSize(of: image)
        let bounds = CGRect(origin: .zero, size: size)
        let clamped = pixelRect.integral.intersection(bounds)
        guard clamped.width >= 4, clamped.height >= 4,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCG = cgImage.cropping(to: clamped) else {
            return nil
        }
        return nsImage(from: croppedCG, width: Int(clamped.width), height: Int(clamped.height))
    }

    /// Returns a version of `baseImage` with all `.pixelate` regions baked in (used for live canvas preview).
    public static func renderBaseWithPixelations(baseImage: NSImage, annotations: [Stroke]) -> NSImage? {
        let pixelateStrokes = annotations.filter { $0.tool == .pixelate && $0.points.count >= 2 }
        if pixelateStrokes.isEmpty { return baseImage }
        return renderComposite(baseImage: baseImage, strokes: pixelateStrokes)
    }

    /// Composites all `strokes` (pixelations + ink/shapes/text/badges/eraser) on top of `baseImage`
    /// at its exact pixel resolution.
    public static func renderComposite(baseImage: NSImage, strokes: [Stroke]) -> NSImage? {
        let size = pixelSize(of: baseImage)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let finalContext = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        let baseCG = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let baseCG {
            finalContext.draw(baseCG, in: fullRect)
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: finalContext, flipped: false)
            baseImage.draw(in: fullRect)
            NSGraphicsContext.restoreGraphicsState()
        }

        // 1. Apply pixelate redactions directly onto the base image context.
        if let baseCG {
            for stroke in strokes where stroke.tool == .pixelate && stroke.points.count >= 2 {
                let rectTopLeft = CanvasGeometry.rect(from: stroke.points[0], to: stroke.points[1])
                applyPixelation(
                    to: finalContext,
                    baseCGImage: baseCG,
                    regionTopLeft: rectTopLeft,
                    imageWidth: width,
                    imageHeight: height,
                    blockSize: max(12, stroke.lineWidth * 1.8)
                )
            }
        }

        // 2. Render all non-pixelate annotations in an isolated top-down transparent layer.
        let inkStrokes = strokes.filter { $0.tool != .pixelate && $0.tool != .eyedropper }
        if !inkStrokes.isEmpty,
           let strokeContext = CGContext(
               data: nil,
               width: width,
               height: height,
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            strokeContext.translateBy(x: 0, y: CGFloat(height))
            strokeContext.scaleBy(x: 1, y: -1)
            strokeContext.setLineCap(.round)
            strokeContext.setLineJoin(.round)

            for stroke in inkStrokes {
                drawAnnotation(stroke, in: strokeContext)
            }

            if let strokeImage = strokeContext.makeImage() {
                finalContext.draw(strokeImage, in: fullRect)
            }
        }

        guard let outputCGImage = finalContext.makeImage() else { return nil }
        return nsImage(from: outputCGImage, width: width, height: height)
    }

    /// Encodes an `NSImage` as PNG or JPEG data.
    public static func encode(_ image: NSImage, format: NSBitmapImageRep.FileType, compression: CGFloat = 0.92) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg
            ? [.compressionFactor: compression]
            : [:]
        return bitmap.representation(using: format, properties: properties)
    }

    // MARK: - Private Rendering Helpers

    private static func nsImage(from cgImage: CGImage, width: Int, height: Int) -> NSImage {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        bitmapRep.size = NSSize(width: width, height: height)
        let outputImage = NSImage(size: NSSize(width: width, height: height))
        outputImage.addRepresentation(bitmapRep)
        return outputImage
    }

    private static func applyPixelation(
        to context: CGContext,
        baseCGImage: CGImage,
        regionTopLeft: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        blockSize: CGFloat
    ) {
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let clamped = regionTopLeft.integral.intersection(bounds)
        guard clamped.width >= 2, clamped.height >= 2,
              let cropped = baseCGImage.cropping(to: clamped),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return
        }

        let smallW = max(1, Int((clamped.width / blockSize).rounded(.down)))
        let smallH = max(1, Int((clamped.height / blockSize).rounded(.down)))
        guard let tinyCtx = CGContext(
            data: nil,
            width: smallW,
            height: smallH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        tinyCtx.interpolationQuality = .medium
        tinyCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let tinyImage = tinyCtx.makeImage() else { return }

        let bottomUpRect = CGRect(
            x: clamped.minX,
            y: CGFloat(imageHeight) - clamped.maxY,
            width: clamped.width,
            height: clamped.height
        )
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(tinyImage, in: bottomUpRect)
        context.restoreGState()
    }

    private static func drawAnnotation(_ stroke: Stroke, in ctx: CGContext) {
        guard !stroke.points.isEmpty else { return }

        switch stroke.tool {
        case .pen:
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.addPath(CanvasGeometry.smoothedPath(for: stroke.points))
            ctx.strokePath()

        case .highlighter:
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.withAlpha(0.38).cgColor)
            ctx.setLineWidth(stroke.lineWidth * 2.4)
            ctx.addPath(CanvasGeometry.smoothedPath(for: stroke.points))
            ctx.strokePath()

        case .eraser:
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.addPath(CanvasGeometry.smoothedPath(for: stroke.points))
            ctx.strokePath()

        case .rectangle:
            guard stroke.points.count >= 2 else { return }
            let rect = CanvasGeometry.rect(from: stroke.points[0], to: stroke.points[1])
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.stroke(rect)

        case .ellipse:
            guard stroke.points.count >= 2 else { return }
            let rect = CanvasGeometry.rect(from: stroke.points[0], to: stroke.points[1])
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.strokeEllipse(in: rect)

        case .arrow:
            guard stroke.points.count >= 2 else { return }
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.addPath(CanvasGeometry.arrowPath(from: stroke.points[0], to: stroke.points[1], lineWidth: stroke.lineWidth))
            ctx.strokePath()

        case .text:
            guard let text = stroke.text, !text.isEmpty else { return }
            let origin = stroke.points[0]
            let fontSize = max(16, stroke.lineWidth * 3.0)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: stroke.color.nsColor
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attrString.size()
            let padX = fontSize * 0.45
            let padY = fontSize * 0.25
            let pillRect = CGRect(
                x: origin.x,
                y: origin.y,
                width: textSize.width + padX * 2,
                height: textSize.height + padY * 2
            )

            ctx.saveGState()
            ctx.setBlendMode(.normal)
            let isLightText = (stroke.color.red + stroke.color.green + stroke.color.blue) / 3.0 > 0.65
            let bgColor = isLightText
                ? NSColor.black.withAlphaComponent(0.72).cgColor
                : NSColor.white.withAlphaComponent(0.85).cgColor
            let pillPath = CGPath(
                roundedRect: pillRect,
                cornerWidth: fontSize * 0.35,
                cornerHeight: fontSize * 0.35,
                transform: nil
            )
            ctx.setFillColor(bgColor)
            ctx.addPath(pillPath)
            ctx.fillPath()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attrString.draw(at: NSPoint(x: pillRect.minX + padX, y: pillRect.minY + padY))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

        case .stepBadge:
            let center = stroke.points[0]
            let number = stroke.badgeNumber ?? 1
            let diameter = max(28, stroke.lineWidth * 4.0)
            let circleRect = CGRect(
                x: center.x - diameter * 0.5,
                y: center.y - diameter * 0.5,
                width: diameter,
                height: diameter
            )

            ctx.saveGState()
            ctx.setBlendMode(.normal)
            ctx.setFillColor(stroke.color.cgColor)
            ctx.fillEllipse(in: circleRect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(max(2, diameter * 0.08))
            ctx.strokeEllipse(in: circleRect)

            let fontSize = diameter * 0.52
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let isLightFill = (stroke.color.red * 0.299 + stroke.color.green * 0.587 + stroke.color.blue * 0.114) > 0.72
            let textColor: NSColor = isLightFill ? .black : .white
            let attrString = NSAttributedString(
                string: "\(number)",
                attributes: [.font: font, .foregroundColor: textColor]
            )
            let textSize = attrString.size()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attrString.draw(at: NSPoint(
                x: center.x - textSize.width * 0.5,
                y: center.y - textSize.height * 0.5
            ))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()

        case .pixelate, .eyedropper:
            break
        }
    }
}
