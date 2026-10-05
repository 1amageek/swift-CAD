public struct GeometrySurfaceConversionResult: Sendable {
    public let surface: BSplineSurface3D
    public let parameters: SurfaceParameterBox
    public let guarantee: GeometryConversionGuarantee
}
