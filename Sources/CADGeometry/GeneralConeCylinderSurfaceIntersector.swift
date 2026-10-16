import CADCore

struct GeneralConeCylinderSurfaceIntersector {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
  // The former numerical/tolerance branches did not establish original common-set
  // authority. U4 must supply complete original source/UV coverage before success.
  func intersections(
    cone: CanonicalAnalyticSurface.Cone,
    cylinder: CanonicalAnalyticSurface.Cylinder,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
      execution.context = execution.context.at(stage: .relation)
      do {
          try execution.checkpoint()
          throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
              message: "GeneralConeCylinderSurfaceIntersector requires complete original source relation authority.")
      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Existing ordinary callers reach this
  // explicit refusal entry. It performs no numeric solve or fallback;
  // U4 must provide source-bound relation proof and direct execution before success.
  func intersections(
    cone: CanonicalAnalyticSurface.Cone,
    cylinder: CanonicalAnalyticSurface.Cylinder,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(
            cone: cone,
            cylinder: cylinder,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance,
            using: &execution)
    }
}
