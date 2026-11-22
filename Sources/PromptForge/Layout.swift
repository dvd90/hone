import CoreGraphics

extension FlowLayout {
    /// Pure row-wrapping math for FlowLayout, kept out of the view file so it is unit-tested.
    static func arrange(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in sizes {
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + s.width)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}
