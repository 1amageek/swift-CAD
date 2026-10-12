/// Imports each actual guarded graph while retaining its sealed complete source family.
public struct DefaultOriginalCompleteCurveGraphFamilyPreparer<S: Sendable, E: Sendable, C: Sendable>:
    OriginalCompleteCurveGraphFamilyPreparing {
    public typealias Source = S
    public typealias Evidence = E
    public typealias Coverage = C
    public typealias Cover = OriginalCompleteCurveGraphDomainCover<S,E,C>
    public init() {}

    public func prepare<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalCompleteCurveGraphs<S,E,C>,
        request: borrowing OriginalParameterSelection<S,OriginalExactScalarDomain>,
        field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, maximumGraphs: Int,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,E,Cover> {
        do {
            try admission.checkpoint()
            guard maximumGraphs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
            guard family.graphs.count <= limits.maximumCharts, family.graphs.count <= maximumGraphs else {
                throw OriginalDomainIdentityFailure.chartLimit
            }
            try family.admitProof(limits: limits.source, using: &admission)
            guard request.arity == 1, request.frame.coordinateSemantics == [.authoredScalar] else {
                throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics
            }
            let anchor = try family.source.chart(0, limits: limits.source, using: &admission)
            guard request.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            _ = try field.importingBase(family.field.integer(0, using: &admission), using: &admission)
            var value = family.proofDepth.value, coefficient = family.proofDepth.coefficient
            for axis in request.frame.axes {
                try admission.consumeWork(1); value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient)
            }
            for axis in request.axes {
                try admission.consumeWork(1); value = max(value, axis.depth.value); coefficient = max(coefficient, axis.depth.coefficient)
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: family.graphs.count,
                of: OriginalIssuedGraphPreparation<S,E>.self))
            var graphs: [OriginalIssuedGraphPreparation<S,E>] = []; graphs.reserveCapacity(family.graphs.count)
            for graph in family.graphs {
                try admission.consumeWork(1)
                let binding = try DefaultOriginalParametricGraphDomainBinder<S,OriginalExactScalarDomain,E>()
                    .bind(graph: graph, request: request, limits: limits, using: &admission)
                let prepared = try DefaultOriginalIssuedGraphCompiler<S,E>()
                    .compile(binding: binding, field: copy field, limits: limits, using: &admission)
                value = max(value, prepared.depth.value); coefficient = max(coefficient, prepared.depth.coefficient)
                graphs.append(prepared)
            }
            let depth = try ExactScalarDepth(value: value, coefficient: coefficient)
            try admission.admitDepth(value: value, coefficient: coefficient)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Cover.self))
            let cover = Cover(family: copy family, request: copy request, depth: depth)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedGraphFamily<S,E,Cover>.self))
            let result = OriginalIssuedGraphFamily(coverage: cover, source: family.source, field: copy field,
                graphs: graphs, parameterCount: 1, templateCount: family.graphs.count, depth: depth)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
