import CoreGraphics

nonisolated enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case twoToOne = "2:1"
    case sixteenByNine = "16:9"

    var id: Self { self }
    var label: String { rawValue }

    var outputWidth: Int {
        switch self {
        case .twoToOne: 2048
        case .sixteenByNine: 1920
        }
    }

    var outputHeight: Int {
        switch self {
        case .twoToOne: 1024
        case .sixteenByNine: 1080
        }
    }

    /// Width over height.
    var ratio: CGFloat { CGFloat(outputWidth) / CGFloat(outputHeight) }
}
