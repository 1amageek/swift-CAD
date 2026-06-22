import CADCore

public struct SweepStraightPath: Sendable, Hashable {
    public var start: Point3D
    public var end: Point3D
    public var direction: Vector3D
    public var distance: Double

    public init(start: Point3D, end: Point3D, direction: Vector3D, distance: Double) {
        self.start = start
        self.end = end
        self.direction = direction
        self.distance = distance
    }
}
