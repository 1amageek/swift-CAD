import CADCore

extension DefaultCurveSurfaceCorrespondenceValidator {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Manual bounded BRep validation uses
    // original fixed-fraction cells and identical hosted/image structural laws.
    // Nonlinear/critical correspondence and full-family coverage
    // remain required before claiming the legacy validator's complete domain.
    public func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        _ = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(curve: curve,
            from: startCurveParameter, to: endCurveParameter, surface: surface, parameterCurve: parameterCurve,
            options: options, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }
}
