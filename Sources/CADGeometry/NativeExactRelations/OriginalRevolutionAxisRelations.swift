#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
@testable import DI
import SourceIssuer
#endif

/// Complete query-pair owner; restricted axis sections are not whole-surface families.
public struct OriginalRevolutionAxisRelations<S: OriginalRevolutionSourceReading, C: Sendable,
    L: OriginalLinearSourceReading>: OriginalIssuedGraphRelationOwning {
    public typealias Base = OriginalExactScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public typealias LineLaw = OriginalRationalChartReceipt<L,OriginalLinearChartSelection,Base>
    public typealias LineCover = OriginalIssuedDomainCover<L,OriginalLinearChartSelection,Base>
    public typealias SectionEvidence = OriginalRevolutionAxisSectionEvidence<S,C,Base,L>
    public let first: OriginalIssuedGraphFamily<L,LineLaw,LineCover>
    public let originalDomain: OriginalRevolutionDomainCover<S,C,Base>
    public let sections: OriginalRevolutionAxisSectionReceipt<S,C,Base,L>
    public let secondGraphs: [OriginalIssuedGraphPreparation<S,SectionEvidence>]
    public let pairs: [OriginalIssuedGraphRelationPair]
    public let depth: ExactScalarDepth
    public var kind: ExactParametricRelationKind { .curveSurface }

    static func resolve<A: ExactScalarAdmission & ~Copyable>(
        first: OriginalIssuedGraphFamily<L,LineLaw,LineCover>,
        cover: OriginalRevolutionDomainCover<S,C,Base>,
        maximumPairs: Int, maximumPolynomialDegree: Int,
        limits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A) throws -> Self {
        try a.withProofScope() { tracked in
            try resolveTracked(first:first,cover:cover,maximumPairs:maximumPairs,maximumPolynomialDegree:maximumPolynomialDegree,
                limits:limits,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&tracked)
        }
    }

    private static func resolveTracked<A: ExactScalarAdmission & ~Copyable>(
        first: OriginalIssuedGraphFamily<L,LineLaw,LineCover>,
        cover: OriginalRevolutionDomainCover<S,C,Base>,
        maximumPairs: Int, maximumPolynomialDegree: Int,
        limits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A) throws -> Self {
        try a.checkpoint();try first.admitProof(limits:limits,using:&a)
        try cover.admitted(limits,&a)
        let sections = try DefaultOriginalRevolutionAxisSectionIssuer<S,C,Base,L>()
            .issue(family:cover.family,line:first.source,limits:limits.source,using:&a)
        guard maximumPairs >= 0,maximumPolynomialDegree >= 0,first.parameterCount == 1,
            cover.source.owns(sections.family.period.anchor),
            sections.graphs.count == cover.family.laws.count else {
            throw NativeExactRelationFailure.invalidDomain
        }
        for graph in first.graphs {
            try a.consumeWork(1)
            guard sections.line.owns(graph.original.graph.evidence.chart) else {
                throw NativeExactRelationFailure.invalidDomain
            }
        }
        _ = try first.field.importingBase(sections.family.field.integer(0,using:&a),using:&a)
        let count = first.graphs.count.multipliedReportingOverflow(by:sections.graphs.count)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        guard count.partialValue <= maximumPairs,sections.graphs.count <= limits.maximumCharts else {
            throw OriginalDomainIdentityFailure.chartLimit
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:sections.graphs.count,of:OriginalIssuedGraphPreparation<S,SectionEvidence>.self))
        var second: [OriginalIssuedGraphPreparation<S,SectionEvidence>] = [];second.reserveCapacity(sections.graphs.count)
        for graph in sections.graphs {
            try a.consumeWork(1)
            for law in graph.homogeneous { try checkDegree(law,maximum:maximumPolynomialDegree,using:&a) }
            for condition in graph.conditions { try checkDegree(condition.polynomial,maximum:maximumPolynomialDegree,using:&a) }
            let binding = try DefaultOriginalParametricGraphDomainBinder<S,Base,SectionEvidence>()
                .bind(graph:graph,request:cover.effective,limits:limits,using:&a)
            second.append(try DefaultOriginalIssuedGraphCompiler<S,SectionEvidence>()
                .compile(binding:binding,field:first.field,limits:limits,using:&a))
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:OriginalIssuedGraphRelationPair.self))
        var pairs: [OriginalIssuedGraphRelationPair] = [];pairs.reserveCapacity(count.partialValue)
        typealias Cells = ExactRealCellDomain<Base>
        let domain = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(
            cells:Cells.self,topology:.init(cells:Cells.self))
        for i in first.graphs.indices { for j in second.indices {
            try a.consumeWork(1)
            let input = try domain.compile(kind:.curveSurface,first:first.graphs[i].graph,
                second:second[j].graph,using:&a)
            let relation = try domain.resolve(input,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
            pairs.append(try .solved(firstGraphIndex:i,secondGraphIndex:j,relation:relation,using:&a))
        } }
        let depth = try a.depth
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
        let result = Self(first:first,originalDomain:cover,sections:sections,secondGraphs:second,pairs:pairs,depth:depth)
        try a.checkpoint();return result
    }

    private static func checkDegree<A:ExactScalarAdmission & ~Copyable>(_ law:ExactPolynomial<Base>,
        maximum:Int,using a:inout A) throws {
        for term in law.terms {
            try a.consumeWork(1)
            guard term.powers.allSatisfy({ $0 <= maximum }) else { throw ExactScalarFailure.resourceLimit(.work) }
        }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits:OriginalDomainIdentityLimits,
        using a:inout A) throws {
        try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
        try first.admitProof(limits:limits,using:&a);try originalDomain.admitted(limits,&a)
        try sections.admitProof(limits:limits.source,using:&a)
        for graph in secondGraphs { try a.consumeWork(1);try graph.admitProof(limits:limits,using:&a) }
        try a.checkpoint()
    }
}
