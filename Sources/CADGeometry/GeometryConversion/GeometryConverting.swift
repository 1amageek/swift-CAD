import CADCore

public protocol GeometryConverting: Sendable {
    func approximateCurve(source: any GeometryCurveConversionSource, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult
    func interpolateCurve(source: any GeometryCurveConversionSource, at parameters: [Double],
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryCurveConversionResult
    func approximateSurface(source: any GeometrySurfaceConversionSource, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult
    func interpolateSurface(source: any GeometrySurfaceConversionSource, template: BSplineSurface3D,
        points: [GeometrySurfaceInterpolationPoint], over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometrySurfaceConversionResult
    func certifyCurve(source: any GeometryCurveConversionSource, candidate: BSplineCurve3D, over parameters: ScalarInterval,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee
    func certifySurface(source: any GeometrySurfaceConversionSource, candidate: BSplineSurface3D, over parameters: SurfaceParameterBox,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws -> GeometryConversionGuarantee
}
