import CADCore

/// Whole-image theorem for the original single polynomial quadratic traversal.
enum OriginalQuadraticPcurveContainment {
    /// Nil means this representation supplies no quadratic theorem, not exclusion.
    static func contains<A: ExactScalarAdmission & ~Copyable>(_ curve: BSplineCurve2D,
        u: ParameterDomain, v: ParameterDomain, using execution: inout A
    ) throws -> Bool? {
        try execution.consumeWork(1)
        guard curve.degree == 2, curve.controlPoints.count == 3,
            curve.weights.count == 3, curve.knots.count == 6,
            curve.knots[0] == curve.knots[1], curve.knots[1] == curve.knots[2],
            curve.knots[3] == curve.knots[4], curve.knots[4] == curve.knots[5],
            curve.knots[0].isFinite, curve.knots[5].isFinite,
            curve.knots[0] < curve.knots[5], curve.weights[0].isFinite,
            curve.weights[0] > 0, curve.weights[0] == curve.weights[1],
            curve.weights[1] == curve.weights[2] else { return nil }
        for axis in 0..<2 {
            try execution.consumeWork(1)
            let domain = axis == 0 ? u : v
            guard case .closed(let lower, let upper) = domain else { continue }
            let lo = try ExactRationalCoefficient.originalDouble(lower, usage: &execution)
            let hi = try ExactRationalCoefficient.originalDouble(upper, usage: &execution)
            guard try !hi.subtracting(lo, usage: &execution).isNegative else {
                throw ExactScalarFailure.invalidSource
            }
            let p0 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[0].x : curve.controlPoints[0].y, usage: &execution)
            let p1 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[1].x : curve.controlPoints[1].y, usage: &execution)
            let p2 = try ExactRationalCoefficient.originalDouble(axis == 0 ? curve.controlPoints[2].x : curve.controlPoints[2].y, usage: &execution)
            if try p0.subtracting(lo, usage: &execution).isNegative || p0.subtracting(hi, usage: &execution).isPositive
                || p2.subtracting(lo, usage: &execution).isNegative || p2.subtracting(hi, usage: &execution).isPositive { return false }
            let two = try ExactRationalCoefficient.one.adding(.one, usage: &execution)
            let four = try two.adding(two, usage: &execution)
            let a = try p0.subtracting(p1.multiplied(by: two, usage: &execution), usage: &execution).adding(p2, usage: &execution)
            if a.isZero { continue }
            let b = try p1.subtracting(p0, usage: &execution).multiplied(by: two, usage: &execution)
            let t = try b.negated.divided(by: a.multiplied(by: two, usage: &execution), usage: &execution)
            if try t.isNegative || t.subtracting(.one, usage: &execution).isPositive { continue }
            let stationary = try p0.subtracting(b.multiplied(by: b, usage: &execution)
                .divided(by: a.multiplied(by: four, usage: &execution), usage: &execution), usage: &execution)
            if try stationary.subtracting(lo, usage: &execution).isNegative
                || stationary.subtracting(hi, usage: &execution).isPositive { return false }
        }
        try execution.consumeWork(1)
        return true
    }
}
