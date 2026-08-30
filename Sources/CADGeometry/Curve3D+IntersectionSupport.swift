import CADCore

extension Curve3D {
  /// Returns the other exact surface that defines this intersection curve
  /// when `hostingSurface` is one of its retained supports.
  package func otherIntersectionSupportSurface(
    on hostingSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Surface3D? {
    try tolerance.validate()
    guard
      let supports = try intersectionSupportSurfaces(
        tolerance: tolerance
      )
    else {
      return nil
    }
    let equivalence = DefaultAnalyticSurfaceEquivalenceResolver()
    if try equivalence.areEquivalent(
      hostingSurface,
      supports.first,
      tolerance: tolerance
    ) {
      return supports.second
    }
    if try equivalence.areEquivalent(
      hostingSurface,
      supports.second,
      tolerance: tolerance
    ) {
      return supports.first
    }
    return nil
  }

  private func intersectionSupportSurfaces(
    tolerance: ModelingTolerance
  ) throws -> (first: Surface3D, second: Surface3D)? {
    switch self {
    case .analytic(.planeTorus(let curve)):
      return (curve.planeSurface, curve.torusSurface)
    case .implicit(let curve):
      return (curve.firstSurface, curve.secondSurface)
    case .surfaceLift(let curve):
      guard
        let other = try curve.parameterCurve
          .otherIntersectionSupportSurface(
            on: curve.surface,
            tolerance: tolerance
          )
      else {
        return nil
      }
      return (curve.surface, other)
    case .certifiedIntersection(let curve):
      switch curve {
      case .sphereCone(let source):
        return (source.sphereSurface, source.coneSurface)
      case .coneCone(let source):
        return (source.referenceSurface, source.parameterizedSurface)
      case .coneCylinder(let source):
        return (source.coneSurface, source.cylinderSurface)
      case .coneTorus(let source):
        return (source.coneSurface, source.torusSurface)
      case .parallelTorusTorus(let source):
        return (source.primarySurface, source.secondarySurface)
      }
    case .rigidImage(let curve):
      guard
        let sourceSupports = try curve.source
          .intersectionSupportSurfaces(tolerance: tolerance)
      else {
        return nil
      }
      return (
        try curve.transform.applying(
          to: sourceSupports.first,
          tolerance: tolerance
        ),
        try curve.transform.applying(
          to: sourceSupports.second,
          tolerance: tolerance
        )
      )
    case .line, .circle, .bSpline, .affineImage,
      .analytic(.line), .analytic(.circle), .analytic(.arc),
      .analytic(.ellipse), .analytic(.hyperbola),
      .analytic(.parabola):
      return nil
    }
  }
}
