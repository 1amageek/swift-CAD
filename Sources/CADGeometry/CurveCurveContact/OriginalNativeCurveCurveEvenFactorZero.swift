import CADCore

/// Exact globally signed even-monomial identity for a unique real original factor zero.
struct OriginalNativeCurveCurveEvenFactorZero {
    func provesUniqueZero(factor: ExactBivariatePolynomial, over domain: SurfaceParameterBox,
                         budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        let terms = try factor.orderedTerms(usage: &budget)
        try budget.retainExactStorage(6)
        let us = [domain.u.lower, domain.u.midpoint, domain.u.upper]
        let vs = [domain.v.lower, domain.v.midpoint, domain.v.upper]
        for u in us {
            let originU = try ExactRationalCoefficient.originalDouble(u, usage: &budget)
            for v in vs {
                let originV = try ExactRationalCoefficient.originalDouble(v, usage: &budget)
                guard try factor.evaluated(atU: originU, v: originV, usage: &budget).isZero else { continue }
                let uBase = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &budget)
                    .adding(.constant(originU, usage: &budget), usage: &budget)
                let vBase = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &budget)
                    .adding(.constant(originV, usage: &budget), usage: &budget)
                let one = try ExactBivariatePolynomial.constant(.one, usage: &budget)
                let slotsU = factor.uDegree.addingReportingOverflow(1)
                let slotsV = factor.vDegree.addingReportingOverflow(1)
                guard !slotsU.overflow, !slotsV.overflow else { throw budget.exhausted() }
                try budget.retainExactStorage(slotsU.partialValue)
                try budget.retainExactStorage(slotsV.partialValue)
                var uPowers = [one], vPowers = [one]
                if factor.uDegree > 0 {
                    for _ in 1...factor.uDegree {
                        uPowers.append(try uPowers[uPowers.count - 1].multiplied(by: uBase, usage: &budget))
                    }
                }
                if factor.vDegree > 0 {
                    for _ in 1...factor.vDegree {
                        vPowers.append(try vPowers[vPowers.count - 1].multiplied(by: vBase, usage: &budget))
                    }
                }
                var translated = ExactBivariatePolynomial.zero
                for (power, coefficient) in terms {
                    let term = try uPowers[power.u].multiplied(by: vPowers[power.v], usage: &budget)
                        .scaled(by: coefficient, usage: &budget)
                    translated = try translated.adding(term, usage: &budget)
                }
                var positive: Bool?, hasPureU = false, hasPureV = false, admissible = true
                for (power, coefficient) in try translated.orderedTerms(usage: &budget) {
                    try budget.consumeExactWork(1)
                    guard power.u % 2 == 0, power.v % 2 == 0,
                          power.u > 0 || power.v > 0 else { admissible = false; break }
                    if let sign = positive {
                        guard sign == coefficient.isPositive else { admissible = false; break }
                    } else { positive = coefficient.isPositive }
                    if power.u > 0, power.v == 0 { hasPureU = true }
                    if power.v > 0, power.u == 0 { hasPureV = true }
                }
                // Every even monomial has one strict sign. Pure terms in both
                // coordinates make equality possible only at this exact station.
                if admissible, positive != nil, hasPureU, hasPureV { return true }
            }
        }
        return false
    }
}
