import CADCore

/// Retains original homogeneous native-span enclosures of one immutable surface.
/// Periodic queries retain conservative original-cycle covers; selected tokens
/// remain restricted to nonperiodic native sides.
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
    fileprivate let patch: RationalBezierSurfaceJetEncloser.PreparedPatch

    fileprivate init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
                     uSpanIndex: Int, vSpanIndex: Int, uBounds: ScalarInterval,
                     vBounds: ScalarInterval, patch: RationalBezierSurfaceJetEncloser.PreparedPatch) {
      self.surface = surface
      self.tolerance = tolerance
      self.uSpanIndex = uSpanIndex
      self.vSpanIndex = vSpanIndex
      self.uBounds = uBounds
      self.vBounds = vBounds
      self.patch = patch
    }

    func validate(on source: BSplineSurface3D, over box: SurfaceParameterBox,
                  tolerance callerTolerance: ModelingTolerance) throws {
      try callerTolerance.validate()
      try Task.checkCancellation()
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

    func intervalJet(overClosedBox box: SurfaceParameterBox, on source: BSplineSurface3D,
                     tolerance callerTolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
      try validate(on: source, over: box, tolerance: callerTolerance)
      return try PreparedBSplineSurfaceDifferentialEncloser.selectedJet(
        of: patch, over: box, tolerance: callerTolerance)
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

    func pointValue(u: Double, v: Double, on source: BSplineSurface3D,
                    tolerance callerTolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
      guard u.isFinite, v.isFinite else {
        throw KernelError(phase:.geometry,code:.invalidInput,tolerance:callerTolerance,
          message:"An original native-span point value requires finite UV coordinates.")
      }
      let box = SurfaceParameterBox(u:try ScalarInterval(lower:u,upper:u),v:try ScalarInterval(lower:v,upper:v))
      try validate(on:source,over:box,tolerance:callerTolerance)
      return try PreparedBSplineSurfaceDifferentialEncloser.selectedValue(of:patch,over:box,tolerance:callerTolerance)
    }
  }

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
    try surface.validate(tolerance: tolerance)
    try Task.checkCancellation()
    self.surface = surface
    self.preparationTolerance = tolerance
    let encloser = RationalBezierSurfaceJetEncloser()
    let decomposer = BSplineSurfaceBezierDecomposer()
    let singleBezier = !surface.isUPeriodic && !surface.isVPeriodic
      && surface.uControlPointCount == surface.uDegree + 1
      && surface.vControlPointCount == surface.vDegree + 1
      && surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ $0 == surface.uKnots[surface.uDegree] })
      && surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ $0 == surface.uKnots[surface.uControlPointCount] })
      && surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ $0 == surface.vKnots[surface.vDegree] })
      && surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ $0 == surface.vKnots[surface.vControlPointCount] })
    if singleBezier {
      // These are the stored original controls, not a rounded extraction.
      let patch = RationalBezierSurfacePatch3D(controlPoints: surface.controlPoints, weights: surface.weights,
        uLower: surface.uKnots[surface.uDegree], uUpper: surface.uKnots[surface.uControlPointCount],
        vLower: surface.vKnots[surface.vDegree], vUpper: surface.vKnots[surface.vControlPointCount])
      originalSpans = [OriginalNativeSpan(surface: surface, tolerance: tolerance,
        uSpanIndex: surface.uDegree, vSpanIndex: surface.vDegree,
        uBounds: try ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
        vBounds: try ScalarInterval(lower: patch.vLower, upper: patch.vUpper),
        patch: try encloser.prepare(patch, tolerance: tolerance))]
    } else {
      originalSpans = try decomposer.originalHomogeneousPatches(surface: surface, tolerance: tolerance).map {
        OriginalNativeSpan(surface: surface, tolerance: tolerance,
          uSpanIndex: $0.uSpanIndex, vSpanIndex: $0.vSpanIndex,
          uBounds: $0.uBounds, vBounds: $0.vBounds,
          patch: try encloser.prepare(original: $0, tolerance: tolerance))
      }
    }
  }

  package func originalNativeSpans(over box: SurfaceParameterBox,
                                  tolerance: ModelingTolerance) throws -> [OriginalNativeSpan] {
    try tolerance.validate()
    try Task.checkCancellation()
    guard !surface.isUPeriodic, !surface.isVPeriodic else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Original native-span tokens require nonperiodic axes.")
    }
    guard tolerance == preparationTolerance else { throw closedBoxFailure(tolerance: tolerance) }
    try validateClosedBox(box, tolerance: tolerance)
    // Closed intersections preserve every one-sided owner at knot points.
    return originalSpans.filter {
      max(box.u.lower, $0.uBounds.lower) <= min(box.u.upper, $0.uBounds.upper)
        && max(box.v.lower, $0.vBounds.lower) <= min(box.v.upper, $0.vBounds.upper)
    }
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
