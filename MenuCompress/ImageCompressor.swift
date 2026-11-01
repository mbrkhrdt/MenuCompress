import Accelerate
import CJpegli
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageCompressor {
    static let outputWidth = 2048
    static let outputHeight = 1024
    // "Just under 1 MB" in decimal bytes, so it also clears any 1 MiB limit
    static let byteLimit = 1_000_000
    // Uncropped images shrink only as far as needed to stay at or below this jpegli distance (its quality 97).
    // That scores about 90 on ssimulacra2 for photos; going tighter costs far more pixels than it gains.
    static let uncroppedDistanceCeiling: Float = 0.4

    // jpegli distances for quality 100 and quality 0
    private static let bestDistance: Float = 0.1
    private static let worstDistance: Float = 25

    struct Decoded: @unchecked Sendable {
        let full: CGImage
        let preview: CGImage
    }

    struct Output: Sendable {
        let url: URL
        let byteCount: Int
        /// jpegli's equivalent 0–100 quality for the distance that was used.
        let quality: Int
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

    /// Crops (in pixel coordinates, top-left origin) and scales to 2048×1024, or with no crop keeps the
    /// aspect ratio and shrinks only as needed, then writes the best jpegli JPEG under the byte limit.
    static func compress(_ image: CGImage, crop: CGRect?, baseName: String) throws -> Output {
        let colorSpace = outputColorSpace(for: image)
        let final: Bitmap
        if let crop {
            guard let cropped = image.cropping(to: pixelRect(for: crop, in: image)) else { throw Failure.encodeFailed }
            final = try Bitmap(cropped, colorSpace: colorSpace).resized(width: outputWidth, height: outputHeight)
        } else {
            final = try shrinkToFit(Bitmap(image, colorSpace: colorSpace))
        }

        let (data, distance) = try bestJPEG(for: final)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuCompress", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(baseName)-\(final.width)x\(final.height).jpg")
        try data.write(to: url)

        return Output(url: url, byteCount: data.count, quality: equivalentQuality(for: distance))
    }

    // Snap to whole pixels while keeping an exact 2:1 ratio so the scale doesn't stretch
    private static func pixelRect(for crop: CGRect, in image: CGImage) -> CGRect {
        let width = min(crop.width.rounded(), CGFloat(image.width))
        let height = min((width / 2).rounded(), CGFloat(image.height))
        let x = min(max(crop.minX.rounded(), 0), CGFloat(image.width) - width)
        let y = min(max(crop.minY.rounded(), 0), CGFloat(image.height) - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // Keep the source's RGB profile (e.g. Display P3) when it can be written out, otherwise sRGB
    private static func outputColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput, space.copyICCData() != nil {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// The largest copy of `original` whose JPEG at the distance ceiling fits under the limit.
    private static func shrinkToFit(_ original: Bitmap) throws -> Bitmap {
        var candidate = original
        // File size roughly tracks pixel count, so rescale by the overshoot each pass; usually 1–3 passes
        for _ in 0..<8 {
            guard let data = jpeg(candidate, distance: uncroppedDistanceCeiling) else { throw Failure.encodeFailed }
            if data.count < byteLimit { return candidate }

            let factor = (Double(byteLimit) * 0.97 / Double(data.count)).squareRoot()
            let width = max(1, Int(Double(candidate.width) * factor))
            let height = max(1, Int((Double(width) * Double(original.height) / Double(original.width)).rounded()))
            // Always resample from the original so passes don't stack blur
            candidate = try original.resized(width: width, height: height)
        }
        return candidate
    }

    // Search jpegli's distance (log scale, it spans 0.1–25) for the best one that fits under the limit
    private static func bestJPEG(for bitmap: Bitmap) throws -> (Data, Float) {
        guard let best = jpeg(bitmap, distance: bestDistance) else { throw Failure.encodeFailed }
        if best.count < byteLimit {
            return (best, bestDistance)
        }

        guard let worst = jpeg(bitmap, distance: worstDistance) else { throw Failure.encodeFailed }
        guard worst.count < byteLimit else { throw Failure.overLimit }

        var tooLarge = bestDistance
        var fits = (worst, worstDistance)
        for _ in 0..<10 {
            let distance = (tooLarge * fits.1).squareRoot()
            guard let data = jpeg(bitmap, distance: distance) else { throw Failure.encodeFailed }
            if data.count < byteLimit {
                fits = (data, distance)
            } else {
                tooLarge = distance
            }
        }
        return fits
    }

    private static func jpeg(_ bitmap: Bitmap, distance: Float) -> Data? {
        var size = 0
        let bytes = bitmap.icc.withUnsafeBytes { icc in
            cjpegli_encode_rgbx(
                bitmap.buffer.data.assumingMemoryBound(to: UInt8.self),
                Int32(bitmap.width),
                Int32(bitmap.height),
                bitmap.buffer.rowBytes,
                distance,
                icc.bindMemory(to: UInt8.self).baseAddress,
                icc.count,
                &size
            )
        }
        guard let bytes else { return nil }
        return Data(bytesNoCopy: bytes, count: size, deallocator: .free)
    }

    private static func equivalentQuality(for distance: Float) -> Int {
        (0...100).min { abs(cjpegli_quality_to_distance(Int32($0)) - distance) < abs(cjpegli_quality_to_distance(Int32($1)) - distance) } ?? 0
    }
}

/// 8-bit RGBX pixels in a fixed color space, owned by vImage.
private nonisolated final class Bitmap {
    let buffer: vImage_Buffer
    let colorSpace: CGColorSpace
    let icc: Data

    var width: Int { Int(buffer.width) }
    var height: Int { Int(buffer.height) }

    private init(buffer: vImage_Buffer, colorSpace: CGColorSpace) {
        self.buffer = buffer
        self.colorSpace = colorSpace
        self.icc = (colorSpace.copyICCData() as Data?) ?? Data()
    }

    /// Converts `image` into `colorSpace`, dropping alpha.
    convenience init(_ image: CGImage, colorSpace: CGColorSpace) throws {
        guard let format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        ),
            let buffer = try? vImage_Buffer(cgImage: image, format: format)
        else { throw ImageCompressor.Failure.encodeFailed }

        self.init(buffer: buffer, colorSpace: colorSpace)
    }

    deinit {
        buffer.free()
    }

    /// Lanczos resample, which keeps noticeably more fine detail than Core Graphics' high-quality scaling.
    func resized(width: Int, height: Int) throws -> Bitmap {
        var source = buffer
        guard var destination = try? vImage_Buffer(width: width, height: height, bitsPerPixel: 32)
        else { throw ImageCompressor.Failure.encodeFailed }

        let error = vImageScale_ARGB8888(&source, &destination, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else {
            destination.free()
            throw ImageCompressor.Failure.encodeFailed
        }
        return Bitmap(buffer: destination, colorSpace: colorSpace)
    }
}
