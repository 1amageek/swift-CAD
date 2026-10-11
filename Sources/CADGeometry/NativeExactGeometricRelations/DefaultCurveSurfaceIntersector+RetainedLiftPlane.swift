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

extension DefaultCurveSurfaceIntersector: OriginalRetainedLiftPlaneIntersecting {
    public func intersectionResult<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading,A: ExactScalarAdmission & ~Copyable>(
        lift: borrowing OriginalRetainedSurfaceLiftDomainCover<S>,plane: borrowing OriginalIssuedPlaneGraph<P>,
        maximumPairs: Int,limits: OriginalDomainIdentityLimits,geometryLimits: ExactGeometricRelationLimits,
        maximumPoints: Int,using a: inout A) throws(NativeExactGeometricRelationFailure) -> CurveSurfaceIntersectionResult {
        do {
            guard maximumPoints >= 0 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            let original = try DefaultOriginalLiftPlaneRelationResolver().resolve(lift:lift,plane:plane,maximumPairs:maximumPairs,
                limits:limits,cellLimits:geometryLimits.cells,topologyLimits:geometryLimits.topology,using:&a)
            let publication = try OriginalIssuedGeometricPublication.resolve(original,geometryLimits:geometryLimits,maximumPoints:maximumPoints,
                transports:{ pair in (original.firstGraphs[pair.firstGraphIndex].original.graph.parameterTransport,nil) },
                firstCoordinates:{ pair in original.firstReductions[pair.firstGraphIndex].originalCoordinates },using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalLiftPlaneGeometricRelations<S,P>.self))
            let receipt = OriginalLiftPlaneGeometricRelations(original:original,pairs:publication.pairs,exactPoints:publication.points)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points:[],overlaps:[],originalIssuedGeometricRelation:receipt)
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
