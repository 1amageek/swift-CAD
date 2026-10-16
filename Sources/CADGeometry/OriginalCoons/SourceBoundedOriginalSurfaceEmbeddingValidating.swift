import CADCore

/// Separates original source recursion from geometric subdivision authority.
public protocol SourceBoundedOriginalSurfaceEmbeddingValidating: OriginalSurfaceEmbeddingValidating
{
  func validate(
    _ surface: Surface3D, over domain: SurfaceParameterBox, maximumLocalSubdivisionDepth: Int,
    maximumLocalCellCount: Int, maximumPairSubdivisionDepth: Int, remainingSourceDepth: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws

  func validateSeparation(
    first: Surface3D, firstDomain: SurfaceParameterBox, second: Surface3D,
    secondDomain: SurfaceParameterBox, maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws

  func validateBoundaryContacts(
    first: Surface3D, second: Surface3D, sharedBoundaries: [OriginalSurfaceSharedBoundary],
    allowedCorners: [(Point2D, Point2D)], maximumSubdivisionDepth: Int, maximumSpanCount: Int,
    remainingSourceDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws
}
