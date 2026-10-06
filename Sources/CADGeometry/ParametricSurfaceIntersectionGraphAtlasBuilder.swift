import CADCore

/// Covers one already traced regular component with an ordered atlas of
/// interval-certified graph cells. Atlas construction follows the one-
/// dimensional component instead of enumerating the ambient four-dimensional
/// parameter product.
struct ParametricSurfaceIntersectionGraphAtlasBuilder: Sendable {
  typealias Sample = ParametricSurfaceIntersectionSample

  struct Entry: Sendable {
    let record: ParametricSurfaceIntersectionGraphCellRecord
    let cell: CertifiedImplicitIntersectionGraphCell
    let direction: CertifiedImplicitIntersectionDirection
    let componentRange: ClosedRange<Int>
    let coverageRecords: [ParametricSurfaceIntersectionGraphCellRecord]
  }

  let first: Surface3D
  let second: Surface3D
  let domains: BoundedSurfaceParameterDomainMap
  let options: SurfaceSurfaceIntersectionOptions
  let tolerance: ModelingTolerance
  let admission: SurfaceSurfaceQueryAdmission
  private let preparedFirstSurface: PreparedSurfaceDifferentialEncloser
  private let preparedSecondSurface: PreparedSurfaceDifferentialEncloser

  init(
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    domains: BoundedSurfaceParameterDomainMap,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    try tolerance.validate()
    first = preparedFirstSurface.surface
    second = preparedSecondSurface.surface
    self.domains = domains
    self.options = options
    self.tolerance = tolerance
    self.admission = admission
    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
  }

  func build(
    covering component: [Sample],
    remainingRootAttempts: inout Int,
    remainingCellAttempts: inout Int
  ) throws -> [Entry] {
    guard component.count >= 2 else {
      throw failure("A graph atlas requires a traced component.")
    }
    let covered = try cover(
      component: component,
      range: 0...(component.count - 1),
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts
    )
    guard covered.count >= 2 else { return covered }
    try admission.reserve(count: covered.count, stride: MemoryLayout<Entry>.stride)
    var entries: [Entry] = []
    entries.reserveCapacity(covered.count)
    for entry in covered { try admission.step(); entries.append(entry) }
    for index in 1..<entries.count {
      try admission.step()
      let handoff = entries[index].componentRange.lowerBound
      let lower = max(handoff - 1, 0)
      let upper = min(handoff + 1, component.count - 1)
      guard upper - lower >= 2,
        remainingCellAttempts > 0
      else {
        continue
      }
      try admission.step()
      remainingCellAttempts -= 1
      var rejection: String?
      if let bridge = try certifiedEntry(
        component: component,
        range: lower...upper,
        remainingRootAttempts: &remainingRootAttempts,
        rejection: &rejection
      ) {
        let previous = entries[index - 1]
        let count = previous.coverageRecords.count.addingReportingOverflow(1)
        guard !count.overflow else { throw resourceLimit("SSI coverage record count overflowed.") }
        try admission.reserve(count: count.partialValue,
          stride: MemoryLayout<ParametricSurfaceIntersectionGraphCellRecord>.stride)
        var coverage: [ParametricSurfaceIntersectionGraphCellRecord] = []
        coverage.reserveCapacity(count.partialValue)
        for record in previous.coverageRecords { try admission.step(); coverage.append(record) }
        coverage.append(bridge.record)
        entries[index - 1] = Entry(
          record: previous.record,
          cell: previous.cell,
          direction: previous.direction,
          componentRange: previous.componentRange,
          coverageRecords: coverage
        )
      }
    }
    return entries
  }

  private func cover(
    component: [Sample],
    range: ClosedRange<Int>,
    remainingRootAttempts: inout Int,
    remainingCellAttempts: inout Int,
    depth: Int = 0
  ) throws -> [Entry] {
    guard remainingCellAttempts > 0 else {
      throw resourceLimit(
        "Surface intersection graph-atlas certification exhausted its cell-attempt limit."
      )
    }
    try admission.step()
    remainingCellAttempts -= 1
    var rejection: String?
    if let entry = try certifiedEntry(
      component: component,
      range: range,
      remainingRootAttempts: &remainingRootAttempts,
      rejection: &rejection
    ) {
      try admission.reserve(count: 1, stride: MemoryLayout<Entry>.stride)
      return [entry]
    }
    guard range.upperBound - range.lowerBound > 1,
      depth < min(options.maximumBoundarySubdivisionDepth, admission.maximumSubdivisionDepth) else {
      throw failure(
        "A traced surface-intersection segment could not be enclosed by a full-graph interval certificate. First rejection: \(rejection ?? "No admissible monotone graph box or refined midpoint.")"
      )
    }
    let middle =
      range.lowerBound
      + (range.upperBound - range.lowerBound) / 2
    let lower = try cover(
      component: component,
      range: range.lowerBound...middle,
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts, depth: depth + 1
    )
    let upper = try cover(
      component: component,
      range: middle...range.upperBound,
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts, depth: depth + 1
    )
    let combinedCount = lower.count.addingReportingOverflow(upper.count)
    guard !combinedCount.overflow else { throw resourceLimit("SSI atlas entry count overflowed.") }
    try admission.reserve(count: combinedCount.partialValue, stride: MemoryLayout<Entry>.stride)
    var combined: [Entry] = []
    combined.reserveCapacity(combinedCount.partialValue)
    for entry in lower { try admission.step(); combined.append(entry) }
    for entry in upper { try admission.step(); combined.append(entry) }
    return combined
  }

  private func certifiedEntry(
    component: [Sample],
    range: ClosedRange<Int>,
    remainingRootAttempts: inout Int,
    rejection: inout String?
  ) throws -> Entry? {
    let samples = component[range]
    let candidates = try monotoneFreeParameters(in: samples)
    for freeParameter in candidates {
      try admission.step()
      if let entry = try certifiedEntry(
        component: component,
        range: range,
        freeParameter: freeParameter,
        remainingRootAttempts: &remainingRootAttempts,
        rejection: &rejection
      ) {
        return entry
      }
    }
    return nil
  }

  private func certifiedEntry(
    component: [Sample],
    range: ClosedRange<Int>,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    remainingRootAttempts: inout Int,
    rejection: inout String?
  ) throws -> Entry? {
    let samples = component[range]
    guard let componentStart = samples.first,
      let componentEnd = samples.last
    else {
      return nil
    }
    let freeIndex = freeParameter.rawValue
    let lowerSample: Sample
    let upperSample: Sample
    let direction: CertifiedImplicitIntersectionDirection
    if componentStart.normalized[freeIndex]
      <= componentEnd.normalized[freeIndex]
    {
      lowerSample = componentStart
      upperSample = componentEnd
      direction = .forward
    } else {
      lowerSample = componentEnd
      upperSample = componentStart
      direction = .reversed
    }
    let freeLower = lowerSample.normalized[freeIndex]
    let freeUpper = upperSample.normalized[freeIndex]
    guard freeLower.isFinite, freeUpper.isFinite, freeLower < freeUpper else {
      return nil
    }

    // Prefer the widest reproducible proof tube. A narrow cell may prove
    // the traced samples but leave interval-rounding slivers for the
    // subsequent global completeness sweep.
    for marginScale in [2.0, 1.0, 0.5, 0.25, 0.125] {
      try admission.step()
      var normalizedBounds = try parameterBounds(
        samples: samples,
        freeParameterIndex: freeIndex,
        marginScale: marginScale
      )
      normalizedBounds[freeIndex] = (
        lower: freeLower,
        upper: freeUpper
      )
      guard
        normalizedBounds.allSatisfy({
          $0.lower.isFinite && $0.upper.isFinite && $0.lower < $0.upper
        })
      else {
        continue
      }
      guard remainingRootAttempts > 0 else {
        throw resourceLimit(
          "Surface intersection graph-atlas certification exhausted its root-attempt limit."
        )
      }
      remainingRootAttempts -= 1
      let midpointFree = freeLower + (freeUpper - freeLower) * 0.5
      try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
      var midpointSeed = zip(
        lowerSample.normalized,
        upperSample.normalized
      ).map { ($0.0 + $0.1) * 0.5 }
      midpointSeed[freeIndex] = midpointFree
      guard
        let midpoint = try rootRefiner.gaugeRoot(
          seed: midpointSeed,
          fixedParameterIndex: freeIndex,
          constraints: normalizedBounds
        )
      else {
        continue
      }
      for index in normalizedBounds.indices where index != freeIndex {
        normalizedBounds[index] = (
          lower: min(
            normalizedBounds[index].lower,
            midpoint.normalized[index].nextDown
          ),
          upper: max(
            normalizedBounds[index].upper,
            midpoint.normalized[index].nextUp
          )
        )
      }
      let parameterBox = try actualParameterBox(
        normalizedBounds: normalizedBounds
      )
      let record = try ParametricSurfaceIntersectionGraphCellRecord(
        parameterBox: parameterBox,
        freeParameter: freeParameter,
        lowerAnchor: SurfaceIntersectionParameterPair(
          values: lowerSample.actual
        ),
        midpointAnchor: SurfaceIntersectionParameterPair(
          values: midpoint.actual
        ),
        upperAnchor: SurfaceIntersectionParameterPair(
          values: upperSample.actual
        )
      )
      do {
        let cell = try record.cell(
          direction: direction,
          first: preparedFirstSurface,
          second: preparedSecondSurface,
          tolerance: tolerance, admission: admission
        )
        try admission.reserve(count: 1,
          stride: MemoryLayout<ParametricSurfaceIntersectionGraphCellRecord>.stride)
        return Entry(
          record: record,
          cell: cell,
          direction: direction,
          componentRange: range,
          coverageRecords: [record]
        )
      } catch let error as KernelError
        where error.code == .intersectionFailure
        || error.code == .singularSystem
      {
        if rejection == nil {
          rejection = "Free coordinate \(freeParameter); anchors \(lowerSample.actual) -> \(upperSample.actual). \(error.message)"
        }
        continue
      }
    }
    return nil
  }

  private var rootRefiner: ParametricSurfaceIntersectionRootRefiner {
    ParametricSurfaceIntersectionRootRefiner(
      first: first,
      second: second,
      domains: domains,
      maximumIterations: options.maximumIterations,
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
  }

  private func monotoneFreeParameters(in samples: ArraySlice<Sample>) throws -> [SurfaceIntersectionParameterCoordinate] {
    try admission.reserve(count: 4,
      stride: MemoryLayout<(SurfaceIntersectionParameterCoordinate, Double)>.stride)
    var candidates: [(coordinate: SurfaceIntersectionParameterCoordinate, span: Double)] = []
    candidates.reserveCapacity(4)
    for coordinate in SurfaceIntersectionParameterCoordinate.allCases {
      let index = coordinate.rawValue
      guard let initial = samples.first?.normalized[index] else { continue }
      var lower = initial, upper = initial, previous = initial
      var nondecreasing = true, nonincreasing = true
      for sample in samples {
        try admission.step()
        let value = sample.normalized[index]
        lower = min(lower, value); upper = max(upper, value)
        nondecreasing = nondecreasing && value >= previous - tolerance.relative
        nonincreasing = nonincreasing && value <= previous + tolerance.relative
        previous = value
      }
      guard lower.isFinite, upper.isFinite, lower < upper, nondecreasing || nonincreasing else { continue }
      candidates.append((coordinate, upper - lower))
    }
    // At most four candidates: insertion order avoids an opaque sort scratch buffer.
    for index in candidates.indices.dropFirst() {
      var current = index
      while current > 0 {
        try admission.step()
        let first = candidates[current], second = candidates[current - 1]
        let precedes = first.span != second.span ? first.span > second.span
          : first.coordinate.rawValue < second.coordinate.rawValue
        if !precedes { break }
        candidates.swapAt(current, current - 1)
        current -= 1
      }
    }
    try admission.reserve(count: candidates.count,
      stride: MemoryLayout<SurfaceIntersectionParameterCoordinate>.stride)
    return candidates.map(\.coordinate)
  }

  private func parameterBounds(samples: ArraySlice<Sample>, freeParameterIndex: Int,
    marginScale: Double) throws -> [(lower: Double, upper: Double)] {
    guard let first = samples.first else { throw failure("SSI graph bounds require a sample.") }
    func range(_ index: Int) throws -> (lower: Double, upper: Double) {
      var lower = first.normalized[index], upper = lower
      for sample in samples {
        try admission.step()
        lower = min(lower, sample.normalized[index]); upper = max(upper, sample.normalized[index])
      }
      return (lower, upper)
    }
    let free = try range(freeParameterIndex)
    let freeSpan = free.upper - free.lower
    try admission.reserve(count: 4, stride: MemoryLayout<(Double, Double)>.stride)
    return try first.normalized.indices.map { index in
      let values = try range(index)
      let margin = max((values.upper - values.lower) * marginScale,
        freeSpan * marginScale * 0.25, tolerance.relative * 32)
      return (lower: max(0, (values.lower - margin).nextDown),
        upper: min(1, (values.upper + margin).nextUp))
    }
  }

  private func actualParameterBox(
    normalizedBounds: [(lower: Double, upper: Double)]
  ) throws -> SurfaceIntersectionParameterBox {
    try domains.actualParameterBox(normalizedBounds: normalizedBounds, admission: admission)
  }

  private func failure(_ message: String) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .intersectionFailure,
      tolerance: tolerance,
      message: message
    )
  }

  private func resourceLimit(_ message: String) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: tolerance,
      message: message
    )
  }
}
