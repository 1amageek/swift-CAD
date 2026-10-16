import CADCore

/// Produces the complete discrete event set in the requested curve and
/// surface ranges. Implementations must throw a typed error when completeness
/// cannot be certified and must report a continuous overlap as
/// `KernelError.Code.nonDiscreteIntersection`; an empty array therefore
/// certifies that no discrete event exists in the requested ranges.
public protocol CurveSurfaceIntersecting: Sendable {
  func intersections(
    curve: Curve3D,
    surface: Surface3D,
    options: CurveSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws -> [CurveSurfaceIntersection]

  func intersections(
    curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection]
}

extension CurveSurfaceIntersecting {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom producers must implement direct original
  // traversal before admitted callers may use their results as complete crossing evidence.
  public func intersections(
    curve: Curve3D, surface: Surface3D,
    options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [CurveSurfaceIntersection] {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This curve-surface producer does not implement direct original execution.")
  }
}
