import CADCore

extension PreparedBSplineSurfaceDifferentialEncloser {
  /// Intersection source coverage admits finite multi-period boxes while the mesh
  /// entry retains its existing bounded-width capability contract.
  package func originalIntersectionNativeSpans(over box: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int = 262_144,
    consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> [OriginalNativeSpan] {
    try selectedOriginalNativeSpans(over: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, consumeWork: consumeWork,
      admittingStorage: consumeStorage, permitsMultiplePeriods: true)
  }

  package func originalIntersectionNativeSpans(over box: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int = 262_144,
    consumeWork: () throws -> Void, consumeStorage: (Int) throws -> Void)
    throws -> [OriginalNativeSpan] {
    try withoutActuallyEscaping(consumeStorage) { storage in
      try selectedOriginalNativeSpans(over: box, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, consumeWork: consumeWork,
        admittingStorage: storage, permitsMultiplePeriods: true)
    }
  }

}
