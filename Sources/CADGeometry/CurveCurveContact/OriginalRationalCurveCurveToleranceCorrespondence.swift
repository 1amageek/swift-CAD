import CADCore

/// Complete original rational residual bounds on one directed affine trim map.
struct OriginalRationalCurveCurveToleranceCorrespondence {
  func proves(
    equations: [ExactBivariatePolynomial],
    denominator: ExactBivariatePolynomial,
    first: ScalarInterval,
    second: ScalarInterval,
    reversed: Bool,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    guard equations.count == 3, first.width > 0, second.width > 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &execution)
    func parameter(
      _ start: Double,
      _ end: Double,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> ExactBivariatePolynomial {
      let a = try ExactRationalCoefficient.originalDouble(start, usage: &execution)
      let b = try ExactRationalCoefficient.originalDouble(end, usage: &execution)
      return try t.scaled(by: b.subtracting(a, usage: &execution), usage: &execution)
        .adding(.constant(a, usage: &execution), usage: &execution)
    }
    let u = try parameter(
      first.lower,
      first.upper,
      tolerance: tolerance,
      using: &execution)
    let v = try parameter(
      reversed ? second.upper : second.lower,
      reversed ? second.lower : second.upper,
      tolerance: tolerance,
      using: &execution)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: ExactBivariatePolynomial.self))
    let numerators = try equations.map { try $0.composed(withU: u, v: v, usage: &execution) }
    let weight = try denominator.composed(withU: u, v: v, usage: &execution)
    let zero = try ScalarInterval(lower: 0, upper: 0)
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    func residual(
      _ range: ScalarInterval,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws
      -> OutwardScalarInterval?
    {
      let domain = SurfaceParameterBox(u: range, v: zero)
      let w = try weight.enclosure(over: domain, usage: &execution)
      guard w.lower > 0 else { return nil }
      var square = OutwardScalarInterval.exact(0)
      for value in numerators {
        let numerator = try value.enclosure(over: domain, usage: &execution)
        guard let r = numerator.divided(by: w), r.isFinite else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        let low = r.absoluteLowerBound
        let high = r.absoluteUpperBound
        square =
          square
          + OutwardScalarInterval(
            lower: max(0, (low * low).nextDown),
            upper: (high * high).nextUp)
      }
      return square
    }
    // Original singleton residuals can disprove this map candidate only.
    // They never exclude contacts under other original correspondences.
    for station in [0.0, 0.5, 1.0] {
      if let r = try residual(
        ScalarInterval(lower: station, upper: station),
        tolerance: tolerance,
        using: &execution),
        r.lower > threshold.upper
      {
        return false
      }
    }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 1, of: (ScalarInterval, Int).self))
    var pending = [(try ScalarInterval(lower: 0, upper: 1), 0)]
    while let (range, depth) = pending.popLast() {
      try execution.visitGeometricCell(depth: depth)
      if let r = try residual(
        range,
        tolerance: tolerance,
        using: &execution)
      {
        if r.lower > threshold.upper { return false }
        if r.upper <= threshold.lower { continue }
      }
      guard depth < min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        range.midpoint > range.lower, range.midpoint < range.upper
      else { return false }
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 2, of: (ScalarInterval, Int).self))
      pending.append((try ScalarInterval(lower: range.lower, upper: range.midpoint), depth + 1))
      pending.append((try ScalarInterval(lower: range.midpoint, upper: range.upper), depth + 1))
    }
    return true
  }
}
