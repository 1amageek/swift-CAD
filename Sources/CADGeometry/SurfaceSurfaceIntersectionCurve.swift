import CADCore

public struct SurfaceSurfaceIntersectionCurve: Codable, Hashable, Sendable {
    public let curve: Curve3D
    public let kind: CurveSurfaceIntersectionKind
    public let firstSurfaceParameterCurve: SurfaceParameterCurve
    public let secondSurfaceParameterCurve: SurfaceParameterCurve
    public let firstSurfaceAnchor: SurfaceParameterProjection
    public let secondSurfaceAnchor: SurfaceParameterProjection
    public let maximumResidual: Double

    public init(
        curve: Curve3D,
        kind: CurveSurfaceIntersectionKind,
        firstSurfaceParameterCurve: SurfaceParameterCurve,
        secondSurfaceParameterCurve: SurfaceParameterCurve,
        firstSurfaceAnchor: SurfaceParameterProjection,
        secondSurfaceAnchor: SurfaceParameterProjection,
        maximumResidual: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard maximumResidual.isFinite,
              maximumResidual >= 0.0,
              maximumResidual <= tolerance.distance,
              firstSurfaceAnchor.residual <= tolerance.distance,
              secondSurfaceAnchor.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Surface-surface intersection curve failed residual verification."
            )
        }
        self.curve = curve
        self.kind = kind
        self.firstSurfaceParameterCurve = firstSurfaceParameterCurve
        self.secondSurfaceParameterCurve = secondSurfaceParameterCurve
        self.firstSurfaceAnchor = firstSurfaceAnchor
        self.secondSurfaceAnchor = secondSurfaceAnchor
        self.maximumResidual = maximumResidual
    }
}
