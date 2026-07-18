import CADCore

public struct BooleanUVPoint: Codable, Hashable, Sendable {
    public let point: Point3D
    public let targetU: Double
    public let targetV: Double
    public let toolU: Double
    public let toolV: Double
    public let residual: Double

    public init(
        point: Point3D,
        targetU: Double,
        targetV: Double,
        toolU: Double,
        toolV: Double,
        residual: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try point.validate()
        guard targetU.isFinite,
              targetV.isFinite,
              toolU.isFinite,
              toolV.isFinite,
              residual.isFinite,
              residual >= 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "Boolean UV point values must be finite and non-negative."
            )
        }
        self.point = point
        self.targetU = targetU
        self.targetV = targetV
        self.toolU = toolU
        self.toolV = toolV
        self.residual = residual
    }
}
