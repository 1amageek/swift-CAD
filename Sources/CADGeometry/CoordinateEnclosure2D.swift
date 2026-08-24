import CADCore

package struct CoordinateEnclosure2D: Sendable {
    package let x: ScalarInterval
    package let y: ScalarInterval

    package init(x: ScalarInterval, y: ScalarInterval) {
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
