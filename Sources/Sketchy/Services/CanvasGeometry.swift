import CoreGraphics

/// Shared coordinate mapping, shape math, and path smoothing between SwiftUI view and image-pixel space.
public enum CanvasGeometry {
    /// Computes the aspect-fit rectangle for an image of `imageSize` inside `containerSize`.
    public static func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedWidth = imageSize.width * scale
        let fittedHeight = imageSize.height * scale
        let originX = (containerSize.width - fittedWidth) * 0.5
        let originY = (containerSize.height - fittedHeight) * 0.5
        return CGRect(x: originX, y: originY, width: fittedWidth, height: fittedHeight)
    }

    /// Converts a point in view coordinates to image-pixel coordinates, clamped to image bounds.
    public static func viewToImage(
        point: CGPoint,
        imageRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let normalizedX = min(max((point.x - imageRect.minX) / imageRect.width, 0), 1)
        let normalizedY = min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
        return CGPoint(
            x: normalizedX * imageSize.width,
            y: normalizedY * imageSize.height
        )
    }

    /// Converts a point in image-pixel coordinates to view coordinates.
    public static func imageToView(
        point: CGPoint,
        imageRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scaleX = imageRect.width / imageSize.width
        let scaleY = imageRect.height / imageSize.height
        return CGPoint(
            x: imageRect.minX + point.x * scaleX,
            y: imageRect.minY + point.y * scaleY
        )
    }

    /// Builds a normalized rectangle from two corner points.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Snaps `end` relative to `start` when Shift is held:
    /// - for `.rectangle` / `.ellipse`: constrains to a 1:1 square/circle
    /// - for `.arrow`: snaps angle to nearest 45° increment
    public static func snappedEndPoint(from start: CGPoint, to end: CGPoint, tool: ToolType) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        switch tool {
        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(
                x: start.x + (dx >= 0 ? side : -side),
                y: start.y + (dy >= 0 ? side : -side)
            )
        case .arrow:
            let length = hypot(dx, dy)
            guard length > 0 else { return end }
            let angle = atan2(dy, dx)
            let snapStep = CGFloat.pi / 4
            let snappedAngle = (angle / snapStep).rounded() * snapStep
            return CGPoint(
                x: start.x + cos(snappedAngle) * length,
                y: start.y + sin(snappedAngle) * length
            )
        default:
            return end
        }
    }

    /// Builds a smooth quadratic Bézier CGPath through `points`.
    public static func smoothedPath(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }

        if points.count == 1 {
            path.move(to: first)
            path.addLine(to: first)
            return path
        }

        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(
                x: (current.x + next.x) * 0.5,
                y: (current.y + next.y) * 0.5
            )
            path.addQuadCurve(to: midpoint, control: current)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    /// Builds an arrow CGPath from `start` to `end` with a proportional arrowhead.
    public static func arrowPath(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return path }

        path.move(to: start)
        path.addLine(to: end)

        let headLength = min(max(lineWidth * 3.2, 12), length * 0.45)
        let angle = atan2(dy, dx)
        let spread: CGFloat = .pi / 6.5

        let wing1 = CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let wing2 = CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )

        path.move(to: wing1)
        path.addLine(to: end)
        path.addLine(to: wing2)
        return path
    }

    /// Rotates a point 90 degrees clockwise inside an image of `originalSize` (top-left origin).
    public static func rotatePointClockwise(_ point: CGPoint, originalSize: CGSize) -> CGPoint {
        CGPoint(x: originalSize.height - point.y, y: point.x)
    }

    /// Translates a point into a cropped image coordinate space.
    public static func translatePointForCrop(_ point: CGPoint, cropRect: CGRect) -> CGPoint {
        CGPoint(x: point.x - cropRect.minX, y: point.y - cropRect.minY)
    }
}
