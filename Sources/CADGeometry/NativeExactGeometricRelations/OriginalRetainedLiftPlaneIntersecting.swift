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

public protocol OriginalRetainedLiftPlaneIntersecting: Sendable {
    func intersectionResult<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading,A: ExactScalarAdmission & ~Copyable>(
        lift: borrowing OriginalRetainedSurfaceLiftDomainCover<S>,plane: borrowing OriginalIssuedPlaneGraph<P>,
        maximumPairs: Int,limits: OriginalDomainIdentityLimits,geometryLimits: ExactGeometricRelationLimits,
        maximumPoints: Int,using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> CurveSurfaceIntersectionResult
}
