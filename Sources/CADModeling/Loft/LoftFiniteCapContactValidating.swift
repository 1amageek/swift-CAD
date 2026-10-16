import CADCore
import CADGeometry
import CADTopology

/// Owns complete original intersection admission against both finite authored face regions.
public protocol LoftFiniteCapContactValidating: Sendable {
    /// Permits only shared topological boundaries, and rejects nonincident material contacts.
    /// Intersections outside either finite face, including its holes, do not invalidate the Loft.
    /// Unresolved loci, cancellation and exhausted original budgets must propagate as failure.
    func validate(capFaceIDs: [FaceID], sideFaceIDs: [FaceID],
                  model: BRepModel, tolerance: ModelingTolerance) throws
    /// Composes finite contact proof under the caller's cumulative resource owner.
    func validate(capFaceIDs: [FaceID], sideFaceIDs: [FaceID],
                  model: BRepModel, tolerance: ModelingTolerance,
                  using execution: inout OriginalQueryExecution) throws
}
