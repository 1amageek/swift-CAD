import CADCore

/// Positive original near-parallel correspondence; never a zero-root exclusion.
struct OriginalProjectedCurveCurveToleranceContact {
  func certificate(
    equations: [ExactBivariatePolynomial],
    denominator: ExactBivariatePolynomial,
    over domain: SurfaceParameterBox,
    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterBox? {
    guard equations.count == 3, domain.u.width > 0, domain.v.width > 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let dU = try denominator.differentiated(alongU: true, usage: &execution)
    let dV = try denominator.differentiated(alongU: false, usage: &execution)
    try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &execution)
    var firstTangent: [ExactBivariatePolynomial] = []
    var secondTangent: [ExactBivariatePolynomial] = []
    for equation in equations {
      firstTangent.append(
        try equation.differentiated(alongU: true, usage: &execution)
          .multiplied(by: denominator, usage: &execution)
          .subtracting(equation.multiplied(by: dU, usage: &execution), usage: &execution))
      secondTangent.append(
        try equation.multiplied(by: dV, usage: &execution)
          .subtracting(
            equation.differentiated(alongU: false, usage: &execution)
              .multiplied(by: denominator, usage: &execution), usage: &execution))
    }
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      let low = value.absoluteLowerBound
      let high = value.absoluteUpperBound
      return .init(lower: max(0, (low * low).nextDown), upper: (high * high).nextUp)
    }
    func admitted(
      _ box: SurfaceParameterBox,
      relation: ExactBivariatePolynomial,
      hu: ExactBivariatePolynomial,
      hv: ExactBivariatePolynomial,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      let weight = try denominator.enclosure(over: box, usage: &execution)
      guard weight.excludesZero else { return false }
      var residual = OutwardScalarInterval.exact(0)
      for equation in equations {
        let remainder = try equation.quotientAndRemainder(dividingBy: relation, usage: &execution)
          .remainder
        guard let value = try remainder.enclosure(over: box, usage: &execution).divided(by: weight)
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        residual = residual + square(value)
      }
      guard residual.upper <= threshold.lower else { return false }
      let u = try hu.enclosure(over: box, usage: &execution)
      let v = try hv.enclosure(over: box, usage: &execution)
      // Both original parameters must vary. A scalar graph with
      // constant other parameter is not a paired overlap witness.
      guard u.excludesZero, v.excludesZero,
        let mapDerivative = (-u).divided(by: v), mapDerivative.excludesZero
      else { return false }
      let direction = OutwardScalarInterval.exact(mapDerivative.lower > 0 ? 1 : -1)
      try RationalAlgebraStorage.retain(6, of: OutwardScalarInterval.self, usage: &execution)
      var a: [OutwardScalarInterval] = []
      var b: [OutwardScalarInterval] = []
      for axis in 0..<3 {
        let ar = try firstTangent[axis].quotientAndRemainder(
          dividingBy: relation, usage: &execution
        ).remainder
        let br = try secondTangent[axis].quotientAndRemainder(
          dividingBy: relation, usage: &execution
        ).remainder
        a.append(try ar.enclosure(over: box, usage: &execution))
        b.append(try br.enclosure(over: box, usage: &execution) * direction)
      }
      var lengthA = OutwardScalarInterval.exact(0)
      var lengthB = lengthA
      var dot = lengthA
      for axis in 0..<3 {
        lengthA = lengthA + square(a[axis])
        lengthB = lengthB + square(b[axis])
        dot = dot + a[axis] * b[axis]
      }
      guard lengthA.lower > 0, lengthB.lower > 0, dot.lower > 0 else { return false }
      var crossSquared = OutwardScalarInterval.exact(0)
      var exactParallel = true
      for axis in 0..<3 {
        let i = (axis + 1) % 3
        let j = (axis + 2) % 3
        let originalCross = try firstTangent[i].multiplied(by: secondTangent[j], usage: &execution)
          .subtracting(
            firstTangent[j].multiplied(by: secondTangent[i], usage: &execution), usage: &execution
          )
          .quotientAndRemainder(dividingBy: relation, usage: &execution).remainder
        if !originalCross.isZero { exactParallel = false }
        crossSquared =
          try crossSquared + square(originalCross.enclosure(over: box, usage: &execution))
      }
      // On [0,1], sin(angle) >= angle/2. Positive dot restricts
      // the actual angle to [0,pi/2], so this sufficient original
      // bound preserves the authored angular tolerance without
      // admitting transverse crossings or changing its value.
      if exactParallel { return true }
      let angular = OutwardScalarInterval.exact(min(1, tolerance.angle)) * .exact(0.5)
      let allowed = angular * angular * lengthA * lengthB
      return crossSquared.upper <= allowed.lower
    }
    for coordinate in equations.indices where !equations[coordinate].isZero {
      let authority = try OriginalRationalZeroSetAuthority(
        original: equations[coordinate], usage: &execution)
      let relation = authority.squareFree
      let hu = try relation.differentiated(alongU: true, usage: &execution)
      let hv = try relation.differentiated(alongU: false, usage: &execution)
      for freeAlongU in [true, false] {
        guard
          let graph = try ExactMonotoneRectangleGraphProducer.graph(
            of: relation,
            over: domain, freeAlongU: freeAlongU, maximumDepth: maximumDepth, usage: &execution),
          !graph.spans.isEmpty
        else { continue }
        for span in graph.spans {
          let low = try graph.stations[span.lowerStation].endpoint.upper.outwardInterval(
            usage: &execution
          ).upper
          let high = try graph.stations[span.upperStation].endpoint.lower.outwardInterval(
            usage: &execution
          ).lower
          guard low < high else { continue }
          let free = try ScalarInterval(lower: low, upper: high)
          let box =
            freeAlongU
            ? SurfaceParameterBox(u: free, v: domain.v)
            : SurfaceParameterBox(u: domain.u, v: free)
          if try admitted(
            box,
            relation: relation,
            hu: hu,
            hv: hv,
            tolerance: tolerance,
            using: &execution)
          {
            return box
          }
        }
      }
      let projection = try OriginalRationalPlaneCurveProjection(
        original: authority,
        over: domain, maximumDepth: maximumDepth, usage: &execution)
      // A finite exact zero set has no positive original relation sector.
      // It supplies no tolerance-contact absence authority.
      if try projection.finiteOriginalRoots(usage: &execution) != nil { continue }
      let atlas = try OriginalRationalPlaneCurveAtlas(
        retaining: projection,
        maximumDepth: maximumDepth, usage: &execution)
      for strip in atlas.strips {
        for piece in strip.originalCover.pieces {
          try execution.consumeWork(1)
          guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
          if try admitted(
            piece.domain,
            relation: relation,
            hu: hu,
            hv: hv,
            tolerance: tolerance,
            using: &execution)
          {
            return piece.domain
          }
        }
      }
    }
    return nil
  }
}
