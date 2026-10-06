import CADCore

/// Producer-created source admission and its paid prefix for one continuation request.
public struct PreparedPolynomialSurfaceContinuationPositionRequest: Sendable {
    public let source: BSplineSurface3D
    public let parameters: SurfaceParameterBox
    public let maximumPositionError: Double
    public let limits: NativeSurfacePositionCertificationLimits
    public let tolerance: ModelingTolerance
    public let admittedScalarCount: Int
    public let admittedWorkUnits: Int
    public let admittedBoxCount: Int

    let originalLaw: PreparedPolynomialSurfaceContinuationLaw?

    init(source: BSplineSurface3D, parameters: SurfaceParameterBox, maximumPositionError: Double,
        tolerance: ModelingTolerance, originalLaw: PreparedPolynomialSurfaceContinuationLaw?, budget: PolynomialSurfacePositionDifferenceNet.Budget) {
        self.originalLaw = originalLaw
        self.source = source
        self.parameters = parameters
        self.maximumPositionError = maximumPositionError
        self.limits = budget.limits
        self.tolerance = tolerance
        self.admittedScalarCount = budget.scalars
        self.admittedWorkUnits = budget.work
        self.admittedBoxCount = budget.boxes
    }
}
