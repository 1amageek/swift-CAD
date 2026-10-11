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

public protocol OriginalLiftPlaneRelationResolving: Sendable {
    func resolve<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading,A: ExactScalarAdmission & ~Copyable>(
        lift: borrowing OriginalRetainedSurfaceLiftDomainCover<S>,plane: borrowing OriginalIssuedPlaneGraph<P>,
        maximumPairs: Int,limits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalLiftPlaneRelations<S,P>
}
