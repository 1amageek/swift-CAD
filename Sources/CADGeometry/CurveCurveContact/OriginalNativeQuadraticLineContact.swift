import CADCore

/// Repeated quadratic roots are proved from original homogeneous coefficients, not fitted roots.
struct OriginalNativeQuadraticLineContact {
  enum Result {
    case notApplicable
    case excluded
    case unique(first: ScalarInterval, second: ScalarInterval, axes: (Int, Int))
  }

  func certificate(
    firstSource: BSplineCurve3D,
    first: RationalBezierCurveJetEncloser.NativeSpan,
    secondSource: BSplineCurve3D,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result {
    if firstSource.degree == 2, secondSource.degree == 1 {
      return try certificate(
        quadratic: firstSource,
        span: first,
        line: secondSource,
        lineSpan: second,
        swaps: false,
        tolerance: tolerance,
        using: &execution)
    }
    if secondSource.degree == 2, firstSource.degree == 1 {
      return try certificate(
        quadratic: secondSource,
        span: second,
        line: firstSource,
        lineSpan: first,
        swaps: true,
        tolerance: tolerance,
        using: &execution)
    }
    return .notApplicable
  }

  private func certificate(
    quadratic: BSplineCurve3D,
    span: RationalBezierCurveJetEncloser.NativeSpan,
    line: BSplineCurve3D,
    lineSpan: RationalBezierCurveJetEncloser.NativeSpan,
    swaps: Bool,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result {
    let index = span.index
    guard quadratic.knots[(index - 1)...index].allSatisfy({ $0 == span.lower }),
      quadratic.knots[(index + 1)...(index + 2)].allSatisfy({ $0 == span.upper }),
      line.weights[lineSpan.index - 1] == line.weights[lineSpan.index]
    else { return .notApplicable }
    let origin = line.controlPoints[lineSpan.index - 1]
    let end = line.controlPoints[lineSpan.index]
    func coordinate(_ point: Point3D, _ axis: Int) -> Double {
      axis == 0 ? point.x : axis == 1 ? point.y : point.z
    }
    let directions = try (0..<3).map {
      try FloatingPointExpansion.difference(
        coordinate(end, $0), coordinate(origin, $0), using: &execution)
    }
    guard
      let varying = try (0..<3).max(by: {
        abs(try FloatingPointExpansion.estimate(directions[$0], using: &execution))
          < abs(try FloatingPointExpansion.estimate(directions[$1], using: &execution))
      }),
      try FloatingPointExpansion.sign(directions[varying], using: &execution) != .zero
    else { return .notApplicable }
    let arithmetic = OriginalCurveCurveWitness()
    func multiply(_ a: [Double], _ b: [Double]) throws -> [Double]? {
      try arithmetic.multiply(
        a,
        b,
        tolerance: tolerance,
        using: &execution)
    }
    func add(_ a: [Double], _ b: [Double]) throws -> [Double] {

      return try FloatingPointExpansion.sum(a, b, using: &execution)
    }
    func subtract(_ a: [Double], _ b: [Double]) throws -> [Double] {

      return try FloatingPointExpansion.subtract(a, b, using: &execution)
    }
    func interval(_ expansion: [Double]) throws -> OutwardScalarInterval {
      try execution.consumeWork(expansion.count)
      return expansion.reduce(OutwardScalarInterval.exact(0)) { $0 + .exact($1) }
    }
    try execution.retainStorage(
      count: quadratic.degree + 1, stride: MemoryLayout<[[Double]]>.stride)
    var homogeneous: [[[Double]]] = []
    for control in (index - 2)...index {
      let p = quadratic.controlPoints[control]
      let w = quadratic.weights[control]
      try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
      var row: [[Double]] = []
      for axis in 0..<3 {
        guard let product = try multiply([coordinate(p, axis)], [w]) else { return .notApplicable }
        row.append(product)
      }
      row.append([w])
      homogeneous.append(row)
    }
    for other in 0..<3 where other != varying {
      try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
      var bernstein: [[Double]] = []
      for row in homogeneous {
        guard let ov = try multiply([coordinate(origin, varying)], row[3]),
          let oo = try multiply([coordinate(origin, other)], row[3])
        else { return .notApplicable }
        let v = try subtract(row[varying], ov)
        let o = try subtract(row[other], oo)
        guard let a = try multiply(directions[varying], o),
          let b = try multiply(directions[other], v)
        else { return .notApplicable }
        bernstein.append(try subtract(a, b))
      }
      guard let twiceMiddle = try multiply([2], bernstein[1]) else { return .notApplicable }
      let a = try add(subtract(bernstein[0], twiceMiddle), bernstein[2])
      guard try FloatingPointExpansion.sign(a, using: &execution) != .zero else { continue }
      guard let b = try multiply([2], subtract(bernstein[1], bernstein[0])),
        let bb = try multiply(b, b), let ac = try multiply(a, bernstein[0]),
        let fourAC = try multiply([4], ac)
      else { return .notApplicable }
      let discriminant = try subtract(bb, fourAC)
      let sign = try FloatingPointExpansion.sign(discriminant, using: &execution)
      if sign == .negative { return .excluded }
      guard sign == .zero else { continue }
      guard let denominator = try multiply([2], a) else { return .notApplicable }
      let numerator = b.map { -$0 }
      let q: OutwardScalarInterval
      if try FloatingPointExpansion.sign(numerator, using: &execution) == .zero {
        q = .exact(0)
      } else if try FloatingPointExpansion.sign(
        try subtract(numerator, denominator), using: &execution) == .zero
      {
        q = .exact(1)
      } else {
        guard let ratio = try interval(numerator).divided(by: interval(denominator)), ratio.isFinite
        else { return .notApplicable }
        q = ratio
      }
      if q.upper < 0 || q.lower > 1 { return .excluded }
      guard q.lower >= 0, q.upper <= 1 else { return .notApplicable }
      let parameter =
        OutwardScalarInterval.exact(span.lower)
        + (OutwardScalarInterval.exact(span.upper) - .exact(span.lower)) * q
      let firstRange: ScalarInterval
      if q.lower == 0, q.upper == 0 {
        firstRange = try ScalarInterval(lower: span.lower, upper: span.lower)
      } else if q.lower == 1, q.upper == 1 {
        firstRange = try ScalarInterval(lower: span.upper, upper: span.upper)
      } else {
        firstRange = try ScalarInterval(
          lower: max(span.lower, parameter.lower), upper: min(span.upper, parameter.upper))
      }
      let encloser = RationalBezierCurveJetEncloser()
      try execution.consumeWork(
        (quadratic.degree + 1) * (quadratic.degree + 1) * (quadratic.degree + 1) * 4)
      let value = try encloser.enclosure(
        of: span, over: firstRange, tolerance: tolerance, using: &execution)
      let axisValue = varying == 0 ? value.x.value : varying == 1 ? value.y.value : value.z.value
      guard
        let ratio = try (axisValue - .exact(coordinate(origin, varying))).divided(
          by: interval(directions[varying]))
      else {
        return .notApplicable
      }
      let mapped =
        OutwardScalarInterval.exact(lineSpan.lower)
        + (.exact(lineSpan.upper) - .exact(lineSpan.lower)) * ratio
      if mapped.upper < lineSpan.lower || mapped.lower > lineSpan.upper { return .excluded }
      var secondLower = mapped.lower
      var secondUpper = mapped.upper
      if mapped.lower < lineSpan.lower || mapped.upper > lineSpan.upper {
        // Exact rational substitution admits a native endpoint even when
        // outward quotient arithmetic straddles its domain boundary.
        let complement = try subtract(denominator, numerator)
        guard let cc = try multiply(complement, complement),
          let nn = try multiply(numerator, numerator),
          let nc = try multiply(numerator, complement), let twiceNC = try multiply([2], nc)
        else { return .notApplicable }
        try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
        var valueAtRoot: [[Double]] = []
        for axis in 0..<4 {
          guard let h0 = try multiply(homogeneous[0][axis], cc),
            let h1 = try multiply(homogeneous[1][axis], twiceNC),
            let h2 = try multiply(homogeneous[2][axis], nn)
          else { return .notApplicable }
          valueAtRoot.append(try add(add(h0, h1), h2))
        }
        var endpoint: Double?
        for (point, parameter) in [(origin, lineSpan.lower), (end, lineSpan.upper)] {
          var equal = true
          for axis in 0..<3 {
            guard let product = try multiply([coordinate(point, axis)], valueAtRoot[3]),
              try FloatingPointExpansion.sign(
                try subtract(valueAtRoot[axis], product), using: &execution) == .zero
            else {
              equal = false
              break
            }
          }
          if equal { endpoint = parameter }
        }
        guard let endpoint else { return .notApplicable }
        secondLower = endpoint
        secondUpper = endpoint
      }
      let secondRange = try ScalarInterval(lower: secondLower, upper: secondUpper)
      return .unique(
        first: swaps ? secondRange : firstRange, second: swaps ? firstRange : secondRange,
        axes: (min(varying, other), max(varying, other)))
    }
    return .notApplicable
  }
}
