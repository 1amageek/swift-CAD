import CADCore

public struct SweepPathFrame: Sendable, Hashable {
    public var origin: Point3D
    public var tangent: Vector3D
    public var normal: Vector3D
    public var binormal: Vector3D
    public var distance: Double

    public init(
        origin: Point3D,
        tangent: Vector3D,
        normal: Vector3D,
        binormal: Vector3D,
        distance: Double
    ) {
        self.origin = origin
        self.tangent = tangent
        self.normal = normal
        self.binormal = binormal
        self.distance = distance
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try origin.validate()
        try tangent.validateUnitLength(tolerance: tolerance)
        try normal.validateUnitLength(tolerance: tolerance)
        try binormal.validateUnitLength(tolerance: tolerance)
        guard abs(tangent.dot(normal)) <= max(tolerance.distance, tolerance.angle),
              abs(tangent.dot(binormal)) <= max(tolerance.distance, tolerance.angle),
              abs(normal.dot(binormal)) <= max(tolerance.distance, tolerance.angle) else {
            throw FeatureEvaluationError.invalidGraph("Sweep path frame axes must be orthonormal.")
        }
        guard distance.isFinite, distance >= 0.0 else {
            throw GeometryError.invalidDistance(distance)
        }
    }
}
