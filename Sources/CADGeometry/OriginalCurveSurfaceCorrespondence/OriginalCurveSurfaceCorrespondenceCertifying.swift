import CADCore

/// Certifies the actual directed original curve against its original surface lift.
public protocol OriginalCurveSurfaceCorrespondenceCertifying: Sendable {
    func certify(
        curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance
    ) throws -> OriginalCurveSurfaceCorrespondenceCertificate
}
