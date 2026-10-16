import CADCore

/// Immutable original native-span selection for a finite polynomial continuation law.
struct PreparedPolynomialSurfaceContinuationLaw: Sendable {
  typealias Preparation = NativePolynomialSurfacePositionPreparation
  typealias Arithmetic = PolynomialSurfacePositionDifferenceNet.Arithmetic

  struct Span: Sendable {
    let index: Int
    let lower: Double
    let upper: Double
  }

  struct Cell {
    let lower: Double
    let upper: Double
    let sourceIndex: Int
    let candidateSpan: Int
  }

  let uSpans: [Span]
  let vSpans: [Span]

  init(validated surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws {
    try execution.charge(scalars: (MemoryLayout<Self>.stride + 7) / 8, work: 4)
    uSpans = try Self.spans(
      knots: surface.uKnots, degree: surface.uDegree,
      count: surface.uControlPointCount, using: &execution)
    vSpans = try Self.spans(
      knots: surface.vKnots, degree: surface.vDegree,
      count: surface.vControlPointCount, using: &execution)
  }

  func originalCells(u: Bool, using execution: inout OriginalQueryExecution) throws -> [Preparation
    .AxisCell]
  {
    let spans = u ? uSpans : vSpans
    let words = (MemoryLayout<Preparation.AxisCell>.stride + 7) / 8
    try execution.charge(
      scalars: Arithmetic.multiply(spans.count, words), work: Arithmetic.multiply(spans.count, 8))
    var result: [Preparation.AxisCell] = []
    try OriginalCoefficientAllocation.reserve(
      count: spans.count, of: NativePolynomialSurfacePositionPreparation.AxisCell.self,
      using: &execution)
    result.reserveCapacity(spans.count)
    for span in spans {
      try CurrentTaskCancellationChecker().checkCancellation()
      result.append(
        .init(
          lower: span.lower, upper: span.upper,
          sourceSpan: span.index, candidateSpan: span.index))
    }
    return result
  }

  func commonCells(
    candidate: Self, u: Bool, interval: ScalarInterval,
    using execution: inout OriginalQueryExecution
  ) throws -> [Cell] {
    let original = u ? uSpans : vSpans
    let target = u ? candidate.uSpans : candidate.vSpans
    var sourceIndex = 0
    var candidateIndex = 0
    var lower = interval.lower
    var cells: [Cell] = []
    while lower < interval.upper {
      try execution.charge(work: 12)
      while sourceIndex + 1 < original.count {
        try execution.charge(work: 4)
        if original[sourceIndex].upper > lower { break }
        sourceIndex += 1
      }
      while candidateIndex + 1 < target.count {
        try execution.charge(work: 4)
        if target[candidateIndex].upper > lower { break }
        candidateIndex += 1
      }
      guard target[candidateIndex].lower <= lower, target[candidateIndex].upper > lower else {
        throw Arithmetic.exhausted()
      }
      // The first/last polynomial continues beyond its support; only genuine
      // internal source boundaries partition that law. Candidate stays contained.
      let sourceUpper =
        sourceIndex + 1 < original.count
        ? original[sourceIndex].upper : interval.upper
      let upper = min(interval.upper, sourceUpper, target[candidateIndex].upper)
      guard upper.isFinite, upper > lower else { throw Arithmetic.exhausted() }
      let words = (MemoryLayout<Cell>.stride + 7) / 8
      try execution.charge(scalars: Arithmetic.multiply(words, 4), work: 4)
      try OriginalCoefficientAllocation.reserve(count: 4, of: Cell.self, using: &execution)
      cells.append(
        Cell(
          lower: lower, upper: upper, sourceIndex: sourceIndex,
          candidateSpan: target[candidateIndex].index))
      lower = upper
    }
    return cells
  }

  func candidateCells(_ cells: [Cell], u: Bool, using execution: inout OriginalQueryExecution)
    throws -> [Preparation.AxisCell]
  {
    let spans = u ? uSpans : vSpans
    let words = (MemoryLayout<Preparation.AxisCell>.stride + 7) / 8
    try execution.charge(
      scalars: Arithmetic.multiply(cells.count, words), work: Arithmetic.multiply(cells.count, 8))
    var result: [Preparation.AxisCell] = []
    try OriginalCoefficientAllocation.reserve(
      count: cells.count, of: NativePolynomialSurfacePositionPreparation.AxisCell.self,
      using: &execution)
    result.reserveCapacity(cells.count)
    for cell in cells {
      try CurrentTaskCancellationChecker().checkCancellation()
      result.append(
        .init(
          lower: cell.lower, upper: cell.upper,
          sourceSpan: spans[cell.sourceIndex].index, candidateSpan: cell.candidateSpan))
    }
    return result
  }

  static func ratios(cell: Cell, span: Span, using execution: inout OriginalQueryExecution) throws
    -> (OutwardScalarInterval, OutwardScalarInterval)
  {
    try execution.charge(scalars: 12, work: 64)
    let lower = OutwardScalarInterval.exact(span.lower)
    let width = OutwardScalarInterval.exact(span.upper) - lower
    guard let a = (OutwardScalarInterval.exact(cell.lower) - lower).divided(by: width),
      let b = (OutwardScalarInterval.exact(cell.upper) - lower).divided(by: width),
      a.isFinite, b.isFinite
    else { throw Arithmetic.exhausted() }
    return (a, b)
  }

  private static func spans(
    knots: [Double], degree: Int, count: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> [Span] {
    var result: [Span] = []
    for index in degree..<count {
      try execution.charge(work: 4)
      if knots[index + 1] > knots[index] {
        let words = (MemoryLayout<Span>.stride + 7) / 8
        try execution.charge(scalars: Arithmetic.multiply(words, 4), work: 4)
        try OriginalCoefficientAllocation.reserve(count: 4, of: Span.self, using: &execution)
        result.append(Span(index: index, lower: knots[index], upper: knots[index + 1]))
      }
    }
    guard !result.isEmpty else { throw Arithmetic.exhausted() }
    return result
  }
}
