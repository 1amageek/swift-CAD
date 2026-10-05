import CADCore

/// Actual original scalar derivatives; absence of third order never means zero.
struct SurfaceSilhouetteScalarJet: Sendable {
    let value: OutwardScalarInterval
    let u: OutwardScalarInterval
    let v: OutwardScalarInterval
    let uu: OutwardScalarInterval
    let uv: OutwardScalarInterval
    let vv: OutwardScalarInterval
    let third: Third?

    struct Third: Sendable {
        let uuu: OutwardScalarInterval
        let uuv: OutwardScalarInterval
        let uvv: OutwardScalarInterval
        let vvv: OutwardScalarInterval
    }

    init(originalBounds bounds: OriginalRationalScalarDerivativeBounds) {
        value = bounds.value; u = bounds.u; v = bounds.v
        uu = bounds.uu; uv = bounds.uv; vv = bounds.vv
        third = Third(uuu: bounds.uuu, uuv: bounds.uuv, uvv: bounds.uvv, vvv: bounds.vvv)
    }

    init(surface: SurfaceIntervalVectorJet, view: Vector3D) {
        let field = surface.differentiatedUThroughSecondOrder()
            .cross(surface.differentiatedVThroughSecondOrder())
            .dot(.constant(view))
        value = field.value; u = field.derivativeU; v = field.derivativeV
        uu = field.secondDerivativeUU; uv = field.secondDerivativeUV
        vv = field.secondDerivativeVV; third = nil
    }

    init(original field: SurfaceAreaIntervalTaylorScalarJet) throws {
        value = try field.coefficient(0, 0)
        u = try field.coefficient(1, 0); v = try field.coefficient(0, 1)
        uu = try field.coefficient(2, 0) * .exact(2)
        uv = try field.coefficient(1, 1)
        vv = try field.coefficient(0, 2) * .exact(2)
        third = try Third(uuu: field.coefficient(3, 0) * .exact(6),
            uuv: field.coefficient(2, 1) * .exact(2),
            uvv: field.coefficient(1, 2) * .exact(2),
            vvv: field.coefficient(0, 3) * .exact(6))
    }
}
