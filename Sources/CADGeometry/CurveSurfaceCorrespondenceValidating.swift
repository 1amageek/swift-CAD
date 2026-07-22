import CADCore

public protocol CurveSurfaceCorrespondenceValidating: Sendable {
    func validate(
        curve: Curve3D,
        from startCurveParameter: Double,
        to endCurveParameter: Double,
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance
    ) throws
}
