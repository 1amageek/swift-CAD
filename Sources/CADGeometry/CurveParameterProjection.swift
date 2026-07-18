import CADCore

public struct CurveParameterProjection: Codable, Hashable, Sendable {
    public let parameter: Double
    public let point: Point3D
    public let residual: Double
    public let iterations: Int

    public init(
        parameter: Double,
        point: Point3D,
        residual: Double,
        iterations: Int
    ) throws {
        try point.validate()
        guard parameter.isFinite,
              residual.isFinite,
              residual >= 0.0,
              iterations >= 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: nil,
                message: "Curve parameter projection values must be finite and non-negative."
            )
        }
        self.parameter = parameter
        self.point = point
        self.residual = residual
        self.iterations = iterations
    }
}
