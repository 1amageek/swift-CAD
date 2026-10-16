import CADCore

extension Curve3D {
  /// Returns the other exact surface that defines this intersection curve
  /// when `hostingSurface` is one of its retained supports.
  package func otherIntersectionSupportSurface(
    on hostingSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> Surface3D? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try otherIntersectionSupportSurface(on: hostingSurface, tolerance: tolerance, using: &execution)
  }

  package func otherIntersectionSupportSurface(
    on hostingSurface: Surface3D,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Surface3D? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard let supports = try intersectionSupportSurfaces(tolerance: tolerance, using: &execution) else {
      return nil
    }
    try hostingSurface.validate(tolerance: tolerance, using: &execution)
    try supports.first.validate(tolerance: tolerance, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: supports.first, using: &execution)
    if hostingSurface == supports.first { return supports.second }
    try supports.second.validate(tolerance: tolerance, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: hostingSurface, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: supports.second, using: &execution)
    if hostingSurface == supports.second { return supports.first }
    // FIXME(INCOMPLETE_IMPLEMENTATION): General equivalent-description support membership
    // is not proved. Exact trim-contact consumers reach this metadata lookup; only retained
    // structural hosts may succeed until a complete original host-identity authority exists.
    return nil
  }

  private func intersectionSupportSurfaces(
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> (first: Surface3D, second: Surface3D)? {
    try execution.consumeWork(1)
    try execution.admitSourceDepth(0)
    switch self {
    case .parameterImage(let image):
      return try execution.withSourceDepthOffset(1) { execution in
        try image.source.intersectionSupportSurfaces(tolerance: tolerance, using: &execution)
      }

    case .originalConstructionChart(let image):
      return try execution.withSourceDepthOffset(1) { execution in
        try image.source.intersectionSupportSurfaces(tolerance: tolerance, using: &execution)
      }

    case .analytic(.planeTorus(let curve)):
      return (curve.planeSurface, curve.torusSurface)
    case .implicit(let curve):
      return (curve.firstSurface, curve.secondSurface)
    case .surfaceLift(let curve):
      guard
        let other = (try execution.withSourceDepthOffset(1) { execution in
          try execution.admitSourceDepth(0)
          return try curve.parameterCurve.otherIntersectionSupportSurface(
            on: curve.surface, tolerance: tolerance, using: &execution)
        })
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
        let sourceSupports = (try execution.withSourceDepthOffset(1) { execution in
          try curve.source.intersectionSupportSurfaces(tolerance: tolerance, using: &execution)
        })
      else {
        return nil
      }
      return (
        try curve.transform.applying(
          to: sourceSupports.first,
          tolerance: tolerance,
          using: &execution
        ),
        try curve.transform.applying(
          to: sourceSupports.second,
          tolerance: tolerance,
          using: &execution
        )
      )
    case .line, .circle, .bSpline, .affineImage,
      .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain,
      .originalPolyline, .originalGuideEndpointConnector, .originalDrafted,
      .originalAngularTransport, .originalAffineWord,
      .analytic(.line), .analytic(.circle), .analytic(.arc),
      .analytic(.ellipse), .analytic(.hyperbola),
      .analytic(.parabola):
      return nil
    }
  }
}
