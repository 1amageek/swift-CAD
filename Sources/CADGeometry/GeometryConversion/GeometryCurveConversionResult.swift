public struct GeometryCurveConversionResult: Sendable {
    public let curve: BSplineCurve3D
    public let parameters: ScalarInterval
    public let guarantee: GeometryConversionGuarantee
}
