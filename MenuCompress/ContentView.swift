import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var session: CompressSession
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.phase {
            case .empty: emptyState
            case .loading: loading
            case .cropping: cropping
            case .done: done
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.arrow.down")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop an image on the menu bar icon")
                    .font(.headline)
                Text("It'll be cropped to \(session.aspect.label) and saved as a \(outputSizeLabel) JPEG just under 1 MB.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Choose Image…", action: chooseImage)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            if let errorMessage = session.errorMessage {
                errorLabel(errorMessage)
            }

            HStack {
                Picker("Crop", selection: $session.aspect) {
                    ForEach(CropAspect.allCases) { aspect in
                        Text(aspect.label).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Button("Check for Updates…", action: checkForUpdates)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate()
        panel.begin { response in
            if response == .OK, let url = panel.url {
                session.load(url)
            }
        }
    }

    // MARK: - Loading

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Cropping

    @ViewBuilder
    private var cropping: some View {
        if let source = session.source {
            HStack(alignment: .firstTextBaseline) {
                Text(source.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(cropSizeLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isUpscaling ? .orange : .secondary)
                    .help(isUpscaling ? "The crop is smaller than \(outputSizeLabel), so it'll be upscaled." : "")
            }

            CropEditor(image: source.preview, pixelSize: source.pixelSize, ratio: session.aspect.ratio, crop: $session.crop)
                .frame(maxWidth: .infinity, maxHeight: 360)
                .overlay {
                    if session.isCompressing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

            if let errorMessage = session.errorMessage {
                errorLabel(errorMessage)
            }

            HStack {
                Button("Cancel", action: session.reset)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Compress Without Cropping") { session.compress(cropping: false) }
                    .help("Keep the whole image and its shape, shrinking it only as much as needed to fit under 1 MB")
                    .disabled(session.isCompressing)
                Button("Compress") { session.compress() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.isCompressing)
            }
        }
    }

    private var cropSizeLabel: String {
        let width = Int(session.crop.width.rounded())
        let height = Int((session.crop.width / session.aspect.ratio).rounded())
        return "\(width) × \(height) → \(outputSizeLabel)"
    }

    private var outputSizeLabel: String {
        "\(session.aspect.outputWidth) × \(session.aspect.outputHeight)"
    }

    private var isUpscaling: Bool {
        session.crop.width.rounded() < CGFloat(session.aspect.outputWidth)
    }

    // MARK: - Done

    @ViewBuilder
    private var done: some View {
        if let result = session.result {
            Group {
                if let preview = result.preview {
                    // Uncropped results keep the source's shape, so use the preview's own ratio
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(2, contentMode: .fit)
                        .background(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: 360)
            .onDrag {
                // Without a suggested name, Finder names the dropped file after its type ("JPEG image")
                let provider = NSItemProvider(contentsOf: result.output.url) ?? NSItemProvider()
                provider.suggestedName = result.output.url.lastPathComponent
                return provider
            }
            .help("Drag to a folder")

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.output.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(result.output.byteCount.formatted(.byteCount(style: .file))) · quality \(result.output.quality)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Drag the image to a folder", systemImage: "hand.draw")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Adjust Crop", action: session.adjustCrop)
                Spacer()
                Button("New Image", action: session.reset)
            }
        }
    }

    // MARK: - Shared

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }
}
