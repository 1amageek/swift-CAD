import CADCore

/// Complete final-candidate certification under the original caller allowance.
public protocol CallerAdmittedGeometryConverting: GeometryConverting {
    func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryCurveConversionResult
    func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryCurveConversionResult
    func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D,
        over parameters: ScalarInterval, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee
    func certifyCurveCorrespondence(source: any GeometryCurveConversionSource,
        target: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee
    func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometrySurfaceConversionResult
    func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, requirements: GeometryConversionRequirements,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee
}

public extension CallerAdmittedGeometryConverting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom converter correspondence needs
    // its actual complete original-source D0/D1/D2 comparison under the supplied
    // admission. The public requirement cannot inherit a fitted guarantee or
    // use legacy unmetered source queries before that witness is implemented.
    func certifyCurveCorrespondence(source: any GeometryCurveConversionSource,
        target: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> GeometryConversionGuarantee {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This converter has no caller-admitted original curve correspondence witness.")
    }
}
