import CADCore

/// Retains original homogeneous native-span enclosures of one immutable surface.
/// Whole periodic queries retain conservative original-cycle covers. Selected
/// tokens separately retain proved base spans and exact unwrapped cycle lifts.
package struct PreparedBSplineSurfaceDifferentialEncloser: Sendable {
  package let surface: BSplineSurface3D
  private let preparationTolerance: ModelingTolerance
  private let originalSpans: [OriginalNativeSpan]

  package struct OriginalNativeSpan: Sendable {
    package let surface: BSplineSurface3D
    package let tolerance: ModelingTolerance
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let uBounds: ScalarInterval
    package let vBounds: ScalarInterval
    package let uCycle: Int
    package let vCycle: Int
    fileprivate let baseUBounds: ScalarInterval
    fileprivate let baseVBounds: ScalarInterval
    fileprivate let uTranslation: Double
    fileprivate let vTranslation: Double
    /// Exact stored cyclic lift selected and validated by the original owning token.
    package var originalUTranslation: Double { uTranslation }
    package var originalVTranslation: Double { vTranslation }
    package var originalBaseUBounds: ScalarInterval { baseUBounds }
    package var originalBaseVBounds: ScalarInterval { baseVBounds }
    fileprivate let patch: RationalBezierSurfaceJetEncloser.PreparedPatch

    fileprivate init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
                     uSpanIndex: Int, vSpanIndex: Int, uBounds: ScalarInterval,
                     vBounds: ScalarInterval, patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                     liftedUBounds: ScalarInterval? = nil, liftedVBounds: ScalarInterval? = nil,
                     uCycle: Int = 0, vCycle: Int = 0,
                     uTranslation: Double = 0, vTranslation: Double = 0) {
      self.surface = surface
      self.tolerance = tolerance
      self.uSpanIndex = uSpanIndex
      self.vSpanIndex = vSpanIndex
      self.baseUBounds = uBounds
      self.baseVBounds = vBounds
      self.uBounds = liftedUBounds ?? uBounds
      self.vBounds = liftedVBounds ?? vBounds
      self.uCycle = uCycle
      self.vCycle = vCycle
      self.uTranslation = uTranslation
      self.vTranslation = vTranslation
      self.patch = patch
    }

    package func validate(on source: BSplineSurface3D, over box: SurfaceParameterBox,
                  tolerance callerTolerance: ModelingTolerance,
                  consumeWork: (() throws -> Void)? = nil) throws {
      try callerTolerance.validate()
      try Task.checkCancellation()
      if let consumeWork {
        func charge(_ count: Int) throws {
          for _ in 0..<count { try consumeWork(); try Task.checkCancellation() }
        }
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(source), using: charge)
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(surface), using: charge)
        try consumeWork()
      }
      guard source == surface, callerTolerance == tolerance,
        box.u.lower.isFinite, box.u.upper.isFinite,
        box.v.lower.isFinite, box.v.upper.isFinite,
        box.u.lower <= box.u.upper, box.v.lower <= box.v.upper,
        box.u.lower >= uBounds.lower, box.u.upper <= uBounds.upper,
        box.v.lower >= vBounds.lower, box.v.upper <= vBounds.upper
      else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: callerTolerance,
          message: "A selected native span requires its original source, preparation tolerance, and closed native support.")
      }
    }

    package func validate(on source: BSplineSurface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws {
      try withoutActuallyEscaping(consumeWork) { borrowed in
        try validate(on: source, over: box, tolerance: tolerance,
          consumeWork: Optional(borrowed))
      }
    }

    /// Retains the original homogeneous value net after this token admits the
    /// original closed query and its exact periodic one-sided lift.
    package func originalCoefficientReceipt(overClosedBox box: SurfaceParameterBox,
        on source: BSplineSurface3D, tolerance callerTolerance: ModelingTolerance,
        consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaOriginalCoefficientReceipt {
      try validate(on:source,over:box,tolerance:callerTolerance,consumeWork:consumeWork)
      try consumeWork()
      let cover = try baseBox(box,tolerance:callerTolerance)
      func station(_ query: ScalarInterval, translation: Double,
                   cover: ScalarInterval) throws -> ScalarInterval {
        guard query.lower == query.upper else { return cover }
        let exact = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(
          query.lower,translation,tolerance:callerTolerance)
        // A zero expansion tail proves the real original station is exactly
        // represented. Other singleton queries retain the original whole cover.
        guard exact.tail == 0 else { return cover }
        return try ScalarInterval(lower:exact.head,upper:exact.head)
      }
      let base = SurfaceParameterBox(
        u:try station(box.u,translation:uTranslation,cover:cover.u),
        v:try station(box.v,translation:vTranslation,cover:cover.v))
      try OriginalCoefficientAllocation.reserve(count: 1,
        of: SurfaceAreaOriginalCoefficientReceipt.self, consumeStorage: consumeStorage)
      return try RationalBezierSurfaceJetEncloser().originalCoefficientReceipt(of:patch,
        source:source,tolerance:callerTolerance,query:box,
        baseQuery:base,uSpanIndex:uSpanIndex,vSpanIndex:vSpanIndex)
    }

    package func originalCoefficientReceipt(overClosedBox box: SurfaceParameterBox,
        on source: BSplineSurface3D, tolerance callerTolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: (Int) throws -> Void)
        throws -> SurfaceAreaOriginalCoefficientReceipt {
      try withoutActuallyEscaping(consumeStorage) { storage in
        let optionalStorage: ((Int) throws -> Void)? = storage
        return try originalCoefficientReceipt(overClosedBox: box, on: source,
          tolerance: callerTolerance, consumeWork: consumeWork,
          consumeStorage: optionalStorage)
      }
    }

    package func intervalJet(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
      tolerance callerTolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
      try validate(on: source, over: box, tolerance: callerTolerance)
      return try PreparedBSplineSurfaceDifferentialEncloser.selectedJet(
        of: patch, over: try baseBox(box, tolerance: callerTolerance), tolerance: callerTolerance)
    }

    package func intervalJet(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
      tolerance callerTolerance: ModelingTolerance,
      consumeWork: () throws -> Void) throws -> SurfaceIntervalVectorJet {
      let receipt = try originalCoefficientReceipt(overClosedBox: box, on: source,
        tolerance: callerTolerance, consumeWork: consumeWork)
      let original = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
        order: 3, consumeWork: consumeWork)
      return try original.intervalTaylorJet(using: receipt, consumeWork: consumeWork).intervalJet()
    }

    package func intervalJet(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
      tolerance callerTolerance: ModelingTolerance, consumeWork: () throws -> Void,
      consumeStorage: (Int) throws -> Void) throws -> SurfaceIntervalVectorJet {
      try withoutActuallyEscaping(consumeStorage) { storage in
        let receipt = try originalCoefficientReceipt(overClosedBox: box, on: source,
          tolerance: callerTolerance, consumeWork: consumeWork,
          consumeStorage: storage)
        let original = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
          order: 3, consumeWork: consumeWork, consumeStorage: storage)
        return try original.intervalTaylorJet(using: receipt, consumeWork: consumeWork,
          consumeStorage: storage).intervalJet()
      }
    }

    func pointJet(u: Double, v: Double, on source: BSplineSurface3D,
                  tolerance callerTolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
      guard u.isFinite, v.isFinite else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: callerTolerance,
          message: "A selected native-span point requires finite UV coordinates.")
      }
      return try intervalJet(overClosedBox: SurfaceParameterBox(
        u: ScalarInterval(lower: u, upper: u), v: ScalarInterval(lower: v, upper: v)),
        on: source, tolerance: callerTolerance)
    }

    package struct RowEvaluator: Sendable {
      fileprivate let span: OriginalNativeSpan
      fileprivate let u: Double
      fileprivate let numeric: BSplineSurface3D.StationNumericRow
      fileprivate let firstOrder: RationalBezierSurfaceJetEncloser.PreparedFirstOrderRow

      struct Materialization: Sendable {
        let point: Point3D
        let normal: Vector3D
        let enclosure: RationalBezierSurfaceJetEncloser.FirstOrderEnclosure
      }

      /// The immutable token retains source, tolerance, selected side and U.
      func materialize(v: Double, overClosedV interval: ScalarInterval,
                       pointCandidate: Point3D? = nil) throws -> Materialization {
        guard v.isFinite, interval.lower.isFinite, interval.upper.isFinite,
              interval.lower <= v, v <= interval.upper,
              interval.lower >= span.vBounds.lower, interval.upper <= span.vBounds.upper else {
          throw KernelError(phase: .geometry, code: .invalidInput, tolerance: span.tolerance,
            message: "An original station row requires its admitted closed V interval and actual station.")
        }
        if let pointCandidate {
          guard pointCandidate.x.isFinite, pointCandidate.y.isFinite, pointCandidate.z.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: span.tolerance,
              message: "A retained mesh station candidate must have finite coordinates.")
          }
        }
        try Task.checkCancellation()
        let base = try span.basePointAssumingValidated(u: u, v: v, tolerance: span.tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u), v: interval)
        let baseInterval = try span.baseBox(box, tolerance: span.tolerance).v
        let point = try pointCandidate ?? numeric.point(v: v)
        let normal = try numeric.normal(baseV: base.v)
        let enclosure = try RationalBezierSurfaceJetEncloser().firstOrderEnclosure(
          row: firstOrder, overClosedV: baseInterval, tolerance: span.tolerance)
        try Task.checkCancellation()
        return Materialization(point: point, normal: normal, enclosure: enclosure)
      }
    }

    /// Original U preparation is immutable and paid by the consumer's existing usage.
    package func prepareStationRow(u: Double, on source: BSplineSurface3D,
                                   tolerance callerTolerance: ModelingTolerance,
                                   consumeWork: () throws -> Void) throws -> RowEvaluator {
      for _ in 0..<8 { try consumeWork() }
      let uInterval = try ScalarInterval(lower: u, upper: u)
      try validate(on: source, over: SurfaceParameterBox(u: uInterval, v: vBounds), tolerance: callerTolerance)
      let base = try basePointAssumingValidated(u: u, v: vBounds.lower, tolerance: callerTolerance)
      let numeric = try source.prepareStationNumericRow(u: u, baseU: base.u,
        owningUSpan: uSpanIndex, owningVSpan: vSpanIndex, tolerance: callerTolerance,
        consumeWork: consumeWork)
      let row = try RationalBezierSurfaceJetEncloser().prepareFirstOrderRow(
        of: patch, u: base.u, tolerance: callerTolerance, consumeWork: consumeWork)
      try Task.checkCancellation()
      return RowEvaluator(span: self, u: u, numeric: numeric, firstOrder: row)
    }

    func firstOrderEnclosure(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
                             tolerance callerTolerance: ModelingTolerance) throws
      -> RationalBezierSurfaceJetEncloser.FirstOrderEnclosure {
      try validate(on: source, over: box, tolerance: callerTolerance)
      let base = try baseBox(box, tolerance: callerTolerance)
      return try RationalBezierSurfaceJetEncloser().firstOrderEnclosure(of: patch, u: base.u, v: base.v,
                                                                      tolerance: callerTolerance)
    }

    func pointValue(u: Double, v: Double, on source: BSplineSurface3D,
                    tolerance callerTolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
      guard u.isFinite, v.isFinite else {
        throw KernelError(phase:.geometry,code:.invalidInput,tolerance:callerTolerance,
          message:"An original native-span point value requires finite UV coordinates.")
      }
      let box = SurfaceParameterBox(u:try ScalarInterval(lower:u,upper:u),v:try ScalarInterval(lower:v,upper:v))
      try validate(on:source,over:box,tolerance:callerTolerance)
      return try PreparedBSplineSurfaceDifferentialEncloser.selectedValue(of:patch,over:try baseBox(box,tolerance:callerTolerance),tolerance:callerTolerance)
    }

    /// Exact scalar stations retain their selected side, including a cycle's upper endpoint.
    func basePoint(u: Double, v: Double, on source: BSplineSurface3D,
                   tolerance callerTolerance: ModelingTolerance) throws -> (u: Double, v: Double) {
      let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                                    v: try ScalarInterval(lower: v, upper: v))
      try validate(on: source, over: box, tolerance: callerTolerance)
      return try basePointAssumingValidated(u: u, v: v, tolerance: callerTolerance)
    }

    private func basePointAssumingValidated(u: Double, v: Double,
                                           tolerance callerTolerance: ModelingTolerance) throws -> (u: Double, v: Double) {
      func station(_ value: Double, translation: Double, base: ScalarInterval) throws -> Double {
        let difference = try PreparedBSplineSurfaceDifferentialEncloser.exactDifference(value, translation,
                                                                                      tolerance: callerTolerance)
        guard difference.tail == 0, difference.head >= base.lower, difference.head <= base.upper else {
          throw PreparedBSplineSurfaceDifferentialEncloser.liftFailure(.resourceLimitExceeded,
            "An original periodic selected station has no exact represented base parameter.", callerTolerance)
        }
        return difference.head
      }
      return (try station(u, translation: uTranslation, base: baseUBounds),
              try station(v, translation: vTranslation, base: baseVBounds))
    }

    private func baseBox(_ box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceParameterBox {
      func interval(_ requested: ScalarInterval, translation: Double, base: ScalarInterval) throws -> ScalarInterval {
        guard translation != 0 else { return requested }
        let lower = OutwardScalarInterval.exact(requested.lower) - .exact(translation)
        let upper = OutwardScalarInterval.exact(requested.upper) - .exact(translation)
        // Exact lifted support admission proves the true translated query lies in this
        // base span. Intersection removes only interval-arithmetic overhang, not geometry.
        let a = max(base.lower, lower.lower), b = min(base.upper, upper.upper)
        guard a.isFinite, b.isFinite, a <= b else {
          throw PreparedBSplineSurfaceDifferentialEncloser.liftFailure(.resourceLimitExceeded,
            "An original periodic selected box lost its finite base cover.", tolerance)
        }
        return try ScalarInterval(lower: a, upper: b)
      }
      return SurfaceParameterBox(u: try interval(box.u, translation: uTranslation, base: baseUBounds),
                                 v: try interval(box.v, translation: vTranslation, base: baseVBounds))
    }

  }

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: false, consumeWork: { try Task.checkCancellation() })
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
    try Task.checkCancellation()
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
    try originalNativeSpans(over: box, tolerance: tolerance, maximumSpanCount: 262_144)
  }

  /// Q3 preparation and queries pay original cover scans and token storage before allocation.
  package func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
                                  consumeWork: () throws -> Void) throws -> [OriginalNativeSpan] {
    try originalNativeSpans(over:box,tolerance:tolerance,maximumSpanCount:262_144,consumeWork:consumeWork)
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
    try Task.checkCancellation()
    guard (1...262_144).contains(maximumSpanCount) else {
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
        try Task.checkCancellation(); try consumeWork()
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
      try Task.checkCancellation(); try consumeWork()
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
        try Task.checkCancellation(); try consumeWork()
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
      try Task.checkCancellation(); try consumeWork()
      let delta = try Self.exactDifference(knots[i + cycleCount], knots[i], tolerance: tolerance)
      guard delta.head == period.head, delta.tail == 0 else { throw refusal() }
    }
    var i = 0
    while i < knots.count {
      try Task.checkCancellation(); try consumeWork()
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
      try Task.checkCancellation(); try consumeWork()
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

  private static func exactDifference(_ upper: Double, _ lower: Double,
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

  private static func liftFailure(_ code: KernelErrorCode, _ message: String,
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
    try Task.checkCancellation()
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
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "The surface parameter box did not intersect a prepared B-spline Bezier span."
      )
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
    try Task.checkCancellation()
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

  private static func selectedJet(of patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                                  over box: SurfaceParameterBox,
                                  tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    try Task.checkCancellation()
    let encloser = RationalBezierSurfaceJetEncloser()
    if box.u.lower == box.u.upper, box.v.lower == box.v.upper {
      return try encloser.pointEnclosure(of: patch, u: box.u.lower, v: box.v.lower, tolerance: tolerance)
    }
    let u = try numericallyStableInterval(box.u, within: (patch.uLower, patch.uUpper), tolerance: tolerance)
    let v = try numericallyStableInterval(box.v, within: (patch.vLower, patch.vUpper), tolerance: tolerance)
    return try encloser.enclosure(of: patch, u: u, v: v, tolerance: tolerance)
  }

  private static func selectedValue(of patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
                                    over box: SurfaceParameterBox,
                                    tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
    try Task.checkCancellation()
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
