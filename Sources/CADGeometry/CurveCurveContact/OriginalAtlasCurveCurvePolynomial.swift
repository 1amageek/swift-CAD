import CADCore

/// Original rational atlas equations without geometric conversion or fitted control points.
struct OriginalAtlasCurveCurvePolynomial {
  func prepare(
    source: Curve3D,
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    alongU: Bool,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalAtlasCurveHomogeneousPolynomial? {
    let parameter = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &execution)
    guard
      let values = try homogeneous(
        source,
        owner: owner,
        parameter: parameter,
        alongU: alongU,
        depth: 0,
        tolerance: tolerance,
        using: &execution)
    else { return nil }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 1, of: OriginalAtlasCurveHomogeneousPolynomial.self))
    return OriginalAtlasCurveHomogeneousPolynomial(
      source: source, nativeIndex: owner.nativeIndex,
      nativeDomain: owner.nativeDomain, originalPeriodicCycle: owner.originalPeriodicCycle,
      alongU: alongU, values: values)
  }

  func equations(
    first: OriginalAtlasCurveHomogeneousPolynomial,
    second: OriginalAtlasCurveHomogeneousPolynomial,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial] {
    guard first.alongU, !second.alongU, first.values.count == 4, second.values.count == 4 else {
      throw KernelError(
        phase: .geometry, code: .classificationFailure, tolerance: tolerance,
        message: "Original atlas equations require retained first-U and second-V homogeneous laws.")
    }
    let a = first.values
    let b = second.values
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
    var result: [ExactBivariatePolynomial] = []
    for axis in 0..<3 {
      result.append(
        try a[axis].multiplied(by: b[3], usage: &execution)
          .subtracting(b[axis].multiplied(by: a[3], usage: &execution), usage: &execution))
    }
    return result
  }

  /// Shares the raw selected-owner extraction with exact ordered-field action.
  func originalHomogeneous(
    source: Curve3D,
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    parameter: ExactBivariatePolynomial,
    alongU: Bool,
    depth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial]? {
    try homogeneous(
      source,
      owner: owner,
      parameter: parameter,
      alongU: alongU,
      depth: depth,
      tolerance: tolerance,
      using: &execution)
  }

  private func homogeneous(
    _ source: Curve3D,
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    parameter: ExactBivariatePolynomial,
    alongU: Bool,
    depth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial]? {
    try execution.consumeWork(1)
    guard depth <= min(32, execution.effectiveLimits.remainingSourceDepth) else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    try execution.admitSourceDepth(depth)
    switch source {
    case .line(let line):
      return try lineValue(
        origin: line.origin,
        direction: line.direction,
        parameter: parameter,
        tolerance: tolerance,
        using: &execution)
    case .analytic(.line(let origin, let direction)):
      return try lineValue(
        origin: origin,
        direction: direction,
        parameter: parameter,
        tolerance: tolerance,
        using: &execution)
    case .bSpline(let original):
      let nativeParameter: ExactBivariatePolynomial
      if original.isPeriodic {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Historical unbound periodic
        // covers have no selected-cycle receipt. Loft's bounded preparation
        // supplies it; legacy nil metadata must retain the unresolved atlas
        // instead of inferring an exact lift from outward domain bounds.
        guard let cycle = owner.originalPeriodicCycle else { return nil }
        guard cycle.isFinite, cycle.rounded(.towardZero) == cycle,
          abs(cycle) <= 9_007_199_254_740_990
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        try execution.consumeWork(1)
        // The wrapping owner's period is this stored Double subtraction,
        // not an independently redefined rational knot difference.
        let period = original.knots[original.controlPointCount] - original.knots[original.degree]
        guard period.isFinite, period > 0 else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        let shift = try ExactRationalCoefficient.originalDouble(cycle, usage: &execution)
          .multiplied(by: .originalDouble(period, usage: &execution), usage: &execution)
        nativeParameter = try parameter.subtracting(
          .constant(shift, usage: &execution), usage: &execution)
      } else {
        nativeParameter = parameter
      }
      let index = owner.nativeIndex
      guard index >= original.degree, index < original.controlPointCount,
        original.knots[index] < original.knots[index + 1]
      else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "Original atlas algebra lost its retained positive native span index.")
      }
      let basis = try OriginalRationalBSplineBasis.powerPolynomials(
        knots: original.knots,
        degree: original.degree, span: index, alongU: alongU, translation: 0, usage: &execution)
      let parameterPowers = try powers(
        of: nativeParameter,
        throughDegree: original.degree,
        tolerance: tolerance,
        using: &execution)
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 4, of: ExactBivariatePolynomial.self))
      var result = [ExactBivariatePolynomial](repeating: .zero, count: 4)
      for control in (index - original.degree)...index {
        guard let nativeCoefficient = basis[control] else {
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message: "Original atlas algebra lacks an owning native basis coefficient.")
        }
        let coefficient = try composed(
          nativeCoefficient,
          with: parameterPowers,
          alongU: alongU,
          tolerance: tolerance,
          using: &execution)
        let weight = try ExactRationalCoefficient.originalDouble(
          original.weights[control], usage: &execution)
        let point = original.controlPoints[control]
        for (axis, coordinate) in [point.x, point.y, point.z].enumerated() {
          let value = try ExactRationalCoefficient.originalDouble(coordinate, usage: &execution)
            .multiplied(by: weight, usage: &execution)
          result[axis] = try result[axis].adding(
            coefficient.scaled(by: value, usage: &execution), usage: &execution)
        }
        result[3] = try result[3].adding(
          coefficient.scaled(by: weight, usage: &execution), usage: &execution)
      }
      return result
    case .originalGuideTraversalChain(let chain):
      guard owner.originalGuideTraversal != nil, owner.originalAffineParameterMap == nil else {
        return nil
      }
      for traversal in chain.traversals {
        guard try OriginalSplineTraversalPolynomialPiece.supports(traversal, usage: &execution)
        else { return nil }
      }
      let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(
        of: source,
        remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth) - depth,
        tolerance: tolerance, usage: &execution)
      return try selectedPiece(
        pieces,
        owner: owner,
        parameter: parameter,
        tolerance: tolerance,
        using: &execution)
    case .originalGuideEndpointConnector(let connector):
      guard owner.originalGuideTraversal != nil, owner.originalAffineParameterMap == nil,
        try OriginalSplineTraversalPolynomialPiece.supports(connector.source, usage: &execution),
        try OriginalSplineTraversalPolynomialPiece.supports(
          connector.startBoundary, usage: &execution),
        try OriginalSplineTraversalPolynomialPiece.supports(
          connector.endBoundary, usage: &execution)
      else { return nil }
      let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(
        of: source,
        remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth) - depth,
        tolerance: tolerance, usage: &execution)
      return try selectedPiece(
        pieces,
        owner: owner,
        parameter: parameter,
        tolerance: tolerance,
        using: &execution)
    case .originalPlaneDerivative(let image):
      guard image.source.start == .authored(0), image.source.end == .authored(1),
        owner.originalAffineParameterMap == nil,
        try OriginalSplineTraversalPolynomialPiece.supports(image.source, usage: &execution)
      else { return nil }
      let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(of: image, usage: &execution)
      return try selectedPiece(
        pieces,
        owner: owner,
        parameter: parameter,
        tolerance: tolerance,
        using: &execution)
    case .parameterImage(let image):
      let gain = try image.parameterGain.exactCoefficient(usage: &execution)
      let mapped = try parameter.scaled(by: gain, usage: &execution)
        .adding(
          .constant(.originalDouble(image.offset, usage: &execution), usage: &execution),
          usage: &execution)
      return try homogeneous(
        image.source,
        owner: owner,
        parameter: mapped,
        alongU: alongU,
        depth: depth + 1,
        tolerance: tolerance,
        using: &execution)
    case .originalConstructionChart(let image):
      guard case .parameterLaw(let chart) = image.chart, chart.law == .affine,
        let map = owner.originalAffineParameterMap
      else { return nil }
      let mapped = try parameter.scaled(by: map.gain, usage: &execution)
        .adding(.constant(map.offset, usage: &execution), usage: &execution)
      return try homogeneous(
        chart.source,
        owner: owner,
        parameter: mapped,
        alongU: alongU,
        depth: depth + 1,
        tolerance: tolerance,
        using: &execution)
    case .rigidImage(let image):
      guard
        let original = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      return try transformed(
        original,
        basisX: image.transform.basisX,
        basisY: image.transform.basisY,
        basisZ: image.transform.basisZ,
        translation: image.transform.translation,
        tolerance: tolerance,
        using: &execution)
    case .affineImage(let image):
      guard
        let original = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      return try transformed(
        original,
        basisX: image.transform.basisX,
        basisY: image.transform.basisY,
        basisZ: image.transform.basisZ,
        translation: image.transform.translation,
        tolerance: tolerance,
        using: &execution)
    case .originalAffineWord(let image):
      try execution.consumeWork(image.operationWord.factors.count)
      // FIXME(INCOMPLETE_IMPLEMENTATION): Loft original pair atlases
      // still need ordered-field polynomials for normalized spatial words.
      // Rational coefficient enclosures cannot stand in for exact algebra.
      guard
        !image.operationWord.factors.contains(where: {
          switch $0 {
          case .normalizedForward, .normalizedInverse: true
          default: false
          }
        })
      else { return nil }
      guard
        let original = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      let word = try image.operationWord.prepared(usage: &execution)
      try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &execution)
      var result: [ExactBivariatePolynomial] = []
      result.reserveCapacity(4)
      for row in 0..<3 {
        var value = try original[3].scaled(
          by: word.translationCoefficient(row: row), usage: &execution)
        for column in 0..<3 {
          try execution.consumeWork(1)
          value = try value.adding(
            original[column].scaled(
              by: word.linearCoefficient(row: row, column: column), usage: &execution),
            usage: &execution)
        }
        result.append(value)
      }
      result.append(original[3])
      return result
    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft's original angular/procedural
    // contact atlas reaches these families. Their original critical charts
    // must be supplied before finite algebraic coverage can be published;
    // nil retains the marked atlas search rather than proving absence.
    default: return nil
    }
  }

  private func selectedPiece(
    _ pieces: [OriginalSplineTraversalPolynomialPiece],
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    parameter: ExactBivariatePolynomial,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> [ExactBivariatePolynomial]?
  {
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    if owner.originalGuideTraversal != nil {
      guard let first = owner.originalGuideLowerParameter,
        let last = owner.originalGuideUpperParameter
      else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "Original polynomial contact lost its exact aggregate owner bounds.")
      }
      lower = first
      upper = last
    } else {
      lower = try .originalDouble(owner.nativeDomain.lower, usage: &execution)
      upper = try .originalDouble(owner.nativeDomain.upper, usage: &execution)
    }
    for piece in pieces {
      try execution.consumeWork(1)
      guard try !lower.subtracting(piece.lower, usage: &execution).isNegative,
        try !piece.upper.subtracting(upper, usage: &execution).isNegative
      else { continue }
      try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &execution)
      var values: [ExactBivariatePolynomial] = []
      values.reserveCapacity(4)
      for value in piece.homogeneous {
        values.append(try value.composed(withU: parameter, v: .zero, usage: &execution))
      }
      return values
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): A retained guide traversal can
    // contain several native polynomial owners. Generic contact search
    // must partition that exact aggregate owner before issuing one law;
    // a whole traversal hull cannot authorize a single polynomial.
    return nil
  }

  private func lineValue(
    origin: Point3D,
    direction: Vector3D,
    parameter: ExactBivariatePolynomial,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial] {
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: ExactBivariatePolynomial.self))
    var result: [ExactBivariatePolynomial] = []
    for (origin, direction) in [
      (origin.x, direction.x), (origin.y, direction.y), (origin.z, direction.z),
    ] {
      result.append(
        try parameter.scaled(by: .originalDouble(direction, usage: &execution), usage: &execution)
          .adding(
            .constant(.originalDouble(origin, usage: &execution), usage: &execution),
            usage: &execution))
    }
    result.append(try .constant(.one, usage: &execution))
    return result
  }

  private func powers(
    of parameter: ExactBivariatePolynomial,
    throughDegree degree: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial] {
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: degree + 1, of: ExactBivariatePolynomial.self))
    var result = [try ExactBivariatePolynomial.constant(.one, usage: &execution)]
    if degree > 0 {
      for _ in 1...degree {
        result.append(try result[result.count - 1].multiplied(by: parameter, usage: &execution))
      }
    }
    return result
  }

  private func composed(
    _ original: ExactBivariatePolynomial,
    with powers: [ExactBivariatePolynomial],
    alongU: Bool,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ExactBivariatePolynomial {
    var result = ExactBivariatePolynomial.zero
    for term in try original.orderedTerms(usage: &execution) {
      guard (alongU ? term.key.v : term.key.u) == 0 else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "A retained native basis law contains an unrelated atlas parameter.")
      }
      result = try result.adding(
        powers[alongU ? term.key.u : term.key.v]
          .scaled(by: term.value, usage: &execution), usage: &execution)
    }
    return result
  }

  private func transformed(
    _ original: [ExactBivariatePolynomial],
    basisX: Vector3D,
    basisY: Vector3D,
    basisZ: Vector3D,
    translation: Vector3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ExactBivariatePolynomial] {
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: ExactBivariatePolynomial.self))
    var result: [ExactBivariatePolynomial] = []
    for (x, y, z, offset) in [
      (basisX.x, basisY.x, basisZ.x, translation.x),
      (basisX.y, basisY.y, basisZ.y, translation.y),
      (basisX.z, basisY.z, basisZ.z, translation.z),
    ] {
      var value = try original[3].scaled(
        by: .originalDouble(offset, usage: &execution), usage: &execution)
      for (axis, coefficient) in [x, y, z].enumerated() {
        value = try value.adding(
          original[axis].scaled(
            by: .originalDouble(coefficient, usage: &execution), usage: &execution),
          usage: &execution)
      }
      result.append(value)
    }
    result.append(original[3])
    return result
  }
}
