import CADCore

struct RationalBezierCurveJetEncloser: Sendable {
  func enclosure(of patch: RationalBezierCurvePatch3D, tolerance: ModelingTolerance) throws
    -> SurfaceIntervalVectorJet
  {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try enclosure(of: patch, tolerance: tolerance, using: &execution)
  }

  func enclosure(
    of patch: RationalBezierCurvePatch3D, over parameters: ScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    return try enclosure(of: patch, over: parameters, tolerance: tolerance, using: &execution)
  }

  func enclosure<A: ExactScalarAdmission & ~Copyable>(
    of patch: RationalBezierCurvePatch3D,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceIntervalVectorJet {
    try enclosure(
      of: patch,
      over: try ScalarInterval(lower: patch.lower, upper: patch.upper),
      tolerance: tolerance, using: &execution)
  }

  func enclosure<A: ExactScalarAdmission & ~Copyable>(
    of patch: RationalBezierCurvePatch3D,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceIntervalVectorJet {
    guard patch.controlPoints.isEmpty == false,
      patch.controlPoints.count == patch.weights.count,
      patch.upper > patch.lower,
      parameters.lower >= patch.lower,
      parameters.upper <= patch.upper,
      parameters.upper >= parameters.lower
    else {
      throw invalidPatchError(tolerance: tolerance)
    }
    let sourceControls = try homogeneousControls(
      patch,
      tolerance: tolerance, using: &execution)
    let controls =
      parameters.width == 0
      ? sourceControls
      : try trimmedHomogeneousControls(
        patch,
        sourceControls: sourceControls,
        lower: parameters.lower,
        upper: parameters.upper,
        tolerance: tolerance, using: &execution)
    let normalizedLower = try normalizedParameter(
      parameters.lower,
      lower: patch.lower,
      upper: patch.upper,
      tolerance: tolerance, using: &execution)
    let normalizedUpper = try normalizedParameter(
      parameters.upper,
      lower: patch.lower,
      upper: patch.upper,
      tolerance: tolerance, using: &execution)
    // The validated real endpoint ratios lie in [0,1]. Intersect numerical
    // overhang with that independently established geometric containment.
    let normalizedParameters = OutwardScalarInterval(
      lower: max(0.0, normalizedLower.lower),
      upper: min(1.0, normalizedUpper.upper)
    )
    let sourceSpan =
      OutwardScalarInterval(patch.upper)
      - OutwardScalarInterval(patch.lower)
    let sourceProjectionCount = sourceControls.count.multipliedReportingOverflow(by: 8)
    guard !sourceProjectionCount.overflow else { throw finiteFailure(tolerance) }
    try OriginalCoefficientAllocation.reserve(
      count: sourceProjectionCount.partialValue, of: OutwardScalarInterval.self, using: &execution)
    let weight = try jet(
      coefficients: sourceControls.map({ $0.weight }),
      value: parameters.width == 0
        ? try evaluated(
          sourceControls.map({ $0.weight }), at: normalizedParameters, tolerance: tolerance,
          using: &execution) : .enclosing(controls.map({ $0.weight })),
      parameters: normalizedParameters,
      sourceSpan: sourceSpan,
      tolerance: tolerance, using: &execution)
    guard let reciprocalWeight = weight.reciprocal() else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        residual: weight.value.lower,
        tolerance: tolerance,
        message: "A rational curve enclosure requires a certified positive weight range."
      )
    }
    let controlProjectionCount = controls.count.multipliedReportingOverflow(by: 4)
    guard !controlProjectionCount.overflow else { throw finiteFailure(tolerance) }
    try OriginalCoefficientAllocation.reserve(
      count: controlProjectionCount.partialValue, of: OutwardScalarInterval.self, using: &execution)
    return SurfaceIntervalVectorJet(
      x: try jet(
        coefficients: sourceControls.map({ $0.x }),
        value: parameters.width == 0
          ? try evaluated(
            sourceControls.map({ $0.x }), at: normalizedParameters, tolerance: tolerance,
            using: &execution) : .enclosing(controls.map({ $0.x })),
        parameters: normalizedParameters,
        sourceSpan: sourceSpan,
        tolerance: tolerance, using: &execution) * reciprocalWeight,
      y: try jet(
        coefficients: sourceControls.map({ $0.y }),
        value: parameters.width == 0
          ? try evaluated(
            sourceControls.map({ $0.y }), at: normalizedParameters, tolerance: tolerance,
            using: &execution) : .enclosing(controls.map({ $0.y })),
        parameters: normalizedParameters,
        sourceSpan: sourceSpan,
        tolerance: tolerance, using: &execution) * reciprocalWeight,
      z: try jet(
        coefficients: sourceControls.map({ $0.z }),
        value: parameters.width == 0
          ? try evaluated(
            sourceControls.map({ $0.z }), at: normalizedParameters, tolerance: tolerance,
            using: &execution) : .enclosing(controls.map({ $0.z })),
        parameters: normalizedParameters,
        sourceSpan: sourceSpan,
        tolerance: tolerance, using: &execution) * reciprocalWeight
    )
  }

  struct NativeSpan: Sendable {
    let index: Int
    let lower: Double
    let upper: Double
    let coefficients: [[OutwardScalarInterval]]
    let weightRange: OutwardScalarInterval
    let commonWeight: Double?
  }

  /// Original coefficient authority; no rounded Cartesian extraction is retained.
  func originalNativeSpans<A: ExactScalarAdmission & ~Copyable>(
    of curve: BSplineCurve3D, tolerance: ModelingTolerance,
    owningSpanIndex: Int? = nil,
    using execution: inout A
  ) throws -> [NativeSpan] {
    try CurrentTaskCancellationChecker().checkCancellation()
    try curve.validate(tolerance: tolerance, using: &execution)
    let n = curve.degree.addingReportingOverflow(1)
    let square = n.partialValue.multipliedReportingOverflow(by: n.partialValue)
    let payload = square.partialValue.multipliedReportingOverflow(by: 4)
    let total = payload.partialValue.multipliedReportingOverflow(by: curve.controlPointCount)
    guard !n.overflow, !square.overflow, !payload.overflow, !total.overflow else {
      throw finiteFailure(tolerance)
    }
    var spanCount = 0
    for index in curve.degree..<curve.controlPointCount {
      try execution.consumeWork(1)
      if curve.knots[index] < curve.knots[index + 1],
        owningSpanIndex == nil || owningSpanIndex == index
      {
        spanCount += 1
      }
    }
    try OriginalCoefficientAllocation.reserve(
      count: spanCount, of: NativeSpan.self, using: &execution)
    var spans: [NativeSpan] = []
    spans.reserveCapacity(spanCount)
    for span in curve.degree..<curve.controlPointCount {
      try execution.consumeWork(1)
      guard curve.knots[span] < curve.knots[span + 1] else { continue }
      if let owningSpanIndex, span != owningSpanIndex { continue }
      try CurrentTaskCancellationChecker().checkCancellation()
      try execution.consumeWork(1)
      let lower = curve.knots[span]
      let upper = curve.knots[span + 1]
      let indices = (span - curve.degree)...span
      let firstWeight = curve.weights[indices.lowerBound]
      var weightLower = firstWeight
      var weightUpper = firstWeight
      for index in indices {
        try execution.consumeWork(1)
        weightLower = min(weightLower, curve.weights[index])
        weightUpper = max(weightUpper, curve.weights[index])
      }
      let commonWeight = weightLower == weightUpper
      let weightRange = OutwardScalarInterval(lower: weightLower, upper: weightUpper)
      for _ in 0..<4 { for _ in 0..<n.partialValue { try execution.consumeWork(1) } }
      try OriginalCoefficientAllocation.reserve(
        count: 4, of: [OutwardScalarInterval].self, using: &execution)
      for _ in 0..<4 {
        try OriginalCoefficientAllocation.reserve(
          count: n.partialValue, of: OutwardScalarInterval.self, using: &execution)
      }
      var nets = Array(
        repeating: Array(repeating: OutwardScalarInterval.exact(0), count: n.partialValue), count: 4
      )
      var isolated = true
      for index in (span - curve.degree + 1)...span {
        try execution.consumeWork(1)
        if curve.knots[index] != lower { isolated = false }
      }
      for index in (span + 1)...(span + curve.degree) {
        try execution.consumeWork(1)
        if curve.knots[index] != upper { isolated = false }
      }
      if isolated {
        for (offset, index) in indices.enumerated() {
          try execution.consumeWork(1)
          let p = curve.controlPoints[index]
          let w = OutwardScalarInterval.exact(curve.weights[index])
          nets[0][offset] = .exact(p.x) * w
          nets[1][offset] = .exact(p.y) * w
          nets[2][offset] = .exact(p.z) * w
          nets[3][offset] = w
        }
      } else {
        let basis = try BSplineBasis.nonzeroIntervalDerivativeValues(
          parameter: lower, degree: curve.degree,
          throughDerivativeOrder: curve.degree, knots: curve.knots, count: curve.controlPointCount,
          owningSpan: span, tolerance: tolerance, using: &execution)
        for _ in 0..<4 { for _ in 0..<n.partialValue { try execution.consumeWork(1) } }
        try OriginalCoefficientAllocation.reserve(
          count: 4, of: [OutwardScalarInterval].self, using: &execution)
        for _ in 0..<4 {
          try OriginalCoefficientAllocation.reserve(
            count: n.partialValue, of: OutwardScalarInterval.self, using: &execution)
        }
        var derivatives = nets
        for order in 0...curve.degree {
          try CurrentTaskCancellationChecker().checkCancellation()
          for offset in basis[order].values.indices {
            try execution.consumeWork(1)
            let index = basis[order].startIndex + offset
            let p = curve.controlPoints[index]
            let c = basis[order].values[offset] * .exact(curve.weights[index])
            derivatives[0][order] = derivatives[0][order] + .exact(p.x) * c
            derivatives[1][order] = derivatives[1][order] + .exact(p.y) * c
            derivatives[2][order] = derivatives[2][order] + .exact(p.z) * c
            derivatives[3][order] = derivatives[3][order] + c
          }
        }
        let width = OutwardScalarInterval.exact(upper) - .exact(lower)
        for index in 0...curve.degree {
          for order in 0...index {
            var scale = OutwardScalarInterval.exact(1)
            for j in 0..<order {
              try execution.consumeWork(1)
              guard
                let next = (scale * .exact(Double(index - j)) * width)
                  .divided(by: .exact(Double(j + 1)) * .exact(Double(curve.degree - j))),
                next.isFinite
              else {
                throw finiteFailure(tolerance)
              }
              scale = next
            }
            for axis in 0..<4 {
              try execution.consumeWork(1)
              nets[axis][index] = nets[axis][index] + derivatives[axis][order] * scale
            }
          }
        }
      }
      if commonWeight {
        for _ in 0..<n.partialValue { try execution.consumeWork(1) }
        try OriginalCoefficientAllocation.reserve(
          count: n.partialValue, of: OutwardScalarInterval.self, using: &execution)
        nets[3] = Array(repeating: .exact(firstWeight), count: n.partialValue)
      }
      for net in nets {
        for coefficient in net {
          try execution.consumeWork(1)
          guard coefficient.isFinite else { throw finiteFailure(tolerance) }
        }
      }
      try execution.consumeWork(1)
      spans.append(
        NativeSpan(
          index: span, lower: lower, upper: upper,
          coefficients: nets, weightRange: weightRange,
          commonWeight: commonWeight ? firstWeight : nil))
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    return spans
  }

  func enclosure<A: ExactScalarAdmission & ~Copyable>(
    of span: NativeSpan, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceIntervalVectorJet {
    try CurrentTaskCancellationChecker().checkCancellation()
    guard parameters.lower >= span.lower, parameters.upper <= span.upper,
      parameters.lower <= parameters.upper
    else { throw invalidPatchError(tolerance: tolerance) }
    let a = try normalizedParameter(
      parameters.lower, lower: span.lower, upper: span.upper, tolerance: tolerance,
      using: &execution)
    let b = try normalizedParameter(
      parameters.upper, lower: span.lower, upper: span.upper, tolerance: tolerance,
      using: &execution)
    let q = OutwardScalarInterval(lower: max(0, a.lower), upper: min(1, b.upper))
    let width = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
    guard width.isFinite, width.lower > 0 else { throw finiteFailure(tolerance) }
    let weightValue = try evaluated(
      span.coefficients[3], at: q, tolerance: tolerance, using: &execution)
    guard let boundedWeight = weightValue.intersection(with: span.weightRange) else {
      throw KernelError(
        phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
        message: "Original curve denominator and positive source-weight hull are inconsistent.")
    }
    let weight: SurfaceIntervalJet
    if let commonWeight = span.commonWeight {
      weight = .constant(commonWeight)
    } else {
      weight = try jet(
        coefficients: span.coefficients[3], value: boundedWeight,
        parameters: q, sourceSpan: width, tolerance: tolerance, using: &execution)
    }
    guard let inverse = weight.reciprocal() else {
      throw KernelError(
        phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "Original curve denominator has no certified positive reciprocal.")
    }
    func coordinate(_ axis: Int, using execution: inout A) throws -> SurfaceIntervalJet {
      let coefficients = span.coefficients[axis]
      return try jet(
        coefficients: coefficients,
        value: try evaluated(coefficients, at: q, tolerance: tolerance, using: &execution),
        parameters: q, sourceSpan: width, tolerance: tolerance, using: &execution) * inverse
    }
    let result = try SurfaceIntervalVectorJet(
      x: try coordinate(0, using: &execution), y: try coordinate(1, using: &execution),
      z: try coordinate(2, using: &execution))
    guard
      [result.x, result.y, result.z].allSatisfy({
        [$0.value, $0.derivativeU, $0.secondDerivativeUU, $0.thirdDerivativeUUU].allSatisfy({
          $0.isFinite
        })
      })
    else { throw finiteFailure(tolerance) }
    try CurrentTaskCancellationChecker().checkCancellation()
    return result
  }

  /// Original endpoint-span continuation. Convex-hull bounds are used only
  /// inside the native span; outside it, full interval polynomial evaluation
  /// retains the original rational denominator and derivative law.
  func continuationEnclosure<A: ExactScalarAdmission & ~Copyable>(
    of span: NativeSpan, over parameters: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceIntervalVectorJet {
    try CurrentTaskCancellationChecker().checkCancellation()
    guard parameters.lower.isFinite, parameters.upper.isFinite,
      parameters.lower <= parameters.upper
    else { throw invalidPatchError(tolerance: tolerance) }
    if parameters.lower >= span.lower, parameters.upper <= span.upper {
      return try enclosure(of: span, over: parameters, tolerance: tolerance, using: &execution)
    }
    let width = OutwardScalarInterval.exact(span.upper) - .exact(span.lower)
    guard width.isFinite, width.lower > 0,
      let q =
        (OutwardScalarInterval(lower: parameters.lower, upper: parameters.upper)
        - .exact(span.lower)).divided(by: width), q.isFinite
    else { throw finiteFailure(tolerance) }
    func polynomial(_ coefficients: [OutwardScalarInterval], using execution: inout A) throws
      -> OutwardScalarInterval
    {
      guard !coefficients.isEmpty, coefficients.allSatisfy({ $0.isFinite }) else {
        throw finiteFailure(tolerance)
      }
      try OriginalCoefficientAllocation.reserve(
        count: coefficients.count, of: OutwardScalarInterval.self, using: &execution)
      var level = coefficients
      let complement = OutwardScalarInterval.exact(1) - q
      while level.count > 1 {
        try CurrentTaskCancellationChecker().checkCancellation()
        try OriginalCoefficientAllocation.reserve(
          count: level.count - 1, of: OutwardScalarInterval.self, using: &execution)
        var next: [OutwardScalarInterval] = []
        next.reserveCapacity(level.count - 1)
        for index in 0..<(level.count - 1) {
          try execution.consumeWork(1)
          let value = level[index] * complement + level[index + 1] * q
          guard value.isFinite else { throw finiteFailure(tolerance) }
          next.append(value)
        }
        level = next
      }
      return level[0]
    }
    func scalarJet(_ coefficients: [OutwardScalarInterval], using execution: inout A) throws
      -> SurfaceIntervalJet
    {
      let first = try differentiated(
        coefficients, span: width, tolerance: tolerance, using: &execution)
      let second = try differentiated(first, span: width, tolerance: tolerance, using: &execution)
      let third = try differentiated(second, span: width, tolerance: tolerance, using: &execution)
      let zero = OutwardScalarInterval.exact(0)
      return try SurfaceIntervalJet(
        value: try polynomial(coefficients, using: &execution),
        derivativeU: try polynomial(first, using: &execution), derivativeV: zero,
        secondDerivativeUU: try polynomial(second, using: &execution), secondDerivativeUV: zero,
        secondDerivativeVV: zero,
        thirdDerivativeUUU: try polynomial(third, using: &execution), thirdDerivativeUUV: zero,
        thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }
    let weight: SurfaceIntervalJet
    if let constant = span.commonWeight {
      weight = .constant(constant)
    } else {
      weight = try scalarJet(span.coefficients[3], using: &execution)
    }
    guard weight.value.lower > 0, let inverse = weight.reciprocal() else {
      throw KernelError(
        phase: .geometry, code: .singularGeometry, tolerance: tolerance,
        message:
          "Original rational endpoint continuation has no positive denominator on this complete interval."
      )
    }
    let result = try SurfaceIntervalVectorJet(
      x: try scalarJet(span.coefficients[0], using: &execution) * inverse,
      y: try scalarJet(span.coefficients[1], using: &execution) * inverse,
      z: try scalarJet(span.coefficients[2], using: &execution) * inverse)
    guard
      [result.x, result.y, result.z].allSatisfy({
        [$0.value, $0.derivativeU, $0.secondDerivativeUU, $0.thirdDerivativeUUU].allSatisfy({
          $0.isFinite
        })
      })
    else { throw finiteFailure(tolerance) }
    return result
  }

  private func finiteFailure(_ tolerance: ModelingTolerance) -> KernelError {
    KernelError(
      phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
      message: "Original native curve coefficient work exceeds finite storage or arithmetic.")
  }

  private func homogeneousControls<A: ExactScalarAdmission & ~Copyable>(
    _ patch: RationalBezierCurvePatch3D,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> [IntervalHomogeneousControl] {
    try OriginalCoefficientAllocation.reserve(
      count: patch.controlPoints.count, of: IntervalHomogeneousControl.self, using: &execution)
    return try patch.controlPoints.indices.map { index in
      try execution.consumeWork(1)
      let point = patch.controlPoints[index]
      let weight = patch.weights[index]
      guard weight.isFinite, weight > 0.0 else {
        throw invalidPatchError(tolerance: tolerance)
      }
      return IntervalHomogeneousControl(
        x: OutwardScalarInterval(point.x) * OutwardScalarInterval(weight),
        y: OutwardScalarInterval(point.y) * OutwardScalarInterval(weight),
        z: OutwardScalarInterval(point.z) * OutwardScalarInterval(weight),
        weight: OutwardScalarInterval(weight)
      )
    }
  }

  private func trimmedHomogeneousControls<A: ExactScalarAdmission & ~Copyable>(
    _ patch: RationalBezierCurvePatch3D,
    sourceControls: [IntervalHomogeneousControl],
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> [IntervalHomogeneousControl] {
    var controls = sourceControls
    var currentLower = patch.lower
    let currentUpper = patch.upper
    if lower > currentLower {
      let parameter = try normalizedParameter(
        lower,
        lower: currentLower,
        upper: currentUpper,
        tolerance: tolerance, using: &execution)
      controls = try split(controls, parameter: parameter, using: &execution).upper
      currentLower = lower
    }
    if upper < currentUpper {
      let parameter = try normalizedParameter(
        upper,
        lower: currentLower,
        upper: currentUpper,
        tolerance: tolerance, using: &execution)
      controls = try split(controls, parameter: parameter, using: &execution).lower
    }
    return controls
  }

  private func jet<A: ExactScalarAdmission & ~Copyable>(
    coefficients: [OutwardScalarInterval],
    value: OutwardScalarInterval,
    parameters: OutwardScalarInterval,
    sourceSpan: OutwardScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceIntervalJet {
    guard coefficients.isEmpty == false,
      coefficients.allSatisfy({ $0.isFinite }),
      parameters.isFinite,
      parameters.lower >= 0.0,
      parameters.upper <= 1.0,
      parameters.lower <= parameters.upper,
      sourceSpan.isFinite,
      sourceSpan.lower > 0.0
    else {
      throw invalidPatchError(tolerance: tolerance)
    }
    let first = try differentiated(
      coefficients,
      span: sourceSpan,
      tolerance: tolerance, using: &execution)
    let second = try differentiated(
      first,
      span: sourceSpan,
      tolerance: tolerance, using: &execution)
    let third = try differentiated(
      second,
      span: sourceSpan,
      tolerance: tolerance, using: &execution)
    let zero = OutwardScalarInterval(0.0)
    let result = SurfaceIntervalJet(
      value: value,
      derivativeU: try evaluated(first, at: parameters, tolerance: tolerance, using: &execution),
      derivativeV: zero,
      secondDerivativeUU: try evaluated(
        second, at: parameters, tolerance: tolerance, using: &execution),
      secondDerivativeUV: zero,
      secondDerivativeVV: zero,
      thirdDerivativeUUU: try evaluated(
        third, at: parameters, tolerance: tolerance, using: &execution),
      thirdDerivativeUUV: zero,
      thirdDerivativeUVV: zero,
      thirdDerivativeVVV: zero
    )
    guard result.value.isFinite,
      result.derivativeU.isFinite,
      result.secondDerivativeUU.isFinite
    else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Rational curve differential enclosure exceeded finite arithmetic."
      )
    }
    return result
  }

  private func evaluated<A: ExactScalarAdmission & ~Copyable>(
    _ coefficients: [OutwardScalarInterval],
    at parameter: OutwardScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> OutwardScalarInterval {
    guard !coefficients.isEmpty, coefficients.allSatisfy({ $0.isFinite }),
      parameter.isFinite, parameter.lower >= 0, parameter.upper <= 1,
      parameter.lower <= parameter.upper
    else { throw invalidPatchError(tolerance: tolerance) }
    // Patch containment proves exact normalized parameters lie in [0,1].
    // Both interval de Casteljau and the Bernstein convex hull contain the value.
    let hull = OutwardScalarInterval.enclosing(coefficients)
    try OriginalCoefficientAllocation.reserve(
      count: coefficients.count, of: OutwardScalarInterval.self, using: &execution)
    var level = coefficients
    let complement = OutwardScalarInterval(1.0) - parameter
    while level.count > 1 {
      try OriginalCoefficientAllocation.reserve(
        count: level.count - 1, of: OutwardScalarInterval.self, using: &execution)
      level = try (0..<(level.count - 1)).map { index in
        try execution.consumeWork(1)
        return level[index] * complement + level[index + 1] * parameter
      }
    }
    guard let value = level.first,
      let result = value.intersection(
        with: try restrictedHull(coefficients, over: parameter, using: &execution) ?? hull
      )
      .flatMap({ $0.intersection(with: hull) })
    else {
      throw KernelError(
        phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
        message: "Interval Bernstein evaluation and its certified coefficient hull are disjoint.")
    }
    return result
  }

  /// The hull of the Bernstein coefficients restricted to the parameter interval. A de Casteljau
  /// run at the interval parameter only shrinks with the interval's width; the restricted hull
  /// shrinks with its square, as a cell refined toward a point needs.
  private func restrictedHull<A: ExactScalarAdmission & ~Copyable>(
    _ coefficients: [OutwardScalarInterval],
    over parameter: OutwardScalarInterval, using execution: inout A
  ) throws -> OutwardScalarInterval? {
    let (lower, upper) = (parameter.lower, parameter.upper)
    guard coefficients.count > 1, lower < 1.0, upper > 0.0, lower <= upper else { return nil }
    // de Casteljau at `t`, keeping the side toward 1 (`keepsUpper`) or toward 0.
    func split(
      _ controls: [OutwardScalarInterval], at t: OutwardScalarInterval,
      keepsUpper: Bool, using execution: inout A
    ) throws -> [OutwardScalarInterval] {
      try OriginalCoefficientAllocation.reserve(
        count: controls.count, of: OutwardScalarInterval.self, using: &execution)
      try OriginalCoefficientAllocation.reserve(
        count: controls.count, of: OutwardScalarInterval.self, using: &execution)
      var level = controls
      var kept = [keepsUpper ? level[level.count - 1] : level[0]]
      let complement = OutwardScalarInterval(1.0) - t
      while level.count > 1 {
        try OriginalCoefficientAllocation.reserve(
          count: level.count - 1, of: OutwardScalarInterval.self, using: &execution)
        level = try (0..<(level.count - 1)).map { index in
          try execution.consumeWork(1)
          return level[index] * complement + level[index + 1] * t
        }
        kept.append(keepsUpper ? level[level.count - 1] : level[0])
      }
      if keepsUpper {
        try OriginalCoefficientAllocation.reserve(
          count: kept.count, of: OutwardScalarInterval.self, using: &execution)
      }
      return keepsUpper ? kept.reversed() : kept
    }
    var controls = coefficients
    if lower > 0.0 {
      controls = try split(
        controls, at: OutwardScalarInterval(lower), keepsUpper: true, using: &execution)
    }
    if upper < 1.0 {
      // On [lower, 1] the end `upper` sits at (upper - lower) / (1 - lower).
      let local = (OutwardScalarInterval(upper) - OutwardScalarInterval(lower))
        .divided(by: OutwardScalarInterval(1.0) - OutwardScalarInterval(lower))
      guard let local, local.isFinite else { return nil }
      let clamped = OutwardScalarInterval(
        lower: max(0.0, local.lower), upper: min(1.0, local.upper))
      controls = try split(controls, at: clamped, keepsUpper: false, using: &execution)
    }
    guard controls.allSatisfy({ $0.isFinite }) else { return nil }
    return OutwardScalarInterval.enclosing(controls)
  }

  private func differentiated<A: ExactScalarAdmission & ~Copyable>(
    _ coefficients: [OutwardScalarInterval],
    span: OutwardScalarInterval,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> [OutwardScalarInterval] {
    try OriginalCoefficientAllocation.reserve(
      count: max(1, coefficients.count - 1), of: OutwardScalarInterval.self, using: &execution)
    guard coefficients.count > 1 else {
      return [OutwardScalarInterval(0.0)]
    }
    guard
      let scale = OutwardScalarInterval(
        Double(coefficients.count - 1)
      ).divided(by: span)
    else {
      throw invalidPatchError(tolerance: tolerance)
    }
    return try (0..<(coefficients.count - 1)).map { index in
      try execution.consumeWork(1)
      return (coefficients[index + 1] - coefficients[index]) * scale
    }
  }

  private func normalizedParameter<A: ExactScalarAdmission & ~Copyable>(
    _ value: Double,
    lower: Double,
    upper: Double,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws -> OutwardScalarInterval {
    try execution.consumeWork(1)
    if value == lower { return .exact(0) }
    if value == upper { return .exact(1) }
    let numerator =
      OutwardScalarInterval.exact(value)
      - .exact(lower)
    let denominator =
      OutwardScalarInterval.exact(upper)
      - .exact(lower)
    guard let parameter = numerator.divided(by: denominator),
      parameter.isFinite
    else {
      throw invalidPatchError(tolerance: tolerance)
    }
    return parameter
  }

  private func split<A: ExactScalarAdmission & ~Copyable>(
    _ controls: [IntervalHomogeneousControl],
    parameter: OutwardScalarInterval, using execution: inout A
  ) throws -> (
    lower: [IntervalHomogeneousControl],
    upper: [IntervalHomogeneousControl]
  ) {
    guard controls.count > 1 else {
      return (controls, controls)
    }
    try OriginalCoefficientAllocation.reserve(
      count: controls.count, of: [IntervalHomogeneousControl].self, using: &execution)
    var levels = [controls]
    while let previous = levels.last, previous.count > 1 {
      try OriginalCoefficientAllocation.reserve(
        count: previous.count - 1, of: IntervalHomogeneousControl.self, using: &execution)
      levels.append(
        try (0..<(previous.count - 1)).map { index in
          try execution.consumeWork(1)
          return previous[index].interpolated(
            to: previous[index + 1],
            parameter: parameter
          )
        })
    }
    let endpointCount = levels.count.multipliedReportingOverflow(by: 2)
    guard !endpointCount.overflow else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve split storage overflowed.")
    }
    try OriginalCoefficientAllocation.reserve(
      count: endpointCount.partialValue, of: IntervalHomogeneousControl.self, using: &execution)
    return (
      levels.map { $0[0] },
      levels.reversed().map { $0[$0.count - 1] }
    )
  }

  private func invalidPatchError(tolerance: ModelingTolerance) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .invalidInput,
      tolerance: tolerance,
      message: "A rational Bezier curve enclosure requires a finite positive patch."
    )
  }
}

private struct IntervalHomogeneousControl: Sendable {
  let x: OutwardScalarInterval
  let y: OutwardScalarInterval
  let z: OutwardScalarInterval
  let weight: OutwardScalarInterval

  func interpolated(
    to other: IntervalHomogeneousControl,
    parameter: OutwardScalarInterval
  ) -> IntervalHomogeneousControl {
    let complement = OutwardScalarInterval(1.0) - parameter
    return IntervalHomogeneousControl(
      x: x * complement + other.x * parameter,
      y: y * complement + other.y * parameter,
      z: z * complement + other.z * parameter,
      weight: weight * complement + other.weight * parameter
    )
  }
}
