import SwiftUI

struct AnnotationToolbar: View {
    @Bindable var viewModel: SketchViewModel
    @State private var customColor: Color = StrokeColor.presets[0].color.swiftUIColor

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Drawing & annotation tools
            HStack(spacing: 4) {
                ForEach(ToolType.allCases, id: \.self) { tool in
                    toolButton(tool: tool)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Undo / Redo / Clear
                Button {
                    viewModel.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo (⌘Z)")
                .buttonStyle(.borderless)
                .frame(width: 26, height: 26)

                Button {
                    viewModel.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo (⇧⌘Z)")
                .buttonStyle(.borderless)
                .frame(width: 26, height: 26)

                Button {
                    viewModel.clearStrokes()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(!viewModel.canClear)
                .help("Clear All Annotations")
                .buttonStyle(.borderless)
                .frame(width: 26, height: 26)
            }

            // Row 2: Color swatches + custom ColorPicker + brush size
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(StrokeColor.presets, id: \.name) { preset in
                        let isSelected = viewModel.selectedColor == preset.color
                        Button {
                            if viewModel.selectedTool == .eraser || viewModel.selectedTool == .eyedropper {
                                viewModel.selectedTool = .pen
                            }
                            viewModel.selectedColor = preset.color
                            customColor = preset.color.swiftUIColor
                        } label: {
                            Circle()
                                .fill(preset.color.swiftUIColor)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? Color.white : Color.primary.opacity(0.25),
                                            lineWidth: isSelected ? 2.5 : 1
                                        )
                                )
                                .shadow(color: isSelected ? Color.accentColor.opacity(0.6) : .clear, radius: 3)
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }

                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .fill(customColor)
                                    .frame(width: 9, height: 9)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                            )

                        ColorPicker("", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()
                            .opacity(0.02)
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .frame(width: 20, height: 20)
                    .onChange(of: customColor) { _, newValue in
                        if viewModel.selectedTool == .eraser || viewModel.selectedTool == .eyedropper {
                            viewModel.selectedTool = .pen
                        }
                        viewModel.selectedColor = StrokeColor(color: newValue)
                    }
                    .help("Custom Color")
                }

                Divider()
                    .frame(height: 18)

                HStack(spacing: 6) {
                    ForEach([4.0, 10.0, 20.0], id: \.self) { size in
                        Button {
                            viewModel.brushSize = size
                        } label: {
                            Circle()
                                .fill(abs(viewModel.brushSize - size) < 1.0 ? Color.accentColor : Color.primary.opacity(0.55))
                                .frame(width: max(6, size * 0.65), height: max(6, size * 0.65))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Size \(Int(size))pt")
                    }

                    Slider(value: $viewModel.brushSize, in: 2...40, step: 1)
                        .frame(width: 85)
                        .help("Brush / Stroke Size: \(Int(viewModel.brushSize))pt")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }

    @ViewBuilder
    private func toolButton(tool: ToolType) -> some View {
        let isSelected = !viewModel.isPanMode && !viewModel.isCropMode && viewModel.selectedTool == tool
        Button {
            viewModel.isPanMode = false
            if viewModel.isCropMode {
                viewModel.cancelCrop()
            }
            viewModel.selectedTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}
