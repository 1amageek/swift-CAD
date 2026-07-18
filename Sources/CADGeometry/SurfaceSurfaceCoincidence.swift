import CADCore

public struct SurfaceSurfaceCoincidence: Codable, Hashable, Sendable {
    public let residual: Double

    public init(residual: Double, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard residual.isFinite,
              residual >= 0.0,
              residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Coincident surfaces exceeded the requested tolerance."
            )
        }
        self.residual = residual
    }
}
