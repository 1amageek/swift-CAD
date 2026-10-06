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

    func validate(
        curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int?
    ) throws
}

public extension CurveSurfaceCorrespondenceValidating {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected bounded BRep consumers need
    // actual original preparation/traversal callbacks from each conformer.
    // Legacy validation without caller admission cannot satisfy this witness.
    func validate(curve: Curve3D, from startCurveParameter: Double, to endCurveParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws {
        throw KernelError(phase: .validation, code: .unsupportedCapability, tolerance: tolerance,
            message: "Curve-surface correspondence conformer has no original caller-admitted proof.")
    }
}
