import CADCore

extension DefaultSurfaceSurfaceIntersector {
  public func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionResult {
    try options.validate(tolerance: tolerance)
    var execution = try OriginalQueryExecution.surfaceSurface(options: options,
      context: .init(operation: .surfaceSurface, entry: .ordinary, stage: .request,
        first: .init(role: .firstSurface, request: .surfaceBox(firstBox)),
        second: .init(role: .secondSurface, request: .surfaceBox(secondBox))))
    return try intersectionResult(first: first, over: firstBox, second: second, over: secondBox,
      options: options, tolerance: tolerance, using: &execution)
  }

  public func intersectionResult(first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult {
    try options.validate(tolerance: tolerance)
    var execution = try OriginalQueryExecution.surfaceSurface(options: options,
      context: .init(operation: .surfaceSurface, entry: .ordinary, stage: .request,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    return try intersectionResult(first: first, second: second, options: options, tolerance: tolerance, using: &execution)
  }

  public func intersectionResult(first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
    try originalIntersectionResult(first: first, second: second, options: options,
      tolerance: tolerance, includeRelations: true, using: &execution)
  }

  public func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
    try originalIntersectionResult(first: first, second: second, firstBox: firstBox, secondBox: secondBox,
      options: options, tolerance: tolerance, includeRelations: true, using: &execution)
  }
}
