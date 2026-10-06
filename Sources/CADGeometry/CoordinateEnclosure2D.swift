import CADCore

public struct CoordinateEnclosure2D: Sendable {
    public let x: ScalarInterval
    public let y: ScalarInterval

    public init(x: ScalarInterval, y: ScalarInterval) {
        self.x = x
        self.y = y
    }

    package func contains(_ point: Point2D) -> Bool {
        x.contains(point.x) && y.contains(point.y)
    }

    package var maximumWidth: Double {
        max(x.width, y.width)
    }
}
