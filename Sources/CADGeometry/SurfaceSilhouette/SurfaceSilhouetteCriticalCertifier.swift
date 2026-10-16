import CADCore

/// Original gradient-root isolation; uncertainty in F=0 remains explicit.
struct SurfaceSilhouetteCriticalCertifier {
    enum Classification {
        case excluded
        case unresolved
        case uniqueCritical(SurfaceParameterBox)
        case isolatedExactZero(SurfaceParameter)
    }

    static func classify(field: OriginalSurfaceSilhouetteField, box: SurfaceParameterBox,
                         jet: SurfaceSilhouetteScalarJet, usage: inout OriginalQueryExecution)
        throws -> Classification {
        guard jet.u.contains(0), jet.v.contains(0) else { return .unresolved }
        let h00 = jet.uu, h01 = jet.uv, h11 = jet.vv
        guard h00.isFinite, h01.isFinite, h11.isFinite else { return .unresolved }
        let a = h00.midpoint, b = h01.midpoint, d = h11.midpoint
        let determinant = a * d - b * b
        guard determinant.isFinite, determinant != 0 else { return .unresolved }
        let r00 = d / determinant, r01 = -b / determinant, r11 = a / determinant
        guard r00.isFinite, r01.isFinite, r11.isFinite else { return .unresolved }
        let u = box.u.lower + box.u.width * 0.5
        let v = box.v.lower + box.v.width * 0.5
        let station = try SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
            v: ScalarInterval(lower: v, upper: v))
        let center = try field.evaluate(over: station, usage: &usage).scalar
        try usage.consumeWork(24)
        let du = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper) - .exact(u)
        let dv = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper) - .exact(v)
        let k00 = OutwardScalarInterval.exact(1) - .exact(r00) * h00 - .exact(r01) * h01
        let k01 = -(OutwardScalarInterval.exact(r00) * h01 + .exact(r01) * h11)
        let k10 = -(OutwardScalarInterval.exact(r01) * h00 + .exact(r11) * h01)
        let k11 = OutwardScalarInterval.exact(1) - .exact(r01) * h01 - .exact(r11) * h11
        let ku = OutwardScalarInterval.exact(u) - .exact(r00) * center.u - .exact(r01) * center.v + k00 * du + k01 * dv
        let kv = OutwardScalarInterval.exact(v) - .exact(r01) * center.u - .exact(r11) * center.v + k10 * du + k11 * dv
        let originalU = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
        let originalV = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
        guard ku.isFinite, kv.isFinite else { return .unresolved }
        guard let iu = ku.intersection(with: originalU), let iv = kv.intersection(with: originalV) else {
            return .unresolved
        }
        // Strict Krawczyk inclusion and contraction prove one original gradient
        // root. The represented midpoint inverse is only a preconditioner; every
        // arithmetic consequence is enclosed with the original Hessian bounds.
        let row0 = (k00.absoluteUpperBound + k01.absoluteUpperBound).nextUp
        let row1 = (k10.absoluteUpperBound + k11.absoluteUpperBound).nextUp
        guard ku.isStrictlyInside(originalU), kv.isStrictlyInside(originalV),
              max(row0, row1) < 1 else { return .unresolved }
        let root = try SurfaceParameterBox(u: ScalarInterval(lower: iu.lower, upper: iu.upper),
            v: ScalarInterval(lower: iv.lower, upper: iv.upper))
        let critical = try field.evaluate(over: root, usage: &usage).scalar.value
        let hessianDeterminant = h00 * h11 - h01 * h01
        if hessianDeterminant.lower > 0 {
            if h00.lower > 0, critical.lower > 0 { return .excluded }
            if h00.upper < 0, critical.upper < 0 { return .excluded }
        }
        if hessianDeterminant.lower > 0, h00.excludesZero,
           let original = field.zeroSetAuthority {
            let ru = iu.lower + (iu.upper - iu.lower) * 0.5
            let rv = iv.lower + (iv.upper - iv.lower) * 0.5
            let eu = try ExactRationalCoefficient.originalDouble(ru, usage: &usage)
            let ev = try ExactRationalCoefficient.originalDouble(rv, usage: &usage)
            let polynomial = original.squareFree
            let pu = try polynomial.differentiated(alongU: true, usage: &usage)
            let pv = try polynomial.differentiated(alongU: false, usage: &usage)
            if try polynomial.evaluated(atU: eu, v: ev, usage: &usage).isZero,
               try pu.evaluated(atU: eu, v: ev, usage: &usage).isZero,
               try pv.evaluated(atU: eu, v: ev, usage: &usage).isZero {
                // Positive or negative definite original Hessian over the whole
                // convex cell and an exact stationary zero prove this is its
                // sole zero, not merely a small interval containing zero.
                return try .isolatedExactZero(SurfaceParameter(u: ru, v: rv))
            }
        }
        // A unique gradient root is not a zero witness. An outward interval
        // containing zero cannot prove the original exact equation F(root)=0.
        return .uniqueCritical(root)
    }
}
