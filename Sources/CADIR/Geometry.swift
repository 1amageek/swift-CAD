import CADCore

public struct Line3D: Codable, Sendable, Hashable {
    public var origin: Point3D
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
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

    public func validate(tolerance: ModelingTolerance = .standard) throws {
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

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try origin.validate()
        try normal.validateUnitLength(tolerance: tolerance)
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

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try origin.validate()
        try axis.validateUnitLength(tolerance: tolerance)
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
    }
}
