import CADCore

/// Original XYZ homogeneous differences in the two original native parameters.
struct OriginalNativeCurveCurvePolynomial: Sendable {
  let equations: [ExactBivariatePolynomial]
  let denominator: ExactBivariatePolynomial
  let commonFactor: OriginalNativeCurveCurveCommonFactor?

  init(
    firstSource: BSplineCurve3D,
    first: RationalBezierCurveJetEncloser.NativeSpan,
    secondSource: BSplineCurve3D,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    func homogeneous(
      _ source: BSplineCurve3D,
      span: RationalBezierCurveJetEncloser.NativeSpan,
      alongU: Bool,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [ExactBivariatePolynomial] {
      guard span.index >= source.degree, span.index < source.controlPointCount,
        source.knots[span.index] == span.lower, source.knots[span.index + 1] == span.upper
      else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "Exact original curve algebra lost its validated native source span.")
      }
      let basis = try OriginalRationalBSplineBasis.powerPolynomials(
        knots: source.knots,
        degree: source.degree, span: span.index, alongU: alongU, translation: 0, usage: &execution)
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 4, of: ExactBivariatePolynomial.self))
      var values = [ExactBivariatePolynomial](repeating: .zero, count: 4)
      for index in (span.index - source.degree)...span.index {
        guard let coefficient = basis[index] else {
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message:
              "An original curve polynomial has no coefficient for its owning native control.")
        }
        let weight = try ExactRationalCoefficient.originalDouble(
          source.weights[index], usage: &execution)
        let point = source.controlPoints[index]
        for (axis, coordinate) in [point.x, point.y, point.z].enumerated() {
          let value = try ExactRationalCoefficient.originalDouble(coordinate, usage: &execution)
            .multiplied(by: weight, usage: &execution)
          values[axis] = try values[axis].adding(
            coefficient.scaled(by: value, usage: &execution), usage: &execution)
        }
        values[3] = try values[3].adding(
          coefficient.scaled(by: weight, usage: &execution), usage: &execution)
      }
      return values
    }
    let a = try homogeneous(
      firstSource,
      span: first,
      alongU: true,
      tolerance: tolerance,
      using: &execution)
    let b = try homogeneous(
      secondSource,
      span: second,
      alongU: false,
      tolerance: tolerance,
      using: &execution)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
    var output: [ExactBivariatePolynomial] = []
    for axis in 0..<3 {
      output.append(
        try a[axis].multiplied(by: b[3], usage: &execution)
          .subtracting(b[axis].multiplied(by: a[3], usage: &execution), usage: &execution))
    }
    equations = output
    denominator = try a[3].multiplied(by: b[3], usage: &execution)
    commonFactor = try OriginalNativeCurveCurveCommonFactor(
      equations: output,
      tolerance: tolerance,
      using: &execution)
  }
}
