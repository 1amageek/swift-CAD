import CADCore

extension PreparedBSplineSurfaceDifferentialEncloser {
  package struct OriginalNativeSpan: Sendable {
    package let surface: BSplineSurface3D
    package let tolerance: ModelingTolerance
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let uBounds: ScalarInterval
    package let vBounds: ScalarInterval
    package let uCycle: Int
    package let vCycle: Int
    let baseUBounds: ScalarInterval
    let baseVBounds: ScalarInterval
    let uTranslation: Double
    let vTranslation: Double
    /// Exact stored cyclic lift selected and validated by the original owning token.
    package var originalUTranslation: Double { uTranslation }
    package var originalVTranslation: Double { vTranslation }
    package var originalBaseUBounds: ScalarInterval { baseUBounds }
    package var originalBaseVBounds: ScalarInterval { baseVBounds }
    let patch: RationalBezierSurfaceJetEncloser.PreparedPatch

    init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
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

    /// Retains the original homogeneous value net after this token admits the
    /// original closed query and its exact periodic one-sided lift.
    package func originalCoefficientReceipt(overClosedBox box: SurfaceParameterBox,
        on source: BSplineSurface3D, tolerance callerTolerance: ModelingTolerance,
        consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaOriginalCoefficientReceipt {
      try withoutActuallyEscaping(consumeWork) { work in
        try validate(on:source,over:box,tolerance:callerTolerance,consumeWork:work)
      }
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


  static func selectOriginalNativeSpans(from originalSpans: [OriginalNativeSpan],
    surface: BSplineSurface3D, preparationTolerance: ModelingTolerance,
    over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int) throws -> [OriginalNativeSpan] {
    try tolerance.validate()
    try Task.checkCancellation()
    guard (1...262_144).contains(maximumSpanCount), tolerance == preparationTolerance,
      box.u.lower.isFinite, box.u.upper.isFinite, box.v.lower.isFinite, box.v.upper.isFinite,
      box.u.lower <= box.u.upper, box.v.lower <= box.v.upper,
      box.u.lower >= surface.uKnots[surface.uDegree],
      box.u.upper <= surface.uKnots[surface.uControlPointCount],
      box.v.lower >= surface.vKnots[surface.vDegree],
      box.v.upper <= surface.vKnots[surface.vControlPointCount] else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original native span selection requires its preparation tolerance and actual closed source domain.")
    }
    var result: [OriginalNativeSpan] = []
    for span in originalSpans {
      try Task.checkCancellation()
      guard max(box.u.lower, span.uBounds.lower) <= min(box.u.upper, span.uBounds.upper),
        max(box.v.lower, span.vBounds.lower) <= min(box.v.upper, span.vBounds.upper) else { continue }
      guard result.count < maximumSpanCount else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original native span cover exhausted its aggregate ceiling.")
      }
      result.append(span)
    }
    return result
  }
}

