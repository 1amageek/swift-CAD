import CADCore

/// Complete original rational residual bounds on one directed affine trim map.
struct OriginalRationalCurveCurveToleranceCorrespondence {
    func proves(equations: [ExactBivariatePolynomial], denominator: ExactBivariatePolynomial,
        first: ScalarInterval, second: ScalarInterval, reversed: Bool,
        budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        guard equations.count == 3, first.width > 0, second.width > 0 else { throw budget.exhausted() }
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &budget)
        func parameter(_ start: Double, _ end: Double,
            budget: inout NativeCurveCurveContactBudget) throws -> ExactBivariatePolynomial {
            let a = try ExactRationalCoefficient.originalDouble(start, usage: &budget)
            let b = try ExactRationalCoefficient.originalDouble(end, usage: &budget)
            return try t.scaled(by: b.subtracting(a, usage: &budget), usage: &budget)
                .adding(.constant(a, usage: &budget), usage: &budget)
        }
        let u = try parameter(first.lower, first.upper, budget: &budget)
        let v = try parameter(reversed ? second.upper : second.lower,
            reversed ? second.lower : second.upper, budget: &budget)
        try budget.retainExactStorage(4)
        let numerators = try equations.map { try $0.composed(withU: u, v: v, usage: &budget) }
        let weight = try denominator.composed(withU: u, v: v, usage: &budget)
        let zero = try ScalarInterval(lower: 0, upper: 0)
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        func residual(_ range: ScalarInterval, budget: inout NativeCurveCurveContactBudget) throws
            -> OutwardScalarInterval? {
            let domain = SurfaceParameterBox(u: range, v: zero)
            let w = try weight.enclosure(over: domain, usage: &budget)
            guard w.lower > 0 else { return nil }
            var square = OutwardScalarInterval.exact(0)
            for value in numerators {
                let numerator = try value.enclosure(over: domain, usage: &budget)
                guard let r = numerator.divided(by: w), r.isFinite else { throw budget.exhausted() }
                let low = r.absoluteLowerBound, high = r.absoluteUpperBound
                square = square + OutwardScalarInterval(lower: max(0, (low * low).nextDown),
                    upper: (high * high).nextUp)
            }
            return square
        }
        // Original singleton residuals can disprove this map candidate only.
        // They never exclude contacts under other original correspondences.
        for station in [0.0, 0.5, 1.0] {
            if let r = try residual(ScalarInterval(lower: station, upper: station), budget: &budget),
               r.lower > threshold.upper { return false }
        }
        try budget.retainExactStorage(1)
        var pending = [(try ScalarInterval(lower: 0, upper: 1), 0)]
        while let (range, depth) = pending.popLast() {
            try budget.visitExactCell(depth: depth)
            if let r = try residual(range, budget: &budget) {
                if r.lower > threshold.upper { return false }
                if r.upper <= threshold.lower { continue }
            }
            guard depth < budget.maximumDepth,
                  range.midpoint > range.lower, range.midpoint < range.upper else { return false }
            try budget.retainExactStorage(2)
            pending.append((try ScalarInterval(lower: range.lower, upper: range.midpoint), depth + 1))
            pending.append((try ScalarInterval(lower: range.midpoint, upper: range.upper), depth + 1))
        }
        return true
    }
}
