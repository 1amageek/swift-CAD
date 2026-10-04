import CADCore

public struct Line3D: Codable, Sendable, Hashable {
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

public struct Circle3D: Codable, Sendable, Hashable {
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

public struct Plane3D: Codable, Sendable, Hashable {
    public var origin: Point3D
    public var normal: Vector3D

    public init(origin: Point3D, normal: Vector3D) {
        self.origin = origin
        self.normal = normal
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try normal.validateUnitLength(tolerance: tolerance)
    }
}

extension Plane3D {
    /// The directions the plane's u and v parameters run along, as `Surface3D` places its points:
    /// the one rule every reader of a plane's parameters (trimming curves, their integrals) shares.
    package func parameterBasis(tolerance: ModelingTolerance) throws -> (u: Vector3D, v: Vector3D) {
        let unit = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(unit.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(unit).normalized(tolerance: tolerance.distance)
        return (u, unit.cross(u))
    }
}

public struct Cylinder3D: Codable, Sendable, Hashable {
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
