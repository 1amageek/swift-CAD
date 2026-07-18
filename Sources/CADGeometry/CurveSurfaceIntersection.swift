import CADCore

public struct CurveSurfaceIntersection: Codable, Hashable, Sendable {
    public let point: Point3D
    public let curveParameter: Double
    public let surfaceU: Double
    public let surfaceV: Double
    public let kind: CurveSurfaceIntersectionKind
    public let residual: Double
    public let iterations: Int

    public init(
        point: Point3D,
        curveParameter: Double,
        surfaceU: Double,
        surfaceV: Double,
        kind: CurveSurfaceIntersectionKind,
        residual: Double,
        iterations: Int
    ) throws {
        try point.validate()
        guard curveParameter.isFinite,
              surfaceU.isFinite,
              surfaceV.isFinite,
              residual.isFinite,
              residual >= 0.0,
              iterations >= 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: nil,
                message: "Curve-surface intersection values must be finite and non-negative."
            )
        }
        self.point = point
        self.curveParameter = curveParameter
        self.surfaceU = surfaceU
        self.surfaceV = surfaceV
        self.kind = kind
        self.residual = residual
        self.iterations = iterations
    }
}
