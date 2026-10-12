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

public protocol OriginalIssuedGeometricRelationResolving: Sendable {
    func resolve<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ relations: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>, limits: OriginalDomainIdentityLimits,
        geometryLimits: ExactGeometricRelationLimits, maximumPoints: Int, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> OriginalIssuedGeometricRelations<S,E,C,T,F,D>
}
