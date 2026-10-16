import CADCore
import CADGeometry

/// A factorial-scaled interval Taylor jet used for directional rational
/// surface-flux derivative bounds. Every coefficient operation uses the
/// caller's original admission and owns its requested typed output storage.
struct CertifiedUnivariateTaylorJet: Sendable {
  typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval
  static let order = 7
  var coefficients: [Interval]

  static func constant<A: ExactScalarAdmission & ~Copyable>(
    _ value: Double,
    using execution: inout A
  ) throws -> Self {
    try constant(.exact(value), using: &execution)
  }

  static func constant<A: ExactScalarAdmission & ~Copyable>(
    _ value: Interval,
    using execution: inout A
  ) throws -> Self {
    var coefficients = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: order + 1, using: &execution)
    try execution.consumeWork(1)
    coefficients[0] = value
    return Self(coefficients: coefficients)
  }

  static func variable<A: ExactScalarAdmission & ~Copyable>(
    _ value: Interval,
    using execution: inout A
  ) throws -> Self {
    var coefficients = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: order + 1, using: &execution)
    try execution.consumeWork(2)
    coefficients[0] = value
    coefficients[1] = .exact(1)
    return Self(coefficients: coefficients)
  }

  static func series<A: ExactScalarAdmission & ~Copyable>(
    _ values: [Interval],
    using execution: inout A
  ) throws -> Self {
    var coefficients = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: order + 1, using: &execution)
    for index in 0..<min(values.count, order + 1) {
      try execution.consumeWork(1)
      coefficients[index] = values[index]
    }
    return Self(coefficients: coefficients)
  }

  var value: Interval { coefficients[0] }

  func derivative<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> Self {
    var result = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: Self.order + 1, using: &execution)
    for degree in 0..<Self.order {
      try execution.consumeWork(1)
      result[degree] = coefficients[degree + 1] * .exact(Double(degree + 1))
    }
    return Self(coefficients: result)
  }

  func divided<A: ExactScalarAdmission & ~Copyable>(
    by denominator: Self,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> Self {
    let inverse = try denominator.reciprocal(tolerance: tolerance, using: &execution)
    return try multiplied(by: inverse, using: &execution)
  }

  func reciprocal<A: ExactScalarAdmission & ~Copyable>(
    tolerance: ModelingTolerance,
    using execution: inout A
  ) throws -> Self {
    try execution.consumeWork(1)
    let constant = value
    guard constant.lower > 0 || constant.upper < 0 else {
      let minimumAbsolute =
        constant.lower <= 0 && constant.upper >= 0
        ? 0 : min(abs(constant.lower), abs(constant.upper))
      throw KernelError(
        phase: .topology, code: .singularSystem, residual: minimumAbsolute,
        tolerance: tolerance,
        message: "Certified directional surface flux encountered a singular reciprocal jet.")
    }
    let inverse = Interval.exact(1) / constant
    var result = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: Self.order + 1, using: &execution)
    result[0] = inverse
    for degree in 1...Self.order {
      var sum = Interval.exact(0)
      for index in 1...degree {
        try execution.consumeWork(1)
        sum = sum + coefficients[index] * result[degree - index]
      }
      try execution.consumeWork(1)
      result[degree] = -inverse * sum
    }
    return Self(coefficients: result)
  }

  func negated<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> Self {
    Self(
      coefficients: try OriginalParameterQueryStorage.map(
        coefficients, using: &execution,
        transform: { value, _ in -value }))
  }

  func adding<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A) throws
    -> Self
  {
    Self(
      coefficients: try OriginalParameterQueryStorage.map(
        zip(coefficients, other.coefficients), using: &execution,
        transform: { pair, _ in pair.0 + pair.1 }))
  }

  func subtracting<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A)
    throws -> Self
  {
    let negative = try other.negated(using: &execution)
    return try adding(negative, using: &execution)
  }

  func multiplied<A: ExactScalarAdmission & ~Copyable>(by other: Self, using execution: inout A)
    throws -> Self
  {
    var result = try OriginalParameterQueryStorage.repeated(
      Interval.exact(0), count: Self.order + 1, using: &execution)
    for degree in 0...Self.order {
      for index in 0...degree {
        try execution.consumeWork(1)
        result[degree] = result[degree] + coefficients[index] * other.coefficients[degree - index]
      }
    }
    return Self(coefficients: result)
  }
}
