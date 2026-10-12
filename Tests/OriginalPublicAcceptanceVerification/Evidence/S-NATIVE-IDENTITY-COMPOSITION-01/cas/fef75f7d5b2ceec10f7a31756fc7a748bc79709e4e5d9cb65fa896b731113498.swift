public struct Point3D: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let origin = Point3D(x: 0.0, y: 0.0, z: 0.0)

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    public func validate() throws {
        try validateCoordinate(x)
        try validateCoordinate(y)
        try validateCoordinate(z)
    }

    public static func + (lhs: Point3D, rhs: Vector3D) -> Point3D {
        Point3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Point3D, rhs: Point3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public func isApproximatelyEqual(to other: Point3D, tolerance: Double) -> Bool {
        (self - other).length <= tolerance
    }
}

private func validateCoordinate(_ value: Double) throws {
    guard value.isFinite else {
        throw GeometryError.invalidCoordinate(value)
    }
}

#if !hasFeature(Embedded)
extension Point3D: Codable {}
#endif
