import CADCore

/// Establishes only a whole original differential contraction. The atlas must
/// separately establish continuity on its convex authored parameter box.
package enum OriginalSurfaceProjectionContraction {
    package static func proves(_ jet: SurfaceIntervalVectorJet,
        consumeWork: () throws -> Void) throws -> Bool {
        for projection in 0..<3 {
            try Task.checkCancellation()
            try consumeWork()
            let first: SurfaceIntervalJet
            let second: SurfaceIntervalJet
            switch projection {
            case 0: first = jet.x; second = jet.y
            case 1: first = jet.x; second = jet.z
            default: first = jet.y; second = jet.z
            }
            if try proves(a: first.derivativeU, b: first.derivativeV,
                c: second.derivativeU, d: second.derivativeV, consumeWork: consumeWork) { return true }
        }
        return false
    }

    /// Consumes the retained pair session's original public differential bounds.
    package static func proves(_ enclosure: SurfaceDifferentialEnclosure,
        consumeWork: () throws -> Void) throws -> Bool {
        func interval(_ value: ScalarInterval) -> OutwardScalarInterval {
            .init(lower: value.lower, upper: value.upper)
        }
        for projection in 0..<3 {
            try Task.checkCancellation()
            try consumeWork()
            let a: ScalarInterval
            let b: ScalarInterval
            let c: ScalarInterval
            let d: ScalarInterval
            switch projection {
            case 0:
                a = enclosure.tangentU.x; b = enclosure.tangentV.x
                c = enclosure.tangentU.y; d = enclosure.tangentV.y
            case 1:
                a = enclosure.tangentU.x; b = enclosure.tangentV.x
                c = enclosure.tangentU.z; d = enclosure.tangentV.z
            default:
                a = enclosure.tangentU.y; b = enclosure.tangentV.y
                c = enclosure.tangentU.z; d = enclosure.tangentV.z
            }
            if try proves(a: interval(a), b: interval(b), c: interval(c), d: interval(d),
                consumeWork: consumeWork) { return true }
        }
        return false
    }

    private static func proves(a: OutwardScalarInterval, b: OutwardScalarInterval,
        c: OutwardScalarInterval, d: OutwardScalarInterval,
        consumeWork: () throws -> Void) throws -> Bool {
        try consumeWork()
        guard a.isFinite, b.isFinite, c.isFinite, d.isFinite else { return false }
        // Every stored preconditioner coefficient is an exact binary real in
        // the acceptance expression; its numerical construction proves nothing.
        let am = a.lower * 0.5 + a.upper * 0.5
        let bm = b.lower * 0.5 + b.upper * 0.5
        let cm = c.lower * 0.5 + c.upper * 0.5
        let dm = d.lower * 0.5 + d.upper * 0.5
        let determinant = am * dm - bm * cm
        guard determinant.isFinite, determinant != 0 else { return false }
        let ca = dm / determinant
        let cb = -bm / determinant
        let cc = -cm / determinant
        let cd = am / determinant
        guard ca.isFinite, cb.isFinite, cc.isFinite, cd.isFinite else { return false }
        try consumeWork()
        let e00 = OutwardScalarInterval.exact(1) - .exact(ca) * a - .exact(cb) * c
        let e01 = -(.exact(ca) * b + .exact(cb) * d)
        try consumeWork()
        let e10 = -(.exact(cc) * a + .exact(cd) * c)
        let e11 = OutwardScalarInterval.exact(1) - .exact(cc) * b - .exact(cd) * d
        guard e00.isFinite, e01.isFinite, e10.isFinite, e11.isFinite else { return false }
        let firstRow = OutwardScalarInterval.exact(magnitude(e00)) + .exact(magnitude(e01))
        let secondRow = OutwardScalarInterval.exact(magnitude(e10)) + .exact(magnitude(e11))
        try consumeWork()
        return firstRow.upper < 1 && secondRow.upper < 1
    }

    private static func magnitude(_ interval: OutwardScalarInterval) -> Double {
        max(abs(interval.lower), abs(interval.upper))
    }
}
