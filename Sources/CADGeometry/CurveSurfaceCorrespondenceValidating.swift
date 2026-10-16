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

    func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws

    func validate(
        curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution
    ) throws
}

public extension CurveSurfaceCorrespondenceValidating {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected ordinary correspondence consumers
    // require a conformer-owned numerical policy executed on this caller execution.
    // Do not publish success by calling an independent ordinary implementation.
    func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        throw KernelError(phase: .validation, code: .unsupportedCapability, tolerance: tolerance,
            message: "Curve-surface correspondence conformer has no direct ordinary policy producer.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected bounded BRep consumers need
    // actual original preparation/traversal admission from each conformer.
    // Legacy validation without caller admission cannot satisfy this witness.
    func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        throw KernelError(phase: .validation, code: .unsupportedCapability, tolerance: tolerance,
            message: "Curve-surface correspondence conformer has no original caller-admitted proof.")
    }
}
