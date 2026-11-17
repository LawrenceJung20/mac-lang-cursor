import CoreGraphics

/// Placement for a centered sprite square, using AppKit desktop coordinates.
public enum CatPlacement {
    public static func target(cursor: CGPoint, screen: CGRect, catSize: CGSize) -> CGPoint {
        clamp(
            position: CGPoint(x: cursor.x - catSize.width * 0.58, y: cursor.y - catSize.height * 0.65),
            to: screen,
            catSize: catSize
        )
    }

    public static func clamp(position: CGPoint, to screen: CGRect, catSize: CGSize) -> CGPoint {
        let insetX = max(0, catSize.width / 2) + 4
        let insetY = max(0, catSize.height / 2) + 4
        let x = screen.width < insetX * 2
            ? screen.midX
            : min(max(position.x, screen.minX + insetX), screen.maxX - insetX)
        let y = screen.height < insetY * 2
            ? screen.midY
            : min(max(position.y, screen.minY + insetY), screen.maxY - insetY)
        return CGPoint(x: x, y: y)
    }
}
