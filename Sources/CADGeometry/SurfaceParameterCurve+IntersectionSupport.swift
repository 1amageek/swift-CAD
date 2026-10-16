import CADCore

extension SurfaceParameterCurve {
  /// Returns the second exact support of a certified intersection pcurve.
  ///
  /// The receiver is the parameter-space representation on `hostingSurface`.
  /// A non-`nil` result certifies that the lifted curve is the intersection
  /// of `hostingSurface` and the returned surface. Curves without retained
  /// two-surface provenance deliberately return `nil`.
  package func otherIntersectionSupportSurface(
    on hostingSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Surface3D? {
      var execution = try OriginalQueryExecution.independentGeometry()
      return try otherIntersectionSupportSurface(on: hostingSurface, tolerance: tolerance, using: &execution)
  }

  package func otherIntersectionSupportSurface(
    on hostingSurface: Surface3D,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Surface3D? {
      try execution.consumeWork(1)
    try tolerance.validate()
    switch self {
    case .certifiedImplicit(let curve):
      let expectedHostingSurface: Surface3D
      switch curve.role {
      case .first:
        expectedHostingSurface = curve.intersection.firstSurface
        try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: expectedHostingSurface, using: &execution)
        guard hostingSurface == expectedHostingSurface else {
          throw supportSurfaceMismatch(tolerance: tolerance)
        }
        return curve.intersection.secondSurface
      case .second:
        expectedHostingSurface = curve.intersection.secondSurface
        try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: expectedHostingSurface, using: &execution)
        guard hostingSurface == expectedHostingSurface else {
          throw supportSurfaceMismatch(tolerance: tolerance)
        }
        return curve.intersection.firstSurface
      }
    case .certifiedAnalyticImplicit(let curve):
      try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: curve.intersection.analyticSurface, using: &execution)
      guard hostingSurface == curve.intersection.analyticSurface else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      return .bSpline(curve.intersection.boundedSurface)
    case .certifiedAnalyticPair(let curve):
      let retainedSupport = curve.intersection.surface(for: curve.role)
      try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: retainedSupport, using: &execution)
      guard hostingSurface == retainedSupport else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      switch curve.role {
      case .first:
        return curve.intersection.secondSurface
      case .second:
        return curve.intersection.firstSurface
      }
    case .originalAffineWord(let curve):
      try curve.validate(on: hostingSurface, tolerance: tolerance, using: &execution)
      guard let support = try curve.source.parameterCurve.otherIntersectionSupportSurface(
        on: curve.source.surface, tolerance: tolerance, using: &execution) else { return nil }
      return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: support,
        operationWord: curve.target.operationWord, tolerance: tolerance,
        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)))
    case .originalImage(let curve):
      try curve.validate(on: hostingSurface, tolerance: tolerance, using: &execution)
      guard let support = try curve.source.parameterCurve.otherIntersectionSupportSurface(
        on: curve.source.surface, tolerance: tolerance, using: &execution) else { return nil }
      return .affineImage(try OriginalImageSurface3D(source: support,
        transform: curve.targetImage.transform, tolerance: tolerance,
        remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
        maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution))
    case .rigidImage(let curve):
      try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: curve.targetSurface, using: &execution)
      guard hostingSurface == curve.targetSurface else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      guard
        let sourceSupport = try curve.source.parameterCurve
          .otherIntersectionSupportSurface(
            on: curve.source.surface,
            tolerance: tolerance
          , using: &execution)
      else {
        return nil
      }
      return try curve.transform.applying(
        to: sourceSupport,
        tolerance: tolerance, using: &execution
      )
    case .offsetSurfaceImage(let curve):
      let retainedTarget = try curve.targetSurface(tolerance: tolerance, using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
      try GeometryStructuralComparisonWork.charge(surface: retainedTarget, using: &execution)
      guard hostingSurface == retainedTarget else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      return nil
    case .periodicTranslation(let base, _, _):
      return try base.otherIntersectionSupportSurface(
        on: hostingSurface,
        tolerance: tolerance
      , using: &execution)
    case .affine, .constantU, .constantV, .harmonic,
      .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation,
      .projectedAnalytic:
      return nil
    }
  }

  private func supportSurfaceMismatch(
    tolerance: ModelingTolerance
  ) -> KernelError {
    KernelError(
      phase: .geometry,
      code: .invalidInput,
      tolerance: tolerance,
      message: "Certified intersection provenance does not belong to the requested hosting surface."
    )
  }

  /// Returns the full-branch box retained by certified intersection truth.
  /// A face-local cache without such truth returns `nil`.
  package func exactIntersectionBoundingBox(
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D? {
      var execution = try OriginalQueryExecution.independentGeometry()
      return try exactIntersectionBoundingBox(tolerance: tolerance, using: &execution)
  }

  package func exactIntersectionBoundingBox(
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> BoundingBox3D? {
      try execution.consumeWork(1)
    try tolerance.validate()
    switch self {
    case .certifiedImplicit(let curve):
      return try implicitIntersectionBoundingBox(
        curve.intersection,
        startFraction: curve.startFraction,
        endFraction: curve.endFraction,
        tolerance: tolerance
      , using: &execution)
    case .certifiedAnalyticImplicit(let curve):
      return try implicitIntersectionBoundingBox(
        curve.intersection.implicitCurve,
        startFraction: curve.startFraction,
        endFraction: curve.endFraction,
        tolerance: tolerance
      , using: &execution)
    case .certifiedAnalyticPair(let curve):
      return try curve.intersection.boundingBox(tolerance: tolerance, using: &execution)
    case .originalAffineWord(let curve):
      let q = try curve.source.boundingBox(over: curve.mappedRange(.init(lower: 0, upper: 1)), tolerance: tolerance, using: &execution)
      let field = IntervalVector3DBounds(x: .init(lower: q.minimum.x, upper: q.maximum.x),
        y: .init(lower: q.minimum.y, upper: q.maximum.y), z: .init(lower: q.minimum.z, upper: q.maximum.z))
      let value = try OriginalAffineWordJetTransport.position(curve.target.preparedWord,
        bounds: field, using: &execution)
      return try BoundingBox3D(minimum: .init(x: value.x.lower, y: value.y.lower, z: value.z.lower),
        maximum: .init(x: value.x.upper, y: value.y.upper, z: value.z.upper)).expanded(by: tolerance.distance)
    case .originalImage(let curve):
      let bounds = try curve.source.boundingBox(over: curve.mappedRange(ScalarInterval(lower: 0, upper: 1)), tolerance: tolerance, using: &execution)
      return try BoundingBox3D(points: OriginalCoefficientAllocation.map(elements: boundingBoxCorners(bounds, using: &execution), using: &execution) { point, _ in curve.targetImage.transform.applying(to: point) })
        .expanded(by: tolerance.distance)
    case .rigidImage(let curve):
      let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
      let sourceBounds = try curve.source.boundingBox(
        over: interval,
        tolerance: tolerance
      , using: &execution)
      return try BoundingBox3D(
        points: OriginalCoefficientAllocation.map(elements: boundingBoxCorners(sourceBounds, using: &execution), using: &execution) { point, _ in
          curve.transform.applying(to: point)
        }
      ).expanded(by: tolerance.distance)
    case .offsetSurfaceImage:
      return nil
    case .periodicTranslation(let base, _, _):
      return try base.exactIntersectionBoundingBox(
        tolerance: tolerance
      , using: &execution)
    case .affine, .constantU, .constantV, .harmonic,
      .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation,
      .projectedAnalytic:
      return nil
    }
  }

  private func implicitIntersectionBoundingBox(
    _ intersection: CertifiedImplicitIntersectionCurve,
    startFraction: Double,
    endFraction: Double,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
      try execution.consumeWork(1)
    let lower = min(startFraction, endFraction)
    let upper = max(startFraction, endFraction)
    if upper <= 1.0 {
      return try intersection.boundingBox(
        fromNormalizedFraction: lower,
        toNormalizedFraction: upper,
        tolerance: tolerance
      , using: &execution)
    }
    if lower >= 1.0 {
      return try intersection.boundingBox(
        fromNormalizedFraction: lower - 1.0,
        toNormalizedFraction: upper - 1.0,
        tolerance: tolerance
      , using: &execution)
    }
    let first = try intersection.boundingBox(
      fromNormalizedFraction: lower,
      toNormalizedFraction: 1.0,
      tolerance: tolerance
    , using: &execution)
    let second = try intersection.boundingBox(
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: upper - 1.0,
      tolerance: tolerance
    , using: &execution)
    return try first.union(second)
  }

  private func boundingBoxCorners(
    _ bounds: BoundingBox3D
  , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
      try execution.consumeWork(1)
    try OriginalCoefficientAllocation.reserve(count: 8, of: Point3D.self, using: &execution)
    return [
      Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z),
      Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z),
      Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z),
      Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z),
      Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z),
      Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z),
      Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z),
      Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z),
    ]
  }
}
