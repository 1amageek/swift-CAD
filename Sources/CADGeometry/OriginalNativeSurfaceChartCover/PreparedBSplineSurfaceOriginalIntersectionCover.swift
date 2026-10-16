import CADCore

extension PreparedBSplineSurfaceDifferentialEncloser {
  /// Intersection coverage retains finite multi-period boxes on the same admission.
  package func originalIntersectionNativeSpans<A: ExactScalarAdmission & ~Copyable>(over box: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int = 262_144,
    using execution: inout A) throws -> [OriginalNativeSpan] {
    try selectedOriginalNativeSpans(over: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, permitsMultiplePeriods: true, using: &execution)
  }
}
