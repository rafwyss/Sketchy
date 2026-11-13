import AppKit
import CoreGraphics
import SwiftUI

/// Drawing and annotation tools supported on the canvas.
public enum ToolType: String, Sendable, CaseIterable {
    case pen
    case highlighter
    case eraser
    case arrow
    case rectangle
    case ellipse
    case text
    case stepBadge
    case pixelate
    case eyedropper

    public var displayName: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Circle / Ellipse"
        case .text: "Text Callout"
        case .stepBadge: "Step Badge"
        case .pixelate: "Blur / Pixelate"
        case .eyedropper: "Eyedropper"
        }
    }

    public var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser.fill"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .stepBadge: "1.circle.fill"
        case .pixelate: "checkerboard.rectangle"
        case .eyedropper: "eyedropper"
        }
    }
}

/// Sendable RGBA color representation for annotations.
public struct StrokeColor: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = converted.redComponent
        self.green = converted.greenComponent
        self.blue = converted.blueComponent
        self.alpha = converted.alphaComponent
    }

    public init(color: Color) {
        self.init(nsColor: NSColor(color))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ newAlpha: CGFloat) -> StrokeColor {
        StrokeColor(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Default Gemini-Web-inspired palette presets.
    public static let presets: [(name: String, color: StrokeColor)] = [
        ("Red", StrokeColor(red: 0.92, green: 0.26, blue: 0.21)),
        ("Orange", StrokeColor(red: 0.98, green: 0.55, blue: 0.00)),
        ("Yellow", StrokeColor(red: 0.98, green: 0.74, blue: 0.02)),
        ("Green", StrokeColor(red: 0.20, green: 0.66, blue: 0.33)),
        ("Blue", StrokeColor(red: 0.26, green: 0.52, blue: 0.96)),
        ("Purple", StrokeColor(red: 0.61, green: 0.32, blue: 0.88)),
        ("White", StrokeColor(red: 1.00, green: 1.00, blue: 1.00)),
        ("Black", StrokeColor(red: 0.10, green: 0.10, blue: 0.12))
    ]
}

/// An annotation element stored in image-pixel coordinates.
public struct Stroke: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var points: [CGPoint]
    public let color: StrokeColor
    public let lineWidth: CGFloat
    public let tool: ToolType
    public var text: String?
    public var badgeNumber: Int?

    public init(
        id: UUID = UUID(),
        points: [CGPoint],
        color: StrokeColor,
        lineWidth: CGFloat,
        tool: ToolType,
        text: String? = nil,
        badgeNumber: Int? = nil
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.tool = tool
        self.text = text
        self.badgeNumber = badgeNumber
    }
}
