import CADCore

struct BoundedBSplineSurfaceIntersector {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
  // The former numerical/tolerance branches did not establish original common-set
  // authority. U4 must supply complete original source/UV coverage before success.
  func intersections(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
      execution.context = execution.context.at(stage: .relation)
      do {
          try execution.checkpoint()
          try first.validate(tolerance: tolerance, using: &execution)
          try second.validate(tolerance: tolerance, using: &execution)
          func equal(_ lhs: BSplineSurface3D, _ rhs: BSplineSurface3D,
              using execution: inout OriginalQueryExecution) throws -> Bool {
              func count(_ source: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> Int {
                  var total = try exactScalarCount(source.uKnots.count, source.vKnots.count, multiply: false)
                  for row in source.controlPoints {
                      try execution.consumeWork(1)
                      total = try exactScalarCount(total, row.count, multiply: false)
                  }
                  for row in source.weights {
                      try execution.consumeWork(1)
                      total = try exactScalarCount(total, row.count, multiply: false)
                  }
                  return total
              }
              let lhsCount = try count(lhs, using: &execution)
              let rhsCount = try count(rhs, using: &execution)
              try execution.consumeWork(exactScalarCount(lhsCount, rhsCount, multiply: false))
              return lhs == rhs
          }
          if case .bSpline(let originalFirst) = firstSurface,
              case .bSpline(let originalSecond) = secondSurface,
              try equal(originalFirst, first, using: &execution),
              try equal(originalSecond, second, using: &execution),
              try equal(first, second, using: &execution) {
              try execution.retainStorage(bytes: MemoryLayout<SurfaceSurfaceIntersection>.stride)
              let result: [SurfaceSurfaceIntersection] = [.coincident(try .init(residual: 0, tolerance: tolerance))]
              try execution.checkpoint()
              return result
          }
          throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
              message: "BoundedBSplineSurfaceIntersector requires complete original source relation authority.")
      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
  // this ordinary publication entry. It performs no numeric solve or fallback;
  // U4 must provide source-bound relation proof and direct execution before success.
  func intersections(
    first: BSplineSurface3D,
    second: BSplineSurface3D,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
      try CurrentTaskCancellationChecker().checkCancellation()
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message: "BoundedBSplineSurfaceIntersector has no ordinary original-proof publication.")
  }

}
