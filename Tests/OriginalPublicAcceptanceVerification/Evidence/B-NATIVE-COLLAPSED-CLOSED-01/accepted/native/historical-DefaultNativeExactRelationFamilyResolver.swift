#if NATIVE_FAMILY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
#endif

/// Prepares each selected law once and publishes only complete chart-pair topology.
public struct DefaultNativeExactRelationFamilyResolver: NativeExactRelationFamilyResolving {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Cells = ExactRealCellDomain<ExactRationalScalarDomain>
    typealias Domain = ExactParametricRelationDomain<ExactRationalScalarDomain,Cells,ExactRealTopology<ExactRationalScalarDomain>>
    public init() {}

    public func exactParameterRelations<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        A: ExactScalarAdmission & ~Copyable>(first: OriginalBSplineDomainCover<First,Field>,
        second: OriginalBSplineDomainCover<Second,Field>,kind: ExactParametricRelationKind,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelations<First,Second> {
        try exactParameterRelations(first:first,second:second,kind:kind,
            firstIssuer:DefaultOriginalDomainBoundBSplineChartIssuer<First,Field>(),
            secondIssuer:DefaultOriginalDomainBoundBSplineChartIssuer<Second,Field>(),
            domainLimits:domainLimits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }

    public func exactParameterRelations<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        I: OriginalDomainBoundRationalChartIssuing,J: OriginalDomainBoundRationalChartIssuing,
        A: ExactScalarAdmission & ~Copyable>(first: OriginalBSplineDomainCover<First,Field>,
        second: OriginalBSplineDomainCover<Second,Field>,kind: ExactParametricRelationKind,
        firstIssuer: I,secondIssuer: J,domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelations<First,Second>
        where I.Source == First,J.Source == Second,I.Field == Field,J.Field == Field {
        do {
            try admission.checkpoint()
            guard maximumMaps >= 0,maximumPairs >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            let arity = first.space.frame.arity
            guard second.space.frame.arity == 2,
                (kind == .curveSurface && arity == 1) || (kind == .surfaceSurface && arity == 2) else {
                throw NativeExactRelationFailure.invalidDomain
            }
            let a = try prepare(first,issuer:firstIssuer,limits:domainLimits,maximumMaps:maximumMaps,using:&admission)
            let b = try prepare(second,issuer:secondIssuer,limits:domainLimits,maximumMaps:maximumMaps,using:&admission)
            let domain = Domain(cells:Cells.self,topology:.init(cells:Cells.self))
            let count = a.count.multipliedReportingOverflow(by:b.count)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            guard count.partialValue <= maximumPairs else { throw NativeExactRelationFailure.domain(.chartLimit) }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:NativeExactParametricRelationPiece<First,Second>.self))
            var pieces: [NativeExactParametricRelationPiece<First,Second>] = []; pieces.reserveCapacity(count.partialValue)
            for left in a {
                for right in b {
                    try admission.consumeWork(1)
                    let compiled = try domain.compile(kind:kind,first:left.map,second:right.map,using:&admission)
                    let relation = try domain.resolve(compiled,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
                    pieces.append(.init(first:left.chart,second:right.chart,relation:relation))
                }
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:NativeExactParametricRelations<First,Second>.self))
            let result = NativeExactParametricRelations(first:first,second:second,pieces:pieces)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    private func prepare<S: OriginalBSplineSourceReading,I: OriginalDomainBoundRationalChartIssuing,
        A: ExactScalarAdmission & ~Copyable>(_ cover: OriginalBSplineDomainCover<S,Field>,issuer: I,
        limits: OriginalDomainIdentityLimits,maximumMaps: Int,using admission: inout A
    ) throws -> [(chart: OriginalDomainBoundRationalChart<S,Field>,map: ExactParametricMap<ExactRationalScalarDomain>)]
        where I.Source == S,I.Field == Field {
        let occurrences = try cover.selectedMembers(limits:limits,using:&admission)
        var result: [(chart: OriginalDomainBoundRationalChart<S,Field>,map: ExactParametricMap<ExactRationalScalarDomain>)] = []
        for occurrence in occurrences {
            try admission.consumeWork(1)
            // The selected occurrence preserves the template and unreduced cycle owners.
            guard let index = try cover.space.sourceCharts.firstIndex(where: { chart in
                try admission.consumeWork(1)
                return chart.selection.spans == occurrence.sourceChart.selection.spans
            }) else {
                throw NativeExactRelationFailure.invalidDomain
            }
            let chart = try issuer.issue(cover:cover,template:index,cycles:occurrence.cycles,limits:limits,using:&admission)
            guard cover.source.owns(chart.law.chart),cover.source.owns(chart.occurrence.sourceChart),
                chart.law.chart.selection.spans == occurrence.sourceChart.selection.spans,
                chart.occurrence.sourceChart.selection.spans == occurrence.sourceChart.selection.spans,
                try chart.occurrence.selectedImage.equals(occurrence.selectedImage,limits:limits,using:&admission) else {
                throw NativeExactRelationFailure.domain(.foreignOwner)
            }
            try chart.law.admitProof(using:&admission)
            let cells = try Cells(field:cover.space.frame.scalarField,variableCount:chart.localSelection.arity,using:&admission)
            let roots = try ExactRealRootDomain(field:cover.space.frame.scalarField,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<Field>.self))
            var laws: [ExactPolynomial<Field>] = []; laws.reserveCapacity(4)
            for law in chart.law.homogeneous {
                try admission.consumeWork(1)
                laws.append(try cells.polynomials.importing(law,using:&admission))
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[ExactRealRootInterval<Field.Value>].self))
            var products: [[ExactRealRootInterval<Field.Value>]] = [[]]
            for axis in chart.localSelection.axes {
                var expanded: [[ExactRealRootInterval<Field.Value>]] = []
                for prefix in products {
                    for interval in axis.intervals {
                        try admission.consumeWork(1)
                        guard case .finite(let lo) = interval.lower,case .finite(let hi) = interval.upper else {
                            throw NativeExactRelationFailure.unsupportedCoverage
                        }
                        guard expanded.count < maximumMaps - result.count else { throw NativeExactRelationFailure.domain(.chartLimit) }
                        let domain = try roots.domain(lower:.finite(lo),upper:.finite(hi),includesLower:interval.includesLower,
                            includesUpper:interval.includesUpper,using:&admission)
                        let count = prefix.count.addingReportingOverflow(1)
                        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
                        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:ExactRealRootInterval<Field.Value>.self))
                        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[ExactRealRootInterval<Field.Value>].self))
                        var tuple = prefix; tuple.append(domain); expanded.append(tuple)
                    }
                }
                products = expanded
            }
            for domains in products {
                try admission.consumeWork(1)
                guard result.count < maximumMaps else { throw NativeExactRelationFailure.domain(.chartLimit) }
                let system = try cells.bind(polynomials:laws,domains:domains,using:&admission)
                let map = try Domain(cells:Cells.self,topology:.init(cells:Cells.self)).map(from:system,using:&admission)
                try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:(OriginalDomainBoundRationalChart<S,Field>,ExactParametricMap<ExactRationalScalarDomain>).self))
                result.append((chart,map))
            }
        }
        return result
    }
}
