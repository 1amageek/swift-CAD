import CADCore

/// Retains original homogeneous native-span enclosures of one immutable surface.
/// Whole periodic queries retain conservative original-cycle covers. Selected
/// tokens separately retain proved base spans and exact unwrapped cycle lifts.
package struct PreparedBSplineSurfaceDifferentialEncloser: Sendable {
  /// Existing aggregate span retention ceiling shared by every selected axis lift.
  package static let maximumOriginalNativeSpanCount = 262_144

  package let surface: BSplineSurface3D
  private let preparationTolerance: ModelingTolerance
  private let originalSpans: [OriginalNativeSpan]

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: false, consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
  }

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws {
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: true,
      consumeWork: consumeWork, consumeStorage: consumeStorage)
  }

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void, consumeStorage: (Int) throws -> Void) throws {
    self = try withoutActuallyEscaping(consumeStorage) { storage in
      try Self(surface: surface, tolerance: tolerance, chargePreparation: true,
        consumeWork: consumeWork, consumeStorage: storage)
    }
  }

  private init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
    chargePreparation: Bool, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws {
    guard surface.uDegree >= 0, surface.vDegree >= 0,
      surface.uDegree < surface.uControlPointCount, surface.vDegree < surface.vControlPointCount else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original surface degree dimensions do not admit native preparation.")
    }
    try surface.validate(tolerance: tolerance, consumeWork: consumeWork)
    try CurrentTaskCancellationChecker().checkCancellation()
    self.surface = surface
    self.preparationTolerance = tolerance
    let encloser = RationalBezierSurfaceJetEncloser()
    let decomposer = BSplineSurfaceBezierDecomposer()
    let singleBezier = try !surface.isUPeriodic && !surface.isVPeriodic
      && surface.uControlPointCount == surface.uDegree + 1
      && surface.vControlPointCount == surface.vDegree + 1
      && (try surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ try consumeWork(); return $0 == surface.uKnots[surface.uDegree] }))
      && (try surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ try consumeWork(); return $0 == surface.uKnots[surface.uControlPointCount] }))
      && (try surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ try consumeWork(); return $0 == surface.vKnots[surface.vDegree] }))
      && (try surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ try consumeWork(); return $0 == surface.vKnots[surface.vControlPointCount] }))
    if singleBezier {
      // These are the stored original controls, not a rounded extraction.
      let patch = RationalBezierSurfacePatch3D(controlPoints: surface.controlPoints, weights: surface.weights,
        uLower: surface.uKnots[surface.uDegree], uUpper: surface.uKnots[surface.uControlPointCount],
        vLower: surface.vKnots[surface.vDegree], vUpper: surface.vKnots[surface.vControlPointCount])
      try OriginalCoefficientAllocation.reserve(count: 1, of: OriginalNativeSpan.self, consumeStorage: consumeStorage)
      originalSpans = [OriginalNativeSpan(surface: surface, tolerance: tolerance,
        uSpanIndex: surface.uDegree, vSpanIndex: surface.vDegree,
        uBounds: try ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
        vBounds: try ScalarInterval(lower: patch.vLower, upper: patch.vUpper),
        patch: try encloser.prepare(patch, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage))]
    } else {
      let originals = try decomposer.originalHomogeneousPatches(surface: surface, tolerance: tolerance,
        consumeWork: consumeWork, consumeStorage: consumeStorage)
      try OriginalCoefficientAllocation.reserve(count: originals.count, of: OriginalNativeSpan.self, consumeStorage: consumeStorage)
      originalSpans = try originals.map {
        try consumeWork()
        return OriginalNativeSpan(surface: surface, tolerance: tolerance,
          uSpanIndex: $0.uSpanIndex, vSpanIndex: $0.vSpanIndex,
          uBounds: $0.uBounds, vBounds: $0.vBounds,
          patch: try encloser.prepare(original: $0, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage))
      }
    }
  }

  package func originalNativeSpans(over box: SurfaceParameterBox,
                                  tolerance: ModelingTolerance) throws -> [OriginalNativeSpan] {
    try originalNativeSpans(over: box, tolerance: tolerance, maximumSpanCount: Self.maximumOriginalNativeSpanCount)
  }

  /// Q3 preparation and queries pay original cover scans and token storage before allocation.
  package func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
                                  consumeWork: () throws -> Void) throws -> [OriginalNativeSpan] {
    try originalNativeSpans(over:box,tolerance:tolerance,maximumSpanCount:Self.maximumOriginalNativeSpanCount,consumeWork:consumeWork)
  }

  /// The selected-cover ceiling is shared by all axis lifts, not reset per cycle.
  func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
                           maximumSpanCount: Int) throws -> [OriginalNativeSpan] {
    try originalNativeSpans(over:box,tolerance:tolerance,maximumSpanCount:maximumSpanCount,consumeWork:{})
  }

  package func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
                                  maximumSpanCount: Int, consumeWork: () throws -> Void) throws -> [OriginalNativeSpan] {
    try originalNativeSpans(over: box, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      consumeWork: consumeWork, admittingStorage: nil)
  }

  package func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int, consumeWork: () throws -> Void,
    consumeStorage: (Int) throws -> Void) throws -> [OriginalNativeSpan] {
    try withoutActuallyEscaping(consumeStorage) { storage in
      try originalNativeSpans(over: box, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        consumeWork: consumeWork, admittingStorage: storage)
    }
  }

  private func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int, consumeWork: () throws -> Void,
    admittingStorage consumeStorage: ((Int) throws -> Void)?) throws -> [OriginalNativeSpan] {
    try tolerance.validate()
    try CurrentTaskCancellationChecker().checkCancellation()
    guard (1...Self.maximumOriginalNativeSpanCount).contains(maximumSpanCount) else {
      throw Self.liftFailure(.invalidInput, "Original native span cover requires its existing finite ceiling.", tolerance)
    }
    guard tolerance == preparationTolerance else { throw closedBoxFailure(tolerance: tolerance) }
    try validateClosedBox(box, tolerance: tolerance)
    func reserveAppend(_ count: Int, _ capacity: inout Int) throws -> Int? {
      guard count >= capacity else { return nil }
      let doubled = capacity.multipliedReportingOverflow(by: 2)
      guard !doubled.overflow else {
        throw GeometryConversionError.resourceLimitExceeded("Original native cover capacity overflowed.")
      }
      let next = min(maximumSpanCount, max(1, doubled.partialValue))
      guard next > count else {
        throw GeometryConversionError.resourceLimitExceeded("Original native cover exhausted caller retention.")
      }
      try OriginalCoefficientAllocation.reserve(count: next, of: OriginalNativeSpan.self, consumeStorage: consumeStorage)
      capacity = next
      return next
    }
    if !surface.isUPeriodic && !surface.isVPeriodic {
      var result: [OriginalNativeSpan] = []
      var capacity = 0
      for span in originalSpans {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        if max(box.u.lower, span.uBounds.lower) <= min(box.u.upper, span.uBounds.upper),
           max(box.v.lower, span.vBounds.lower) <= min(box.v.upper, span.vBounds.upper) {
          guard result.count < maximumSpanCount else {
            throw Self.liftFailure(.resourceLimitExceeded, "Original native span cover exhausted its aggregate ceiling.", tolerance)
          }
          try consumeWork()
          if let next = try reserveAppend(result.count, &capacity) { result.reserveCapacity(next) }
          result.append(span)
        }
      }
      return result
    }
    let us = try selectedLifts(over: box.u, direction: .u, tolerance: tolerance, maximumSpanCount: maximumSpanCount, consumeWork:consumeWork, consumeStorage: consumeStorage)
    let vs = try selectedLifts(over: box.v, direction: .v, tolerance: tolerance, maximumSpanCount: maximumSpanCount, consumeWork:consumeWork, consumeStorage: consumeStorage)
    var result: [OriginalNativeSpan] = []
    var capacity = 0
    for u in us { for v in vs { for span in originalSpans {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      let ub = try Self.translated(span.uBounds, by: u.translation, tolerance: tolerance)
      let vb = try Self.translated(span.vBounds, by: v.translation, tolerance: tolerance)
      guard max(box.u.lower, ub.lower) <= min(box.u.upper, ub.upper),
            max(box.v.lower, vb.lower) <= min(box.v.upper, vb.upper) else { continue }
      guard result.count < maximumSpanCount else {
        throw Self.liftFailure(.resourceLimitExceeded, "Original native span cover exhausted its aggregate ceiling.", tolerance)
      }
      try consumeWork()
      if let next = try reserveAppend(result.count, &capacity) { result.reserveCapacity(next) }
      result.append(OriginalNativeSpan(surface: surface, tolerance: tolerance,
        uSpanIndex: span.uSpanIndex, vSpanIndex: span.vSpanIndex,
        uBounds: span.uBounds, vBounds: span.vBounds, patch: span.patch,
        liftedUBounds: ub, liftedVBounds: vb, uCycle: u.cycle, vCycle: v.cycle,
        uTranslation: u.translation, vTranslation: v.translation))
    } } }
    guard !result.isEmpty else { throw closedBoxFailure(tolerance: tolerance) }
    return result
  }

  private struct AxisLift {
    let cycle: Int
    let translation: Double
  }

  private func selectedLifts(over interval: ScalarInterval, direction: SurfaceParameterDirection,
                             tolerance: ModelingTolerance, maximumSpanCount: Int,
                             consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> [AxisLift] {
    let periodic = direction == .u ? surface.isUPeriodic : surface.isVPeriodic
    let knots = direction == .u ? surface.uKnots : surface.vKnots
    let degree = direction == .u ? surface.uDegree : surface.vDegree
    let count = direction == .u ? surface.uControlPointCount : surface.vControlPointCount
    let lower = knots[degree], upper = knots[count]
    func refusal() -> KernelError {
      Self.liftFailure(.unsupportedCapability,
        "Original periodic selected spans require exact translated C0 knots, continuous native open axes, and at most one period.", tolerance)
    }
    guard periodic else {
      var i = degree + 1
      while i < count {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        var end = i + 1
        while end < count, knots[end] == knots[i] { try consumeWork(); end += 1 }
        guard end - i <= degree else { throw refusal() }
        i = end
      }
      try consumeWork()
      try OriginalCoefficientAllocation.reserve(count: 1, of: AxisLift.self, consumeStorage: consumeStorage)
      return [AxisLift(cycle: 0, translation: 0)]
    }
    let period = try Self.exactDifference(upper, lower, tolerance: tolerance)
    guard period.head > 0, period.tail == 0 else { throw refusal() }
    let cycleCount = count - degree
    for i in 0..<(knots.count - cycleCount) {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      let delta = try Self.exactDifference(knots[i + cycleCount], knots[i], tolerance: tolerance)
      guard delta.head == period.head, delta.tail == 0 else { throw refusal() }
    }
    var i = 0
    while i < knots.count {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      var end = i + 1
      while end < knots.count, knots[end] == knots[i] { try consumeWork(); end += 1 }
      guard end - i <= degree else { throw refusal() }
      i = end
    }
    let width = try Self.exactDifference(interval.upper, interval.lower, tolerance: tolerance)
    guard width.head <= period.head,
          width.head < period.head || width.tail <= 0 else { throw refusal() }
    guard let quotientLower = (OutwardScalarInterval.exact(interval.lower) - .exact(lower))
      .divided(by: .exact(period.head)),
      let quotientUpper = (OutwardScalarInterval.exact(interval.upper) - .exact(lower))
      .divided(by: .exact(period.head)) else { throw refusal() }
    let first = quotientLower.lower.rounded(.down) - 1
    let last = quotientUpper.upper.rounded(.down)
    guard first.isFinite, last.isFinite, abs(first) <= 4_503_599_627_370_496,
          abs(last) <= 4_503_599_627_370_496, first > Double(Int.min), last < Double(Int.max),
          last >= first, last - first <= 4 else {
      throw Self.liftFailure(.resourceLimitExceeded, "Original periodic span lifts exceed exact finite cycle enumeration.", tolerance)
    }
    var lifts: [AxisLift] = []
    var capacity = 0
    for cycle in Int(first)...Int(last) {
      try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
      let translation = Double(cycle) * period.head
      guard translation.isFinite, (-translation).addingProduct(Double(cycle), period.head) == 0 else {
        throw Self.liftFailure(.resourceLimitExceeded, "Original periodic span translation is not exactly representable.", tolerance)
      }
      // Discard wholly unrelated cycles before allocating any selected token.
      let base = try ScalarInterval(lower: lower, upper: upper)
      let lifted = try Self.translated(base, by: translation, tolerance: tolerance)
      if max(lifted.lower, interval.lower) <= min(lifted.upper, interval.upper) {
        let storage = lifts.count.addingReportingOverflow(1)
        guard !storage.overflow, storage.partialValue <= maximumSpanCount else {
          throw Self.liftFailure(.resourceLimitExceeded,
            "Original periodic axis lifts exhausted the caller's aggregate cover ceiling.", tolerance)
        }
        try consumeWork()
        if lifts.count == capacity {
          let doubled = capacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original periodic lift storage overflowed.")
          }
          capacity = min(maximumSpanCount, max(1, doubled.partialValue))
          try OriginalCoefficientAllocation.reserve(count: capacity, of: AxisLift.self, consumeStorage: consumeStorage)
          lifts.reserveCapacity(capacity)
        }
        lifts.append(AxisLift(cycle: cycle, translation: translation))
      }
    }
    return lifts
  }

  private static func translated(_ interval: ScalarInterval, by translation: Double,
                                 tolerance: ModelingTolerance) throws -> ScalarInterval {
    let lower = try exactDifference(interval.lower, -translation, tolerance: tolerance)
    let upper = try exactDifference(interval.upper, -translation, tolerance: tolerance)
    guard lower.tail == 0, upper.tail == 0 else {
      throw liftFailure(.resourceLimitExceeded, "Original periodic closed span endpoints have no exact represented lift.", tolerance)
    }
    return try ScalarInterval(lower: lower.head, upper: upper.head)
  }

  static func exactDifference(_ upper: Double, _ lower: Double,
                                      tolerance: ModelingTolerance) throws -> (head: Double, tail: Double) {
    let head = upper - lower
    let virtualLower = upper - head
    let virtualUpper = head + virtualLower
    let tail = (upper - virtualUpper) + (virtualLower - lower)
    guard head.isFinite, virtualLower.isFinite, virtualUpper.isFinite, tail.isFinite else {
      throw liftFailure(.resourceLimitExceeded, "Original periodic span arithmetic exceeded finite resolution.", tolerance)
    }
    return (head, tail)
  }

  static func liftFailure(_ code: KernelErrorCode, _ message: String,
                                  _ tolerance: ModelingTolerance) -> KernelError {
    KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
  }

  func intervalJet(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try parameters.validateAssumingSurfaceValidated(
      for: .bSpline(surface),
      tolerance: tolerance
    )
    return try intervalJetAssumingPrepared(
      over: parameters,
      tolerance: tolerance
    )
  }

  func intervalJetAssumingPrepared(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try CurrentTaskCancellationChecker().checkCancellation()
    var result: SurfaceIntervalVectorJet?
    let us = try surface.enclosureIntervals(parameters.u, direction: .u, tolerance: tolerance)
    let vs = try surface.enclosureIntervals(parameters.v, direction: .v, tolerance: tolerance)
    func accumulate(_ patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                    u: ScalarInterval, v: ScalarInterval) throws {
      let uLower = max(u.lower, patch.uLower), uUpper = min(u.upper, patch.uUpper)
      let vLower = max(v.lower, patch.vLower), vUpper = min(v.upper, patch.vUpper)
      guard uUpper >= uLower, vUpper >= vLower else { return }
      let jet = try Self.selectedJet(of: patch, over: SurfaceParameterBox(
        u: ScalarInterval(lower: uLower, upper: uUpper), v: ScalarInterval(lower: vLower, upper: vUpper)),
        tolerance: tolerance)
      result = result.map { $0.union(jet) } ?? jet
    }
    for u in us {
      for v in vs {
        for span in originalSpans { try accumulate(span.patch, u: u, v: v) }
      }
    }
    guard let result else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "The surface parameter box did not intersect a prepared B-spline Bezier span.")
    }
    return result
  }

  /// Internal chart composition permits a constant UV coordinate without
  /// weakening the public positive-width surface-box contract.
  func intervalJet(overClosedBox parameters: SurfaceParameterBox,
                   tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    try validateClosedBox(parameters, tolerance: tolerance)
    return try intervalJetAssumingPrepared(over:parameters,tolerance:tolerance)
  }

  private func validateClosedBox(_ parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
    try tolerance.validate()
    for (interval,domain) in [(parameters.u,surface.uDomain),(parameters.v,surface.vDomain)] {
      guard interval.lower.isFinite, interval.upper.isFinite, interval.lower <= interval.upper else {
        throw closedBoxFailure(tolerance:tolerance)
      }
      if case let .closed(lower,upper) = domain {
        guard interval.lower >= lower, interval.upper <= upper else {
          throw closedBoxFailure(tolerance:tolerance)
        }
      }
    }
  }

  /// A native knot point retains every owning span's one-sided derivative jet.
  func pointJet(u: Double, v: Double,
                tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    guard u.isFinite, v.isFinite else { throw closedBoxFailure(tolerance: tolerance) }
    return try intervalJet(overClosedBox:SurfaceParameterBox(
      u:ScalarInterval(lower:u,upper:u),v:ScalarInterval(lower:v,upper:v)),tolerance:tolerance)
  }

  /// Values retain every original closed owning span and the existing periodic
  /// point lift covers. Unrequested derivatives are never synthesized.
  func pointValue(u: Double, v: Double, tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
    try CurrentTaskCancellationChecker().checkCancellation()
    guard u.isFinite, v.isFinite, tolerance == preparationTolerance else {
      throw closedBoxFailure(tolerance:tolerance)
    }
    let box = SurfaceParameterBox(u:try ScalarInterval(lower:u,upper:u),v:try ScalarInterval(lower:v,upper:v))
    try validateClosedBox(box,tolerance:tolerance)
    let us = try surface.enclosureIntervals(box.u,direction:.u,tolerance:tolerance)
    let vs = try surface.enclosureIntervals(box.v,direction:.v,tolerance:tolerance)
    var result: IntervalVector3DBounds?
    for u in us { for v in vs { for span in originalSpans {
      let uLower = max(u.lower,span.patch.uLower), uUpper = min(u.upper,span.patch.uUpper)
      let vLower = max(v.lower,span.patch.vLower), vUpper = min(v.upper,span.patch.vUpper)
      guard uLower <= uUpper, vLower <= vUpper else { continue }
      let value = try Self.selectedValue(of:span.patch,over:SurfaceParameterBox(
        u:ScalarInterval(lower:uLower,upper:uUpper),v:ScalarInterval(lower:vLower,upper:vUpper)),tolerance:tolerance)
      if let prior = result {
        result = IntervalVector3DBounds(x:prior.x.union(value.x),y:prior.y.union(value.y),z:prior.z.union(value.z))
      } else { result = value }
    } } }
    guard let result else { throw closedBoxFailure(tolerance:tolerance) }
    return result
  }

  private func closedBoxFailure(tolerance: ModelingTolerance) -> KernelError {
    KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
      message:"A prepared B-spline closed box requires finite ordered UV bounds inside its support domain.")
  }

  static func selectedJet(of patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                                  over box: SurfaceParameterBox,
                                  tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    try CurrentTaskCancellationChecker().checkCancellation()
    let encloser = RationalBezierSurfaceJetEncloser()
    if box.u.lower == box.u.upper, box.v.lower == box.v.upper {
      return try encloser.pointEnclosure(of: patch, u: box.u.lower, v: box.v.lower, tolerance: tolerance)
    }
    let u = try numericallyStableInterval(box.u, within: (patch.uLower, patch.uUpper), tolerance: tolerance)
    let v = try numericallyStableInterval(box.v, within: (patch.vLower, patch.vUpper), tolerance: tolerance)
    return try encloser.enclosure(of: patch, u: u, v: v, tolerance: tolerance)
  }

  static func selectedValue(of patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                                    over box: SurfaceParameterBox,
                                    tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
    try CurrentTaskCancellationChecker().checkCancellation()
    let encloser = RationalBezierSurfaceJetEncloser()
    if box.u.lower == box.u.upper, box.v.lower == box.v.upper {
      return try encloser.pointValueEnclosure(of:patch,u:box.u.lower,v:box.v.lower,tolerance:tolerance)
    }
    // A periodic point may own a positive-width outward lift cover. Preserve
    // the full-jet owner's conditioning and localization, evaluating value nets only.
    let u = try numericallyStableInterval(box.u,within:(patch.uLower,patch.uUpper),tolerance:tolerance)
    let v = try numericallyStableInterval(box.v,within:(patch.vLower,patch.vUpper),tolerance:tolerance)
    return try encloser.valueEnclosure(of:patch,u:u,v:v,tolerance:tolerance)
  }

  private static func numericallyStableInterval(
    _ interval: ScalarInterval,
    within bounds: (lower: Double, upper: Double),
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
    let scale = max(1.0, abs(bounds.lower), abs(bounds.upper))
    // Conditioning belongs to finite arithmetic, not the modeling tolerance.
    let requestedWidth = Double.ulpOfOne * scale * 4_096.0
    let minimumWidth = min(requestedWidth, bounds.upper - bounds.lower)
    guard interval.width < minimumWidth else { return interval }

    // Expand from the certified endpoints instead of reconstructing them
    // from the midpoint. The latter can round inward and lose containment
    // for intervals close to a Bezier-span boundary.
    let lower = max(bounds.lower, interval.lower - minimumWidth)
    let upper = min(bounds.upper, interval.upper + minimumWidth)
    guard lower <= interval.lower,
      upper >= interval.upper,
      upper > lower
    else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        residual: upper - lower,
        tolerance: tolerance,
        message:
          "A prepared B-spline differential enclosure could not construct a stable containing interval."
      )
    }
    return try ScalarInterval(lower: lower, upper: upper)
  }
}
