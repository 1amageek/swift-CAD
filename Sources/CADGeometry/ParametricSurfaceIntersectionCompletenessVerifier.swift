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
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
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
    try execution.consumeWork(1)
    try execution.retainStorage(count: 1, stride: MemoryLayout<SearchBox>.stride)
    try execution.consumeWork(1)
    try execution.retainStorage(
      count: 4, stride: MemoryLayout<(Double, Double)>.stride + MemoryLayout<Int>.stride)
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
    remainingRootAttempts: inout Int, using execution: inout OriginalQueryExecution
  ) throws -> Result {
    if atlas.count > knownAtlasRecordCount {
      try execution.consumeWork(1)
      try execution.retainStorage(count: deferred.count, stride: MemoryLayout<SearchBox>.stride)
      let restored = try deferred.map { item in
        try execution.consumeWork(1)
        return item.searchBox
      }
      pending.insert(contentsOf: restored, at: 0)
      deferred.removeAll(keepingCapacity: true)
      knownAtlasRecordCount = atlas.count
    }
    while let searchBox = pending.popLast() {
      try execution.consumeWork(1)
      switch try inspect(
        searchBox: searchBox,
        atlas: atlas,
        remainingCells: &remainingCells,
        remainingRootAttempts: &remainingRootAttempts, using: &execution)
      {
      case .covered:
        continue
      case .uncoveredSeed(let seed):
        // The current box may contain more than the discovered
        // component. Revisit it after the caller extends the atlas.
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<SearchBox>.stride)
        pending.append(searchBox)
        return .uncoveredSeed(seed)
      case .unresolved(let reason):
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<DeferredSearchBox>.stride)
        deferred.append(
          DeferredSearchBox(
            searchBox: searchBox,
            reason: reason
          ))
        continue
      case .continueWith(let children):
        try execution.consumeWork(1)
        try execution.retainStorage(count: children.count, stride: MemoryLayout<SearchBox>.stride)
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
    remainingRootAttempts: inout Int, using execution: inout OriginalQueryExecution
  ) throws -> SearchStep {
    guard remainingCells > 0 else {
      throw resourceLimit(
        "Parametric surface-intersection completeness exhausted its subdivision-cell limit. Atlas records=\(atlas.count), remaining root attempts=\(remainingRootAttempts), depths=\(searchBox.subdivisionDepths), normalized bounds=\(searchBox.normalizedBounds). \(try atlasDiagnostic(searchBox: searchBox, atlas: atlas, using: &execution))"
      )
    }
    try execution.visitGeometricCell(depth: searchBox.subdivisionDepths.max() ?? 0)
    remainingCells -= 1
    let parameterBox = try actualParameterBox(
      normalizedBounds: searchBox.normalizedBounds, using: &execution)
    if try atlas.contains(where: {
      try execution.consumeWork(1)
      return contains($0.parameterBox, parameterBox)
    }) {
      return .covered
    }

    try parameterBox.validate(first: first, second: second, tolerance: tolerance)
    let firstJet: SurfaceIntervalVectorJet
    do {
      firstJet = try (preparedFirstSurface).intervalJet(
        overClosedBox: SurfaceParameterBox(u: parameterBox.firstU, v: parameterBox.firstV),
        tolerance: tolerance, using: &execution)
    } catch let error as KernelError
      where error.code == .singularSystem
      || error.code == .intersectionFailure
    {
      return try subdivideOrReport(
        searchBox: searchBox,
        reason: error.message,
        atlas: atlas,
        atlasDiagnostic: try atlasDiagnostic(
          searchBox: searchBox,
          atlas: atlas, using: &execution),
        restrictedTo: preparedFirstSurface.enclosureRefinementCoordinates, using: &execution)
    }
    let secondJet: SurfaceIntervalVectorJet
    do {
      secondJet = try (preparedSecondSurface).intervalJet(
        overClosedBox: SurfaceParameterBox(u: parameterBox.secondU, v: parameterBox.secondV),
        tolerance: tolerance, using: &execution)
    } catch let error as KernelError
      where error.code == .singularSystem || error.code == .intersectionFailure
    {
      return try subdivideOrReport(
        searchBox: searchBox, reason: error.message, atlas: atlas,
        atlasDiagnostic: try atlasDiagnostic(searchBox: searchBox, atlas: atlas, using: &execution),
        restrictedTo: (preparedSecondSurface.enclosureRefinementCoordinates.lowerBound + 2)..<(preparedSecondSurface
          .enclosureRefinementCoordinates.upperBound + 2), using: &execution)
    }
    let prover = ParametricSurfaceIntersectionGraphProver(
      firstSurface: first, secondSurface: second, parameterBox: parameterBox,
      firstJet: firstJet, secondJet: secondJet, using: &execution,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
    if prover.excludesIntersection() { return .covered }

    let freeParameters = try prover.rankCertifiedFreeParameters(using: &execution)
    var contractions: [Contraction] = []
    for freeParameter in freeParameters {
      try execution.consumeWork(1)
      switch try prover.parameterizedGraphCertificate(
        freeParameter: freeParameter,
        tolerance: tolerance, using: &execution)
      {
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
      let contracted = try contractedSearchBox(
        searchBox,
        using: contraction, using: &execution)
      if let contracted {
        let contractedParameterBox = try actualParameterBox(
          normalizedBounds: contracted.normalizedBounds, using: &execution)
        if try atlas.contains(where: {
          try execution.consumeWork(1)
          return contains($0.parameterBox, contractedParameterBox)
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
      remainingRootAttempts: &remainingRootAttempts, using: &execution)
    {
      return .uncoveredSeed(seed)
    }

    if let contraction = contractions.max(by: {
      $0.reduction < $1.reduction
    }),
      let contracted = try contractedSearchBox(
        searchBox,
        using: contraction, using: &execution)
    {
      return .continueWith([contracted])
    }
    return try subdivideOrReport(
      searchBox: searchBox,
      reason:
        "The interval root set was neither excluded, atlas-covered, nor certified as a regular graph.",
      atlas: atlas,
      atlasDiagnostic: try atlasDiagnostic(
        searchBox: searchBox,
        atlas: atlas, using: &execution), using: &execution)
  }

  private func certifiedSeed(
    searchBox: SearchBox,
    prover: ParametricSurfaceIntersectionGraphProver,
    freeParameters: [SurfaceIntersectionParameterCoordinate],
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    remainingRootAttempts: inout Int, using execution: inout OriginalQueryExecution
  ) throws -> Sample? {
    for freeParameter in freeParameters {
      try execution.consumeWork(1)
      let freeIndex = freeParameter.rawValue
      let freeBounds = searchBox.normalizedBounds[freeIndex]
      for fraction in [0.5, 0.0, 1.0] {
        try execution.consumeWork(1)
        guard
          case .uniqueRoot(let localParameters) =
            try prover
            .gaugeCertificate(
              freeParameter: freeParameter,
              atNormalizedFraction: fraction,
              tolerance: tolerance, using: &execution)
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
            constraints: searchBox.normalizedBounds, using: &execution)
        else {
          continue
        }
        let parameterPair = try SurfaceIntersectionParameterPair(
          values: root.actual
        )
        if try atlas.contains(where: {
          try execution.consumeWork(1)
          return $0.parameterBox.contains(parameterPair)
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
      tolerance: tolerance,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
  }

  private func subdivideOrReport(
    searchBox: SearchBox,
    reason: String,
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    atlasDiagnostic: String,
    restrictedTo coordinates: Range<Int>? = nil, using execution: inout OriginalQueryExecution
  ) throws -> SearchStep {
    let atlasSplit =
      coordinates == nil
      ? try atlasAlignedSplit(
        searchBox: searchBox,
        atlas: atlas, using: &execution) : nil
    guard
      let splitIndex = atlasSplit?.index
        ?? splitIndex(for: searchBox, among: coordinates ?? 0..<4, using: &execution)
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
    try execution.consumeWork(1)
    try execution.retainStorage(count: 2, stride: MemoryLayout<SearchBox>.stride)
    let children = try [
      (lower: bounds.lower, upper: middle),
      (lower: middle, upper: bounds.upper),
    ].map { child -> SearchBox in
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: 4, stride: MemoryLayout<(Double, Double)>.stride + MemoryLayout<Int>.stride)
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
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    using execution: inout OriginalQueryExecution
  ) throws -> (index: Int, value: Double)? {
    let midpoint = searchBox.normalizedBounds.map {
      $0.lower + ($0.upper - $0.lower) * 0.5
    }
    var candidates: [(index: Int, value: Double, score: Double)] = []
    var greatestOverlap = 0.0
    for record in atlas {
      try execution.consumeWork(1)
      let normalizedLower = try domains.normalized(
        record.parameterBox.intervals.map({ $0.lower }), using: &execution)
      let normalizedUpper = try domains.normalized(
        record.parameterBox.intervals.map({ $0.upper }), using: &execution)
      // A disjoint atlas cell cannot cover either child of this box.
      guard
        searchBox.normalizedBounds.indices.allSatisfy({ index in
          let search = searchBox.normalizedBounds[index]
          return normalizedLower[index] <= search.upper
            && normalizedUpper[index] >= search.lower
        })
      else { continue }
      let overlap = searchBox.normalizedBounds.indices.reduce(1.0) { product, index in
        let search = searchBox.normalizedBounds[index]
        let width =
          min(search.upper, normalizedUpper[index])
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
    atlas: [ParametricSurfaceIntersectionGraphCellRecord],
    using execution: inout OriginalQueryExecution
  ) throws -> String {
    guard atlas.isEmpty == false else { return "The graph atlas is empty." }
    let candidates = try atlas.map { record -> (gap: Double, bounds: [Double]) in
      try execution.consumeWork(1)
      let normalizedLower = try domains.normalized(
        record.parameterBox.intervals.map({ $0.lower }), using: &execution)
      let normalizedUpper = try domains.normalized(
        record.parameterBox.intervals.map({ $0.upper }), using: &execution)
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

  private func splitIndex(
    for searchBox: SearchBox, among coordinates: Range<Int>,
    using execution: inout OriginalQueryExecution
  ) -> Int? {
    let eligible = coordinates.filter { index in
      searchBox.subdivisionDepths[index]
        < min(options.maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
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
    using contraction: Contraction, using execution: inout OriginalQueryExecution
  ) throws -> SearchBox? {
    try execution.consumeWork(1)
    try execution.retainStorage(count: 4, stride: MemoryLayout<(Double, Double)>.stride)
    var bounds = searchBox.normalizedBounds
    let proofBox = try actualParameterBox(
      normalizedBounds: searchBox.normalizedBounds, using: &execution)
    var reduction = 0.0
    for index in bounds.indices {
      try execution.consumeWork(1)
      let original = searchBox.normalizedBounds[index]
      let width = original.upper - original.lower
      let local = contraction.localBounds[index]
      guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
        throw GeometryConversionError.invalidInput(
          "Original SSI contraction lost its chart coordinate.")
      }
      let native = proofBox.interval(for: coordinate)
      let actual =
        OutwardScalarInterval.exact(native.lower)
        + (OutwardScalarInterval.exact(native.upper) - .exact(native.lower))
        * OutwardScalarInterval(lower: local.lower, upper: local.upper)
      let normalized = try domains.originalNormalizedBounds(
        actual, coordinate: index, using: &execution)
      let lower = max(original.lower, normalized.lower)
      let upper = min(original.upper, normalized.upper)
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
    normalizedBounds: [(lower: Double, upper: Double)],
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterBox {
    try domains.actualParameterBox(normalizedBounds: normalizedBounds, using: &execution)
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
