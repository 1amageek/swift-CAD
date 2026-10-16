import CADCore

/// Whole original-law admission using the invocation owner's cumulative allowance.
public protocol OriginalSurfaceEmbeddingValidating: Sendable {
  func validate(
    _ surface: Surface3D, over domain: SurfaceParameterBox, maximumLocalSubdivisionDepth: Int,
    maximumLocalCellCount: Int, maximumPairSubdivisionDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws

  func validateSeparation(
    first: Surface3D, firstDomain: SurfaceParameterBox, second: Surface3D,
    secondDomain: SurfaceParameterBox, maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
  func validateBoundaryContacts(
    first: Surface3D, second: Surface3D, sharedBoundaries: [OriginalSurfaceSharedBoundary],
    allowedCorners: [(Point2D, Point2D)], maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
}
