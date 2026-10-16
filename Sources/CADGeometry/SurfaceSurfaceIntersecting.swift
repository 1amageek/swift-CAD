import CADCore

public protocol SurfaceSurfaceIntersecting: Sendable {
  func intersectionResult(
    first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionResult
  func intersectionResult(
    first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersectionResult
  func intersectionResult(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionResult
  func intersectionResult(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersectionResult
  func intersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection]
  func intersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection]
  func intersections(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection]

  func prepareOriginalPair(
    first: Surface3D, second: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> any OriginalSurfacePairIntersecting

  func prepareOriginalSelf(
    surface: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> any OriginalSurfacePairIntersecting

}

extension SurfaceSurfaceIntersecting {
  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must implement the
  // ordinary bounded rich-result witness with complete original box coverage
  // before callers can treat this entry as an accepted intersection result.
  public func intersectionResult(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionResult {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no ordinary bounded rich result producer.")
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must implement rich
  // original coverage before this public witness may return a complete receipt.
  public func intersectionResult(
    first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionResult {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no rich original result producer.")
  }
  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must forward the
  // caller ledger through rich publication; array replay is not that witness.
  public func intersectionResult(
    first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersectionResult {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no admitted rich result producer.")
  }
  // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must retain selected
  // original domain-pair coverage before publishing this rich public result.
  public func intersectionResult(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersectionResult {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no rich original domain-pair producer.")
  }
  // FIXME(INCOMPLETE_IMPLEMENTATION): An injected surface-pair conformer
  // must forward every original work/storage visit before bounded callers can
  // consume its results. The legacy requirement cannot supply that witness.
  public func intersections(
    first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no caller-admitted original producer.")
  }
  // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
  // the same original-domain pair producer and forward every caller visit;
  // no legacy restricted-surface conversion establishes this witness.
  public func intersections(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer has no original domain-pair producer.")
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
  // retained original support preparation under the supplied invocation.
  // A legacy per-box intersection replay cannot establish this session.
  public func prepareOriginalPair(
    first: Surface3D, second: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> any OriginalSurfacePairIntersecting {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer cannot prepare a caller-admitted original session.")
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
  // one retained original support aliased for both self-query roles under
  // this invocation; replaying independent legacy preparation is not a witness.
  public func prepareOriginalSelf(
    surface: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> any OriginalSurfacePairIntersecting {
    throw KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message: "This surface-pair conformer cannot prepare an original self-query session.")
  }

}
