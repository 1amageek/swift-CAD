import CADCore
import CADGeometry

/// Resolves true nonzero material boundaries from complete original contacts.
public protocol OriginalPlanarNonzeroBoundaryResolving: Sendable {
    func boundary(from source: PreparedOriginalPlanarContourContacts,
        allowance: inout OriginalCurveContactAllowance,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void) throws -> OriginalPlanarNonzeroBoundary
}
