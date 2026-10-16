import CADCore

/// Original near-parallel field continuation with whole spatial and angular bounds.
struct OriginalProjectedFieldCurveCurveToleranceContact {
  func certificate(
    original: OriginalAtlasCurveCurveFieldEquationSet,
    over domain: SurfaceParameterBox, maximumDepth: Int,
    selectedJets: (ScalarInterval, ScalarInterval, inout OriginalQueryExecution) throws
      -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterBox? {
    let equations = original.equations
    let denominator = original.denominator
    guard equations.count == 3, maximumDepth >= 0, domain.u.width > 0, domain.v.width > 0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let coefficientWidth = try ExactRationalCoefficient.originalDouble(
      tolerance.relative, usage: &execution)
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    func derivative(
      _ value: OriginalSingularFieldPlanePolynomial,
      alongU: Bool,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldPlanePolynomial {
      return try execution.withProofScope(
        maximum: try ExactScalarDepth(
          value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
      ) { execution in
        return try value.differentiated(
          alongU: alongU, maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)

      }
    }
    func product(
      _ first: OriginalSingularFieldPlanePolynomial,
      _ second: OriginalSingularFieldPlanePolynomial,
      minusThird: OriginalSingularFieldPlanePolynomial,
      timesFourth: OriginalSingularFieldPlanePolynomial,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldPlanePolynomial {
      return try execution.withProofScope(
        maximum: try ExactScalarDepth(
          value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
      ) { execution in
        return try first.multiplied(
          by: second, maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution
        )
        .subtracting(
          minusThird.multiplied(
            by: timesFourth,
            maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
            usage: &execution),
          maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)

      }
    }
    func remainder(
      _ value: OriginalSingularFieldPlanePolynomial,
      by relation: OriginalSingularFieldPlanePolynomial,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> OriginalSingularFieldPlanePolynomial {
      return try execution.withProofScope(
        maximum: try ExactScalarDepth(
          value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
      ) { execution in
        return try value.quotientAndRemainder(
          dividingBy: relation,
          maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution
        ).remainder

      }
    }
    func bounds(
      _ value: OriginalSingularFieldPlanePolynomial,
      over box: SurfaceParameterBox,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> OutwardScalarInterval {
      return try execution.withProofScope(
        maximum: try ExactScalarDepth(
          value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
      ) { execution in
        return try value.partial(
          over: box, uOrder: 0, vOrder: 0,
          maximumCoefficientWidth: coefficientWidth,
          maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)

      }
    }
    func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      .init(
        lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
        upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
    }
    let dU = try derivative(
      denominator,
      alongU: true,
      tolerance: tolerance,
      using: &execution)
    let dV = try derivative(
      denominator,
      alongU: false,
      tolerance: tolerance,
      using: &execution)
    try RationalAlgebraStorage.retain(
      6, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
    var firstTangents: [OriginalSingularFieldPlanePolynomial] = []
    var secondTangents: [OriginalSingularFieldPlanePolynomial] = []
    firstTangents.reserveCapacity(3)
    secondTangents.reserveCapacity(3)
    for equation in equations {
      let du = try derivative(
        equation,
        alongU: true,
        tolerance: tolerance,
        using: &execution)
      let dv = try derivative(
        equation,
        alongU: false,
        tolerance: tolerance,
        using: &execution)
      firstTangents.append(
        try product(
          du,
          denominator,
          minusThird: equation,
          timesFourth: dU,
          tolerance: tolerance,
          using: &execution))
      secondTangents.append(
        try product(
          equation,
          dV,
          minusThird: dv,
          timesFourth: denominator,
          tolerance: tolerance,
          using: &execution))
    }
    func admitted(
      _ box: SurfaceParameterBox,
      relation: OriginalSingularFieldPlanePolynomial,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      let weight = try bounds(
        denominator,
        over: box,
        tolerance: tolerance,
        using: &execution)
      guard weight.lower > 0 else { return false }
      var residual = OutwardScalarInterval.exact(0)
      for equation in equations {
        let originalRemainder = try remainder(
          equation,
          by: relation,
          tolerance: tolerance,
          using: &execution)
        guard
          let value = try bounds(
            originalRemainder,
            over: box,
            tolerance: tolerance,
            using: &execution
          ).divided(by: weight)
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        residual = residual + square(value)
      }
      guard residual.upper <= threshold.lower else { return false }
      let hu = try derivative(
        relation,
        alongU: true,
        tolerance: tolerance,
        using: &execution)
      let hv = try derivative(
        relation,
        alongU: false,
        tolerance: tolerance,
        using: &execution)
      let u = try bounds(
        hu,
        over: box,
        tolerance: tolerance,
        using: &execution)
      let v = try bounds(
        hv,
        over: box,
        tolerance: tolerance,
        using: &execution)
      guard u.excludesZero, v.excludesZero,
        let mapDerivative = (-u).divided(by: v), mapDerivative.excludesZero
      else { return false }
      let direction = OutwardScalarInterval.exact(mapDerivative.lower > 0 ? 1 : -1)
      try RationalAlgebraStorage.retain(6, of: OutwardScalarInterval.self, usage: &execution)
      var a: [OutwardScalarInterval] = []
      var b: [OutwardScalarInterval] = []
      a.reserveCapacity(3)
      b.reserveCapacity(3)
      for axis in 0..<3 {
        let ar = try remainder(
          firstTangents[axis],
          by: relation,
          tolerance: tolerance,
          using: &execution)
        let br = try remainder(
          secondTangents[axis],
          by: relation,
          tolerance: tolerance,
          using: &execution)
        a.append(
          try bounds(
            ar,
            over: box,
            tolerance: tolerance,
            using: &execution))
        b.append(
          try bounds(
            br,
            over: box,
            tolerance: tolerance,
            using: &execution) * direction)
      }
      var lengthA = OutwardScalarInterval.exact(0)
      var lengthB = lengthA
      var dot = lengthA
      for axis in 0..<3 {
        try execution.consumeWork(1)
        lengthA = lengthA + square(a[axis])
        lengthB = lengthB + square(b[axis])
        dot = dot + a[axis] * b[axis]
      }
      guard lengthA.lower > 0, lengthB.lower > 0, dot.lower > 0 else { return false }
      var cross = OutwardScalarInterval.exact(0)
      var exactParallel = true
      for axis in 0..<3 {
        let i = (axis + 1) % 3
        let j = (axis + 2) % 3
        let originalCross = try product(
          firstTangents[i],
          secondTangents[j],
          minusThird: firstTangents[j],
          timesFourth: secondTangents[i],
          tolerance: tolerance,
          using: &execution)
        let reduced = try remainder(
          originalCross,
          by: relation,
          tolerance: tolerance,
          using: &execution)
        if !reduced.isZero { exactParallel = false }
        cross =
          cross
          + square(
            try bounds(
              reduced,
              over: box,
              tolerance: tolerance,
              using: &execution))
      }
      if exactParallel { return true }
      let angular = OutwardScalarInterval.exact(min(1, tolerance.angle)) * .exact(0.5)
      return cross.upper <= (angular * angular * lengthA * lengthB).lower
    }
    for equation in equations where !equation.isZero {
      let projection = try OriginalSingularFieldPlaneProjection(
        original: equation,
        over: domain, inheritedDepth: 0, maximumDepth: maximumDepth, usage: &execution)
      guard projection.sectors.contains(where: { !$0.fiberRoots.isEmpty }) else { continue }
      let atlas = try OriginalFieldPlaneAtlas(
        retaining: projection, maximumDepth: maximumDepth, usage: &execution)
      for strip in atlas.strips {
        for piece in strip.originalInteriorCover.pieces {
          try execution.consumeWork(1)
          guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
          if try admitted(
            piece.domain,
            relation: projection.squareFree,
            tolerance: tolerance,
            using: &execution)
          {
            _ = try selectedJets(piece.domain.u, piece.domain.v, &execution)
            return piece.domain
          }
        }
      }
    }
    return nil
  }
}
