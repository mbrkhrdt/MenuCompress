import AppKit
import Observation

@Observable
final class CompressSession {
    enum Phase {
        case empty
        case loading
        case cropping
        case done
    }

    struct Source {
        let url: URL
        let image: CGImage
        let preview: NSImage

        var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
    }

    struct Result {
        let output: ImageCompressor.Output
        let preview: NSImage?
    }

    private(set) var phase: Phase = .empty
    private(set) var source: Source?
    private(set) var result: Result?
    private(set) var isCompressing = false
    private(set) var errorMessage: String?

    /// Pixel coordinates in the source image, top-left origin, always in `aspect`'s ratio.
    var crop: CGRect = .zero

    /// The user's crop shape, remembered across launches. Only changeable before an image is loaded.
    var aspect = CropAspect(rawValue: UserDefaults.standard.string(forKey: aspectKey) ?? "") ?? .twoToOne {
        didSet { UserDefaults.standard.set(aspect.rawValue, forKey: Self.aspectKey) }
    }
    private static let aspectKey = "cropAspect"

    @ObservationIgnored var presentPopover: (() -> Void)?
    @ObservationIgnored private var loadGeneration = 0

    func load(_ url: URL) {
        presentPopover?()
        discardResult()
        source = nil
        errorMessage = nil
        phase = .loading

        loadGeneration += 1
        let generation = loadGeneration
        Task {
            do {
                let decoded = try await Task.detached { try ImageCompressor.decode(url) }.value
                guard generation == loadGeneration else { return }

                let source = Source(url: url, image: decoded.full, preview: NSImage(cgImage: decoded.preview, size: .zero))
                self.source = source
                crop = Self.defaultCrop(for: source.pixelSize, ratio: aspect.ratio)
                phase = .cropping
            } catch {
                guard generation == loadGeneration else { return }
                errorMessage = error.localizedDescription
                phase = .empty
            }
        }
    }

    /// Without cropping, the whole image keeps its aspect ratio and shrinks only as much as it needs to.
    func compress(cropping: Bool = true) {
        guard let source, !isCompressing else { return }
        isCompressing = true
        errorMessage = nil

        let image = source.image
        let crop = cropping ? crop : nil
        let aspect = aspect
        let baseName = source.url.deletingPathExtension().lastPathComponent
        Task {
            defer { isCompressing = false }
            do {
                let output = try await Task.detached {
                    try ImageCompressor.compress(image, crop: crop, aspect: aspect, baseName: baseName)
                }.value
                discardResult()
                result = Result(output: output, preview: NSImage(contentsOf: output.url))
                phase = .done
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func adjustCrop() {
        phase = .cropping
    }

    func reset() {
        loadGeneration += 1
        discardResult()
        source = nil
        errorMessage = nil
        phase = .empty
    }

    func discardResult() {
        if let url = result?.output.url {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        result = nil
    }

    static func defaultCrop(for size: CGSize, ratio: CGFloat) -> CGRect {
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}
