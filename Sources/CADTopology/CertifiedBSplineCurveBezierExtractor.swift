import CADCore
import CADGeometry

/// Extracts every active rational B-spline span as a homogeneous Bezier patch.
/// All basis, derivative, and Bernstein reconstruction arithmetic is enclosed
/// with outward-rounded scalar bounds.
struct CertifiedBSplineCurveBezierExtractor {
  private typealias Patch = CertifiedHomogeneousBezierCurvePatch
  private typealias Point = Patch.HomogeneousPoint
  private typealias Scalar = Patch.ScalarBounds

  private let maximumControlOperations: Int

  init(maximumControlOperations: Int = 1_000_000) {
    self.maximumControlOperations = maximumControlOperations
  }

  func patches(
    curve: BSplineCurve2D,
    tolerance: ModelingTolerance
  ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: Int.max),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try patches(curve: curve, tolerance: tolerance, using: &execution)
  }

  func patches(
    curve: BSplineCurve2D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> [CertifiedHomogeneousBezierCurvePatch]
        {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          execution.context = execution.context.at(stage: .source)
          try curve.validate(tolerance: tolerance, using: &execution)
          execution.context = execution.context.at(stage: .refinement)
          guard curve.degree >= 1,
            case .closed(let domainLower, let domainUpper) = curve.domain,
            domainUpper > domainLower
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message: "Certified B-spline curve extraction requires a positive bounded domain."
            )
          }
          let breaks =
            (try parameterBreaks(
              knots: curve.knots,
              lower: domainLower,
              upper: domainUpper, using: &execution
            ))
          guard breaks.count >= 2 else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              tolerance: tolerance,
              message: "Certified B-spline curve extraction found no active Bezier span."
            )
          }

          var operationCount = 0
          var spanCursor = curve.degree
          var result: [CertifiedHomogeneousBezierCurvePatch] = []
          (try OriginalParameterQueryStorage.reserve(
            breaks.count - 1, in: &result, using: &execution))
          for spanIndex in 0..<(breaks.count - 1) {
            try execution.consumeWork(1)

            let lower = breaks[spanIndex]
            let upper = breaks[spanIndex + 1]
            let span = Scalar.exact(upper) - Scalar.exact(lower)
            guard span.lower > 0.0 else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: span.lower,
                tolerance: tolerance,
                message: "Certified B-spline curve extraction found a non-positive active span."
              )
            }
            // Only the degree + 1 controls of the span are supported on it: the span is read from
            // them and their knots alone, whose basis functions equal the curve's there.
            let local = try localCurve(
              curve,
              lower: lower,
              spanCursor: &spanCursor,
              operationCount: &operationCount,
              tolerance: tolerance, using: &execution
            )
            var derivatives: [Point] = []
            (try OriginalParameterQueryStorage.reserve(
              curve.degree + 1, in: &derivatives, using: &execution))
            for derivativeOrder in 0...curve.degree {
              try execution.consumeWork(1)

              let basis = try basisDerivativeValues(
                parameter: lower,
                degree: local.degree,
                derivativeOrder: derivativeOrder,
                knots: local.knots,
                count: local.controlPointCount,
                operationCount: &operationCount,
                tolerance: tolerance, using: &execution
              )
              (try OriginalParameterQueryStorage.append(
                homogeneousDerivative(
                  curve: local,
                  basis: basis,
                  operationCount: &operationCount,
                  tolerance: tolerance, using: &execution
                ), to: &derivatives, using: &execution))
            }
            let controls = try bernsteinControls(
              derivatives: derivatives,
              degree: curve.degree,
              span: span,
              operationCount: &operationCount,
              tolerance: tolerance, using: &execution
            )
            guard
              try OriginalParameterQueryStorage.allSatisfy(
                controls, using: &execution,
                predicate: { element, execution in element.isFiniteAndPositiveWeight })
            else {
              throw KernelError(
                phase: .topology,
                code: .singularSystem,
                tolerance: tolerance,
                message:
                  "Certified B-spline curve extraction could not prove positive finite homogeneous weights."
              )
            }
            (try OriginalParameterQueryStorage.append(
              Patch(
                controls: controls,
                lower: lower,
                upper: upper
              ), to: &result, using: &execution))
          }
          return result
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  /// The span starting at `lower` as its own curve: its degree + 1 controls (from the span's last
  /// knot index `k`, the largest with `knots[k] <= lower`, back by the degree) with their 2p + 2
  /// knots.
  private func localCurve(
    _ curve: BSplineCurve2D,
    lower: Double,
    spanCursor: inout Int,
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve2D {
    try execution.consumeWork(1)

    let degree = curve.degree
    var span = spanCursor
    while span + 1 < curve.controlPointCount {
      try execution.consumeWork(1)

      // Charge the ordered cursor probe before reading the next original knot. A failed
      // probe is charged too, so the bounded operation contract covers the comparison.
      try consume(
        1,
        operationCount: &operationCount,
        tolerance: tolerance, using: &execution
      )
      guard curve.knots[span + 1] <= lower else { break }
      span += 1
    }
    spanCursor = span
    // Charge the exact local materialization before any Array slice is allocated: 2p + 2
    // knots, p + 1 control points, and p + 1 weights.
    try consume(
      4 * degree + 4,
      operationCount: &operationCount,
      tolerance: tolerance, using: &execution
    )
    return BSplineCurve2D(
      degree: degree,
      knots: (try OriginalParameterQueryStorage.materialize(
        curve.knots[(span - degree)...(span + degree + 1)], using: &execution)),
      controlPoints: (try OriginalParameterQueryStorage.materialize(
        curve.controlPoints[(span - degree)...span], using: &execution)),
      weights: (try OriginalParameterQueryStorage.materialize(
        curve.weights[(span - degree)...span], using: &execution)))
  }

  private func basisDerivativeValues(
    parameter: Double,
    degree: Int,
    derivativeOrder: Int,
    knots: [Double],
    count: Int,
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Scalar] {
    try execution.consumeWork(1)

    if derivativeOrder == 0 {
      return try basisValues(
        parameter: parameter,
        degree: degree,
        knots: knots,
        count: count,
        operationCount: &operationCount,
        tolerance: tolerance, using: &execution
      )
    }
    guard derivativeOrder <= degree else {
      return
        (try OriginalParameterQueryStorage.repeated(.exact(0.0), count: count, using: &execution))
    }
    let lowerDegree = try basisDerivativeValues(
      parameter: parameter,
      degree: degree - 1,
      derivativeOrder: derivativeOrder - 1,
      knots: knots,
      count: count + 1,
      operationCount: &operationCount,
      tolerance: tolerance, using: &execution
    )
    let factor = Scalar.exact(Double(degree))
    var result =
      (try OriginalParameterQueryStorage.repeated(
        Scalar.exact(0.0), count: count, using: &execution))
    for index in 0..<count {
      try execution.consumeWork(1)

      try consume(
        4,
        operationCount: &operationCount,
        tolerance: tolerance, using: &execution
      )
      let leftDenominator = knots[index + degree] - knots[index]
      let rightDenominator = knots[index + degree + 1] - knots[index + 1]
      let left =
        leftDenominator > 0.0
        ? factor * lowerDegree[index] / Scalar.exact(leftDenominator)
        : Scalar.exact(0.0)
      let right =
        rightDenominator > 0.0
        ? factor * lowerDegree[index + 1] / Scalar.exact(rightDenominator)
        : Scalar.exact(0.0)
      result[index] = left - right
    }
    return result
  }

  private func basisValues(
    parameter: Double,
    degree: Int,
    knots: [Double],
    count: Int,
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Scalar] {
    try execution.consumeWork(1)

    guard degree > 0 else {
      return
        (try OriginalParameterQueryStorage.map(
          (0..<count), using: &execution,
          transform: { index, execution in
            parameter >= knots[index] && parameter < knots[index + 1]
              ? Scalar.exact(1.0)
              : Scalar.exact(0.0)
          }))
    }
    let lowerDegree = try basisValues(
      parameter: parameter,
      degree: degree - 1,
      knots: knots,
      count: count + 1,
      operationCount: &operationCount,
      tolerance: tolerance, using: &execution
    )
    var result =
      (try OriginalParameterQueryStorage.repeated(
        Scalar.exact(0.0), count: count, using: &execution))
    for index in 0..<count {
      try execution.consumeWork(1)

      try consume(
        6,
        operationCount: &operationCount,
        tolerance: tolerance, using: &execution
      )
      let leftDenominator = knots[index + degree] - knots[index]
      let rightDenominator = knots[index + degree + 1] - knots[index + 1]
      let left = try
        leftDenominator > 0.0 && !isExactlyZero(lowerDegree[index], using: &execution)
        ? (Scalar.exact(parameter) - Scalar.exact(knots[index]))
          * lowerDegree[index]
          / Scalar.exact(leftDenominator)
        : Scalar.exact(0.0)
      let right = try
        rightDenominator > 0.0 && !isExactlyZero(lowerDegree[index + 1], using: &execution)
        ? (Scalar.exact(knots[index + degree + 1]) - Scalar.exact(parameter))
          * lowerDegree[index + 1]
          / Scalar.exact(rightDenominator)
        : Scalar.exact(0.0)
      result[index] = left + right
    }
    return result
  }

  /// The span starting at `lower` as its own curve: its degree + 1 controls (from the span's last
  /// knot index `k`, the largest with `knots[k] <= lower`, back by the degree) with their 2p + 2
  /// knots.

  private func homogeneousDerivative(
    curve: BSplineCurve2D,
    basis: [Scalar],
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Point {
    try execution.consumeWork(1)

    var result = zeroPoint
    for index in 0..<curve.controlPointCount
    where !(try isExactlyZero(basis[index], using: &execution)) {
      try execution.consumeWork(1)

      try consume(
        10,
        operationCount: &operationCount,
        tolerance: tolerance, using: &execution
      )
      let weight = Scalar.exact(curve.weights[index])
      let coefficient = basis[index] * weight
      result =
        (try adding(
          result,
          Point(
            x: Scalar.exact(curve.controlPoints[index].x) * coefficient,
            y: Scalar.exact(curve.controlPoints[index].y) * coefficient,
            weight: coefficient
          ), using: &execution
        ))
    }
    return result
  }

  private func bernsteinControls(
    derivatives: [Point],
    degree: Int,
    span: Scalar,
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Point] {
    try execution.consumeWork(1)

    var result: [Point] = []
    (try OriginalParameterQueryStorage.reserve(degree + 1, in: &result, using: &execution))
    for controlIndex in 0...degree {
      try execution.consumeWork(1)

      var control = zeroPoint
      var scale = Scalar.exact(1.0)
      for derivativeOrder in 0...controlIndex {
        try execution.consumeWork(1)

        try consume(
          12,
          operationCount: &operationCount,
          tolerance: tolerance, using: &execution
        )
        control =
          (try adding(
            control,
            scaled(derivatives[derivativeOrder], by: scale, using: &execution), using: &execution
          ))
        guard derivativeOrder < controlIndex else { continue }
        scale =
          scale
          * Scalar.exact(Double(controlIndex - derivativeOrder))
          * span
          / Scalar.exact(Double(derivativeOrder + 1))
          / Scalar.exact(Double(degree - derivativeOrder))
      }
      (try OriginalParameterQueryStorage.append(control, to: &result, using: &execution))
    }
    return result
  }

  private func consume(
    _ amount: Int,
    operationCount: inout Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)

    guard amount >= 0,
      operationCount <= maximumControlOperations - amount
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: Double(operationCount),
        tolerance: tolerance,
        message: "Certified B-spline curve extraction exhausted its control-operation budget."
      )
    }
    operationCount += amount
  }

  private func parameterBreaks(
    knots: [Double],
    lower: Double,
    upper: Double, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)

    var result =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in [lower]
      })
    for knot in knots where knot > lower && knot < upper && result.last != knot {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(knot, to: &result, using: &execution))
    }
    (try OriginalParameterQueryStorage.append(upper, to: &result, using: &execution))
    return result
  }

  private func adding(_ lhs: Point, _ rhs: Point, using execution: inout OriginalQueryExecution)
    throws -> Point
  {
    try execution.consumeWork(1)
    return

      Point(
        x: lhs.x + rhs.x,
        y: lhs.y + rhs.y,
        weight: lhs.weight + rhs.weight
      )
  }

  private func scaled(
    _ point: Point, by scalar: Scalar, using execution: inout OriginalQueryExecution
  ) throws -> Point {
    try execution.consumeWork(1)
    return

      Point(
        x: point.x * scalar,
        y: point.y * scalar,
        weight: point.weight * scalar
      )
  }

  private func isExactlyZero(_ value: Scalar, using execution: inout OriginalQueryExecution) throws
    -> Bool
  {
    try execution.consumeWork(1)
    return

      value.lower == 0.0 && value.upper == 0.0
  }

  private var zeroPoint: Point {
    Point(
      x: .exact(0.0),
      y: .exact(0.0),
      weight: .exact(0.0)
    )
  }
}
