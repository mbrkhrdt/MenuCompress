import SwiftUI

/// Aspect-locked crop. Drag inside to move, drag a corner to resize, drag outside to draw a new one.
struct CropEditor: View {
    let image: NSImage
    let pixelSize: CGSize
    /// Width over height.
    let ratio: CGFloat
    @Binding var crop: CGRect

    @State private var dragMode: DragMode?

    private enum DragMode {
        case move(from: CGRect)
        case resize(anchor: CGPoint)
        case draw(anchor: CGPoint, original: CGRect)
    }

    private let handleHitRadius: CGFloat = 16
    private let minimumCropWidth: CGFloat = 128

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / pixelSize.width
            let rect = viewRect(scale: scale)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)

                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(rect)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                thirds(in: rect)
                    .stroke(.white.opacity(0.35), lineWidth: 0.5)

                Path(rect)
                    .stroke(.white, lineWidth: 1)

                cornerBrackets(in: rect)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragChanged($0, scale: scale) }
                    .onEnded { _ in dragMode = nil }
            )
        }
        .aspectRatio(pixelSize.width / pixelSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func viewRect(scale: CGFloat) -> CGRect {
        CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
    }

    private func thirds(in rect: CGRect) -> Path {
        Path { path in
            for fraction in [1.0 / 3, 2.0 / 3] {
                let x = rect.minX + rect.width * fraction
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }

    private func cornerBrackets(in rect: CGRect) -> Path {
        let length = min(18, rect.width / 3, rect.height / 3)
        return Path { path in
            for corner in corners(of: rect) {
                let dx: CGFloat = corner.x == rect.minX ? length : -length
                let dy: CGFloat = corner.y == rect.minY ? length : -length
                path.move(to: CGPoint(x: corner.x + dx, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy))
            }
        }
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    // MARK: - Dragging

    private func dragChanged(_ value: DragGesture.Value, scale: CGFloat) {
        if dragMode == nil {
            dragMode = mode(at: value.startLocation, scale: scale)
        }

        let point = clamped(CGPoint(x: value.location.x / scale, y: value.location.y / scale))

        switch dragMode {
        case .move(let original):
            var moved = original.offsetBy(dx: value.translation.width / scale, dy: value.translation.height / scale)
            moved.origin.x = min(max(moved.minX, 0), pixelSize.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), pixelSize.height - moved.height)
            crop = moved
        case .resize(let anchor):
            // Pinned against an edge there may be no room; hold the last good rect instead of collapsing
            let resized = aspectRect(from: anchor, to: point, minimumWidth: minimumCropWidth)
            if resized.width >= min(minimumCropWidth, crop.width) {
                crop = resized
            }
        case .draw(let anchor, let original):
            // Ignore clicks and tiny drags outside the crop so they don't collapse it
            let drawn = aspectRect(from: anchor, to: point, minimumWidth: 0)
            crop = drawn.width >= minimumCropWidth ? drawn : original
        case nil:
            break
        }
    }

    private func mode(at location: CGPoint, scale: CGFloat) -> DragMode {
        let rect = viewRect(scale: scale)
        let opposite = [3, 2, 1, 0]

        for (index, corner) in corners(of: rect).enumerated()
        where hypot(location.x - corner.x, location.y - corner.y) <= handleHitRadius {
            let anchor = corners(of: crop)[opposite[index]]
            return .resize(anchor: anchor)
        }

        if rect.contains(location) {
            return .move(from: crop)
        }

        let start = clamped(CGPoint(x: location.x / scale, y: location.y / scale))
        return .draw(anchor: start, original: crop)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), pixelSize.width), y: min(max(point.y, 0), pixelSize.height))
    }

    /// The `ratio`-shaped rect spanning from `anchor` toward `point`, kept inside the image.
    private func aspectRect(from anchor: CGPoint, to point: CGPoint, minimumWidth: CGFloat) -> CGRect {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let goesRight = dx >= 0
        let goesDown = dy >= 0

        let roomX = goesRight ? pixelSize.width - anchor.x : anchor.x
        let roomY = goesDown ? pixelSize.height - anchor.y : anchor.y
        let maxWidth = min(roomX, roomY * ratio)

        let width = min(max(abs(dx), abs(dy) * ratio, min(minimumWidth, maxWidth)), maxWidth)
        let height = width / ratio

        return CGRect(
            x: goesRight ? anchor.x : anchor.x - width,
            y: goesDown ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }
}
