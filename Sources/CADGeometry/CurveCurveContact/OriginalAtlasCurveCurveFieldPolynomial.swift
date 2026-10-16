import CADCore

/// Original pair equations over one retained ordered placement coefficient field.
struct OriginalAtlasCurveCurveFieldPolynomial {
  private struct State {
    var context: OriginalSingularFieldContext
    var transport: OriginalSingularFieldTransport
  }

  func equations(
    first: Curve3D,
    firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    second: Curve3D,
    secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [OriginalSingularFieldPlanePolynomial]? {
    try prepare(
      first: first,
      firstOwner: firstOwner,
      second: second,
      secondOwner: secondOwner,
      tolerance: tolerance,
      using: &execution)?.equations
  }

  func prepare(
    first: Curve3D,
    firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    second: Curve3D,
    secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalAtlasCurveCurveFieldEquationSet? {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
    ) { execution in
      var state = State(
        context: try OriginalSingularFieldContext(usage: &execution),
        transport: OriginalSingularFieldTransport())
      let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &execution)
      let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &execution)
      guard
        let a = try homogeneous(
          first,
          owner: firstOwner,
          parameter: u,
          alongU: true,
          depth: 0,
          state: &state,
          tolerance: tolerance,
          using: &execution),
        let b = try homogeneous(
          second,
          owner: secondOwner,
          parameter: v,
          alongU: false,
          depth: 0,
          state: &state,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      let firstValues = try embedded(
        a,
        in: state.context,
        tolerance: tolerance,
        using: &execution)
      let secondValues = try embedded(
        b,
        in: state.context,
        tolerance: tolerance,
        using: &execution)
      try RationalAlgebraStorage.retain(
        3, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
      var result: [OriginalSingularFieldPlanePolynomial] = []
      result.reserveCapacity(3)
      for axis in 0..<3 {
        result.append(
          try firstValues[axis].multiplied(
            by: secondValues[3],
            maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
            usage: &execution
          ).subtracting(
            secondValues[axis].multiplied(
              by: firstValues[3],
              maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
              usage: &execution),
            maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
            usage: &execution))
      }
      let denominator = try firstValues[3].multiplied(
        by: secondValues[3],
        maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth), usage: &execution)
      try RationalAlgebraStorage.retain(
        1, of: OriginalAtlasCurveCurveFieldEquationSet.self, usage: &execution)
      return .init(equations: result, denominator: denominator)

    }
  }

  private func homogeneous(
    _ source: Curve3D,
    owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    parameter: ExactBivariatePolynomial,
    alongU: Bool,
    depth: Int,
    state: inout State,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> [OriginalSingularFieldPlanePolynomial]?
  {
    try execution.consumeWork(1)
    guard depth <= min(32, execution.effectiveLimits.remainingSourceDepth) else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    try execution.admitSourceDepth(depth)
    switch source {
    case .bSpline, .line, .analytic(.line), .originalGuideTraversalChain,
      .originalGuideEndpointConnector, .originalPlaneDerivative:
      guard
        let original = try OriginalAtlasCurveCurvePolynomial().originalHomogeneous(
          source: source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      try RationalAlgebraStorage.retain(
        4, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
      var result: [OriginalSingularFieldPlanePolynomial] = []
      result.reserveCapacity(4)
      for value in original {
        result.append(
          try .original(
            value, in: state.context,
            maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
            usage: &execution))
      }
      return result
    case .parameterImage(let image):
      let parameter = try parameter.scaled(
        by: image.parameterGain.exactCoefficient(usage: &execution),
        usage: &execution
      ).adding(
        .constant(.originalDouble(image.offset, usage: &execution), usage: &execution),
        usage: &execution)
      return try homogeneous(
        image.source,
        owner: owner,
        parameter: parameter,
        alongU: alongU,
        depth: depth + 1,
        state: &state,
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
        state: &state,
        tolerance: tolerance,
        using: &execution)
    case .rigidImage(let image):
      guard
        let values = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          state: &state,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      return try transformed(
        values,
        x: image.transform.basisX,
        y: image.transform.basisY,
        z: image.transform.basisZ,
        translation: image.transform.translation,
        tolerance: tolerance,
        using: &execution)
    case .affineImage(let image):
      guard
        let values = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          state: &state,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      return try transformed(
        values,
        x: image.transform.basisX,
        y: image.transform.basisY,
        z: image.transform.basisZ,
        translation: image.transform.translation,
        tolerance: tolerance,
        using: &execution)
    case .originalAffineWord(let image):
      guard
        let values = try homogeneous(
          image.source,
          owner: owner,
          parameter: parameter,
          alongU: alongU,
          depth: depth + 1,
          state: &state,
          tolerance: tolerance,
          using: &execution)
      else { return nil }
      let prepared = image.preparedWord
      let frame = try prepared.originalNormalizedFrame(usage: &execution)
      let algebraDepth =
        frame.map {
          min(min(32, execution.effectiveLimits.maximumCoefficientDepth), $0.maximumAlgebraicDepth)
        } ?? min(32, execution.effectiveLimits.maximumCoefficientDepth)
      if let frame {
        guard frame.frame.basisX.count == 3, frame.frame.basisY.count == 3,
          frame.frame.basisZ.count == 3, frame.frame.translation.count == 3
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        state.context = try state.transport.importing(
          frame.frame.basisX[0].context,
          into: state.context, maximumDepth: algebraDepth, usage: &execution)
      }
      let original = try embedded(
        values,
        in: state.context,
        tolerance: tolerance,
        using: &execution)
      try RationalAlgebraStorage.retain(
        4, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
      var result: [OriginalSingularFieldPlanePolynomial] = []
      result.reserveCapacity(4)
      for row in 0..<3 {
        var value = try OriginalSingularFieldPlanePolynomial(
          context: state.context,
          coefficients: [:], maximumDepth: algebraDepth, usage: &execution)
        for column in 0..<4 {
          let coefficient: OriginalSingularFieldElement
          if let frame {
            let raw: OriginalSingularFieldElement
            switch column {
            case 0: raw = frame.frame.basisX[row]
            case 1: raw = frame.frame.basisY[row]
            case 2: raw = frame.frame.basisZ[row]
            default: raw = frame.frame.translation[row]
            }
            coefficient = try state.transport.applying(
              to: raw, in: state.context,
              maximumDepth: algebraDepth, usage: &execution)
          } else {
            let raw =
              try column == 3
              ? prepared.translationCoefficient(row: row)
              : prepared.linearCoefficient(row: row, column: column)
            coefficient = try .constant(
              raw, in: state.context,
              maximumDepth: algebraDepth, usage: &execution)
          }
          let scale = try OriginalSingularFieldPlanePolynomial.constant(
            coefficient,
            maximumDepth: algebraDepth, usage: &execution)
          value = try value.adding(
            original[column].multiplied(
              by: scale,
              maximumDepth: algebraDepth, usage: &execution), maximumDepth: algebraDepth,
            usage: &execution)
        }
        result.append(value)
      }
      result.append(original[3])
      return result
    // FIXME(INCOMPLETE_IMPLEMENTATION): Loft's original guide contact route
    // requires exact original angular/procedural coefficient charts here.
    // This field producer handles native rational laws and spatial words;
    // an unavailable original law remains unresolved, never exact absence.
    default: return nil
    }
  }

  private func embedded(
    _ values: [OriginalSingularFieldPlanePolynomial],
    in context: OriginalSingularFieldContext,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  )
    throws -> [OriginalSingularFieldPlanePolynomial]
  {
    try RationalAlgebraStorage.retain(
      values.count, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
    var result: [OriginalSingularFieldPlanePolynomial] = []
    result.reserveCapacity(values.count)
    for value in values {
      result.append(
        try value.embedded(
          in: context, maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution))
    }
    return result
  }

  private func transformed(
    _ original: [OriginalSingularFieldPlanePolynomial],
    x: Vector3D,
    y: Vector3D,
    z: Vector3D,
    translation: Vector3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [OriginalSingularFieldPlanePolynomial] {
    guard let first = original.first, original.count == 4 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    try RationalAlgebraStorage.retain(
      4, of: OriginalSingularFieldPlanePolynomial.self, usage: &execution)
    try RationalAlgebraStorage.retain(
      3, of: (Double, Double, Double, Double).self, usage: &execution)
    var result: [OriginalSingularFieldPlanePolynomial] = []
    result.reserveCapacity(4)
    for (a, b, c, shift) in [
      (x.x, y.x, z.x, translation.x),
      (x.y, y.y, z.y, translation.y), (x.z, y.z, z.z, translation.z),
    ] {
      var value = try OriginalSingularFieldPlanePolynomial(
        context: first.context,
        coefficients: [:], maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
        usage: &execution)
      try RationalAlgebraStorage.retain(4, of: Double.self, usage: &execution)
      for (column, raw) in [a, b, c, shift].enumerated() {
        let exact = try OriginalSingularFieldElement.constant(
          .originalDouble(raw, usage: &execution),
          in: first.context,
          maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)
        value = try value.adding(
          original[column].multiplied(
            by:
              .constant(
                exact, maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
                usage: &execution),
            maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
            usage: &execution),
          maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
          usage: &execution)
      }
      result.append(value)
    }
    result.append(original[3])
    return result
  }
}
