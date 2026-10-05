import CADCore

extension BSplineSurface3D {
    func selectedOriginalDerivatives(
        u: Double, v: Double,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        tolerance: ModelingTolerance
    ) throws -> RationalDerivatives {
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                                      v: try ScalarInterval(lower: v, upper: v))
        try span.validate(on: self, over: box, tolerance: tolerance)
        return try surfaceDerivatives(u: u, v: v, tolerance: tolerance,
            owningUSpan: span.uSpanIndex, owningVSpan: span.vSpanIndex)
    }
}
