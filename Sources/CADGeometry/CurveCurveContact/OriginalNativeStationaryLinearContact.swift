import CADCore

/// Proves injectivity through stationary speed on exact original straight native spans.
struct OriginalNativeStationaryLinearContact {
  enum Result {
    case notApplicable
    case excluded
    case unique(first: ScalarInterval, second: ScalarInterval, axes: (Int, Int))
  }

  private struct Support {
    let origin: Point3D
    let end: Point3D
    let direction: [[Double]]
    let axis: Int
    let homogeneous: [[[Double]]]
  }

  func certificate(
    firstSource: BSplineCurve3D,
    first: RationalBezierCurveJetEncloser.NativeSpan,
    secondSource: BSplineCurve3D,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result {
    let arithmetic = OriginalCurveCurveWitness()
    func multiply(_ a: [Double], _ b: [Double]) throws -> [Double]? {
      try arithmetic.multiply(
        a,
        b,
        tolerance: tolerance,
        using: &execution)
    }
    func sum(_ a: [Double], _ b: [Double]) throws -> [Double] {

      return try FloatingPointExpansion.sum(a, b, using: &execution)
    }
    func subtract(_ a: [Double], _ b: [Double]) throws -> [Double] {

      return try FloatingPointExpansion.subtract(a, b, using: &execution)
    }
    func coordinate(_ point: Point3D, _ axis: Int) -> Double {
      axis == 0 ? point.x : axis == 1 ? point.y : point.z
    }
    func binomial(_ n: Int, _ k: Int) -> Int {
      guard k > 0, k < n else { return 1 }
      var result = 1
      for i in 1...min(k, n - k) { result = result * (n - i + 1) / i }
      return result
    }
    func split(_ values: [[Double]], q: Double) throws -> (left: [[Double]], right: [[Double]])? {
      try execution.retainStorage(count: values.count, stride: MemoryLayout<[Double]>.stride)
      try execution.retainStorage(count: values.count * 2, stride: MemoryLayout<[Double]>.stride)
      var level = values
      var left = [level[0]]
      var right = [level[level.count - 1]]
      try execution.consumeWork(values.count * 3)
      var count = level.count
      while count > 1 {
        for i in 0..<(count - 1) {
          guard
            let a = try multiply(
              level[i], try FloatingPointExpansion.difference(1, q, using: &execution)),
            let b = try multiply(level[i + 1], [q])
          else { return nil }
          level[i] = try sum(a, b)
        }
        count -= 1
        left.append(level[0])
        right.append(level[count - 1])
      }
      right.reverse()
      return (left, right)
    }
    func support(_ source: BSplineCurve3D, _ span: RationalBezierCurveJetEncloser.NativeSpan) throws
      -> Support?
    {
      let p = source.degree
      let index = span.index
      // Native coefficient ownership is exact only for the original isolated span.
      guard p >= 1, p <= 3,
        source.knots[(index - p + 1)...index].allSatisfy({ $0 == span.lower }),
        source.knots[(index + 1)...(index + p)].allSatisfy({ $0 == span.upper })
      else { return nil }
      let origin = source.controlPoints[index - p]
      let end = source.controlPoints[index]
      let direction = try (0..<3).map {
        try FloatingPointExpansion.difference(
          coordinate(end, $0), coordinate(origin, $0), using: &execution)
      }
      guard
        let axis = try (0..<3).max(by: {
          abs(try FloatingPointExpansion.estimate(direction[$0], using: &execution))
            < abs(try FloatingPointExpansion.estimate(direction[$1], using: &execution))
        }),
        try FloatingPointExpansion.sign(direction[axis], using: &execution) != .zero
      else { return nil }
      try execution.retainStorage(count: p + 1, stride: MemoryLayout<[[Double]]>.stride)
      var homogeneous: [[[Double]]] = []
      try execution.consumeWork((p + 1) * 4)
      for i in (index - p)...index {
        let point = source.controlPoints[i]
        let weight = source.weights[i]
        let displacement = try (0..<3).map {
          try FloatingPointExpansion.difference(
            coordinate(point, $0), coordinate(origin, $0), using: &execution)
        }
        for other in 0..<3 where other != axis {
          guard let a = try multiply(displacement[other], direction[axis]),
            let b = try multiply(displacement[axis], direction[other]),
            try FloatingPointExpansion.sign(try subtract(a, b), using: &execution) == .zero
          else { return nil }
        }
        try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
        var row: [[Double]] = []
        for coordinateIndex in 0..<3 {
          guard let value = try multiply([coordinate(point, coordinateIndex)], [weight]) else {
            return nil
          }
          row.append(value)
        }
        row.append([weight])
        homogeneous.append(row)
      }
      // The rational derivative numerator is H'W-HW'. Clearing every
      // positive Bernstein denominator preserves its exact sign.
      let degree = 2 * p - 1
      let denominators = (0...degree).map { binomial(degree, $0) }
      let scale = denominators.reduce(1, *)  // p <= 3 bounds this exact integer by 2500.
      try execution.retainStorage(count: degree + 1, stride: MemoryLayout<[Double]>.stride)
      var derivative: [[Double]] = Array(repeating: [0], count: degree + 1)
      try execution.consumeWork(degree + 1)
      for i in 0..<p {
        let dh = try subtract(homogeneous[i + 1][axis], homogeneous[i][axis])
        let dw = try subtract(homogeneous[i + 1][3], homogeneous[i][3])
        for j in 0...p {
          guard let a = try multiply(dh, homogeneous[j][3]),
            let b = try multiply(dw, homogeneous[j][axis])
          else { return nil }
          let factor = p * binomial(p - 1, i) * binomial(p, j) * (scale / denominators[i + j])
          guard let coefficient = try multiply(try subtract(a, b), [Double(factor)]) else {
            return nil
          }
          derivative[i + j] = try sum(derivative[i + j], coefficient)
        }
      }
      let increasing =
        try FloatingPointExpansion.sign(direction[axis], using: &execution) == .positive
      try execution.retainStorage(count: 1, stride: MemoryLayout<([[Double]], Int)>.stride)
      var pending: [(values: [[Double]], depth: Int)] = [(derivative, 0)]
      while let cell = pending.popLast() {
        execution.context = execution.context.at(stage: .refinement)
        try execution.visitGeometricCell(depth: cell.depth)
        let signs = try cell.values.map { try FloatingPointExpansion.sign($0, using: &execution) }
        let correct = signs.allSatisfy { $0 == .zero || $0 == (increasing ? .positive : .negative) }
        let strict = signs.contains { $0 == (increasing ? .positive : .negative) }
        if correct && strict { continue }
        if signs.allSatisfy({ $0 == .zero }) { return nil }
        if signs.allSatisfy({ $0 == .zero || $0 == (increasing ? .negative : .positive) }) {
          return nil
        }
        guard cell.depth < min(32, execution.effectiveLimits.maximumSubdivisionDepth),
          let halves = try split(cell.values, q: 0.5)
        else { return nil }
        try execution.consumeWork(2)
        try execution.retainStorage(count: 2, stride: MemoryLayout<([[Double]], Int)>.stride)
        pending.append((halves.left, cell.depth + 1))
        pending.append((halves.right, cell.depth + 1))
      }
      return Support(
        origin: origin, end: end, direction: direction, axis: axis, homogeneous: homogeneous)
    }
    guard let a = try support(firstSource, first), let b = try support(secondSource, second) else {
      return .notApplicable
    }
    var selected: (Int, Int)?
    var determinant: [Double] = []
    for axes in [(0, 1), (0, 2), (1, 2)] {
      guard let x = try multiply(a.direction[axes.0], b.direction[axes.1]),
        let y = try multiply(a.direction[axes.1], b.direction[axes.0])
      else { return .notApplicable }
      let value = try subtract(x, y)
      if try FloatingPointExpansion.sign(value, using: &execution) != .zero {
        selected = axes
        determinant = value
        break
      }
    }
    guard let axes = selected else { return .notApplicable }
    let delta = try (0..<3).map {
      try FloatingPointExpansion.difference(
        coordinate(b.origin, $0), coordinate(a.origin, $0), using: &execution)
    }
    guard let a0 = try multiply(delta[axes.0], b.direction[axes.1]),
      let a1 = try multiply(delta[axes.1], b.direction[axes.0]),
      let b0 = try multiply(delta[axes.0], a.direction[axes.1]),
      let b1 = try multiply(delta[axes.1], a.direction[axes.0])
    else { return .notApplicable }
    let na = try subtract(a0, a1)
    let nb = try subtract(b0, b1)
    let remainingAxis = 3 - axes.0 - axes.1
    guard let d = try multiply(delta[remainingAxis], determinant),
      let ad = try multiply(a.direction[remainingAxis], na),
      let bd = try multiply(b.direction[remainingAxis], nb)
    else { return .notApplicable }
    if try FloatingPointExpansion.sign(try subtract(subtract(ad, bd), d), using: &execution)
      != .zero
    {
      return .excluded
    }
    func inverse(
      _ support: Support, span: RationalBezierCurveJetEncloser.NativeSpan,
      numerator: [Double]
    ) throws -> ScalarInterval? {
      guard let origin = try multiply([coordinate(support.origin, support.axis)], determinant),
        let displacement = try multiply(support.direction[support.axis], numerator)
      else { return nil }
      let target = try sum(origin, displacement)
      try execution.retainStorage(
        count: support.homogeneous.count, stride: MemoryLayout<[Double]>.stride)
      var polynomial: [[Double]] = []
      try execution.consumeWork(support.homogeneous.count)
      for row in support.homogeneous {
        guard let h = try multiply(row[support.axis], determinant),
          let w = try multiply(row[3], target)
        else { return nil }
        polynomial.append(try subtract(h, w))
      }
      let startSign = try FloatingPointExpansion.sign(polynomial[0], using: &execution)
      let endSign = try FloatingPointExpansion.sign(
        polynomial[polynomial.count - 1], using: &execution)
      if startSign == .zero { return try ScalarInterval(lower: span.lower, upper: span.lower) }
      if endSign == .zero { return try ScalarInterval(lower: span.upper, upper: span.upper) }
      if startSign == endSign { return nil }
      var lower = 0.0
      var upper = 1.0
      for depth in 0..<min(32, execution.effectiveLimits.maximumSubdivisionDepth) {
        try execution.visitCell(axis: .value, depth: depth)
        let middle = lower + (upper - lower) * 0.5
        guard let value = try split(polynomial, q: middle)?.left.last else { return nil }
        let sign = try FloatingPointExpansion.sign(value, using: &execution)
        if sign == .zero {
          lower = middle
          upper = middle
          break
        }
        if sign == startSign { lower = middle } else { upper = middle }
      }
      let range =
        OutwardScalarInterval.exact(span.lower)
        + (.exact(span.upper) - .exact(span.lower))
        * OutwardScalarInterval(lower: lower, upper: upper)
      return try ScalarInterval(
        lower: max(span.lower, range.lower), upper: min(span.upper, range.upper))
    }
    guard let firstParameters = try inverse(a, span: first, numerator: na),
      let secondParameters = try inverse(b, span: second, numerator: nb)
    else { return .notApplicable }
    return .unique(first: firstParameters, second: secondParameters, axes: axes)
  }
}
