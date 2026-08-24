import CADCore

public struct CurveDirectionalParameterProjection: Codable, Hashable, Sendable {
    public let parameter: Double
    public let point: Point3D
    public let signedDistanceAlongDirection: Double
    public let residual: Double
    public let iterations: Int

    public init(
        parameter: Double,
        point: Point3D,
        signedDistanceAlongDirection: Double,
        residual: Double,
        iterations: Int
    ) throws {
        try point.validate()
        guard parameter.isFinite,
              signedDistanceAlongDirection.isFinite,
              residual.isFinite,
              residual >= 0.0,
              iterations >= 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: nil,
                message: "Directional curve projection values must be finite and non-negative."
            )
        }
        self.parameter = parameter
        self.point = point
        self.signedDistanceAlongDirection = signedDistanceAlongDirection
        self.residual = residual
        self.iterations = iterations
    }
}
