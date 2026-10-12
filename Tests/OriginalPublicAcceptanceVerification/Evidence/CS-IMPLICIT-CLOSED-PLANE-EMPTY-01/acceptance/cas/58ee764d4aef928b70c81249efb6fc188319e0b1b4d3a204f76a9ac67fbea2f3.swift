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

public struct DefaultOriginalIssuedGeometricRelationResolver: OriginalIssuedGeometricRelationResolving {
    public init() {}
    public func resolve<S: Sendable,E: Sendable,C: Sendable,T: Sendable,F: Sendable,D: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ relations: borrowing OriginalIssuedGraphRelations<S,E,C,T,F,D>,limits: OriginalDomainIdentityLimits,
        geometryLimits: ExactGeometricRelationLimits,maximumPoints: Int,using a: inout A)
        throws(NativeExactGeometricRelationFailure) -> OriginalIssuedGeometricRelations<S,E,C,T,F,D> {
        do {
            guard maximumPoints >= 0 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            try relations.admitProof(limits:limits,using:&a)
            let retained = copy relations
            let publication = try OriginalIssuedGeometricPublication.resolve(retained,geometryLimits:geometryLimits,maximumPoints:maximumPoints,
                transports:{ pair in
                    (retained.first.graphs[pair.firstGraphIndex].original.graph.parameterTransport,
                     retained.second.graphs[pair.secondGraphIndex].original.graph.parameterTransport)
                },using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGeometricRelations<S,E,C,T,F,D>.self))
            let result = OriginalIssuedGeometricRelations(original:copy relations,pairs:publication.pairs,exactPoints:publication.points)
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
