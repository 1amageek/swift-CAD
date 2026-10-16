import CADCore

struct PolynomialCurveConversionTarget: GeometryCurveConversionSource {
  private let curve: BSplineCurve3D
  private let patches: [PolynomialConversionTargetPatch]

  static func accepts(_ curve: BSplineCurve3D) -> Bool {
    guard !curve.isPeriodic, (1...3).contains(curve.degree),
      curve.controlPointCount > curve.degree,
      curve.knots.count == curve.controlPointCount + curve.degree + 1,
      curve.weights.count == curve.controlPointCount,
      let weight = curve.weights.first, weight.isFinite, weight > 0,
      curve.weights.allSatisfy({ $0 == weight })
    else { return false }
    let degree = curve.degree
    guard (curve.controlPointCount - 1).isMultiple(of: degree) else { return false }
    let spans = (curve.controlPointCount - 1) / degree
    for span in 0..<spans {
      let start = span * degree
      let upperIndex = start + degree + 1
      let lower = curve.knots[start + degree]
      let upper = curve.knots[upperIndex]
      guard lower.isFinite, upper.isFinite, lower < upper else { return false }
      for i in (upperIndex - degree)..<upperIndex where curve.knots[i] != lower { return false }
      for i in upperIndex..<(upperIndex + degree) where curve.knots[i] != upper { return false }
    }
    return curve.knots.first == curve.knots[degree]
      && curve.knots.last == curve.knots[curve.controlPointCount]
  }

  init(_ source: BSplineCurve3D, tolerance: ModelingTolerance) throws {
    var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    try self.init(source, tolerance: tolerance, using: &execution)
  }

  init(
    _ curve: BSplineCurve3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    try curve.validate(tolerance: tolerance, using: &execution)
    guard Self.accepts(curve) else {
      throw GeometryConversionError.invalidInput(
        "Polynomial curve target requires exact stored Bezier polygons through cubic degree.")
    }
    self.curve = curve
    let spans = (curve.controlPointCount - 1) / curve.degree
    var values: [PolynomialConversionTargetPatch] = []
    try OriginalCoefficientAllocation.reserve(
      count: spans, of: PolynomialConversionTargetPatch.self, using: &execution)
    values.reserveCapacity(spans)
    for span in 0..<spans {
      try CurrentTaskCancellationChecker().checkCancellation()
      let start = span * curve.degree
      values.append(
        try PolynomialConversionTargetPatch(
          u: ScalarInterval(
            lower: curve.knots[start + curve.degree], upper: curve.knots[start + curve.degree + 1]),
          v: ScalarInterval(lower: 0, upper: 1), uDegree: curve.degree, vDegree: 0,
          using: &execution
        ) { u, _ in curve.controlPoints[start + u] })
    }
    patches = values
  }

  func validate(
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.checkpoint()
    try tolerance.validate()
    guard parameters.width > 0, parameters.width.isFinite,
      parameters.lower >= curve.knots[curve.degree],
      parameters.upper <= curve.knots[curve.controlPointCount]
    else {
      throw GeometryConversionError.invalidInput(
        "Polynomial curve target requires its complete requested native interval.")
    }
  }

  func pointAndDerivative(
    at parameter: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> (point: Point3D, derivative: Vector3D) {
    let value = try Curve3D.bSpline(curve).differentialGeometry(
      at: parameter, tolerance: tolerance, using: &execution)
    return (value.position, value.firstDerivative)
  }

  func enclosure(
    over parameters: ScalarInterval, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveDifferentialEnclosure {
    try validate(over: parameters, tolerance: tolerance, using: &execution)
    var position: PolynomialConversionTargetPatch.Vector?
    var first: PolynomialConversionTargetPatch.Vector?
    var second: PolynomialConversionTargetPatch.Vector?
    for patch in patches {
      let lower = max(parameters.lower, patch.u.lower)
      let upper = min(parameters.upper, patch.u.upper)
      guard lower <= upper else { continue }
      let box = SurfaceParameterBox(
        u: try ScalarInterval(lower: lower, upper: upper),
        v: try ScalarInterval(lower: 0, upper: 0))
      position = Self.union(
        position, try patch.derivative(uOrder: 0, vOrder: 0, over: box, using: &execution))
      first = Self.union(
        first, try patch.derivative(uOrder: 1, vOrder: 0, over: box, using: &execution))
      second = Self.union(
        second, try patch.derivative(uOrder: 2, vOrder: 0, over: box, using: &execution))
    }
    guard let position, let first, let second else {
      throw GeometryConversionError.invalidInput(
        "Polynomial curve target lost its requested native spans.")
    }
    return try .init(
      position: PolynomialConversionTargetPatch.coordinates(position),
      firstDerivative: PolynomialConversionTargetPatch.coordinates(first),
      secondDerivative: PolynomialConversionTargetPatch.coordinates(second))
  }

  func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    try validate(over: parameters, tolerance: tolerance, using: &execution)
  }

  func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws
    -> CurveDifferentialEnclosure
  {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
  }

  func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (
    point: Point3D, derivative: Vector3D
  ) {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try pointAndDerivative(at: parameter, tolerance: tolerance, using: &execution)
  }

  private static func union(
    _ a: PolynomialConversionTargetPatch.Vector?,
    _ b: PolynomialConversionTargetPatch.Vector
  ) -> PolynomialConversionTargetPatch.Vector {
    guard let a else { return b }
    return .init(x: a.x.union(b.x), y: a.y.union(b.y), z: a.z.union(b.z))
  }
}
