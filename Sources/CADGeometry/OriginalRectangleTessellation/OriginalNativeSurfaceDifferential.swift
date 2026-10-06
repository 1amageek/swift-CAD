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
        let base = try span.basePoint(u: u, v: v, on: self, tolerance: tolerance)
        return try surfaceDerivatives(u: base.u, v: base.v, tolerance: tolerance,
            owningUSpan: span.uSpanIndex, owningVSpan: span.vSpanIndex)
    }
}
