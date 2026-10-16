import CADCore
import CADGeometry

/// Resolves true nonzero material boundaries from complete original contacts.
public protocol OriginalPlanarNonzeroBoundaryResolving: Sendable {
    func boundary(from source: PreparedOriginalPlanarContourContacts,
        using execution: inout OriginalQueryExecution) throws -> OriginalPlanarNonzeroBoundary
}
