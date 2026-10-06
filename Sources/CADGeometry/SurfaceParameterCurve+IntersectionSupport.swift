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
    try tolerance.validate()
    switch self {
    case .certifiedImplicit(let curve):
      let expectedHostingSurface: Surface3D
      switch curve.role {
      case .first:
        expectedHostingSurface = curve.intersection.firstSurface
        guard hostingSurface == expectedHostingSurface else {
          throw supportSurfaceMismatch(tolerance: tolerance)
        }
        return curve.intersection.secondSurface
      case .second:
        expectedHostingSurface = curve.intersection.secondSurface
        guard hostingSurface == expectedHostingSurface else {
          throw supportSurfaceMismatch(tolerance: tolerance)
        }
        return curve.intersection.firstSurface
      }
    case .certifiedAnalyticImplicit(let curve):
      guard hostingSurface == curve.intersection.analyticSurface else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      return .bSpline(curve.intersection.boundedSurface)
    case .certifiedAnalyticPair(let curve):
      guard hostingSurface == curve.intersection.surface(for: curve.role) else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      switch curve.role {
      case .first:
        return curve.intersection.secondSurface
      case .second:
        return curve.intersection.firstSurface
      }
    case .originalAffineWord(let curve):
      try curve.validate(on: hostingSurface, tolerance: tolerance)
      guard let support = try curve.source.parameterCurve.otherIntersectionSupportSurface(
        on: curve.source.surface, tolerance: tolerance) else { return nil }
      return .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(source: support,
        operationWord: curve.target.operationWord, tolerance: tolerance)))
    case .originalImage(let curve):
      try curve.validate(on: hostingSurface, tolerance: tolerance)
      guard let support = try curve.source.parameterCurve.otherIntersectionSupportSurface(
        on: curve.source.surface, tolerance: tolerance) else { return nil }
      return .affineImage(try OriginalImageSurface3D(source: support,
        transform: curve.targetImage.transform, tolerance: tolerance))
    case .rigidImage(let curve):
      guard hostingSurface == curve.targetSurface else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      guard
        let sourceSupport = try curve.source.parameterCurve
          .otherIntersectionSupportSurface(
            on: curve.source.surface,
            tolerance: tolerance
          )
      else {
        return nil
      }
      return try curve.transform.applying(
        to: sourceSupport,
        tolerance: tolerance
      )
    case .offsetSurfaceImage(let curve):
      guard hostingSurface == (try curve.targetSurface(tolerance: tolerance)) else {
        throw supportSurfaceMismatch(tolerance: tolerance)
      }
      return nil
    case .periodicTranslation(let base, _, _):
      return try base.otherIntersectionSupportSurface(
        on: hostingSurface,
        tolerance: tolerance
      )
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
    try tolerance.validate()
    switch self {
    case .certifiedImplicit(let curve):
      return try implicitIntersectionBoundingBox(
        curve.intersection,
        startFraction: curve.startFraction,
        endFraction: curve.endFraction,
        tolerance: tolerance
      )
    case .certifiedAnalyticImplicit(let curve):
      return try implicitIntersectionBoundingBox(
        curve.intersection.implicitCurve,
        startFraction: curve.startFraction,
        endFraction: curve.endFraction,
        tolerance: tolerance
      )
    case .certifiedAnalyticPair(let curve):
      return try curve.intersection.boundingBox(tolerance: tolerance)
    case .originalAffineWord(let curve):
      let q = try curve.source.boundingBox(over: curve.mappedRange(.init(lower: 0, upper: 1)), tolerance: tolerance)
      let field = IntervalVector3DBounds(x: .init(lower: q.minimum.x, upper: q.maximum.x),
        y: .init(lower: q.minimum.y, upper: q.maximum.y), z: .init(lower: q.minimum.z, upper: q.maximum.z))
      let value = try OriginalAffineWordJetTransport.position(curve.target.preparedWord,
        bounds: field, consumeWork: { try Task.checkCancellation() })
      return try BoundingBox3D(minimum: .init(x: value.x.lower, y: value.y.lower, z: value.z.lower),
        maximum: .init(x: value.x.upper, y: value.y.upper, z: value.z.upper)).expanded(by: tolerance.distance)
    case .originalImage(let curve):
      let bounds = try curve.source.boundingBox(over: curve.mappedRange(ScalarInterval(lower: 0, upper: 1)), tolerance: tolerance)
      return try BoundingBox3D(points: boundingBoxCorners(bounds).map(curve.targetImage.transform.applying(to:)))
        .expanded(by: tolerance.distance)
    case .rigidImage(let curve):
      let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
      let sourceBounds = try curve.source.boundingBox(
        over: interval,
        tolerance: tolerance
      )
      return try BoundingBox3D(
        points: boundingBoxCorners(sourceBounds).map(
          curve.transform.applying(to:)
        )
      ).expanded(by: tolerance.distance)
    case .offsetSurfaceImage:
      return nil
    case .periodicTranslation(let base, _, _):
      return try base.exactIntersectionBoundingBox(
        tolerance: tolerance
      )
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
  ) throws -> BoundingBox3D {
    let lower = min(startFraction, endFraction)
    let upper = max(startFraction, endFraction)
    if upper <= 1.0 {
      return try intersection.boundingBox(
        fromNormalizedFraction: lower,
        toNormalizedFraction: upper,
        tolerance: tolerance
      )
    }
    if lower >= 1.0 {
      return try intersection.boundingBox(
        fromNormalizedFraction: lower - 1.0,
        toNormalizedFraction: upper - 1.0,
        tolerance: tolerance
      )
    }
    let first = try intersection.boundingBox(
      fromNormalizedFraction: lower,
      toNormalizedFraction: 1.0,
      tolerance: tolerance
    )
    let second = try intersection.boundingBox(
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: upper - 1.0,
      tolerance: tolerance
    )
    return try first.union(second)
  }

  private func boundingBoxCorners(
    _ bounds: BoundingBox3D
  ) -> [Point3D] {
    [
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
