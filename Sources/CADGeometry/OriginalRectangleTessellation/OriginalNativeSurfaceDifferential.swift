import CADCore

extension BSplineSurface3D {
    func selectedOriginalDerivatives<A: ExactScalarAdmission & ~Copyable>(
        u: Double, v: Double,
        owning span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalDerivatives {
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                                      v: try ScalarInterval(lower: v, upper: v))
        try span.validate(on: self, over: box, tolerance: tolerance, using: &execution)
        let base = try span.basePoint(u: u, v: v, on: self, tolerance: tolerance, using: &execution)
        return try surfaceDerivatives(u: base.u, v: base.v, tolerance: tolerance,
            owningUSpan: span.uSpanIndex, owningVSpan: span.vSpanIndex, using: &execution)
    }
}
