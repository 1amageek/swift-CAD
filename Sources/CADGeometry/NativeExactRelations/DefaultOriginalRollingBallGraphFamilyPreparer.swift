/// Consumes the complete rolling DI cover and retains exact original witness lifts.
struct DefaultOriginalRollingBallGraphFamilyPreparer<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable>{
    typealias Source = S
    typealias Evidence = OriginalRollingBallGraphReduction<S,E>
    typealias Cover = OriginalRollingBallGraphDomainCover<S,E,C>
    typealias Coverage = OriginalRollingBallGraphFamilyCoverage<S,E,C>
    func prepare<A: ExactScalarAdmission & ~Copyable>(cover: borrowing Cover,
        field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, maximumGraphs: Int,
        limits: OriginalDomainIdentityLimits, using a: inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphFamily<S,Evidence,Coverage> {
        do {
            try a.checkpoint(); try cover.family.admitProof(limits:limits.source,using:&a)
            let count = cover.effectiveEnclosure.isEmpty ? 0:cover.templateCount
            guard maximumGraphs >= 0, count <= maximumGraphs, cover.templateCount <= limits.maximumCharts else {
                throw OriginalDomainIdentityFailure.chartLimit
            }
            _ = try field.importingBase(cover.family.field.integer(0,using:&a),using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:OriginalIssuedGraphPreparation<S,Evidence>.self))
            var graphs: [OriginalIssuedGraphPreparation<S,Evidence>] = []; graphs.reserveCapacity(count)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Coverage.Reduced.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Int.self))
            var excluded: [Coverage.Reduced] = []; excluded.reserveCapacity(count)
            var templates: [Int] = []; templates.reserveCapacity(count)
            var v = cover.family.proofDepth.value, c = cover.family.proofDepth.coefficient
            var previous: Coverage.Reduced?
            for template in 0..<count {
                try a.consumeWork(1)
                let member = try cover.member(template:template,limits:limits,using:&a)
                let graph = try DefaultOriginalRollingBallGraphReducer<S,E>().reduce(member.graph,limits:limits.source,reusing:previous,using:&a)
                previous = graph
                // A single exact false original guard proves complete exclusion of this chart.
                var empty = false
                for condition in graph.conditions {
                    try a.consumeWork(1)
                    if condition.polynomial.terms.allSatisfy({ $0.powers.allSatisfy { $0 == 0 } }) {
                        let value = try condition.polynomial.terms.first?.coefficient ?? graph.field.integer(0,using:&a)
                        if try !condition.accepts(graph.field.sign(of:value,using:&a)) { empty = true; break }
                    }
                }
                v = max(v,graph.proofDepth.value); c = max(c,graph.proofDepth.coefficient)
                if empty { excluded.append(graph); continue }
                templates.append(template)
                let binding = try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,
                    request:cover.effectiveEnclosure,limits:limits,using:&a)
                let prepared = try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:copy field,limits:limits,using:&a)
                v = max(v,prepared.depth.value); c = max(c,prepared.depth.coefficient); graphs.append(prepared)
            }
            let depth = try ExactScalarDepth(value:v,coefficient:c); try a.admitDepth(value:v,coefficient:c)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphFamily<S,Evidence,Coverage>.self))
            let result = OriginalIssuedGraphFamily(coverage:Coverage(original:copy cover,excluded:excluded,graphTemplates:templates),source:cover.source,field:copy field,
                graphs:graphs,parameterCount:2,templateCount:cover.templateCount,depth:depth)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
