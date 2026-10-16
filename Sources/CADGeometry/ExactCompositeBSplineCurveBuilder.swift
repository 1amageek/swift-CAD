import CADCore

package struct ExactCompositeBSplineCurveBuilder: Sendable {
  package var maximumPatchCount: Int
  package var maximumDegree: Int

  package init(
    maximumPatchCount: Int = 65_536,
    maximumDegree: Int = 64
  ) {
    self.maximumPatchCount = maximumPatchCount
    self.maximumDegree = maximumDegree
  }

  package func build(
    spans: [BSplineCurve3D],
    tolerance: ModelingTolerance
  ) throws -> BSplineCurve3D {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try build(spans: spans, tolerance: tolerance, using: &execution)
  }

  package func build(
    spans: [BSplineCurve3D],
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve3D {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard spans.isEmpty == false else {
      throw diagnostic(
        code: .invalidInput,
        tolerance: tolerance,
        message: "Exact composite curve construction requires at least one span."
      )
    }
    guard maximumPatchCount > 0, maximumDegree > 0 else {
      throw diagnostic(
        code: .invalidInput,
        tolerance: tolerance,
        message: "Exact composite curve construction requires positive resource limits."
      )
    }

    var patches: [RationalBezierCurvePatch3D] = []
    for span in spans {
      try execution.consumeWork(1)

      let decomposed = try BSplineCurveBezierDecomposer().curvePatches(
        curve: span,
        tolerance: tolerance, using: &execution
      )
      guard decomposed.isEmpty == false else {
        throw diagnostic(
          code: .invalidInput,
          tolerance: tolerance,
          message: "Exact composite curve construction encountered an empty source span."
        )
      }
      try execution.retainStorage(
        count: decomposed.count, stride: MemoryLayout<RationalBezierCurvePatch3D>.stride)
      patches.append(contentsOf: decomposed)
      guard patches.count <= maximumPatchCount else {
        throw diagnostic(
          code: .resourceLimitExceeded,
          residual: Double(patches.count),
          tolerance: tolerance,
          message: "Exact composite curve construction exceeded its patch budget."
        )
      }
    }

    let degree = try patches.reduce(0) { degree, patch in
      try execution.consumeWork(1)
      return max(degree, patch.controlPoints.count - 1)
    }
    guard degree > 0, degree <= maximumDegree else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        residual: Double(degree),
        tolerance: tolerance,
        message: "Exact composite curve construction exceeded its degree budget."
      )
    }

    try execution.retainStorage(
      count: patches.count, stride: MemoryLayout<[HomogeneousControl]>.stride)
    let controls = try patches.map { patch in
      try execution.retainStorage(
        count: patch.controlPoints.count, stride: MemoryLayout<HomogeneousControl>.stride)
      return try elevated(
        try patch.controlPoints.indices.map { index in
          try execution.consumeWork(1)
          return HomogeneousControl(
            point: patch.controlPoints[index],
            weight: patch.weights[index]
          )
        },
        to: degree,
        tolerance: tolerance, using: &execution)
    }
    try execution.retainStorage(count: patches.count, stride: MemoryLayout<Double>.stride)
    let breaks = try normalizedBreaks(
      weights: try patches.map { try patchWeight($0, using: &execution) },
      count: patches.count, using: &execution)
    return try assembledCurve(
      spanControls: controls,
      breaks: breaks,
      degree: degree,
      tolerance: tolerance, using: &execution)
  }

  private struct HomogeneousControl: Sendable {
    let x: Double
    let y: Double
    let z: Double
    let weight: Double

    init(point: Point3D, weight: Double) {
      x = point.x * weight
      y = point.y * weight
      z = point.z * weight
      self.weight = weight
    }

    init(x: Double, y: Double, z: Double, weight: Double) {
      self.x = x
      self.y = y
      self.z = z
      self.weight = weight
    }

    static func + (
      lhs: HomogeneousControl,
      rhs: HomogeneousControl
    ) -> HomogeneousControl {
      HomogeneousControl(
        x: lhs.x + rhs.x,
        y: lhs.y + rhs.y,
        z: lhs.z + rhs.z,
        weight: lhs.weight + rhs.weight
      )
    }

    static func * (
      lhs: HomogeneousControl,
      rhs: Double
    ) -> HomogeneousControl {
      HomogeneousControl(
        x: lhs.x * rhs,
        y: lhs.y * rhs,
        z: lhs.z * rhs,
        weight: lhs.weight * rhs
      )
    }

    var point: Point3D {
      Point3D(x: x / weight, y: y / weight, z: z / weight)
    }

    var isFinite: Bool {
      x.isFinite && y.isFinite && z.isFinite && weight.isFinite
    }
  }

  private func elevated(
    _ source: [HomogeneousControl],
    to targetDegree: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [HomogeneousControl] {
    try execution.consumeWork(1)
    var result = source
    while result.count - 1 < targetDegree {
      try execution.consumeWork(1)

      let degree = result.count - 1
      try execution.retainStorage(
        count: result.count + 1, stride: MemoryLayout<HomogeneousControl>.stride)
      var next = Array(repeating: result[0], count: result.count + 1)
      next[0] = result[0]
      next[next.count - 1] = result[result.count - 1]
      if degree > 0 {
        for index in 1...degree {
          try execution.consumeWork(1)

          let alpha = Double(index) / Double(degree + 1)
          next[index] =
            result[index - 1] * alpha
            + result[index] * (1.0 - alpha)
        }
      }
      result = next
    }
    guard result.count == targetDegree + 1,
      try result.allSatisfy({
        try execution.consumeWork(1)
        return $0.isFinite && $0.weight > 0.0
      })
    else {
      throw diagnostic(
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Exact composite curve degree elevation exceeded the finite positive-weight range."
      )
    }
    return result
  }

  private func patchWeight(
    _ patch: RationalBezierCurvePatch3D, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    try execution.consumeWork(patch.controlPoints.count)
    let controlLength = zip(
      patch.controlPoints,
      patch.controlPoints.dropFirst()
    ).reduce(0.0) { partial, pair in
      partial + (pair.1 - pair.0).length
    }
    let chord =
      patch.controlPoints.last.map {
        ($0 - patch.controlPoints[0]).length
      } ?? 0.0
    return max(controlLength, chord, Double.ulpOfOne)
  }

  private func normalizedBreaks(
    weights: [Double], count: Int, using execution: inout OriginalQueryExecution
  ) throws -> [Double] {
    try execution.consumeWork(1)
    let total = try weights.reduce(0.0) { total, weight in
      try execution.consumeWork(1)
      return total + weight
    }
    guard total.isFinite, total > 0.0 else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Composite curve parameter weights have no finite positive total.")
    }
    try execution.retainStorage(count: count + 1, stride: MemoryLayout<Double>.stride)
    var result = [0.0]
    result.reserveCapacity(count + 1)
    var accumulated = 0.0
    for index in 0..<count {
      try execution.consumeWork(1)

      accumulated += weights[index]
      result.append(index == count - 1 ? 1.0 : accumulated / total)
    }
    return result
  }

  private func assembledCurve(
    spanControls: [[HomogeneousControl]],
    breaks: [Double],
    degree: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> BSplineCurve3D {
    try execution.consumeWork(1)
    guard var controls = spanControls.first,
      breaks.count == spanControls.count + 1
    else {
      throw diagnostic(
        code: .invalidInput,
        tolerance: tolerance,
        message: "Exact composite curve assembly requires one interval per span."
      )
    }
    for span in spanControls.dropFirst() {
      try execution.consumeWork(1)

      let previousEndpoint = controls[controls.count - 1]
      let nextEndpoint = span[0]
      let residual = (previousEndpoint.point - nextEndpoint.point).length
      guard residual <= tolerance.distance else {
        throw diagnostic(
          code: .invalidInput,
          residual: residual,
          tolerance: tolerance,
          message: "Exact composite curve spans must meet at a common endpoint."
        )
      }
      let scale = previousEndpoint.weight / nextEndpoint.weight
      guard scale.isFinite, scale > 0.0 else {
        throw diagnostic(
          code: .resourceLimitExceeded,
          residual: scale,
          tolerance: tolerance,
          message: "Exact composite curve spans could not be homogeneously aligned."
        )
      }
      try execution.retainStorage(
        count: controls.count + span.count - 1, stride: MemoryLayout<HomogeneousControl>.stride)
      for control in span.dropFirst() {
        try execution.consumeWork(1)
        controls.append(control * scale)
      }
    }

    try execution.retainStorage(
      count: try exactScalarCount(
        try exactScalarCount(spanControls.count, degree, multiply: true), degree + 1),
      stride: MemoryLayout<Double>.stride)
    var knots = Array(repeating: 0.0, count: degree + 1)
    for value in breaks.dropFirst().dropLast() {
      try execution.consumeWork(1)

      knots.append(contentsOf: repeatElement(value, count: degree))
    }
    knots.append(contentsOf: repeatElement(1.0, count: degree + 1))
    try execution.retainStorage(
      count: controls.count, stride: MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride)
    let curve = BSplineCurve3D(
      degree: degree,
      knots: knots,
      controlPoints: try controls.map({
        try execution.consumeWork(1)
        return $0.point
      }),
      weights: try controls.map({
        try execution.consumeWork(1)
        return $0.weight
      })
    )
    try curve.validate(tolerance: tolerance, using: &execution)
    return curve
  }

  private func diagnostic(
    code: KernelErrorCode,
    residual: Double? = nil,
    tolerance: ModelingTolerance,
    message: String
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: code,
      residual: residual,
      tolerance: tolerance,
      message: message
    )
  }
}
