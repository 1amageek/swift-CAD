import CADCore

/// Selected-original polynomial coefficients, without a rounded replacement surface.
struct NativePolynomialSurfacePositionPreparation {
  typealias Net = PolynomialSurfacePositionDifferenceNet
  typealias Arithmetic = Net.Arithmetic
  typealias Coefficient = Net.Coefficient
  typealias Interval = OutwardScalarInterval

  struct AxisCell {
    let lower: Double
    let upper: Double
    let sourceSpan: Int
    let candidateSpan: Int
  }

  fileprivate struct AxisOperator {
    let start: Int
    let inputCount: Int
    let outputCount: Int
    let values: [Interval]
  }

  struct Section {
    fileprivate let uCount: Int
    fileprivate let inputVCount: Int
    fileprivate let intermediate: [Coefficient]
    fileprivate let vOperators: [AxisOperator]

    func net(vIndex: Int, using execution: inout OriginalQueryExecution) throws -> Net {
      let op = vOperators[vIndex]
      let count = try Arithmetic.multiply(uCount, op.outputCount)
      let terms = try Arithmetic.multiply(count, op.inputCount)
      try execution.charge(scalars: Arithmetic.multiply(count, 6))
      try OriginalCoefficientAllocation.reserve(
        count: count, of: Coefficient.self, using: &execution)
      try execution.charge(scalars: (MemoryLayout<Net>.stride + 7) / 8, work: 4)
      // Three scalar interval products per vector term allocate 12 doubles.
      try execution.charge(
        scalars: Arithmetic.multiply(terms, 12),
        work: Arithmetic.add(
          Arithmetic.multiply(terms, 3 * 12 + 3 * 4 + 12), Arithmetic.multiply(count, 8)))
      var values = Array(repeating: Self.zero, count: count)
      for v in 0..<op.outputCount {
        try CurrentTaskCancellationChecker().checkCancellation()
        for u in 0..<uCount {
          var value = Self.zero
          for i in 0..<op.inputCount {
            value = NativePolynomialSurfacePositionPreparation.add(
              value, intermediate[(op.start + i) * uCount + u] * op.values[v * op.inputCount + i])
          }
          values[v * uCount + u] = value
        }
      }
      return Net(prechargedUCount: uCount, vCount: op.outputCount, values: values)
    }

    private static var zero: Coefficient { .init(x: .exact(0), y: .exact(0), z: .exact(0)) }
  }

  private let surface: BSplineSurface3D
  private let origin: Point3D
  private let uOperators: [AxisOperator]
  private let vOperators: [AxisOperator]

  static func hasCommonWeight(
    _ surface: BSplineSurface3D,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    let count = try PreparedBSplineSurfaceDifferentialCost.Arithmetic.product(
      surface.uControlPointCount, surface.vControlPointCount)
    try execution.charge(
      work: PreparedBSplineSurfaceDifferentialCost.Arithmetic.sum(count, surface.weights.count, 4))
    let weight = surface.weights[0][0]
    for row in surface.weights {
      try CurrentTaskCancellationChecker().checkCancellation()
      for value in row where value != weight { return false }
    }
    return true
  }

  /// A cursor merge retains exact original spans, including both closed knot sides.
  static func commonCells(
    sourceKnots: [Double], sourceDegree: Int, sourceCount: Int,
    candidateKnots: [Double], candidateDegree: Int, candidateCount: Int,
    interval: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> [AxisCell] {
    var source = sourceDegree
    var candidate = candidateDegree
    var lower = interval.lower
    var cells: [AxisCell] = []
    while lower < interval.upper {
      while source < sourceCount {
        try execution.charge(work: 4)
        if sourceKnots[source + 1] > lower { break }
        source += 1
      }
      while candidate < candidateCount {
        try execution.charge(work: 4)
        if candidateKnots[candidate + 1] > lower { break }
        candidate += 1
      }
      try execution.charge(work: 12)
      guard source < sourceCount, candidate < candidateCount,
        sourceKnots[source] <= lower, candidateKnots[candidate] <= lower
      else { throw Arithmetic.exhausted() }
      let upper = min(interval.upper, sourceKnots[source + 1], candidateKnots[candidate + 1])
      guard upper > lower, upper.isFinite else { throw Arithmetic.exhausted() }
      // Four fields with fourfold cumulative backing-growth reservation.
      try execution.charge(scalars: 16, work: 4)
      try OriginalCoefficientAllocation.reserve(count: 4, of: AxisCell.self, using: &execution)
      cells.append(
        AxisCell(lower: lower, upper: upper, sourceSpan: source, candidateSpan: candidate))
      lower = upper
    }
    return cells
  }

  init(
    surface: BSplineSurface3D, origin: Point3D, uCells: [AxisCell], vCells: [AxisCell],
    candidate: Bool, uDegree: Int, vDegree: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    self.surface = surface
    self.origin = origin
    // COW source buffers are retained; concrete owner payload and axis-array owners are paid.
    try execution.charge(scalars: (MemoryLayout<Self>.stride + 7) / 8, work: 8)
    uOperators = try Self.operators(
      cells: uCells, candidate: candidate, knots: surface.uKnots,
      degree: surface.uDegree, count: surface.uControlPointCount, targetDegree: uDegree,
      tolerance: tolerance, using: &execution)
    vOperators = try Self.operators(
      cells: vCells, candidate: candidate, knots: surface.vKnots,
      degree: surface.vDegree, count: surface.vControlPointCount, targetDegree: vDegree,
      tolerance: tolerance, using: &execution)
  }

  func section(uIndex: Int, using execution: inout OriginalQueryExecution) throws -> Section {
    let op = uOperators[uIndex]
    let count = try Arithmetic.multiply(op.outputCount, surface.vControlPointCount)
    let terms = try Arithmetic.multiply(count, op.inputCount)
    try execution.charge(scalars: Arithmetic.multiply(count, 6))
    try OriginalCoefficientAllocation.reserve(count: count, of: Coefficient.self, using: &execution)
    try execution.charge(
      scalars: Arithmetic.multiply(terms, 12),
      work: Arithmetic.add(
        Arithmetic.multiply(terms, 3 * 4 + 3 * 12 + 3 * 4 + 12), Arithmetic.multiply(count, 8)))
    try execution.charge(scalars: (MemoryLayout<Section>.stride + 7) / 8, work: 4)
    var values = Array(
      repeating: Coefficient(x: .exact(0), y: .exact(0), z: .exact(0)), count: count)
    for row in 0..<surface.vControlPointCount {
      try CurrentTaskCancellationChecker().checkCancellation()
      for u in 0..<op.outputCount {
        var value = Coefficient(x: .exact(0), y: .exact(0), z: .exact(0))
        for i in 0..<op.inputCount {
          let point = surface.controlPoints[row][op.start + i]
          // BOTH inputs use the same original source origin, preserving translation correlation.
          let relative = Coefficient(
            x: .exact(point.x) - .exact(origin.x),
            y: .exact(point.y) - .exact(origin.y), z: .exact(point.z) - .exact(origin.z))
          value = Self.add(value, relative * op.values[u * op.inputCount + i])
        }
        values[row * op.outputCount + u] = value
      }
    }
    return Section(
      uCount: op.outputCount, inputVCount: surface.vControlPointCount,
      intermediate: values, vOperators: vOperators)
  }

  private static func add(_ a: Coefficient, _ b: Coefficient) -> Coefficient {
    Coefficient(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
  }

  private static func operators(
    cells: [AxisCell], candidate: Bool, knots: [Double],
    degree: Int, count: Int, targetDegree: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [AxisOperator] {
    let words = (MemoryLayout<AxisOperator>.stride + 7) / 8
    try execution.charge(
      scalars: Arithmetic.multiply(cells.count, words), work: Arithmetic.multiply(cells.count, 4))
    var operators: [AxisOperator] = []
    try OriginalCoefficientAllocation.reserve(
      count: cells.count, of: AxisOperator.self, using: &execution)
    operators.reserveCapacity(cells.count)
    let n = try Arithmetic.add(degree, 1)
    let outputCount = try Arithmetic.add(targetDegree, 1)
    let matrixCount = try Arithmetic.multiply(n, outputCount)
    for cell in cells {
      try CurrentTaskCancellationChecker().checkCancellation()
      // Selected basis recurrence owns all previous/next rows, COW row writes,
      // two divisions per side and every interval multiply scratch array.
      var basisScalars = try Arithmetic.multiply(n, 2)
      var basisWork = try Arithmetic.add(Arithmetic.multiply(knots.count, 3), 64)
      if degree > 0 {
        for p in 1...degree {
          let columns = try Arithmetic.add(p, 1)
          let rowStorage = try Arithmetic.multiply(try Arithmetic.multiply(2, n), columns)
          let sideScratch = try Arithmetic.multiply(
            try Arithmetic.multiply(2, columns),
            try Arithmetic.add(12, Arithmetic.multiply(4, columns)))
          basisScalars = try Arithmetic.add(basisScalars, Arithmetic.add(rowStorage, sideScratch))
          let sideWork = try Arithmetic.multiply(
            try Arithmetic.multiply(2, columns),
            try Arithmetic.add(48, Arithmetic.multiply(columns, 16)))
          basisWork = try Arithmetic.add(basisWork, sideWork)
        }
      }
      // Returned basis-row owners retain their existing coefficient buffers.
      basisScalars = try Arithmetic.add(
        basisScalars,
        Arithmetic.multiply(n, (MemoryLayout<BSplineBasis.NonzeroIntervalValues>.stride + 7) / 8))
      // Initial and each recurrence's outer row-owner array are distinct buffers.
      let rowOwnerWords = (MemoryLayout<[Interval]>.stride + 7) / 8
      basisScalars = try Arithmetic.add(
        basisScalars, Arithmetic.multiply(try Arithmetic.multiply(n, n), rowOwnerWords))
      try execution.charge(scalars: basisScalars)
      let span = candidate ? cell.candidateSpan : cell.sourceSpan
      let derivatives = try BSplineBasis.nonzeroIntervalDerivativeValues(
        parameter: cell.lower,
        degree: degree, throughDerivativeOrder: degree, knots: knots, count: count,
        owningSpan: span, tolerance: tolerance, using: &execution)
      // One scale table and one operator table, each with two fields per interval.
      try execution.charge(
        scalars: Arithmetic.multiply(matrixCount, 4), work: Arithmetic.multiply(matrixCount, 4))
      try OriginalCoefficientAllocation.reserve(
        count: matrixCount, of: Interval.self, using: &execution)
      var scales = Array(repeating: Interval.exact(0), count: matrixCount)
      let width = Interval.exact(cell.upper) - .exact(cell.lower)
      for j in 0..<outputCount {
        scales[j * n] = .exact(1)
        let order = min(j, degree)
        if order > 0 {
          for p in 1...order {
            // Three products create 12 scratch doubles; division creates six.
            try execution.charge(scalars: 18, work: 3 * 12 + 20 + 8)
            let numerator = scales[j * n + p - 1] * .exact(Double(j - p + 1)) * width
            let denominator = Interval.exact(Double(p)) * .exact(Double(targetDegree - p + 1))
            guard let scale = numerator.divided(by: denominator), scale.isFinite else {
              throw Arithmetic.exhausted()
            }
            scales[j * n + p] = scale
          }
        }
      }
      try OriginalCoefficientAllocation.reserve(
        count: matrixCount, of: Interval.self, using: &execution)
      var values = Array(repeating: Interval.exact(0), count: matrixCount)
      for j in 0..<outputCount {
        for i in 0..<n {
          let orders = try Arithmetic.add(min(j, degree), 1)
          try execution.charge(
            scalars: Arithmetic.multiply(orders, 4), work: Arithmetic.multiply(orders, 12 + 4 + 8))
          var value = Interval.exact(0)
          for p in 0..<orders { value = value + derivatives[p].values[i] * scales[j * n + p] }
          guard value.isFinite else { throw Arithmetic.exhausted() }
          values[j * n + i] = value
        }
      }
      operators.append(
        AxisOperator(start: span - degree, inputCount: n, outputCount: outputCount, values: values))
    }
    return operators
  }
}
