import CADCore

/// An immutable right-handed, orthonormal screen frame in original model units.
public struct OrthographicProjectionFrame: Sendable, Hashable {
    public let origin: Point3D
    public let normal: Vector3D
    public let horizontal: Vector3D
    public let vertical: Vector3D

    /// Projects the horizontal hint into the screen plane and normalizes it.
    public init(
        origin: Point3D,
        normal: Vector3D,
        horizontalHint: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard origin.isFinite, normal.isFinite, horizontalHint.isFinite,
              tolerance.angle < 1.0,
              normal.length.isFinite, normal.length > 0.0,
              horizontalHint.length.isFinite, horizontalHint.length > 0.0 else {
            throw OrthographicProjectionError.invalidFrame
        }
        let unitNormal = normal / normal.length
        let cross = unitNormal.cross(horizontalHint / horizontalHint.length)
        guard cross.length.isFinite, cross.length > tolerance.angle else {
            throw OrthographicProjectionError.invalidFrame
        }
        let unitVertical = cross / cross.length
        let inPlane = unitVertical.cross(unitNormal)
        guard inPlane.length.isFinite, inPlane.length > 0.0 else {
            throw OrthographicProjectionError.invalidFrame
        }
        self.origin = origin
        self.normal = unitNormal
        self.vertical = unitVertical
        self.horizontal = inPlane / inPlane.length
    }

    public func project(_ point: Point3D) throws -> Point2D {
        try point.validate()
        return try project(point - origin)
    }

    /// Applies only the linear part; translation never affects derivatives.
    public func project(_ vector: Vector3D) throws -> Point2D {
        let x = vector.dot(horizontal)
        let y = vector.dot(vertical)
        guard vector.isFinite, x.isFinite, y.isFinite else {
            throw OrthographicProjectionError.nonfiniteOutput
        }
        return Point2D(x: x, y: y)
    }
}
