import CADCore

public struct SelectionDistanceMeasurement: Codable, Sendable, Hashable {
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var vector: Vector3D
    public var distance: Double

    public init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint) throws {
        self.first = first
        self.second = second
        self.vector = second.point - first.point
        self.distance = vector.length
        guard distance.isFinite else {
            throw GeometryError.invalidDistance(distance)
        }
    }
}
