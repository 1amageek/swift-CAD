import CADCore

extension DefaultCurveSurfaceIntersector: CurveSurfaceIntersectionResolving {
  public func intersectionResult(
    curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance
  ) throws -> CurveSurfaceIntersectionResult {
    try options.validate(tolerance: tolerance)
    var execution = try OriginalQueryExecution.curveSurface(
      options: options,
      context: .init(
        operation: .curveSurface, entry: .ordinary, stage: .request,
        first: .init(role: .curve, request: .curveRange(options.curveRange)),
        second: .init(
          role: .surface,
          request: .surfaceRanges(u: options.surfaceURange, v: options.surfaceVRange))))
    return try intersectionResult(
      curve: curve, surface: surface, options: options,
      tolerance: tolerance, using: &execution)
  }

  public func intersectionResult(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult {
    execution.context = execution.context.fillingMissing(from: .init(operation: .curveSurface, entry: .admitted,
      stage: .request, first: .init(role: .curve, request: .curveRange(options.curveRange)),
      second: .init(role: .surface, request: .surfaceRanges(u: options.surfaceURange, v: options.surfaceVRange)))).at(stage: .request)
    do {
      try execution.checkpoint()
      try options.validate(tolerance: tolerance)
      let result = try originalIntersectionResult(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  private func originalIntersectionResult(curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult {
      if let linear = try OriginalLinearPlanePublicProducer().resolve(curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true) { return linear }
      if let periodic = try OriginalPeriodicOffsetCurvePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return periodic
      }
      if let pairLift = try OriginalCertifiedPairLiftPublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return pairLift
      }
      if let coneCone = try OriginalCertifiedConeConePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return coneCone
      }
      if let node = try OriginalSphereConeNodePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return node
      }
      if let sphereCone = try OriginalCertifiedSphereConePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return sphereCone
      }
      if let coaxial = try OriginalCertifiedCoaxialPublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return coaxial
      }
      if let excluded = try OriginalCertifiedApexPlanePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return excluded
      }
      if let implicit = try OriginalImplicitCurvePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return implicit
      }
      if let angular = try OriginalAngularPlanePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution)
      {
        return angular
      }
      if let axis = try OriginalRevolutionAxisLinePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return axis
      }
      if let drafted = try OriginalDraftedZeroLinePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return drafted
      }
      if let lift = try OriginalRetainedLiftPlanePublicProducer().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, using: &execution, retainingRelations: true)
      {
        return lift
      }
      return try CurveSurfaceOverlapResolver().resolve(
        curve: curve, surface: surface,
        options: options, tolerance: tolerance, intersector: self, using: &execution)
  }
}
