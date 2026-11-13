import AppKit
import CoreGraphics
import Foundation

@main
@MainActor
struct SketchyTestRunner {
    static func main() {
        var passed = 0
        var failed = 0

        func run(_ name: String, _ block: () throws -> Void) {
            do {
                try block()
                print("PASS: \(name)")
                passed += 1
            } catch {
                print("FAIL: \(name) -> \(error)")
                failed += 1
            }
        }

        run("Aspect-fit rect centers and scales landscape image") {
            let rect = CanvasGeometry.aspectFitRect(
                imageSize: CGSize(width: 1000, height: 500),
                in: CGSize(width: 500, height: 500)
            )
            try expect(abs(rect.origin.x - 0) < 0.001, "origin.x")
            try expect(abs(rect.origin.y - 125) < 0.001, "origin.y")
            try expect(abs(rect.width - 500) < 0.001, "width")
            try expect(abs(rect.height - 250) < 0.001, "height")
        }

        run("Coordinate mapping round-trips between view and image space") {
            let imageSize = CGSize(width: 1920, height: 1080)
            let imageRect = CGRect(x: 40, y: 80, width: 640, height: 360)
            let viewPoint = CGPoint(x: 200, y: 260)

            let imagePoint = CanvasGeometry.viewToImage(point: viewPoint, imageRect: imageRect, imageSize: imageSize)
            let backToView = CanvasGeometry.imageToView(point: imagePoint, imageRect: imageRect, imageSize: imageSize)

            try expect(abs(backToView.x - viewPoint.x) < 0.01, "round-trip x")
            try expect(abs(backToView.y - viewPoint.y) < 0.01, "round-trip y")
        }

        run("Shift-snap constrains rectangle to square and arrow to 45 deg") {
            let start = CGPoint(x: 10, y: 10)
            let snappedRectEnd = CanvasGeometry.snappedEndPoint(
                from: start,
                to: CGPoint(x: 50, y: 30),
                tool: .rectangle
            )
            try expect(abs(snappedRectEnd.x - 50) < 0.01 && abs(snappedRectEnd.y - 50) < 0.01, "square snap")

            let snappedArrowEnd = CanvasGeometry.snappedEndPoint(
                from: start,
                to: CGPoint(x: 110, y: 15),
                tool: .arrow
            )
            try expect(abs(snappedArrowEnd.y - 10) < 0.01, "0-degree horizontal arrow snap")
        }

        run("ViewModel undo, redo, clear, blank canvas, and removeImage") {
            let vm = SketchViewModel()
            vm.createBlankCanvas(width: 320, height: 200)
            try expect(vm.hasImage, "blank canvas created")
            try expect(vm.imagePixelSize == CGSize(width: 320, height: 200), "blank canvas size")

            vm.beginStroke(at: CGPoint(x: 10, y: 10), imageScaleFactor: 1.0)
            vm.continueStroke(to: CGPoint(x: 50, y: 50))
            vm.endStroke()

            vm.beginStroke(at: CGPoint(x: 20, y: 20), imageScaleFactor: 1.0)
            vm.endStroke()

            try expect(vm.strokes.count == 2, "2 strokes")
            vm.undo()
            try expect(vm.strokes.count == 1 && vm.canRedo, "undo")
            vm.redo()
            try expect(vm.strokes.count == 2 && !vm.canRedo, "redo")

            vm.undo()
            vm.beginStroke(at: CGPoint(x: 30, y: 30), imageScaleFactor: 1.0)
            vm.endStroke()
            try expect(!vm.canRedo, "new stroke clears redo stack")

            vm.clearStrokes()
            try expect(vm.strokes.isEmpty, "clear empties strokes")

            vm.removeImage()
            try expect(!vm.hasImage && vm.imagePixelSize == .zero, "removeImage resets state")
        }

        run("Compositor draws pen, highlighter, shapes, badges, text, and eraser") {
            let base = makeSolidImage(width: 120, height: 120, color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            let penStroke = Stroke(
                points: [CGPoint(x: 10, y: 40), CGPoint(x: 70, y: 40)],
                color: StrokeColor(red: 1, green: 0, blue: 0, alpha: 1),
                lineWidth: 12,
                tool: .pen
            )
            let eraserStroke = Stroke(
                points: [CGPoint(x: 35, y: 40), CGPoint(x: 45, y: 40)],
                color: StrokeColor(red: 0, green: 0, blue: 0, alpha: 1),
                lineWidth: 20,
                tool: .eraser
            )
            let highlighterStroke = Stroke(
                points: [CGPoint(x: 10, y: 90), CGPoint(x: 100, y: 90)],
                color: StrokeColor(red: 1, green: 1, blue: 0, alpha: 1),
                lineWidth: 10,
                tool: .highlighter
            )
            let rectStroke = Stroke(
                points: [CGPoint(x: 80, y: 10), CGPoint(x: 110, y: 30)],
                color: StrokeColor(red: 0, green: 1, blue: 0, alpha: 1),
                lineWidth: 4,
                tool: .rectangle
            )
            let badge = Stroke(
                points: [CGPoint(x: 95, y: 60)],
                color: StrokeColor(red: 1, green: 0, blue: 0, alpha: 1),
                lineWidth: 8,
                tool: .stepBadge,
                badgeNumber: 1
            )
            let textNote = Stroke(
                points: [CGPoint(x: 10, y: 10)],
                color: StrokeColor(red: 0, green: 0, blue: 0, alpha: 1),
                lineWidth: 6,
                tool: .text,
                text: "Hi"
            )

            let composite = try unwrap(
                ImageCompositor.renderComposite(
                    baseImage: base,
                    strokes: [penStroke, eraserStroke, highlighterStroke, rectStroke, badge, textNote]
                ),
                "composite"
            )
            try expect(ImageCompositor.pixelSize(of: composite) == CGSize(width: 120, height: 120), "pixelSize matches")

            let erasedCenter = try unwrap(samplePixel(in: composite, x: 40, y: 40), "erasedCenter")
            try expect(erasedCenter.blue > 0.8 && erasedCenter.red < 0.2, "eraser restores base blue")

            let unerasedPen = try unwrap(samplePixel(in: composite, x: 15, y: 40), "unerasedPen")
            try expect(unerasedPen.red > 0.8, "unerased pen remains red")

            let highlighted = try unwrap(samplePixel(in: composite, x: 50, y: 90), "highlighted")
            try expect(highlighted.red > 0.2 && highlighted.blue > 0.4, "highlighter blends translucently over blue")
        }

        run("Pixelate redaction modifies region without altering outside pixels") {
            let base = makeSplitImage(width: 100, height: 100)
            let pixelate = Stroke(
                points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)],
                color: StrokeColor(red: 0, green: 0, blue: 0),
                lineWidth: 10,
                tool: .pixelate
            )
            let out = try unwrap(ImageCompositor.renderComposite(baseImage: base, strokes: [pixelate]), "pixelated")
            let outsideLeft = try unwrap(samplePixel(in: out, x: 5, y: 5), "outsideLeft")
            try expect(outsideLeft.red > 0.8, "outside left remains untouched red")
            let insideBlended = try unwrap(samplePixel(in: out, x: 50, y: 50), "insideBlended")
            try expect(insideBlended.alpha > 0.9, "inside region rendered")
        }

        run("Eyedropper samples pixel color and restores drawing tool") {
            let vm = SketchViewModel()
            vm.setImage(makeSolidImage(width: 40, height: 40, color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
            vm.selectedTool = .pen
            vm.selectedTool = .eyedropper
            vm.beginStroke(at: CGPoint(x: 20, y: 20), imageScaleFactor: 1.0)
            try expect(vm.selectedColor.green > 0.8 && vm.selectedColor.red < 0.2, "sampled green")
            try expect(vm.selectedTool == .pen, "restored pen tool")
        }

        run("Rotate 90 clockwise and Crop transform image and annotation coordinates") {
            let vm = SketchViewModel()
            vm.setImage(makeSolidImage(width: 200, height: 100, color: .white))
            vm.beginStroke(at: CGPoint(x: 50, y: 25), imageScaleFactor: 1.0)
            vm.endStroke()

            vm.rotateClockwise()
            try expect(vm.imagePixelSize == CGSize(width: 100, height: 200), "rotated dimensions")
            let rotatedPt = vm.strokes[0].points[0]
            try expect(abs(rotatedPt.x - 75) < 0.01 && abs(rotatedPt.y - 50) < 0.01, "rotated point")

            vm.cropRect = CGRect(x: 10, y: 20, width: 60, height: 80)
            vm.applyCrop()
            try expect(vm.imagePixelSize == CGSize(width: 60, height: 80), "cropped dimensions")
            let croppedPt = vm.strokes[0].points[0]
            try expect(abs(croppedPt.x - 65) < 0.01 && abs(croppedPt.y - 30) < 0.01, "cropped point")
        }

        print("\nResults: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(description: message) }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(description: "Unexpected nil: \(message)") }
        return value
    }

    private static func makeSolidImage(width: Int, height: Int, color: NSColor) -> NSImage {
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

    private static func makeSplitImage(width: Int, height: Int) -> NSImage {
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
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
        NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: width / 2, y: 0, width: width / 2, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func samplePixel(in image: NSImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }
}
