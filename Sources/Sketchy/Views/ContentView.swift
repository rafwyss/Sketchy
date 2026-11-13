import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: SketchViewModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if viewModel.hasImage {
                SketchCanvasView(viewModel: viewModel)
                    .padding(24)
                    .padding(.bottom, 86)

                VStack {
                    Spacer()
                    AnnotationToolbar(viewModel: viewModel)
                        .padding(.bottom, 16)
                }
            } else {
                EmptyDropZoneView(
                    isDropTargeted: viewModel.isDropTargeted,
                    onPaste: { viewModel.pasteFromClipboard() },
                    onOpenFile: { viewModel.openFilePanel() },
                    onBlankCanvas: { viewModel.createBlankCanvas() }
                )
                .padding(32)
            }

            // Drop overlay when replacing an existing image
            if viewModel.hasImage && viewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 16)))
                    .padding(16)
                    .allowsHitTesting(false)
            }

            // Toast notification banner
            if let toast = viewModel.toastMessage {
                VStack {
                    Text(toast)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThickMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .padding(.top, 14)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.toastMessage)
        .onDrop(of: [.fileURL, .image], isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    viewModel.openFilePanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open Image (⌘O)")

                Button {
                    viewModel.pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .help("Paste Image from Clipboard (⌘V)")

                Button {
                    viewModel.createBlankCanvas()
                } label: {
                    Label("Blank", systemImage: "square.and.pencil")
                }
                .help("New Blank Canvas (⌘N)")

                Button {
                    viewModel.removeImage()
                } label: {
                    Label("Remove Image", systemImage: "xmark.circle")
                }
                .disabled(!viewModel.hasImage)
                .help("Remove Current Image (⌘⌫)")
            }

            ToolbarItemGroup(placement: .principal) {
                Button {
                    viewModel.rotateClockwise()
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .disabled(!viewModel.hasImage)
                .help("Rotate 90° Clockwise (⌘R)")

                Button {
                    viewModel.toggleCropMode()
                } label: {
                    Label("Crop", systemImage: "crop")
                }
                .disabled(!viewModel.hasImage)
                .help("Crop Image")

                Button {
                    viewModel.isPanMode.toggle()
                } label: {
                    Label("Pan", systemImage: viewModel.isPanMode ? "hand.raised.fill" : "hand.raised")
                }
                .disabled(!viewModel.hasImage)
                .help("Pan Canvas (or hold ⌥ Option while dragging)")

                Divider()

                Button {
                    viewModel.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(!viewModel.hasImage)
                .help("Zoom Out (⌘-)")

                Button {
                    viewModel.resetZoom()
                } label: {
                    Text("\(Int((viewModel.zoomScale * 100).rounded()))%")
                        .monospacedDigit()
                        .font(.caption.weight(.medium))
                }
                .disabled(!viewModel.hasImage)
                .help("Reset Zoom (⌘0)")

                Button {
                    viewModel.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(!viewModel.hasImage)
                .help("Zoom In (⌘+)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }
                .disabled(!viewModel.hasImage)
                .help("Copy Annotated Image (⌘C)")

                Button {
                    viewModel.saveToFile()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .disabled(!viewModel.hasImage)
                .help("Save Annotated Image (⌘S)")
            }
        }
        .frame(minWidth: 820, minHeight: 580)
    }
}
