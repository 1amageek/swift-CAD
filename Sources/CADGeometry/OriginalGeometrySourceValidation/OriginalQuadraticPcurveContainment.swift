import CADCore

/// Whole-image theorem for the original single polynomial quadratic traversal.
enum OriginalQuadraticPcurveContainment {
    /// Nil means this representation supplies no quadratic theorem, not exclusion.
    static func contains<A: RationalAlgebraAdmitting>(_ curve: BSplineCurve2D,
        u: ParameterDomain, v: ParameterDomain, using usage: inout A
    ) throws -> Bool? {
        try usage.consumeExactWork(1)
        guard curve.degree == 2, curve.controlPoints.count == 3,
            curve.weights.count == 3, curve.knots.count == 6,
            curve.knots[0] == curve.knots[1], curve.knots[1] == curve.knots[2],
            curve.knots[3] == curve.knots[4], curve.knots[4] == curve.knots[5],
            curve.knots[0].isFinite, curve.knots[5].isFinite,
            curve.knots[0] < curve.knots[5], curve.weights[0].isFinite,
            curve.weights[0] > 0, curve.weights[0] == curve.weights[1],
            curve.weights[1] == curve.weights[2] else { return nil }
        for axis in 0..<2 {
            try usage.consumeExactWork(1)
            let domain = axis == 0 ? u : v
            guard case .closed(let lower, let upper) = domain else { continue }
            let lo = try ExactRationalCoefficient.originalDouble(lower, usage: &usage)
            let hi = try ExactRationalCoefficient.originalDouble(upper, usage: &usage)
            guard try !hi.subtracting(lo, usage: &usage).isNegative else {
                throw ExactScalarFailure.invalidSource
            }
            let p0 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[0].x : curve.controlPoints[0].y, usage: &usage)
            let p1 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[1].x : curve.controlPoints[1].y, usage: &usage)
            let p2 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[2].x : curve.controlPoints[2].y, usage: &usage)
            if try p0.subtracting(lo, usage: &usage).isNegative || p0.subtracting(hi, usage: &usage).isPositive
                || p2.subtracting(lo, usage: &usage).isNegative || p2.subtracting(hi, usage: &usage).isPositive { return false }
            let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
            let four = try two.adding(two, usage: &usage)
            let a = try p0.subtracting(p1.multiplied(by: two, usage: &usage), usage: &usage).adding(p2, usage: &usage)
            if a.isZero { continue }
            let b = try p1.subtracting(p0, usage: &usage).multiplied(by: two, usage: &usage)
            let t = try b.negated.divided(by: a.multiplied(by: two, usage: &usage), usage: &usage)
            if try t.isNegative || t.subtracting(.one, usage: &usage).isPositive { continue }
            let stationary = try p0.subtracting(b.multiplied(by: b, usage: &usage)
                .divided(by: a.multiplied(by: four, usage: &usage), usage: &usage), usage: &usage)
            if try stationary.subtracting(lo, usage: &usage).isNegative
                || stationary.subtracting(hi, usage: &usage).isPositive { return false }
        }
        try usage.consumeExactWork(1)
        return true
    }
}
