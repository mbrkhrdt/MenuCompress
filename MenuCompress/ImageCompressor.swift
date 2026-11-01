import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageCompressor {
    static let outputWidth = 2048
    static let outputHeight = 1024
    // "Just under 1 MB" in decimal bytes, so it also clears any 1 MiB limit
    static let byteLimit = 1_000_000

    struct Decoded: @unchecked Sendable {
        let full: CGImage
        let preview: CGImage
    }

    struct Output: Sendable {
        let url: URL
        let byteCount: Int
        let quality: Double
    }

    enum Failure: LocalizedError {
        case unreadable
        case encodeFailed
        case overLimit

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file isn't an image MenuCompress can read."
            case .encodeFailed: "Couldn't encode the JPEG."
            case .overLimit: "Couldn't get this image under 1 MB."
            }
        }
    }

    static func isImage(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) ?? false
    }

    /// Decodes upright (EXIF orientation applied) at full resolution, plus a small copy for the crop UI.
    static func decode(_ url: URL) throws -> Decoded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let full = upright(source, maxPixelSize: max(width, height)),
              let preview = upright(source, maxPixelSize: 1600)
        else { throw Failure.unreadable }

        return Decoded(full: full, preview: preview)
    }

    private static func upright(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Crops (in pixel coordinates, top-left origin), scales to 2048×1024, and writes the
    /// highest-quality JPEG that still lands under the byte limit.
    static func compress(_ image: CGImage, crop: CGRect, baseName: String) throws -> Output {
        guard let cropped = image.cropping(to: pixelRect(for: crop, in: image)),
              let scaled = scale(cropped)
        else { throw Failure.encodeFailed }

        let (data, quality) = try bestJPEG(for: scaled)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuCompress", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(baseName)-\(outputWidth)x\(outputHeight).jpg")
        try data.write(to: url)

        return Output(url: url, byteCount: data.count, quality: quality)
    }

    // Snap to whole pixels while keeping an exact 2:1 ratio so the scale doesn't stretch
    private static func pixelRect(for crop: CGRect, in image: CGImage) -> CGRect {
        let width = min(crop.width.rounded(), CGFloat(image.width))
        let height = min((width / 2).rounded(), CGFloat(image.height))
        let x = min(max(crop.minX.rounded(), 0), CGFloat(image.width) - width)
        let y = min(max(crop.minY.rounded(), 0), CGFloat(image.height) - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func scale(_ image: CGImage) -> CGImage? {
        // Keep the source's RGB profile (e.g. Display P3) when we can draw into it
        let sourceSpace = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        let spaces = [sourceSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }

        for space in spaces {
            guard let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
            return context.makeImage()
        }
        return nil
    }

    // Binary search on JPEG quality for the largest file that stays under the limit
    private static func bestJPEG(for image: CGImage) throws -> (Data, Double) {
        if let data = jpeg(image, quality: 1), data.count < byteLimit {
            return (data, 1)
        }

        var low = 0.0
        var high = 1.0
        var best: (Data, Double)?
        for _ in 0..<10 {
            let quality = (low + high) / 2
            guard let data = jpeg(image, quality: quality) else { throw Failure.encodeFailed }
            if data.count < byteLimit {
                best = (data, quality)
                low = quality
            } else {
                high = quality
            }
        }

        guard let best else { throw Failure.overLimit }
        return best
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }

        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
