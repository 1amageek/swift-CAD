import CADCore

/// Proves that every zero of a bounded regular surface pair is represented by
/// an existing graph atlas, or returns one certified seed outside that atlas.
/// The search contracts the zero set before subdivision and never interprets
/// an unresolved leaf as empty.
struct ParametricSurfaceIntersectionCompletenessVerifier: Sendable {
  typealias Sample = ParametricSurfaceIntersectionSample

  enum Result: Sendable {
    case complete
    case uncoveredSeed(Sample)
    case unresolved(String)
  }

  private enum SearchStep: Sendable {
    case covered
    case uncoveredSeed(Sample)
    case unresolved(String)
    case continueWith([SearchBox])
  }

  private struct SearchBox: Sendable {
    let normalizedBounds: [(lower: Double, upper: Double)]
    let subdivisionDepths: [Int]
    let preferredSplitIndex: Int?
  }

  private struct DeferredSearchBox: Sendable {
    let searchBox: SearchBox
    let reason: String
  }

  private struct Contraction: Sendable {
    let freeParameter: SurfaceIntersectionParameterCoordinate
    let localBounds: [(lower: Double, upper: Double)]
    let fullGraph: Bool

    var reduction: Double {
      localBounds.reduce(0.0) {
        $0 + 1.0 - ($1.upper - $1.lower)
      }
    }
  }

  let first: Surface3D
  let second: Surface3D
  let domains: BoundedSurfaceParameterDomainMap
  let options: SurfaceSurfaceIntersectionOptions
  let tolerance: ModelingTolerance
  private let preparedFirstSurface: PreparedSurfaceDifferentialEncloser
  private let preparedSecondSurface: PreparedSurfaceDifferentialEncloser

  private var pending: [SearchBox]
  private var deferred: [DeferredSearchBox]
  private var knownAtlasRecordCount: Int

  init(
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    domains: BoundedSurfaceParameterDomainMap,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws {
    let first = preparedFirstSurface.surface
    let second = preparedSecondSurface.surface
    self.first = first
    self.second = second
    self.domains = domains
    self.options = options
    self.tolerance = tolerance
    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
    pending = [
      SearchBox(
        normalizedBounds: Array(
          repeating: (lower: 0.0, upper: 1.0),
          count: 4
        ),
        subdivisionDepths: Array(repeating: 0, count: 4),
        preferredSplitIndex: nil
      )
    ]
    deferred = []
    knownAtlasRecordCount = 0
  }

  mutating func firstUncoveredSeed(
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    remainingCells: inout Int,
    remainingRootAttempts: inout Int
  ) throws -> Result {
    if atlas.count > knownAtlasRecordCount {
      pending.insert(
        contentsOf: deferred.map(\.searchBox),
        at: 0
      )
      deferred.removeAll(keepingCapacity: true)
      knownAtlasRecordCount = atlas.count
    }
    while let searchBox = pending.popLast() {
      switch try inspect(
        searchBox: searchBox,
        atlas: atlas,
        remainingCells: &remainingCells,
        remainingRootAttempts: &remainingRootAttempts
      ) {
      case .covered:
        continue
      case .uncoveredSeed(let seed):
        // The current box may contain more than the discovered
        // component. Revisit it after the caller extends the atlas.
        pending.append(searchBox)
        return .uncoveredSeed(seed)
      case .unresolved(let reason):
        deferred.append(
          DeferredSearchBox(
            searchBox: searchBox,
            reason: reason
          ))
        continue
      case .continueWith(let children):
        pending.append(contentsOf: children.reversed())
      }
    }
    if let firstUnresolved = deferred.first {
      return .unresolved(firstUnresolved.reason)
    }
    return .complete
  }

  private func inspect(
    searchBox: SearchBox,
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    remainingCells: inout Int,
    remainingRootAttempts: inout Int
  ) throws -> SearchStep {
    guard remainingCells > 0 else {
      throw resourceLimit(
        "Parametric surface-intersection completeness exhausted its subdivision-cell limit. Atlas records=\(atlas.count), remaining root attempts=\(remainingRootAttempts), depths=\(searchBox.subdivisionDepths), normalized bounds=\(searchBox.normalizedBounds). \(atlasDiagnostic(searchBox: searchBox, atlas: atlas))"
      )
    }
    remainingCells -= 1
    let parameterBox = try actualParameterBox(
      normalizedBounds: searchBox.normalizedBounds
    )
    if atlas.contains(where: {
      contains($0.parameterBox, parameterBox)
    }) {
      return .covered
    }

    try parameterBox.validate(first: first, second: second, tolerance: tolerance)
    let firstJet: SurfaceIntervalVectorJet
    do {
      firstJet = try preparedFirstSurface.intervalJet(
        over: SurfaceParameterBox(u: parameterBox.firstU, v: parameterBox.firstV),
        tolerance: tolerance)
    } catch let error as KernelError
      where error.code == .singularSystem
      || error.code == .intersectionFailure
    {
      return subdivideOrReport(
        searchBox: searchBox,
        reason: error.message,
        atlas: atlas,
        atlasDiagnostic: atlasDiagnostic(
          searchBox: searchBox,
          atlas: atlas
        ),
        restrictedTo: preparedFirstSurface.enclosureRefinementCoordinates
      )
    }
    let secondJet: SurfaceIntervalVectorJet
    do {
      secondJet = try preparedSecondSurface.intervalJet(
        over: SurfaceParameterBox(u: parameterBox.secondU, v: parameterBox.secondV),
        tolerance: tolerance)
    } catch let error as KernelError
      where error.code == .singularSystem || error.code == .intersectionFailure
    {
      return subdivideOrReport(
        searchBox: searchBox, reason: error.message, atlas: atlas,
        atlasDiagnostic: atlasDiagnostic(searchBox: searchBox, atlas: atlas),
        restrictedTo: (preparedSecondSurface.enclosureRefinementCoordinates.lowerBound + 2)..<(preparedSecondSurface.enclosureRefinementCoordinates.upperBound + 2)
      )
    }
    let prover = ParametricSurfaceIntersectionGraphProver(
      firstSurface: first, secondSurface: second, parameterBox: parameterBox,
      firstJet: firstJet, secondJet: secondJet
    )
    if prover.excludesIntersection() { return .covered }

    let freeParameters = prover.rankCertifiedFreeParameters()
    var contractions: [Contraction] = []
    for freeParameter in freeParameters {
      switch try prover.parameterizedGraphCertificate(
        freeParameter: freeParameter,
        tolerance: tolerance
      ) {
      case .empty:
        return .covered
      case .fullGraph(let localBounds):
        contractions.append(
          Contraction(
            freeParameter: freeParameter,
            localBounds: localBounds,
            fullGraph: true
          ))
      case .contracted(let localBounds):
        contractions.append(
          Contraction(
            freeParameter: freeParameter,
            localBounds: localBounds,
            fullGraph: false
          ))
      case .unresolved:
        continue
      }
    }
    for contraction in contractions.sorted(by: {
      $0.reduction > $1.reduction
    }) {
      let contracted = contractedSearchBox(
        searchBox,
        using: contraction
      )
      if let contracted {
        let contractedParameterBox = try actualParameterBox(
          normalizedBounds: contracted.normalizedBounds
        )
        if atlas.contains(where: {
          contains($0.parameterBox, contractedParameterBox)
        }) {
          return .covered
        }
      }
    }

    let orderedFreeParameters = freeParameters.sorted { first, second in
      let firstFull = contractions.contains {
        $0.freeParameter == first && $0.fullGraph
      }
      let secondFull = contractions.contains {
        $0.freeParameter == second && $0.fullGraph
      }
      if firstFull != secondFull { return firstFull }
      return first.rawValue < second.rawValue
    }
    if let seed = try certifiedSeed(
      searchBox: searchBox,
      prover: prover,
      freeParameters: orderedFreeParameters,
      atlas: atlas,
      remainingRootAttempts: &remainingRootAttempts
    ) {
      return .uncoveredSeed(seed)
    }

    if let contraction = contractions.max(by: {
      $0.reduction < $1.reduction
    }),
      let contracted = contractedSearchBox(
        searchBox,
        using: contraction
      )
    {
      return .continueWith([contracted])
    }
    return subdivideOrReport(
      searchBox: searchBox,
      reason:
        "The interval root set was neither excluded, atlas-covered, nor certified as a regular graph.",
      atlas: atlas,
      atlasDiagnostic: atlasDiagnostic(
        searchBox: searchBox,
        atlas: atlas
      )
    )
  }

  private func certifiedSeed(
    searchBox: SearchBox,
    prover: ParametricSurfaceIntersectionGraphProver,
    freeParameters: [SurfaceIntersectionParameterCoordinate],
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    remainingRootAttempts: inout Int
  ) throws -> Sample? {
    for freeParameter in freeParameters {
      let freeIndex = freeParameter.rawValue
      let freeBounds = searchBox.normalizedBounds[freeIndex]
      for fraction in [0.5, 0.0, 1.0] {
        guard
          case .uniqueRoot(let localParameters) =
            try prover
            .gaugeCertificate(
              freeParameter: freeParameter,
              atNormalizedFraction: fraction,
              tolerance: tolerance
            )
        else {
          continue
        }
        guard remainingRootAttempts > 0 else {
          throw resourceLimit(
            "Parametric surface-intersection completeness exhausted its root-attempt limit. Atlas records=\(atlas.count), free coordinate=\(freeParameter), depths=\(searchBox.subdivisionDepths), normalized bounds=\(searchBox.normalizedBounds)."
          )
        }
        remainingRootAttempts -= 1
        let seed = zip(
          localParameters,
          searchBox.normalizedBounds
        ).map { local, bounds in
          bounds.lower + (bounds.upper - bounds.lower) * local
        }
        var fixedSeed = seed
        fixedSeed[freeIndex] =
          freeBounds.lower
          + (freeBounds.upper - freeBounds.lower) * fraction
        guard
          let root = try rootRefiner.gaugeRoot(
            seed: fixedSeed,
            fixedParameterIndex: freeIndex,
            constraints: searchBox.normalizedBounds
          )
        else {
          continue
        }
        let parameterPair = try SurfaceIntersectionParameterPair(
          values: root.actual
        )
        if atlas.contains(where: {
          $0.parameterBox.contains(parameterPair)
        }) == false {
          return root
        }
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

  private func subdivideOrReport(
    searchBox: SearchBox,
    reason: String,
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    atlasDiagnostic: String,
    restrictedTo coordinates: Range<Int>? = nil
  ) -> SearchStep {
    let atlasSplit = coordinates == nil ? atlasAlignedSplit(
      searchBox: searchBox,
      atlas: atlas
    ) : nil
    guard
      let splitIndex = atlasSplit?.index
        ?? splitIndex(for: searchBox, among: coordinates ?? 0..<4)
    else {
      return .unresolved(
        "Normalized box \(searchBox.normalizedBounds.flatMap { [$0.lower, $0.upper] }) remained unresolved at depths \(searchBox.subdivisionDepths). \(reason) \(atlasDiagnostic)"
      )
    }
    let bounds = searchBox.normalizedBounds[splitIndex]
    let middle =
      atlasSplit?.value
      ?? bounds.lower + (bounds.upper - bounds.lower) * 0.5
    guard middle > bounds.lower, middle < bounds.upper else {
      return .unresolved(
        "Normalized subdivision collapsed in coordinate \(splitIndex)."
      )
    }
    let children = [
      (lower: bounds.lower, upper: middle),
      (lower: middle, upper: bounds.upper),
    ].map { child -> SearchBox in
      var childBounds = searchBox.normalizedBounds
      childBounds[splitIndex] = child
      var childDepths = searchBox.subdivisionDepths
      if atlasSplit == nil {
        childDepths[splitIndex] += 1
      }
      return SearchBox(
        normalizedBounds: childBounds,
        subdivisionDepths: childDepths,
        preferredSplitIndex: nil
      )
    }
    return .continueWith(children)
  }

  private func atlasAlignedSplit(
    searchBox: SearchBox,
    atlas: [ParametricSurfaceIntersectionGraphCellRecord]
  ) -> (index: Int, value: Double)? {
    let midpoint = searchBox.normalizedBounds.map {
      $0.lower + ($0.upper - $0.lower) * 0.5
    }
    var candidates: [(index: Int, value: Double, score: Double)] = []
    var greatestOverlap = 0.0
    for record in atlas {
      let normalizedLower = domains.normalized(
        record.parameterBox.intervals.map(\.lower)
      )
      let normalizedUpper = domains.normalized(
        record.parameterBox.intervals.map(\.upper)
      )
      // A disjoint atlas cell cannot cover either child of this box.
      guard searchBox.normalizedBounds.indices.allSatisfy({ index in
        let search = searchBox.normalizedBounds[index]
        return normalizedLower[index] <= search.upper
          && normalizedUpper[index] >= search.lower
      }) else { continue }
      let overlap = searchBox.normalizedBounds.indices.reduce(1.0) { product, index in
        let search = searchBox.normalizedBounds[index]
        let width = min(search.upper, normalizedUpper[index])
          - max(search.lower, normalizedLower[index])
        return product * max(0, width) / (search.upper - search.lower)
      }
      guard overlap > greatestOverlap else { continue }
      var recordCandidates: [(index: Int, value: Double, score: Double)] = []
      for index in searchBox.normalizedBounds.indices {
        let search = searchBox.normalizedBounds[index]
        for boundary in [normalizedLower[index], normalizedUpper[index]]
        where boundary > search.lower
          && boundary < search.upper
          && boundary - search.lower
            > tolerance.relative * 4.0
          && search.upper - boundary
            > tolerance.relative * 4.0
        {
          recordCandidates.append(
            (
              index: index,
              value: boundary,
              score: abs(boundary - midpoint[index])
            ))
        }
      }
      if recordCandidates.isEmpty == false {
        greatestOverlap = overlap
        candidates = recordCandidates
      }
    }
    return candidates.min(by: { $0.score < $1.score }).map {
      (index: $0.index, value: $0.value)
    }
  }

  private func atlasDiagnostic(
    searchBox: SearchBox,
    atlas: [ParametricSurfaceIntersectionGraphCellRecord]
  ) -> String {
    guard atlas.isEmpty == false else { return "The graph atlas is empty." }
    let candidates = atlas.map { record -> (gap: Double, bounds: [Double]) in
      let normalizedLower = domains.normalized(
        record.parameterBox.intervals.map(\.lower)
      )
      let normalizedUpper = domains.normalized(
        record.parameterBox.intervals.map(\.upper)
      )
      let gap = searchBox.normalizedBounds.indices.reduce(0.0) {
        partial, index in
        max(
          partial,
          normalizedLower[index]
            - searchBox.normalizedBounds[index].lower,
          searchBox.normalizedBounds[index].upper
            - normalizedUpper[index],
          0.0
        )
      }
      return (
        gap,
        zip(normalizedLower, normalizedUpper).flatMap {
          [$0.0, $0.1]
        }
      )
    }
    guard let nearest = candidates.min(by: { $0.gap < $1.gap }) else {
      return "The graph atlas has no comparable cell."
    }
    return "Nearest graph-cell containment gap=\(nearest.gap), bounds=\(nearest.bounds)."
  }

  private func splitIndex(for searchBox: SearchBox, among coordinates: Range<Int>) -> Int? {
    let eligible = coordinates.filter { index in
      searchBox.subdivisionDepths[index]
        < options.maximumSubdivisionDepth
        && searchBox.normalizedBounds[index].upper
          - searchBox.normalizedBounds[index].lower
          > tolerance.relative * 4.0
    }
    if let preferred = searchBox.preferredSplitIndex,
      eligible.contains(preferred)
    {
      return preferred
    }
    return eligible.max { first, second in
      let firstWidth =
        searchBox.normalizedBounds[first].upper
        - searchBox.normalizedBounds[first].lower
      let secondWidth =
        searchBox.normalizedBounds[second].upper
        - searchBox.normalizedBounds[second].lower
      if firstWidth != secondWidth { return firstWidth < secondWidth }
      return first < second
    }
  }

  private func contractedSearchBox(
    _ searchBox: SearchBox,
    using contraction: Contraction
  ) -> SearchBox? {
    var bounds = searchBox.normalizedBounds
    var reduction = 0.0
    for index in bounds.indices {
      let original = searchBox.normalizedBounds[index]
      let width = original.upper - original.lower
      let local = contraction.localBounds[index]
      let lower = max(
        original.lower,
        (original.lower + width * local.lower).nextDown
      )
      let upper = min(
        original.upper,
        (original.lower + width * local.upper).nextUp
      )
      guard lower.isFinite,
        upper.isFinite,
        upper - lower > tolerance.relative * 4.0
      else {
        return nil
      }
      reduction += width - (upper - lower)
      bounds[index] = (lower: lower, upper: upper)
    }
    let totalWidth = searchBox.normalizedBounds.reduce(0.0) {
      $0 + $1.upper - $1.lower
    }
    guard
      reduction
        > max(
          tolerance.relative * 16.0,
          totalWidth * 1.0e-3
        )
    else {
      return nil
    }
    let dependentSplit = bounds.indices
      .filter { $0 != contraction.freeParameter.rawValue }
      .max { first, second in
        let firstWidth = bounds[first].upper - bounds[first].lower
        let secondWidth = bounds[second].upper - bounds[second].lower
        return firstWidth < secondWidth
      }
    return SearchBox(
      normalizedBounds: bounds,
      subdivisionDepths: searchBox.subdivisionDepths,
      preferredSplitIndex: contraction.fullGraph
        ? contraction.freeParameter.rawValue
        : dependentSplit
    )
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

  private func contains(
    _ outer: SurfaceIntersectionParameterBox,
    _ inner: SurfaceIntersectionParameterBox
  ) -> Bool {
    zip(outer.intervals, inner.intervals).allSatisfy { outer, inner in
      inner.lower >= outer.lower && inner.upper <= outer.upper
    }
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
