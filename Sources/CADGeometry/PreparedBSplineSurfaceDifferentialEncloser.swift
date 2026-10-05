import CADCore

/// Retains original nonperiodic coefficient authority and closed knot owners.
package struct PreparedBSplineSurfaceDifferentialEncloser: Sendable {
  package let surface: BSplineSurface3D
  private let preparationTolerance: ModelingTolerance
  private let originalSpans: [OriginalNativeSpan]

  package init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
    try surface.validate(tolerance: tolerance)
    try Task.checkCancellation()
    self.surface = surface
    self.preparationTolerance = tolerance
    let encloser = RationalBezierSurfaceJetEncloser()
    let decomposer = BSplineSurfaceBezierDecomposer()
    let singleBezier = surface.uControlPointCount == surface.uDegree + 1
      && surface.vControlPointCount == surface.vDegree + 1
      && surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ $0 == surface.uKnots[surface.uDegree] })
      && surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ $0 == surface.uKnots[surface.uControlPointCount] })
      && surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ $0 == surface.vKnots[surface.vDegree] })
      && surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ $0 == surface.vKnots[surface.vControlPointCount] })
    if singleBezier {
      // This tensor is exactly the stored original source, without extraction.
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
    try originalNativeSpans(over: box, tolerance: tolerance, maximumSpanCount: 262_144)
  }

  func originalNativeSpans(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
                           maximumSpanCount: Int) throws -> [OriginalNativeSpan] {
    try Self.selectOriginalNativeSpans(from: originalSpans, surface: surface,
      preparationTolerance: preparationTolerance, over: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount)
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
    let encloser = RationalBezierSurfaceJetEncloser()
    var result: SurfaceIntervalVectorJet?
    for span in originalSpans {
      let patch = span.patch
      try Task.checkCancellation()
      let uLower = max(parameters.u.lower, patch.uLower)
      let uUpper = min(parameters.u.upper, patch.uUpper)
      let vLower = max(parameters.v.lower, patch.vLower)
      let vUpper = min(parameters.v.upper, patch.vUpper)
      guard uUpper >= uLower, vUpper >= vLower else { continue }
      let box = SurfaceParameterBox(
        u: try ScalarInterval(lower: uLower, upper: uUpper),
        v: try ScalarInterval(lower: vLower, upper: vUpper))
      let patchJet = try Self.selectedJet(of: patch, over: box, tolerance: tolerance)
      result = result.map { $0.union(patchJet) } ?? patchJet
    }
    guard let result else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "The surface parameter box did not intersect a prepared B-spline Bezier span.")
    }
    return result
  }

  static func selectedJet(of patch: RationalBezierSurfaceJetEncloser.PreparedPatch,
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

  private static func numericallyStableInterval(
    _ interval: ScalarInterval,
    within bounds: (lower: Double, upper: Double),
    tolerance: ModelingTolerance
  ) throws -> ScalarInterval {
    let scale = max(1.0, abs(bounds.lower), abs(bounds.upper))
    let requestedWidth = max(
      tolerance.relative * scale * 4.0,
      Double.ulpOfOne * scale * 4_096.0
    )
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
