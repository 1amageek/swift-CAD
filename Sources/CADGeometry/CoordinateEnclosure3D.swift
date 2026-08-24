import CADCore

public struct CoordinateEnclosure3D: Codable, Equatable, Hashable, Sendable {
    public let x: ScalarInterval
    public let y: ScalarInterval
    public let z: ScalarInterval

    public init(x: ScalarInterval, y: ScalarInterval, z: ScalarInterval) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func contains(_ point: Point3D) -> Bool {
        x.contains(point.x) && y.contains(point.y) && z.contains(point.z)
    }

    public func contains(_ vector: Vector3D) -> Bool {
        x.contains(vector.x) && y.contains(vector.y) && z.contains(vector.z)
    }
}
