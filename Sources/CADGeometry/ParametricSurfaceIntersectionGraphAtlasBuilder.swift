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
  private let preparedFirstSurface: PreparedSurfaceDifferentialEncloser
  private let preparedSecondSurface: PreparedSurfaceDifferentialEncloser

  init(
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    domains: BoundedSurfaceParameterDomainMap,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    first = preparedFirstSurface.surface
    second = preparedSecondSurface.surface
    self.domains = domains
    self.options = options
    self.tolerance = tolerance
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
    var entries = try cover(
      component: component,
      range: 0...(component.count - 1),
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts
    )
    guard entries.count >= 2 else { return entries }
    for index in 1..<entries.count {
      let handoff = entries[index].componentRange.lowerBound
      let lower = max(handoff - 1, 0)
      let upper = min(handoff + 1, component.count - 1)
      guard upper - lower >= 2,
        remainingCellAttempts > 0
      else {
        continue
      }
      remainingCellAttempts -= 1
      if let bridge = try certifiedEntry(
        component: component,
        range: lower...upper,
        remainingRootAttempts: &remainingRootAttempts
      ) {
        let previous = entries[index - 1]
        entries[index - 1] = Entry(
          record: previous.record,
          cell: previous.cell,
          direction: previous.direction,
          componentRange: previous.componentRange,
          coverageRecords: previous.coverageRecords + [bridge.record]
        )
      }
    }
    return entries
  }

  private func cover(
    component: [Sample],
    range: ClosedRange<Int>,
    remainingRootAttempts: inout Int,
    remainingCellAttempts: inout Int
  ) throws -> [Entry] {
    guard remainingCellAttempts > 0 else {
      throw resourceLimit(
        "Surface intersection graph-atlas certification exhausted its cell-attempt limit."
      )
    }
    remainingCellAttempts -= 1
    if let entry = try certifiedEntry(
      component: component,
      range: range,
      remainingRootAttempts: &remainingRootAttempts
    ) {
      return [entry]
    }
    guard range.upperBound - range.lowerBound > 1 else {
      throw failure(
        "A traced surface-intersection segment could not be enclosed by a full-graph interval certificate."
      )
    }
    let middle =
      range.lowerBound
      + (range.upperBound - range.lowerBound) / 2
    let lower = try cover(
      component: component,
      range: range.lowerBound...middle,
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts
    )
    let upper = try cover(
      component: component,
      range: middle...range.upperBound,
      remainingRootAttempts: &remainingRootAttempts,
      remainingCellAttempts: &remainingCellAttempts
    )
    return lower + upper
  }

  private func certifiedEntry(
    component: [Sample],
    range: ClosedRange<Int>,
    remainingRootAttempts: inout Int
  ) throws -> Entry? {
    let samples = Array(component[range])
    let candidates = monotoneFreeParameters(in: samples)
    for freeParameter in candidates {
      if let entry = try certifiedEntry(
        component: component,
        range: range,
        freeParameter: freeParameter,
        remainingRootAttempts: &remainingRootAttempts
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
    remainingRootAttempts: inout Int
  ) throws -> Entry? {
    let samples = Array(component[range])
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
    guard freeUpper - freeLower > tolerance.relative * 4.0 else {
      return nil
    }

    // Prefer the widest reproducible proof tube. A narrow cell may prove
    // the traced samples but leave interval-rounding slivers for the
    // subsequent global completeness sweep.
    for marginScale in [2.0, 1.0, 0.5, 0.25, 0.125] {
      var normalizedBounds = parameterBounds(
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
          $0.upper - $0.lower > tolerance.relative * 4.0
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
          tolerance: tolerance
        )
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
      tolerance: tolerance
    )
  }

  private func monotoneFreeParameters(
    in samples: [Sample]
  ) -> [SurfaceIntersectionParameterCoordinate] {
    let candidates:
      [(
        coordinate: SurfaceIntersectionParameterCoordinate,
        span: Double
      )] = SurfaceIntersectionParameterCoordinate.allCases.compactMap { coordinate in
        let index = coordinate.rawValue
        let values = samples.map { $0.normalized[index] }
        guard let lower = values.min(),
          let upper = values.max(),
          upper - lower > tolerance.relative * 4.0
        else {
          return nil
        }
        let nondecreasing = zip(values, values.dropFirst()).allSatisfy {
          $0.1 >= $0.0 - tolerance.relative
        }
        let nonincreasing = zip(values, values.dropFirst()).allSatisfy {
          $0.1 <= $0.0 + tolerance.relative
        }
        guard nondecreasing || nonincreasing else { return nil }
        return (coordinate: coordinate, span: upper - lower)
      }
    return candidates.sorted { first, second in
      if first.span != second.span { return first.span > second.span }
      return first.coordinate.rawValue < second.coordinate.rawValue
    }.map(\.coordinate)
  }

  private func parameterBounds(
    samples: [Sample],
    freeParameterIndex: Int,
    marginScale: Double
  ) -> [(lower: Double, upper: Double)] {
    let freeValues = samples.map { $0.normalized[freeParameterIndex] }
    let freeSpan =
      (freeValues.max() ?? 0.0)
      - (freeValues.min() ?? 0.0)
    return samples[0].normalized.indices.map { index in
      let values = samples.map { $0.normalized[index] }
      let lower = values.min() ?? 0.0
      let upper = values.max() ?? 1.0
      let observedSpan = upper - lower
      let margin = max(
        observedSpan * marginScale,
        freeSpan * marginScale * 0.25,
        tolerance.relative * 32.0
      )
      return (
        lower: max(0.0, (lower - margin).nextDown),
        upper: min(1.0, (upper + margin).nextUp)
      )
    }
  }

  private func actualParameterBox(
    normalizedBounds: [(lower: Double, upper: Double)]
  ) throws -> SurfaceIntersectionParameterBox {
    let lower = domains.actual(normalizedBounds.map(\.lower))
    let upper = domains.actual(normalizedBounds.map(\.upper))
    return SurfaceIntersectionParameterBox(
      firstU: try ScalarInterval(lower: lower[0], upper: upper[0]),
      firstV: try ScalarInterval(lower: lower[1], upper: upper[1]),
      secondU: try ScalarInterval(lower: lower[2], upper: upper[2]),
      secondV: try ScalarInterval(lower: lower[3], upper: upper[3])
    )
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
