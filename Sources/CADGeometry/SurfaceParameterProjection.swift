import CADCore

public struct SurfaceParameterProjection: Codable, Hashable, Sendable {
    public let u: Double
    public let v: Double
    public let point: Point3D
    public let residual: Double
    public let iterations: Int

    public init(
        u: Double,
        v: Double,
        point: Point3D,
        residual: Double,
        iterations: Int = 0
    ) throws {
        try point.validate()
        guard u.isFinite,
              v.isFinite,
              residual.isFinite,
              residual >= 0.0,
              iterations >= 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: nil,
                message: "Surface parameter projection values must be finite and non-negative."
            )
        }
        self.u = u
        self.v = v
        self.point = point
        self.residual = residual
        self.iterations = iterations
    }
}
