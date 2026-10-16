import CADCore

/// Exact globally signed even-monomial identity for a unique real original factor zero.
struct OriginalNativeCurveCurveEvenFactorZero {
  func provesUniqueZero(
    factor: ExactBivariatePolynomial,
    over domain: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let terms = try factor.orderedTerms(usage: &execution)
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
    let us = [domain.u.lower, domain.u.midpoint, domain.u.upper]
    let vs = [domain.v.lower, domain.v.midpoint, domain.v.upper]
    for u in us {
      let originU = try ExactRationalCoefficient.originalDouble(u, usage: &execution)
      for v in vs {
        let originV = try ExactRationalCoefficient.originalDouble(v, usage: &execution)
        guard try factor.evaluated(atU: originU, v: originV, usage: &execution).isZero else {
          continue
        }
        let uBase = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &execution)
          .adding(.constant(originU, usage: &execution), usage: &execution)
        let vBase = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &execution)
          .adding(.constant(originV, usage: &execution), usage: &execution)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &execution)
        let slotsU = factor.uDegree.addingReportingOverflow(1)
        let slotsV = factor.vDegree.addingReportingOverflow(1)
        guard !slotsU.overflow, !slotsV.overflow else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        try execution.retainStorage(
          bytes: exactScalarPayloadBytes(
            count: slotsU.partialValue, of: ExactRationalCoefficient.self))
        try execution.retainStorage(
          bytes: exactScalarPayloadBytes(
            count: slotsV.partialValue, of: ExactRationalCoefficient.self))
        var uPowers = [one]
        var vPowers = [one]
        if factor.uDegree > 0 {
          for _ in 1...factor.uDegree {
            uPowers.append(try uPowers[uPowers.count - 1].multiplied(by: uBase, usage: &execution))
          }
        }
        if factor.vDegree > 0 {
          for _ in 1...factor.vDegree {
            vPowers.append(try vPowers[vPowers.count - 1].multiplied(by: vBase, usage: &execution))
          }
        }
        var translated = ExactBivariatePolynomial.zero
        for (power, coefficient) in terms {
          let term = try uPowers[power.u].multiplied(by: vPowers[power.v], usage: &execution)
            .scaled(by: coefficient, usage: &execution)
          translated = try translated.adding(term, usage: &execution)
        }
        var positive: Bool?
        var hasPureU = false
        var hasPureV = false
        var admissible = true
        for (power, coefficient) in try translated.orderedTerms(usage: &execution) {
          try execution.consumeWork(1)
          guard power.u % 2 == 0, power.v % 2 == 0,
            power.u > 0 || power.v > 0
          else {
            admissible = false
            break
          }
          if let sign = positive {
            guard sign == coefficient.isPositive else {
              admissible = false
              break
            }
          } else {
            positive = coefficient.isPositive
          }
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
