import SwiftUI

struct EmptyDropZoneView: View {
    let isDropTargeted: Bool
    let onPaste: () -> Void
    let onOpenFile: () -> Void
    let onBlankCanvas: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
            }

            VStack(spacing: 6) {
                Text(isDropTargeted ? "Drop image to start sketching" : "Drop an image here")
                    .font(.title2.weight(.semibold))

                Text("Paste from clipboard (⌘V), choose a file (⌘O), or start blank")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button(action: onPaste) {
                    Label("Paste Image", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onOpenFile) {
                    Label("Choose File…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onBlankCanvas) {
                    Label("Blank Canvas", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 520, maxHeight: 340)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }
}
