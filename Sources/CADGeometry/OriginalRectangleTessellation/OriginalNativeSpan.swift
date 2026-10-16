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

    package func validate<A: ExactScalarAdmission & ~Copyable>(on source: BSplineSurface3D, over box: SurfaceParameterBox,
                  tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws {
      try callerTolerance.validate()
      try GeometryStructuralComparisonWork.charge(surface: .bSpline(source), using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: .bSpline(surface), using: &execution)
      try execution.consumeWork(1)
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
    package func originalCoefficientReceipt<A: ExactScalarAdmission & ~Copyable>(overClosedBox box: SurfaceParameterBox,
        on source: BSplineSurface3D, tolerance callerTolerance: ModelingTolerance,
        using execution: inout A) throws -> SurfaceAreaOriginalCoefficientReceipt {
      try validate(on: source, over: box, tolerance: callerTolerance, using: &execution)
      try execution.consumeWork(1)
      let cover = try baseBox(box,tolerance:callerTolerance, using: &execution)
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
      return try RationalBezierSurfaceJetEncloser().originalCoefficientReceipt(of:patch,
        source:source,tolerance:callerTolerance,query:box,
        baseQuery:base,uSpanIndex:uSpanIndex,vSpanIndex:vSpanIndex, using: &execution)
    }

    package func intervalJet<A: ExactScalarAdmission & ~Copyable>(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
      tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceIntervalVectorJet {
      let receipt = try originalCoefficientReceipt(overClosedBox: box, on: source,
        tolerance: callerTolerance, using: &execution)
      let original = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
        order: 3, using: &execution)
      return try original.intervalTaylorJet(using: receipt, admission: &execution).intervalJet()
    }

    func pointJet<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double, on source: BSplineSurface3D,
                  tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceIntervalVectorJet {
      try execution.consumeWork(1)
      guard u.isFinite, v.isFinite else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: callerTolerance,
          message: "A selected native-span point requires finite UV coordinates.")
      }
      return try intervalJet(overClosedBox: SurfaceParameterBox(
        u: ScalarInterval(lower: u, upper: u), v: ScalarInterval(lower: v, upper: v)),
        on: source, tolerance: callerTolerance, using: &execution)
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
      func materialize<A: ExactScalarAdmission & ~Copyable>(v: Double, overClosedV interval: ScalarInterval,
                       pointCandidate: Point3D? = nil, using execution: inout A) throws -> Materialization {
      try execution.consumeWork(1)
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
        try execution.checkpoint()
        let base = try span.basePointAssumingValidated(u: u, v: v, tolerance: span.tolerance, using: &execution)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u), v: interval)
        let baseInterval = try span.baseBox(box, tolerance: span.tolerance, using: &execution).v
        let point = try pointCandidate ?? numeric.point(v: v, using: &execution)
        let normal = try numeric.normal(baseV: base.v, using: &execution)
        let enclosure = try RationalBezierSurfaceJetEncloser().firstOrderEnclosure(
          row: firstOrder, overClosedV: baseInterval, tolerance: span.tolerance, using: &execution)
        try execution.checkpoint()
        return Materialization(point: point, normal: normal, enclosure: enclosure)
      }
    }

    /// Original U preparation is immutable and paid by the consumer's existing usage.
    package func prepareStationRow<A: ExactScalarAdmission & ~Copyable>(u: Double, on source: BSplineSurface3D,
                                   tolerance callerTolerance: ModelingTolerance,
                                   using execution: inout A) throws -> RowEvaluator {
      try execution.consumeWork(8)
      let uInterval = try ScalarInterval(lower: u, upper: u)
      try validate(on: source, over: SurfaceParameterBox(u: uInterval, v: vBounds), tolerance: callerTolerance, using: &execution)
      let base = try basePointAssumingValidated(u: u, v: vBounds.lower, tolerance: callerTolerance, using: &execution)
      let numeric = try source.prepareStationNumericRow(u: u, baseU: base.u,
        owningUSpan: uSpanIndex, owningVSpan: vSpanIndex, tolerance: callerTolerance,
        using: &execution)
      let row = try RationalBezierSurfaceJetEncloser().prepareFirstOrderRow(
        of: patch, u: base.u, tolerance: callerTolerance, using: &execution)
      try execution.checkpoint()
      return RowEvaluator(span: self, u: u, numeric: numeric, firstOrder: row)
    }

    func firstOrderEnclosure<A: ExactScalarAdmission & ~Copyable>(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
                             tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws
      -> RationalBezierSurfaceJetEncloser.FirstOrderEnclosure {
      try execution.consumeWork(1)
      try validate(on: source, over: box, tolerance: callerTolerance, using: &execution)
      let base = try baseBox(box, tolerance: callerTolerance, using: &execution)
      return try RationalBezierSurfaceJetEncloser().firstOrderEnclosure(of: patch, u: base.u, v: base.v,
                                                                      tolerance: callerTolerance, using: &execution)
    }

    func pointValue<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double, on source: BSplineSurface3D,
                    tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws -> IntervalVector3DBounds {
      try execution.consumeWork(1)
      guard u.isFinite, v.isFinite else {
        throw KernelError(phase:.geometry,code:.invalidInput,tolerance:callerTolerance,
          message:"An original native-span point value requires finite UV coordinates.")
      }
      let box = SurfaceParameterBox(u:try ScalarInterval(lower:u,upper:u),v:try ScalarInterval(lower:v,upper:v))
      try validate(on:source,over:box,tolerance:callerTolerance, using: &execution)
      return try PreparedBSplineSurfaceDifferentialEncloser.selectedValue(of:patch,over:try baseBox(box,tolerance:callerTolerance, using: &execution),tolerance:callerTolerance, using: &execution)
    }

    /// Exact scalar stations retain their selected side, including a cycle's upper endpoint.
    func basePoint<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double, on source: BSplineSurface3D,
                   tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws -> (u: Double, v: Double) {
      try execution.consumeWork(1)
      let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
                                    v: try ScalarInterval(lower: v, upper: v))
      try validate(on: source, over: box, tolerance: callerTolerance, using: &execution)
      return try basePointAssumingValidated(u: u, v: v, tolerance: callerTolerance, using: &execution)
    }

    private func basePointAssumingValidated<A: ExactScalarAdmission & ~Copyable>(u: Double, v: Double,
                                           tolerance callerTolerance: ModelingTolerance, using execution: inout A) throws -> (u: Double, v: Double) {
      try execution.consumeWork(1)
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

    private func baseBox<A: ExactScalarAdmission & ~Copyable>(_ box: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceParameterBox {
        try execution.consumeWork(1)
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


  static func selectOriginalNativeSpans<A: ExactScalarAdmission & ~Copyable>(from originalSpans: [OriginalNativeSpan],
    surface: BSplineSurface3D, preparationTolerance: ModelingTolerance,
    over box: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int, using execution: inout A) throws -> [OriginalNativeSpan] {
      try execution.consumeWork(1)
    try tolerance.validate()
    try execution.checkpoint()
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
        try execution.consumeWork(1)
      guard max(box.u.lower, span.uBounds.lower) <= min(box.u.upper, span.uBounds.upper),
        max(box.v.lower, span.vBounds.lower) <= min(box.v.upper, span.vBounds.upper) else { continue }
      guard result.count < maximumSpanCount else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original native span cover exhausted its aggregate ceiling.")
      }
      try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalNativeSpan.self))
      result.append(span)
    }
    return result
  }
}

