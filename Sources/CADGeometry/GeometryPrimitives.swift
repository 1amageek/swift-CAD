import CADCore

public struct Line3D: Sendable, Hashable {
    public var origin: Point3D
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try direction.validateUnitLength(tolerance: tolerance)
    }
}

public struct Circle3D: Sendable, Hashable {
    public var center: Point3D
    public var normal: Vector3D
    public var radius: Double

    public init(center: Point3D, normal: Vector3D, radius: Double) {
        self.center = center
        self.normal = normal
        self.radius = radius
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try center.validate()
        try normal.validateUnitLength(tolerance: tolerance)
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
    }
}

public struct Plane3D: Sendable, Hashable {
    public var origin: Point3D
    public var normal: Vector3D
    /// An authored native U direction; nil uses the normalized stored-N basis.
    public var uDirection: Vector3D?

    public init(origin: Point3D, normal: Vector3D, uDirection: Vector3D? = nil) {
        self.origin = origin
        self.normal = normal
        self.uDirection = uDirection
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try normal.validate()
        guard normal.x != 0 || normal.y != 0 || normal.z != 0 else { throw GeometryError.invalidVectorLength(0) }
        if let uDirection {
            try normal.validateUnitLength(tolerance: tolerance)
            try uDirection.validateUnitLength(tolerance: tolerance)
            let orthogonality = abs(normal.dot(uDirection))
            guard orthogonality <= tolerance.angle else {
                throw KernelError(phase: .geometry, code: .invalidInput,
                    residual: orthogonality, tolerance: tolerance,
                    message: "An explicit plane U direction must be perpendicular to its normal.")
            }
        }
    }
}

extension Plane3D {
    /// The directions the plane's u and v parameters run along, as `Surface3D` places its points:
    /// the one rule every reader of a plane's parameters (trimming curves, their integrals) shares.
    package func parameterBasis(tolerance: ModelingTolerance) throws -> (u: Vector3D, v: Vector3D) {
        if let uDirection {
            try validate(tolerance: tolerance)
            return (uDirection, normal.cross(uDirection))
        }
        return try OriginalStoredPlaneBasis.basis(normal,tolerance:tolerance)
    }
}

public struct Cylinder3D: Sendable, Hashable {
    public var origin: Point3D
    public var axis: Vector3D
    public var radius: Double

    public init(origin: Point3D, axis: Vector3D, radius: Double) {
        self.origin = origin
        self.axis = axis
        self.radius = radius
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try axis.validateUnitLength(tolerance: tolerance)
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
    }
}

#if !hasFeature(Embedded)
extension Line3D: Codable {}
extension Circle3D: Codable {}
extension Plane3D: Codable {}
extension Cylinder3D: Codable {}
#endif
