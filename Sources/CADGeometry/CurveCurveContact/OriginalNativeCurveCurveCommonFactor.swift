import CADCore

/// One retained square-free original factor divided exactly from every XYZ equation.
struct OriginalNativeCurveCurveCommonFactor: Sendable {
  let factor: ExactBivariatePolynomial
  let quotients: [ExactBivariatePolynomial]
  let derivativeU: ExactBivariatePolynomial
  let derivativeV: ExactBivariatePolynomial

  init(
    retainingSubfactor source: ExactBivariatePolynomial,
    of original: OriginalNativeCurveCurveCommonFactor,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    guard !source.isZero, source.uDegree > 0 || source.vDegree > 0 else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "An original contact subfactor must retain a nonconstant original law.")
    }
    let other = try original.factor.dividedExactly(by: source, usage: &execution)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(
        count: original.quotients.count, of: ExactBivariatePolynomial.self))
    quotients = try original.quotients.map { try $0.multiplied(by: other, usage: &execution) }
    factor = source
    derivativeU = try source.differentiated(alongU: true, usage: &execution)
    derivativeV = try source.differentiated(alongU: false, usage: &execution)
  }

  init?(
    equations: [ExactBivariatePolynomial], tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    guard equations.count == 3 else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "An original curve common factor requires every XYZ equation.")
    }
    let gcd = ExactBivariateGCD()
    var source = try gcd.greatestCommonDivisor(equations[0], equations[1], usage: &execution)
    source = try gcd.greatestCommonDivisor(source, equations[2], usage: &execution)
    guard !source.isZero, source.uDegree > 0 || source.vDegree > 0 else { return nil }
    let repeatedU = try gcd.greatestCommonDivisor(
      source,
      source.differentiated(alongU: true, usage: &execution), usage: &execution)
    let repeated = try gcd.greatestCommonDivisor(
      repeatedU,
      source.differentiated(alongU: false, usage: &execution), usage: &execution)
    source = try source.dividedExactly(by: repeated, usage: &execution)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
    quotients = try equations.map { try $0.dividedExactly(by: source, usage: &execution) }
    factor = source
    derivativeU = try source.differentiated(alongU: true, usage: &execution)
    derivativeV = try source.differentiated(alongU: false, usage: &execution)
  }
}
