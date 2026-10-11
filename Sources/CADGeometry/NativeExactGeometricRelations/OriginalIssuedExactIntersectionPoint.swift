#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import L6
import DI0
import DI
import SourceIssuer
import IssuedGraphs
#endif

/// Exact authored parameters; local parameters and every auxiliary lift remain in the geometry receipt.
public struct OriginalIssuedExactIntersectionPoint: Sendable {
    public let sourceRelation: any OriginalIssuedGraphRelationOwning
    public let pairOrdinal: Int
    public let local: ExactGeometricGraphPoint<OriginalExactScalarDomain>
    public let firstParameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>]
    public let secondParameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>]
    /// Forward-restored source coordinates when a checked source reduction removes auxiliaries.
    public let originalFirstCoordinates: [ExactAlgebraicScalar<OriginalExactScalarDomain>]?
    public var position: ExactXYZ<OriginalExactScalarDomain> { local.position }
    init(sourceRelation: any OriginalIssuedGraphRelationOwning, pairOrdinal: Int, local: ExactGeometricGraphPoint<OriginalExactScalarDomain>,
        firstParameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>], secondParameters: [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        originalFirstCoordinates: [ExactAlgebraicScalar<OriginalExactScalarDomain>]? = nil) {
        self.sourceRelation = sourceRelation; self.pairOrdinal = pairOrdinal; self.local = local; self.firstParameters = firstParameters; self.secondParameters = secondParameters
        self.originalFirstCoordinates = originalFirstCoordinates
    }
}
