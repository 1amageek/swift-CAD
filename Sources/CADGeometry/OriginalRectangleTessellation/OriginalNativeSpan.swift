import CADCore

extension PreparedBSplineSurfaceDifferentialEncloser {
  package struct OriginalNativeSpan: Sendable {
    package let surface: BSplineSurface3D
    package let tolerance: ModelingTolerance
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let uBounds: ScalarInterval
    package let vBounds: ScalarInterval
    let patch: RationalBezierSurfaceJetEncloser.PreparedPatch

    func validate(on source: BSplineSurface3D, over box: SurfaceParameterBox,
                  tolerance callerTolerance: ModelingTolerance) throws {
      try callerTolerance.validate()
      try Task.checkCancellation()
      guard source == surface, callerTolerance == tolerance,
        box.u.lower.isFinite, box.u.upper.isFinite,
        box.v.lower.isFinite, box.v.upper.isFinite,
        box.u.lower <= box.u.upper, box.v.lower <= box.v.upper,
        box.u.lower >= uBounds.lower, box.u.upper <= uBounds.upper,
        box.v.lower >= vBounds.lower, box.v.upper <= vBounds.upper else {
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

