import CADCore

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("CADGeometry numeric algorithms require the target C math module.")
#endif

public struct DefaultCurveArcLengthResolver: CurveArcLengthResolving {
  private struct Cell: Sendable {
    let interval: ScalarInterval
    let lowerBound: Double
    let upperBound: Double
    let depth: Int

    var gap: Double {
      upperBound - lowerBound
    }
  }

  private struct CellHeap {
    private var storage: [Cell] = []
    private var admittedCapacity = 0

    var count: Int {
      storage.count
    }

    var cells: [Cell] {
      storage
    }

    /// Transfers the existing paid cell buffer into native parameter order.
    mutating func orderedCells(using execution: inout OriginalQueryExecution) throws -> [Cell] {
      guard storage.count > 1 else { return storage }
      for root in stride(from: storage.count / 2 - 1, through: 0, by: -1) {
        try siftNative(root: root, end: storage.count, using: &execution)
      }
      for end in stride(from: storage.count - 1, through: 1, by: -1) {
        try execution.admitGeometricDepth(max(storage[0].depth, storage[end].depth))
        try execution.consumeWork(1)
        storage.swapAt(0, end)
        try siftNative(root: 0, end: end, using: &execution)
      }
      return storage
    }

    private mutating func siftNative(
      root: Int, end: Int,
      using execution: inout OriginalQueryExecution
    ) throws {
      var parent = root
      while true {
        let left = parent * 2 + 1
        guard left < end else { return }
        var child = left
        let right = left + 1
        if right < end {
          try execution.admitGeometricDepth(max(storage[left].depth, storage[right].depth))
          try execution.consumeWork(1)
          if storage[right].interval.lower > storage[left].interval.lower { child = right }
        }
        try execution.admitGeometricDepth(max(storage[parent].depth, storage[child].depth))
        try execution.consumeWork(1)
        guard storage[parent].interval.lower < storage[child].interval.lower else { return }
        storage.swapAt(parent, child)
        parent = child
      }
    }

    mutating func insert(
      _ cell: Cell, maximumCapacity: Int,
      using execution: inout OriginalQueryExecution
    ) throws {
      try execution.admitGeometricDepth(cell.depth)
      try execution.consumeWork(1)
      if storage.count == admittedCapacity {
        let doubled = admittedCapacity.multipliedReportingOverflow(by: 2)
        guard !doubled.overflow, storage.count < maximumCapacity else {
          throw KernelError(
            phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
            message: "Arc-length heap capacity exceeded original cell admission.")
        }
        let capacity = min(maximumCapacity, max(1, doubled.partialValue))
        try execution.retainStorage(count: capacity, stride: MemoryLayout<Cell>.stride)
        storage.reserveCapacity(capacity)
        admittedCapacity = capacity
      }
      storage.append(cell)
      var child = storage.count - 1
      while child > 0 {
        try execution.consumeWork(1)
        let parent = (child - 1) / 2
        guard storage[child].gap > storage[parent].gap else { break }
        storage.swapAt(child, parent)
        child = parent
      }
    }

    mutating func removeMaximum(using execution: inout OriginalQueryExecution) throws -> Cell? {
      try execution.consumeWork(1)
      guard storage.isEmpty == false else { return nil }
      if storage.count == 1 {
        return storage.removeLast()
      }
      let result = storage[0]
      storage[0] = storage.removeLast()
      var parent = 0
      while true {
        try execution.consumeWork(1)
        let left = parent * 2 + 1
        guard left < storage.count else { break }
        let right = left + 1
        let child =
          (right < storage.count
            && storage[right].gap > storage[left].gap) ? right : left
        guard storage[child].gap > storage[parent].gap else { break }
        storage.swapAt(parent, child)
        parent = child
      }
      return result
    }
  }

  private struct PreparedParameterization: CurveArcLengthParameterization {
    let lengthEnclosure: CurveArcLengthEnclosure
    let curve: Curve3D
    let interval: ScalarInterval
    let absoluteAccuracy: Double
    let options: CurveArcLengthOptions
    let tolerance: ModelingTolerance
    let cells: [Cell]
    let isUniform: Bool
    let resolver: DefaultCurveArcLengthResolver
    let receipt: OriginalGeometryPreparationReceipt

    func parameterBounds(
      atFraction requested: ScalarInterval,
      maximumParameterWidth: Double, using execution: inout OriginalQueryExecution
    ) throws -> ScalarInterval {
      let selected = try resolver.callerMaximumAlgebraicDepth.map {
        try ExactScalarDepth(value: $0, coefficient: $0)
      }
      return try execution.withProofScope(maximum: selected) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)

        let fraction = OutwardScalarInterval(lower: requested.lower, upper: requested.upper)
        try resolver.consume(0, tolerance: tolerance, using: &execution)
        guard resolver.originalPreparation != nil,
          fraction.isFinite, fraction.lower >= 0, fraction.upper <= 1,
          maximumParameterWidth.isFinite, maximumParameterWidth > 0
        else {
          throw KernelError(
            phase: .geometry, code: .invalidInput,
            tolerance: tolerance,
            message:
              "Original inverse localization requires a paid partition, unit fraction interval and positive native width."
          )
        }
        if fraction.lower == 0, fraction.upper == 0 {
          return try ScalarInterval(lower: interval.lower, upper: interval.lower)
        }
        if fraction.lower == 1, fraction.upper == 1 {
          return try ScalarInterval(lower: interval.upper, upper: interval.upper)
        }
        if isUniform {
          try execution.consumeWork(1)
          let width = OutwardScalarInterval.exact(interval.upper) - .exact(interval.lower)
          let values = OutwardScalarInterval.exact(interval.lower) + width * fraction
          let result = try ScalarInterval(
            lower: max(interval.lower, values.lower),
            upper: min(interval.upper, values.upper))
          guard result.width <= maximumParameterWidth else {
            throw KernelError(
              phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
              message:
                "The requested original uniform fraction interval exceeds the selected native width."
            )
          }
          return result
        }
        return try resolver.inverseOriginalParameterBounds(
          fraction: fraction,
          maximumParameterWidth: maximumParameterWidth, curve: curve,
          initialCells: cells, options: options, tolerance: tolerance, using: &execution)

      }
    }

    func hasSmoothNativeInterval(
      over requested: ScalarInterval, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      let selected = try resolver.callerMaximumAlgebraicDepth.map {
        try ExactScalarDepth(value: $0, coefficient: $0)
      }
      return try execution.withProofScope(maximum: selected) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)

        try resolver.consume(0, tolerance: tolerance, using: &execution)
        guard let prepared = resolver.originalPreparation,
          let depth = resolver.callerMaximumDepth,
          let spans = resolver.callerMaximumSpans,
          requested.lower >= interval.lower, requested.upper <= interval.upper,
          requested.width > 0
        else {
          throw KernelError(
            phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "Original native smoothness requires a retained positive interval.")
        }
        if let mapped = try resolver.mappedChartSmoothness(
          prepared.curve,
          over: requested, depth: 0, tolerance: tolerance, using: &execution)
        {
          return mapped
        }
        guard
          try resolver.hasSmoothTaylorAuthority(
            prepared.curve, depth: 0,
            tolerance: tolerance, using: &execution)
        else { return false }
        let receipt = try prepared.closedNativeJets(
          over: requested, tolerance: tolerance,
          maximumSpanCount: spans, maximumSubdivisionDepth: depth,
          remainingSourceDepth: resolver.callerSourceDepth ?? depth, using: &execution)
        var owners = 0
        for span in receipt.spans {
          try resolver.consume(0, tolerance: tolerance, using: &execution)
          if span.parameters.width > 0 {
            owners += 1
            if owners > 1 { return false }
          }
        }
        return owners == 1

      }
    }

    func differentialEnclosure(
      over requested: ScalarInterval, using execution: inout OriginalQueryExecution
    ) throws -> CurveDifferentialEnclosure {
      let selected = try resolver.callerMaximumAlgebraicDepth.map {
        try ExactScalarDepth(value: $0, coefficient: $0)
      }
      return try execution.withProofScope(maximum: selected) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)

        try resolver.consume(0, tolerance: tolerance, using: &execution)
        guard let prepared = resolver.originalPreparation,
          let depth = resolver.callerMaximumDepth,
          let spans = resolver.callerMaximumSpans,
          requested.lower >= interval.lower, requested.upper <= interval.upper
        else {
          throw KernelError(
            phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "Original differential reuse requires its retained bounded native domain.")
        }
        let receipt = try prepared.closedNativeJets(
          over: requested, tolerance: tolerance,
          maximumSpanCount: spans, maximumSubdivisionDepth: depth,
          remainingSourceDepth: resolver.callerSourceDepth ?? depth, using: &execution)
        guard let first = receipt.spans.first else {
          throw KernelError(
            phase: .geometry, code: .intersectionFailure,
            tolerance: tolerance, message: "Original differential coverage is empty.")
        }
        var jet = first.jet
        for span in receipt.spans {
          try resolver.consume(0, tolerance: tolerance, using: &execution)
          jet = jet.union(span.jet)
        }
        func coordinate(
          _ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
          _ z: OutwardScalarInterval, using execution: inout OriginalQueryExecution
        ) throws -> CoordinateEnclosure3D {
          try resolver.consume(0, tolerance: tolerance, using: &execution)
          guard x.isFinite, y.isFinite, z.isFinite else {
            throw KernelError(
              phase: .geometry, code: .resourceLimitExceeded,
              tolerance: tolerance, message: "Original differential hull is not finite.")
          }
          return CoordinateEnclosure3D(
            x: try ScalarInterval(lower: x.lower, upper: x.upper),
            y: try ScalarInterval(lower: y.lower, upper: y.upper),
            z: try ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return CurveDifferentialEnclosure(
          position: try coordinate(jet.x.value, jet.y.value, jet.z.value, using: &execution),
          firstDerivative: try coordinate(
            jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU, using: &execution),
          secondDerivative: try coordinate(
            jet.x.secondDerivativeUU,
            jet.y.secondDerivativeUU, jet.z.secondDerivativeUU, using: &execution))

      }
    }

    func enclosure(over requested: ScalarInterval, using execution: inout OriginalQueryExecution)
      throws -> CurveArcLengthEnclosure
    {
      let selected = try resolver.callerMaximumAlgebraicDepth.map {
        try ExactScalarDepth(value: $0, coefficient: $0)
      }
      return try execution.withProofScope(maximum: selected) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)

        try resolver.consume(0, tolerance: tolerance, using: &execution)
        guard resolver.originalPreparation != nil,
          requested.lower >= interval.lower, requested.upper <= interval.upper
        else {
          throw KernelError(
            phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "Native subinterval lengths require the bounded original preparation domain.")
        }
        if requested.width == 0 { return try CurveArcLengthEnclosure(lowerBound: 0, upperBound: 0) }
        if requested.lower == interval.lower, requested.upper == interval.upper {
          return lengthEnclosure
        }
        if isUniform {
          guard
            let length = try resolver.constantSpeedEnclosure(
              of: curve, over: requested, using: &execution)
          else {
            throw GeometryConversionError.invalidInput(
              "The retained uniform arc law lost its original source.")
          }
          return length
        }
        var lower = 0.0
        var upper = 0.0
        for cell in cells {
          try resolver.consume(cell.depth, tolerance: tolerance, using: &execution)
          let lo = max(cell.interval.lower, requested.lower)
          let hi = min(cell.interval.upper, requested.upper)
          guard lo < hi else { continue }
          let part: CurveArcLengthEnclosure
          if lo == cell.interval.lower, hi == cell.interval.upper {
            part = try CurveArcLengthEnclosure(
              lowerBound: cell.lowerBound,
              upperBound: cell.upperBound)
          } else {
            let boundaryOptions = CurveArcLengthOptions(
              absoluteAccuracy: absoluteAccuracy * 0.25,
              relativeAccuracy: 0, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
              maximumIntervalCount: options.maximumIntervalCount)
            part = try resolver.certifiedPartition(
              curve: curve,
              interval: ScalarInterval(lower: lo, upper: hi),
              absoluteAccuracy: absoluteAccuracy * 0.25, options: boundaryOptions,
              tolerance: tolerance, initialDepth: cell.depth, using: &execution
            ).enclosure
          }
          lower = max(0, (lower + part.lowerBound).nextDown)
          upper = (upper + part.upperBound).nextUp
        }
        guard upper - lower <= max(absoluteAccuracy, options.relativeAccuracy * upper) else {
          throw KernelError(
            phase: .geometry, code: .resourceLimitExceeded,
            residual: upper - lower, tolerance: tolerance,
            message: "Retained arc-length cells cannot meet the native subinterval accuracy.")
        }
        return try CurveArcLengthEnclosure(lowerBound: lower, upperBound: upper)

      }
    }

    func parameterEnclosure(
      atArcLengthFraction fraction: Double, using execution: inout OriginalQueryExecution
    ) throws -> CurveArcLengthParameterEnclosure {
      let selected = try resolver.callerMaximumAlgebraicDepth.map {
        try ExactScalarDepth(value: $0, coefficient: $0)
      }
      return try execution.withProofScope(maximum: selected) { execution in
        try receipt.admit(tolerance: tolerance, using: &execution)

        guard fraction.isFinite,
          fraction >= 0.0,
          fraction <= 1.0
        else {
          throw KernelError(
            phase: .geometry,
            code: .invalidInput,
            residual: fraction,
            tolerance: tolerance,
            message: "Curve arc-length fraction must be finite and lie in the closed unit interval."
          )
        }
        if fraction == 0.0 {
          return try CurveArcLengthParameterEnclosure(
            parameterRange: ScalarInterval(
              lower: interval.lower,
              upper: interval.lower
            ),
            spatialErrorUpperBound: 0.0
          )
        }
        if fraction == 1.0 {
          return try CurveArcLengthParameterEnclosure(
            parameterRange: ScalarInterval(
              lower: interval.upper,
              upper: interval.upper
            ),
            spatialErrorUpperBound: 0.0
          )
        }
        if isUniform {
          try execution.consumeWork(1)
          let parameter = interval.lower + interval.width * fraction
          return try CurveArcLengthParameterEnclosure(
            parameterRange: ScalarInterval(lower: parameter, upper: parameter),
            spatialErrorUpperBound: 0)
        }
        return try resolver.invertedParameterEnclosure(
          atArcLengthFraction: fraction,
          curve: curve,
          interval: interval,
          lengthEnclosure: lengthEnclosure,
          initialCells: cells,
          absoluteAccuracy: absoluteAccuracy,
          options: options,
          tolerance: tolerance, using: &execution)

      }
    }
    func parameterBounds(
      atFraction fraction: ScalarInterval,
      maximumParameterWidth: Double
    ) throws -> ScalarInterval {
      var execution = try resolver.reader()
      return try parameterBounds(
        atFraction: fraction, maximumParameterWidth: maximumParameterWidth, using: &execution)
    }
    func hasSmoothNativeInterval(over interval: ScalarInterval) throws -> Bool {
      var execution = try resolver.reader()
      return try hasSmoothNativeInterval(over: interval, using: &execution)
    }
    func differentialEnclosure(over interval: ScalarInterval) throws -> CurveDifferentialEnclosure {
      var execution = try resolver.reader()
      return try differentialEnclosure(over: interval, using: &execution)
    }
    func enclosure(over interval: ScalarInterval) throws -> CurveArcLengthEnclosure {
      var execution = try resolver.reader()
      return try enclosure(over: interval, using: &execution)
    }
    func parameterEnclosure(atArcLengthFraction fraction: Double) throws
      -> CurveArcLengthParameterEnclosure
    {
      var execution = try resolver.reader()
      return try parameterEnclosure(atArcLengthFraction: fraction, using: &execution)
    }
  }

  private let originalPreparation: PreparedCurveDifferentialEncloser?
  private let callerMaximumDepth: Int?
  private let callerSourceDepth: Int?
  private let callerMaximumAlgebraicDepth: Int?
  private let callerMaximumSpans: Int?

  public init() {
    originalPreparation = nil
    callerMaximumDepth = nil
    callerSourceDepth = nil
    callerMaximumAlgebraicDepth = nil
    callerMaximumSpans = nil
  }

  private init(
    prepared: PreparedCurveDifferentialEncloser, maximumDepth: Int,
    maximumSpans: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int?,
    using execution: inout OriginalQueryExecution
  ) {
    originalPreparation = prepared
    callerMaximumDepth = maximumDepth
    callerSourceDepth = remainingSourceDepth
    callerMaximumAlgebraicDepth = maximumAlgebraicDepth
    callerMaximumSpans = maximumSpans
  }

  private func reader() throws -> OriginalQueryExecution {
    guard let originalPreparation else {
      throw GeometryConversionError.invalidInput("Arc-length readers require retained preparation.")
    }
    return try originalPreparation.makeExecution()
  }

  private func reserve(
    count: Int, stride: Int, depth: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try consume(depth, tolerance: tolerance, using: &execution)
    try execution.retainStorage(count: count, stride: stride)
  }

  private func consume(
    _ depth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    try execution.checkpoint()
    if let callerMaximumDepth, depth > callerMaximumDepth {
      throw KernelError(
        phase: .geometry, code: .resourceLimitExceeded,
        tolerance: tolerance, message: "Arc length exhausted the caller's subdivision depth.")
    }
    try execution.admitGeometricDepth(depth)
    try execution.consumeWork(1)
  }

  public func parameterization(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions = CurveArcLengthOptions(), tolerance: ModelingTolerance
  ) throws -> any CurveArcLengthParameterization {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try parameterization(
      of: curve, over: interval, options: options, tolerance: tolerance,
      maximumSubdivisionDepth: options.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumAlgebraicDepth: nil,
      using: &execution)
  }

  public func parameterization(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> any CurveArcLengthParameterization {
    try prepareOriginal(
      of: curve, over: interval, options: options, tolerance: tolerance,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, partitionAccuracyFactor: 0.5, using: &execution)
  }

  private func prepareOriginal(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int?,
    partitionAccuracyFactor: Double, using execution: inout OriginalQueryExecution
  ) throws -> PreparedParameterization {
    try execution.checkpoint()
    let accuracy = try options.validatedAbsoluteAccuracy(tolerance: tolerance)
    guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0, interval.width > 0,
      maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true
    else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message:
          "Original arc-length preparation requires a positive interval and independent valid ceilings."
      )
    }
    let depth = min(maximumSubdivisionDepth, options.maximumSubdivisionDepth)
    let selected = try maximumAlgebraicDepth.map {
      try ExactScalarDepth(value: $0, coefficient: $0)
    }
    return try execution.withProofScope(maximum: selected) { execution in
      let preparation = try execution.withPreparationScope { execution in
        let prepared = try PreparedCurveDifferentialEncloser(
          curve: curve, tolerance: tolerance,
          remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: depth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        let invocation = Self(
          prepared: prepared, maximumDepth: depth,
          maximumSpans: options.maximumIntervalCount, remainingSourceDepth: remainingSourceDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try invocation.validateOriginalInterval(
          curve, interval: interval,
          remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, using: &execution)
        if let uniform = try invocation.constantSpeedEnclosure(
          of: curve, over: interval, using: &execution)
        {
          try execution.visitGeometricCell(depth: 0)
          try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
          let cells = [
            Cell(
              interval: interval, lowerBound: uniform.lowerBound,
              upperBound: uniform.upperBound, depth: 0)
          ]
          return (invocation, (cells: cells, enclosure: uniform), true)
        }
        let tightened = CurveArcLengthOptions(
          absoluteAccuracy: accuracy * partitionAccuracyFactor,
          relativeAccuracy: partitionAccuracyFactor == 1 ? options.relativeAccuracy : 0,
          maximumSubdivisionDepth: options.maximumSubdivisionDepth,
          maximumIntervalCount: options.maximumIntervalCount)
        let partition = try invocation.certifiedPartition(
          curve: curve, interval: interval,
          absoluteAccuracy: accuracy * partitionAccuracyFactor, options: tightened,
          tolerance: tolerance,
          using: &execution)
        return (invocation, partition, false)
      }
      let receipt = try OriginalGeometryPreparationReceipt(
        tolerance: tolerance,
        depth: preparation.depth, using: &execution)
      try execution.retainStorage(count: 1, stride: MemoryLayout<PreparedParameterization>.stride)
      try execution.checkpoint()
      return PreparedParameterization(
        lengthEnclosure: preparation.result.1.enclosure, curve: curve,
        interval: interval, absoluteAccuracy: accuracy, options: options, tolerance: tolerance,
        cells: preparation.result.1.cells, isUniform: preparation.result.2,
        resolver: preparation.result.0, receipt: receipt)
    }
  }

  public func enclosure(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions = CurveArcLengthOptions(), tolerance: ModelingTolerance
  ) throws -> CurveArcLengthEnclosure {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try enclosure(
      of: curve, over: interval, options: options, tolerance: tolerance,
      maximumSubdivisionDepth: options.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumAlgebraicDepth: nil,
      using: &execution)
  }

  public func enclosure(
    of curve: Curve3D, over interval: ScalarInterval,
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthEnclosure {
    let prepared = try prepareOriginal(
      of: curve, over: interval, options: options, tolerance: tolerance,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, partitionAccuracyFactor: 1, using: &execution)
    try execution.checkpoint()
    return prepared.lengthEnclosure
  }

  public func parameterEnclosure(
    atArcLengthFraction fraction: Double, of curve: Curve3D,
    over interval: ScalarInterval, options: CurveArcLengthOptions = CurveArcLengthOptions(),
    tolerance: ModelingTolerance
  ) throws -> CurveArcLengthParameterEnclosure {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try parameterEnclosure(
      atArcLengthFraction: fraction, of: curve, over: interval,
      options: options, tolerance: tolerance, using: &execution)
  }

  public func parameterEnclosure(
    atArcLengthFraction fraction: Double, of curve: Curve3D,
    over interval: ScalarInterval, options: CurveArcLengthOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthParameterEnclosure {
    let prepared = try parameterization(
      of: curve, over: interval, options: options, tolerance: tolerance,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumAlgebraicDepth: nil,
      using: &execution)
    return try prepared.parameterEnclosure(atArcLengthFraction: fraction, using: &execution)
  }

  private func constantSpeedEnclosure(
    of curve: Curve3D,
    over interval: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthEnclosure? {
    try execution.checkpoint()
    try execution.consumeWork(1)
    let parameterWidth = interval.width
    let speed: Double
    switch curve {
    case .line, .analytic(.line):
      speed = 1.0
    case .circle(let circle):
      speed = circle.radius
    case .analytic(.circle(_, _, let radius)),
      .analytic(.arc(_, _, let radius, _, _)):
      speed = radius
    case .parameterImage(let image):
      return try constantSpeedEnclosure(
        of: image.source, over: image.originalInterval(interval, using: &execution),
        using: &execution)
    case .rigidImage(let image):
      return try constantSpeedEnclosure(of: image.source, over: interval, using: &execution)
    case .analytic, .bSpline, .implicit, .surfaceLift,
      .certifiedIntersection, .affineImage, .originalAffineWord, .originalEndpointConnector,
      .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative,
      .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector,
      .originalPolyline:
      return nil
    }
    let value = speed * parameterWidth
    return try CurveArcLengthEnclosure(
      lowerBound: max(0.0, value.nextDown),
      upperBound: value.nextUp
    )
  }

  private func invertedParameterEnclosure(
    atArcLengthFraction fraction: Double,
    curve: Curve3D,
    interval: ScalarInterval,
    lengthEnclosure total: CurveArcLengthEnclosure,
    initialCells: [Cell],
    absoluteAccuracy: Double,
    options: CurveArcLengthOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> CurveArcLengthParameterEnclosure {
    let target =
      OutwardScalarInterval.exact(fraction)
      * .init(lower: total.lowerBound, upper: total.upperBound)
    let targetLower = target.lower
    let targetUpper = target.upper
    var cells = initialCells
    var admittedCapacity = 0
    var splitCount = 0
    while true {
      try consume(0, tolerance: tolerance, using: &execution)
      let candidates = try candidateCellRange(
        cells: cells,
        targetLower: targetLower,
        targetUpper: targetUpper,
        tolerance: tolerance, using: &execution)
      guard let candidates,
        let firstIndex = candidates.first,
        let lastIndex = candidates.last
      else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          tolerance: tolerance,
          message:
            "Certified curve arc-length inversion lost the target from its cumulative length enclosure."
        )
      }
      var spatialError = 0.0
      for cell in cells[firstIndex...lastIndex] {
        try consume(cell.depth, tolerance: tolerance, using: &execution)
        spatialError = (spatialError + cell.upperBound).nextUp
      }
      let parameterRange = try ScalarInterval(
        lower: cells[firstIndex].interval.lower,
        upper: cells[lastIndex].interval.upper
      )
      if spatialError <= absoluteAccuracy {
        return try CurveArcLengthParameterEnclosure(
          parameterRange: parameterRange,
          spatialErrorUpperBound: spatialError
        )
      }
      guard splitCount < options.maximumIntervalCount,
        cells.count < options.maximumIntervalCount
      else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: spatialError,
          tolerance: tolerance,
          message:
            "Certified curve arc-length inversion exceeded its interval budget before reaching the requested spatial error."
        )
      }
      let splitIndex =
        try (firstIndex...lastIndex).max {
          try consume(
            max(cells[$0].depth, cells[$1].depth), tolerance: tolerance, using: &execution)
          return cells[$0].upperBound < cells[$1].upperBound
        } ?? firstIndex
      let source = cells[splitIndex]
      guard source.depth < options.maximumSubdivisionDepth else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: spatialError,
          tolerance: tolerance,
          message: "Certified curve arc-length inversion exceeded its subdivision depth."
        )
      }
      let halves = try split(
        source,
        curve: curve,
        tolerance: tolerance, using: &execution)
      try replaceRetainedCell(
        at: splitIndex, children: halves, cells: &cells,
        admittedCapacity: &admittedCapacity,
        maximumCapacity: options.maximumIntervalCount, tolerance: tolerance, using: &execution)
      splitCount += 1
    }
  }

  private func inverseOriginalParameterBounds(
    fraction: OutwardScalarInterval,
    maximumParameterWidth: Double, curve: Curve3D, initialCells: [Cell],
    options: CurveArcLengthOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    // This alias borrows the paid immutable partition until the first split.
    // Before COW or growth, reserve the complete destination capacity and pay
    // every original element copied; no preparation or allowance is restarted.
    var cells = initialCells
    var admittedCapacity = 0
    var iteration = 0
    while true {
      try consume(0, tolerance: tolerance, using: &execution)
      var lower = 0.0
      var upper = 0.0
      for cell in cells {
        try consume(cell.depth, tolerance: tolerance, using: &execution)
        lower = max(0, (lower + cell.lowerBound).nextDown)
        upper = (upper + cell.upperBound).nextUp
      }
      let total = OutwardScalarInterval(lower: lower, upper: upper)
      let target = total * fraction
      guard total.isFinite, upper > 0, target.isFinite,
        let candidates = try candidateCellRange(
          cells: cells,
          targetLower: target.lower, targetUpper: target.upper,
          tolerance: tolerance, using: &execution)
      else {
        throw KernelError(
          phase: .geometry, code: .intersectionFailure,
          tolerance: tolerance,
          message: "Original inverse length localization lost its complete target cover.")
      }
      let bracket = try ScalarInterval(
        lower: cells[candidates.lowerBound].interval.lower,
        upper: cells[candidates.upperBound].interval.upper)
      if bracket.width <= maximumParameterWidth { return bracket }
      guard cells.count < options.maximumIntervalCount else {
        throw KernelError(
          phase: .geometry, code: .resourceLimitExceeded,
          residual: bracket.width, tolerance: tolerance,
          message: "Original inverse length localization exhausted its retained cell policy.")
      }
      // Both cumulative-length uncertainty and local native width can
      // obstruct localization. Alternate their refinements; neither a
      // numerical prefix nor a guessed speed determines an exclusion.
      var selected: Int?
      var score = -Double.infinity
      for index in cells.indices {
        try consume(cells[index].depth, tolerance: tolerance, using: &execution)
        guard cells[index].depth < options.maximumSubdivisionDepth,
          callerMaximumDepth.map({ cells[index].depth < $0 }) ?? true
        else { continue }
        if iteration.isMultiple(of: 2), !candidates.contains(index) { continue }
        let priority =
          iteration.isMultiple(of: 2)
          ? cells[index].interval.width : cells[index].gap
        if priority > score {
          selected = index
          score = priority
        }
      }
      guard let selected else {
        throw KernelError(
          phase: .geometry, code: .resourceLimitExceeded,
          residual: bracket.width, tolerance: tolerance,
          message: "Original inverse length localization exhausted original cell depth.")
      }
      let source = cells[selected]
      let children = try split(source, curve: curve, tolerance: tolerance, using: &execution)
      try replaceRetainedCell(
        at: selected, children: children, cells: &cells,
        admittedCapacity: &admittedCapacity,
        maximumCapacity: options.maximumIntervalCount, tolerance: tolerance, using: &execution)
      iteration += 1
    }
  }

  private func replaceRetainedCell(
    at selected: Int, children: (lower: Cell, upper: Cell),
    cells: inout [Cell], admittedCapacity: inout Int, maximumCapacity: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    if cells.count == admittedCapacity || admittedCapacity == 0 {
      let doubled = cells.count.multipliedReportingOverflow(by: 2)
      let next = cells.count.addingReportingOverflow(1)
      guard !doubled.overflow, !next.overflow, next.partialValue <= maximumCapacity else {
        throw KernelError(
          phase: .geometry, code: .resourceLimitExceeded,
          tolerance: tolerance, message: "Original inverse cell capacity overflowed.")
      }
      let capacity = min(maximumCapacity, max(next.partialValue, doubled.partialValue))
      try reserve(
        count: capacity, stride: MemoryLayout<Cell>.stride,
        depth: cells[selected].depth, tolerance: tolerance, using: &execution)
      for cell in cells { try consume(cell.depth, tolerance: tolerance, using: &execution) }
      cells.reserveCapacity(capacity)
      admittedCapacity = capacity
    }
    for index in selected..<cells.count {
      try consume(cells[index].depth, tolerance: tolerance, using: &execution)
    }
    cells[selected] = children.lower
    cells.insert(children.upper, at: selected + 1)
  }

  private func certifiedPartition(
    curve: Curve3D,
    interval: ScalarInterval,
    absoluteAccuracy: Double,
    options: CurveArcLengthOptions,
    tolerance: ModelingTolerance,
    initialDepth: Int = 0, using execution: inout OriginalQueryExecution
  ) throws -> (cells: [Cell], enclosure: CurveArcLengthEnclosure) {
    let initialCells = try initialCells(
      curve: curve,
      interval: interval,
      tolerance: tolerance,
      initialDepth: initialDepth, using: &execution)
    guard initialCells.isEmpty == false,
      initialCells.count <= options.maximumIntervalCount
    else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: Double(initialCells.count),
        tolerance: tolerance,
        message: "Certified curve arc-length evaluation exceeded its initial interval budget."
      )
    }
    var lowerBound = 0.0
    var upperBound = 0.0
    var heap = CellHeap()
    for initial in initialCells {
      try consume(initial.depth, tolerance: tolerance, using: &execution)
      lowerBound = (lowerBound + initial.lowerBound).nextDown
      upperBound = (upperBound + initial.upperBound).nextUp
      try heap.insert(initial, maximumCapacity: options.maximumIntervalCount, using: &execution)
    }
    while upperBound - lowerBound
      > max(
        absoluteAccuracy,
        options.relativeAccuracy * upperBound
      )
    {
      guard heap.count < options.maximumIntervalCount,
        let source = try heap.removeMaximum(using: &execution),
        source.depth < options.maximumSubdivisionDepth
      else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: upperBound - lowerBound,
          tolerance: tolerance,
          message:
            "Certified curve arc-length evaluation exceeded its subdivision budget before reaching the requested enclosure width."
        )
      }
      let halves = try split(
        source,
        curve: curve,
        tolerance: tolerance, using: &execution)
      lowerBound =
        (OutwardScalarInterval.exact(lowerBound)
        + .exact(halves.lower.lowerBound) + .exact(halves.upper.lowerBound)
        - .exact(source.lowerBound)).lower
      upperBound =
        (OutwardScalarInterval.exact(upperBound)
        + .exact(halves.lower.upperBound) + .exact(halves.upper.upperBound)
        - .exact(source.upperBound)).upper
      lowerBound = max(0.0, lowerBound.nextDown)
      upperBound = max(lowerBound, upperBound.nextUp)
      try heap.insert(
        halves.lower, maximumCapacity: options.maximumIntervalCount, using: &execution)
      try heap.insert(
        halves.upper, maximumCapacity: options.maximumIntervalCount, using: &execution)
    }
    // The immutable partition keeps this already-admitted heap backing.
    // In-place ordering avoids an unmetered standard-library sort scratch buffer.
    let ordered = try heap.orderedCells(using: &execution)
    return (
      cells: ordered,
      enclosure: try CurveArcLengthEnclosure(
        lowerBound: lowerBound,
        upperBound: upperBound
      )
    )
  }

  private func split(
    _ source: Cell,
    curve: Curve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (lower: Cell, upper: Cell) {
    try consume(source.depth, tolerance: tolerance, using: &execution)
    let middle = source.interval.midpoint
    return (
      try cell(
        curve: curve,
        interval: ScalarInterval(
          lower: source.interval.lower,
          upper: middle
        ),
        depth: source.depth + 1,
        tolerance: tolerance, using: &execution),
      try cell(
        curve: curve,
        interval: ScalarInterval(
          lower: middle,
          upper: source.interval.upper
        ),
        depth: source.depth + 1,
        tolerance: tolerance, using: &execution)
    )
  }

  private func candidateCellRange(
    cells: [Cell],
    targetLower: Double,
    targetUpper: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ClosedRange<Int>? {
    var prefixLower = 0.0
    var prefixUpper = 0.0
    var first: Int?
    var last: Int?
    for index in cells.indices {
      try consume(cells[index].depth, tolerance: tolerance, using: &execution)
      let endLower = max(0, (prefixLower + cells[index].lowerBound).nextDown)
      let endUpper = (prefixUpper + cells[index].upperBound).nextUp
      if endUpper >= targetLower,
        prefixLower <= targetUpper
      {
        first = first ?? index
        last = index
      }
      prefixLower = endLower
      prefixUpper = endUpper
    }
    guard let first, let last else { return nil }
    return first...last
  }

  private func cell(
    curve: Curve3D, interval: ScalarInterval, depth: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Cell {
    guard let originalPreparation else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original arc-length cells require retained source preparation.")
    }
    try reserve(
      count: 1, stride: MemoryLayout<Cell>.stride, depth: depth,
      tolerance: tolerance, using: &execution)
    return try originalCell(
      prepared: originalPreparation, interval: interval,
      depth: depth, tolerance: tolerance, using: &execution)
  }

  private func initialCells(
    curve: Curve3D, interval: ScalarInterval,
    tolerance: ModelingTolerance, initialDepth: Int = 0,
    using execution: inout OriginalQueryExecution
  ) throws -> [Cell] {
    let original = try cell(
      curve: curve, interval: interval, depth: initialDepth,
      tolerance: tolerance, using: &execution)
    try reserve(
      count: 1, stride: MemoryLayout<Cell>.stride, depth: initialDepth,
      tolerance: tolerance, using: &execution)
    return [original]
  }

  private func validateOriginalInterval(
    _ curve: Curve3D, interval: ScalarInterval,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    try consume(0, tolerance: tolerance, using: &execution)
    func descend(
      _ source: Curve3D, _ range: ScalarInterval, using execution: inout OriginalQueryExecution
    ) throws {
      guard remainingSourceDepth > 0 else {
        throw KernelError(
          phase: .geometry, code: .resourceLimitExceeded,
          tolerance: tolerance, message: "Arc-length domain admission exhausted source depth.")
      }
      try validateOriginalInterval(
        source, interval: range,
        remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, using: &execution)
    }
    switch curve {
    case .parameterImage(let image):
      try descend(
        image.source, image.originalInterval(interval, using: &execution), using: &execution)
    case .rigidImage(let image): try descend(image.source, interval, using: &execution)
    case .affineImage(let image): try descend(image.source, interval, using: &execution)
    case .originalAffineWord(let image): try descend(image.source, interval, using: &execution)
    default:
      guard
        try curve.parameterDomain.containsSpan(
          from: interval.lower,
          to: interval.upper, tolerance: tolerance)
      else {
        throw KernelError(
          phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "Bounded original arc length exceeds the authored curve domain.")
      }
    }
  }

  /// nil leaves the ordinary native-owner proof in charge of this family.
  private func mappedChartSmoothness(
    _ curve: Curve3D, over interval: ScalarInterval,
    depth: Int, tolerance: ModelingTolerance, sourceDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool? {
    try consume(depth, tolerance: tolerance, using: &execution)
    guard let maximumDepth = callerMaximumDepth, let maximumSpans = callerMaximumSpans,
      depth <= maximumDepth
    else {
      throw KernelError(
        phase: .geometry, code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Original chart smoothness exhausted its retained invocation depth.")
    }
    let selectedSource = sourceDepth ?? callerSourceDepth
    func descend(
      _ source: Curve3D, over range: ScalarInterval, using execution: inout OriginalQueryExecution
    ) throws -> Bool? {
      if let selectedSource {
        guard selectedSource > 0 else {
          throw KernelError(
            phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Original arc chart recursion exhausted its selected source depth.")
        }
        return try mappedChartSmoothness(
          source, over: range, depth: depth,
          tolerance: tolerance, sourceDepth: selectedSource - 1, using: &execution)
      }
      return try mappedChartSmoothness(
        source, over: range, depth: depth + 1, tolerance: tolerance, using: &execution)
    }
    switch curve {
    case .originalGuideTraversalChain(let chain):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Arc/Sweep delegates exact local
      // station-map smoothness to the chain issuer. Unknown original joins
      // and unavailable stricter nonnative algebra transport remain lower
      // gaps; neither synthetic owners nor a hull authorize their success.
      return try chain.hasSmoothNativeInterval(
        over: interval, tolerance: tolerance,
        maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
        remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
        maximumAlgebraicDepth: callerMaximumAlgebraicDepth, using: &execution)
    case .originalPolyline(let polyline):
      return try polyline.hasSmoothNativeInterval(
        over: interval, tolerance: tolerance,
        maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
        remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
        maximumAlgebraicDepth: callerMaximumAlgebraicDepth, using: &execution)
    case .originalGuideEndpointConnector(let corrected):
      return try corrected.hasSmoothNativeInterval(
        over: interval, tolerance: tolerance,
        maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
        remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
        maximumAlgebraicDepth: callerMaximumAlgebraicDepth, using: &execution)
    case .originalConstructionChart(let image):
      return try image.hasSmoothNativeInterval(
        over: interval, tolerance: tolerance,
        maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
        remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
        maximumAlgebraicDepth: callerMaximumAlgebraicDepth, using: &execution)
    case .rigidImage(let image):
      return try descend(image.source, over: interval, using: &execution)
    case .affineImage(let image):
      return try descend(image.source, over: interval, using: &execution)
    case .originalAffineWord(let image):
      return try descend(image.source, over: interval, using: &execution)
    case .parameterImage(let image):
      let native = try image.originalInterval(interval, using: &execution)
      return try descend(image.source, over: native, using: &execution)
    default: return nil
    }
  }

  private func hasSmoothTaylorAuthority(
    _ curve: Curve3D, depth: Int,
    tolerance: ModelingTolerance, sourceDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try consume(depth, tolerance: tolerance, using: &execution)
    let selectedSource = sourceDepth ?? callerSourceDepth
    func descend(_ source: Curve3D, using execution: inout OriginalQueryExecution) throws -> Bool {
      if let selectedSource {
        guard selectedSource > 0 else {
          throw KernelError(
            phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Arc Taylor family traversal exhausted selected source depth.")
        }
        return try hasSmoothTaylorAuthority(
          source, depth: depth, tolerance: tolerance,
          sourceDepth: selectedSource - 1, using: &execution)
      }
      return try hasSmoothTaylorAuthority(
        source, depth: depth, tolerance: tolerance, using: &execution)
    }
    switch curve {
    case .line, .circle, .bSpline:
      // Native spline tightening also requires exactly one positive-width owner.
      return true
    case .analytic(.line), .analytic(.circle), .analytic(.arc),
      .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola):
      return true
    case .parameterImage(let image):
      return try descend(image.source, using: &execution)
    case .rigidImage(let image):
      return try descend(image.source, using: &execution)
    case .affineImage(let image):
      return try descend(image.source, using: &execution)
    case .originalAffineWord(let image):
      return try descend(image.source, using: &execution)
    case .originalConstructionChart:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Unknown lifted/implicit owning
      // joins remain outside Arc/Sweep smoothness authority. Construction
      // charts delegate to mappedChartSmoothness before this family selector;
      // a synthetic hull alone never proves a smooth original join.
      return false
    case .originalAngularTransport:
      // Its admitted direct conic phase law is smooth on each original
      // interval. Actual prepared jets and one positive owner still prove
      // speed and Taylor bounds; no binary-pi or scalar shortcut applies.
      return true
    case .originalEndpointConnector:
      // Its exact polynomial correction preserves each smooth construction
      // owner. The corrected original jet, and exactly one positive-width
      // owner, still establish all speed and Taylor quantities below.
      return true
    case .surfaceLift(let lift):
      switch lift.parameterCurve {
      case .constantU, .constantV, .affine, .harmonic: break
      default: return false
      }
      switch lift.surface {
      case .plane, .cylinder,
        .analytic(.plane), .analytic(.cylinder), .analytic(.sphere),
        .analytic(.cone), .analytic(.torus):
        return true
      default: return false
      }
    default:
      // A union jet does not establish smoothness across a lifted source join.
      return false
    }
  }

  private func originalCell(
    prepared: PreparedCurveDifferentialEncloser,
    interval: ScalarInterval, depth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Cell {
    guard let callerMaximumDepth, let callerMaximumSpans else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original arc-length cells require their invocation allowance.")
    }
    guard depth <= callerMaximumDepth else {
      throw KernelError(
        phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Original integration cell exceeds retained subdivision policy.")
    }
    try execution.visitGeometricCell(depth: depth)
    let remaining = callerMaximumDepth - depth
    // FIXME(INCOMPLETE_IMPLEMENTATION): The byte-admitted arc route forwards
    // actual native jet scratch/result bytes alongside owned integration buffers.
    // Supported implicit owning-cell bytes now use the original lower port.
    // General family temporary admission and cross-owner smoothness still
    // need their actual producers; no aggregate hull closes those source gaps.
    let receipt = try execution.withGeometricDepthOffset(depth) { execution in
      try prepared.closedNativeJets(
        over: interval, tolerance: tolerance,
        maximumSpanCount: callerMaximumSpans, maximumSubdivisionDepth: remaining,
        remainingSourceDepth: callerSourceDepth ?? remaining, using: &execution)
    }
    func magnitude(
      _ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
      _ z: OutwardScalarInterval
    ) -> OutwardScalarInterval {
      let vector = IntervalVector3DBounds(x: x, y: y, z: z)
      return OutwardScalarInterval(
        lower: vector.lengthLowerBound,
        upper: vector.lengthUpperBound)
    }
    var speedLower = Double.infinity
    var speedUpper = 0.0
    var second = 0.0
    var third = 0.0
    var owningCount = 0
    for span in receipt.spans {
      try consume(depth, tolerance: tolerance, using: &execution)
      let jet = span.jet
      let speed = magnitude(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU)
      speedLower = min(speedLower, speed.lower)
      speedUpper = max(speedUpper, speed.upper)
      second = max(
        second,
        magnitude(
          jet.x.secondDerivativeUU,
          jet.y.secondDerivativeUU, jet.z.secondDerivativeUU
        ).upper)
      third = max(
        third,
        magnitude(
          jet.x.thirdDerivativeUUU,
          jet.y.thirdDerivativeUUU, jet.z.thirdDerivativeUUU
        ).upper)
      if span.parameters.width > 0 { owningCount += 1 }
    }
    let width = OutwardScalarInterval.exact(interval.upper) - .exact(interval.lower)
    var length = OutwardScalarInterval(lower: speedLower, upper: speedUpper) * width
    // A whole-cell Taylor estimate is valid only within one smooth native owner.
    let smooth: Bool
    if let mapped = try mappedChartSmoothness(
      prepared.curve, over: interval,
      depth: depth, tolerance: tolerance, using: &execution)
    {
      smooth = mapped
    } else {
      if owningCount == 1 {
        smooth = try hasSmoothTaylorAuthority(
          prepared.curve, depth: depth, tolerance: tolerance, using: &execution)
      } else {
        smooth = false
      }
    }
    if smooth, speedLower > 0, second.isFinite, third.isFinite {
      let middle = OutwardScalarInterval.exact(interval.lower) + width * .exact(0.5)
      let singleton = try execution.withGeometricDepthOffset(depth) { execution in
        try prepared.closedNativeJets(
          over: ScalarInterval(lower: middle.lower, upper: middle.upper), tolerance: tolerance,
          maximumSpanCount: callerMaximumSpans, maximumSubdivisionDepth: remaining,
          remainingSourceDepth: callerSourceDepth ?? remaining, using: &execution)
      }
      var middleLower = Double.infinity
      var middleUpper = 0.0
      for span in singleton.spans {
        try consume(depth, tolerance: tolerance, using: &execution)
        let jet = span.jet
        let value = magnitude(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU)
        middleLower = min(middleLower, value.lower)
        middleUpper = max(middleUpper, value.upper)
      }
      guard
        let acceleration = (OutwardScalarInterval.exact(second) * .exact(second))
          .divided(by: .exact(speedLower))
      else {
        throw KernelError(
          phase: .geometry, code: .intersectionFailure,
          tolerance: tolerance, message: "Original arc-length speed lower bound is singular.")
      }
      let curvature = acceleration + .exact(third)
      let error = (curvature * width * width * width)
        .divided(by: .exact(24))
      if let error, error.isFinite {
        let estimate = OutwardScalarInterval(lower: middleLower, upper: middleUpper) * width
        let taylor = OutwardScalarInterval(
          lower: (estimate.lower - error.upper).nextDown,
          upper: (estimate.upper + error.upper).nextUp)
        if let tighter = length.intersection(with: taylor) {
          length = tighter
        } else {
          throw KernelError(
            phase: .geometry, code: .intersectionFailure,
            tolerance: tolerance, message: "Original arc-length bounds disagree.")
        }
      }
    }
    guard length.isFinite, length.upper >= 0 else {
      throw KernelError(
        phase: .geometry, code: .resourceLimitExceeded,
        tolerance: tolerance, message: "Original arc-length cell bounds are nonfinite.")
    }
    return Cell(
      interval: interval, lowerBound: max(0, length.lower),
      upperBound: max(0, length.upper), depth: depth)
  }

}
