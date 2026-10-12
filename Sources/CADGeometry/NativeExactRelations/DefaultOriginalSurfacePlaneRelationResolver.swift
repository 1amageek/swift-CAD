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

public struct DefaultOriginalSurfacePlaneRelationResolver: OriginalSurfacePlaneRelationResolving {
    public init() {}

    public func resolve<S: Sendable, E: Sendable, C: Sendable, P: OriginalPlaneSourceReading,
        A: ExactScalarAdmission & ~Copyable>(
        surface: borrowing OriginalIssuedGraphFamily<S,E,C>,
        plane: borrowing OriginalIssuedPlaneGraph<P>, planeFirst: Bool,
        maximumPairs: Int, limits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using a: inout A) throws(NativeExactRelationFailure) -> OriginalSurfacePlaneRelations<S,E,C,P> {
        do {
            try a.checkpoint()
            try surface.admitProof(limits: limits, using: &a)
            try plane.admitProof(limits: limits, using: &a)
            guard maximumPairs >= 0, surface.parameterCount == 2,
                plane.graph.parameterCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            _ = try plane.field.importing(surface.field.integer(0, using: &a), using: &a)
            guard surface.graphs.count <= maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: surface.graphs.count,
                of: OriginalIssuedGraphRelationPair.self))
            var pairs: [OriginalIssuedGraphRelationPair] = []
            pairs.reserveCapacity(surface.graphs.count)
            typealias Base = OriginalExactScalarDomain
            typealias Cells = ExactRealCellDomain<Base>
            let solver = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(
                cells: Cells.self, topology: .init(cells: Cells.self))
            for index in surface.graphs.indices {
                try a.consumeWork(1)
                let graph = surface.graphs[index].graph
                let input = try solver.compile(kind: .surfaceSurface,
                    first: planeFirst ? plane.graph : graph,
                    second: planeFirst ? graph : plane.graph, using: &a)
                let relation = try solver.resolve(input, cellLimits: cellLimits,
                    topologyLimits: topologyLimits, using: &a)
                pairs.append(.init(firstGraphIndex: planeFirst ? 0 : index,
                    secondGraphIndex: planeFirst ? index : 0, relation: relation))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalSurfacePlaneRelations<S,E,C,P>.self))
            let result = OriginalSurfacePlaneRelations(surface: copy surface, plane: copy plane,
                planeFirst: planeFirst, pairs: pairs)
            try a.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
