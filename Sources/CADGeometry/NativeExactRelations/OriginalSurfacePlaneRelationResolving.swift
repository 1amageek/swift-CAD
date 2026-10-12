#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Consumes sealed source preparations without fabricating a finite plane chart.
public protocol OriginalSurfacePlaneRelationResolving: Sendable {
    func resolve<S: Sendable, E: Sendable, C: Sendable, P: OriginalPlaneSourceReading,
        A: ExactScalarAdmission & ~Copyable>(
        surface: borrowing OriginalIssuedGraphFamily<S,E,C>,
        plane: borrowing OriginalIssuedPlaneGraph<P>, planeFirst: Bool,
        maximumPairs: Int, limits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using a: inout A) throws(NativeExactRelationFailure) -> OriginalSurfacePlaneRelations<S,E,C,P>
}
