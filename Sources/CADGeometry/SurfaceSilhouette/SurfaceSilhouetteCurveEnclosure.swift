/// Original native-parameter enclosures through order three over the entire query.
public struct SurfaceSilhouetteCurveEnclosure: Sendable {
    public let parameters: SurfaceParameterBox
    /// Entries zero through three are value, D1, D2 and D3 in native UV coordinates.
    public let parameterDerivatives: [CoordinateEnclosure2D]
    /// Entries zero through three retain original XYZ value and derivatives.
    public let spatialDerivatives: [CoordinateEnclosure3D]

    init(parameters: SurfaceParameterBox, parameterDerivatives: [CoordinateEnclosure2D],
         spatialDerivatives: [CoordinateEnclosure3D]) {
        self.parameters = parameters; self.parameterDerivatives = parameterDerivatives
        self.spatialDerivatives = spatialDerivatives
    }
}
