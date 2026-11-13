import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SketchyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = SketchViewModel()

    var body: some Scene {
        WindowGroup("Sketchy") {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Blank Canvas") {
                    viewModel.createBlankCanvas()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Image…") {
                    viewModel.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save Annotated Image…") {
                    viewModel.saveToFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.hasImage)

                Divider()

                Button("Remove Image") {
                    viewModel.removeImage()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!viewModel.hasImage)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    viewModel.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndo)

                Button("Redo") {
                    viewModel.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedo)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Paste Image") {
                    viewModel.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Copy Annotated Image") {
                    viewModel.copyToClipboard()
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!viewModel.hasImage)
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    viewModel.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!viewModel.hasImage)

                Button("Zoom Out") {
                    viewModel.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!viewModel.hasImage)

                Button("Actual Size (100%)") {
                    viewModel.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!viewModel.hasImage)

                Divider()

                Button("Rotate 90° Clockwise") {
                    viewModel.rotateClockwise()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!viewModel.hasImage)
            }
        }
    }
}
