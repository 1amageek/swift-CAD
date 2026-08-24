import CADCore
import CADIR

public struct ProfileRegionSummary: Sendable, Hashable {
    public var center: Point2D
    public var areaSquareMeters: Double
    public var points: [Point2D]
    public var innerPoints: [[Point2D]]

    public init(
        center: Point2D,
        areaSquareMeters: Double,
        points: [Point2D],
        innerPoints: [[Point2D]] = []
    ) {
        self.center = center
        self.areaSquareMeters = areaSquareMeters
        self.points = points
        self.innerPoints = innerPoints
    }
}
