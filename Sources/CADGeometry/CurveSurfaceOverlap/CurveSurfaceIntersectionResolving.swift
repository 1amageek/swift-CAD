import CADCore

/// Returns complete isolated intersections and certified continuous overlap intervals.
/// Unresolved membership or incomplete clipping must fail instead of returning a partial set.
public protocol CurveSurfaceIntersectionResolving: Sendable {
  func intersectionResult(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws -> CurveSurfaceIntersectionResult
  func intersectionResult(
    curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveSurfaceIntersectionResult
}

extension CurveSurfaceIntersectionResolving {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom overlap producers must implement direct
  // original sector execution before admitted callers may consume complete receipts.
  public func intersectionResult(
    curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> CurveSurfaceIntersectionResult {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This overlap producer does not implement direct original execution.")
  }
}
