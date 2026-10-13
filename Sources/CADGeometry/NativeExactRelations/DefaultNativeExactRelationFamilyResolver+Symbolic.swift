#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif
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

extension DefaultNativeExactRelationFamilyResolver: NativeExactSymbolicRelationFamilyResolving {
    public func exactParameterRelationFamily<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        A: ExactScalarAdmission & ~Copyable>(first: OriginalBSplineDomainCover<First,Field>,
        second: OriginalBSplineDomainCover<Second,Field>,kind: ExactParametricRelationKind,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicRelationFamily<First,Second> {
        try exactParameterRelationFamily(first:first,second:second,kind:kind,
            firstIssuer:DefaultOriginalDomainBoundBSplineChartIssuer<First,Field>(),
            secondIssuer:DefaultOriginalDomainBoundBSplineChartIssuer<Second,Field>(),domainLimits:domainLimits,
            maximumMaps:maximumMaps,maximumPairs:maximumPairs,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }

    public func exactParameterRelationFamily<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        I: OriginalDomainBoundRationalChartIssuing,J: OriginalDomainBoundRationalChartIssuing,
        A: ExactScalarAdmission & ~Copyable>(first: OriginalBSplineDomainCover<First,Field>,
        second: OriginalBSplineDomainCover<Second,Field>,kind: ExactParametricRelationKind,
        firstIssuer: I,secondIssuer: J,domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicRelationFamily<First,Second>
        where I.Source == First,J.Source == Second,I.Field == Field,J.Field == Field {
        do {
            try admission.checkpoint()
            guard maximumMaps >= 0,maximumPairs >= 0,second.space.frame.arity == 2,
                (kind == .curveSurface && first.space.frame.arity == 1) ||
                (kind == .surfaceSurface && first.space.frame.arity == 2) else { throw NativeExactRelationFailure.invalidDomain }
            guard first.templateCount <= domainLimits.maximumCharts,second.templateCount <= domainLimits.maximumCharts else {
                throw OriginalDomainIdentityFailure.chartLimit
            }
            guard first.integerFamilyRank <= domainLimits.maximumFamilies,second.integerFamilyRank <= domainLimits.maximumFamilies else {
                throw OriginalDomainIdentityFailure.familyLimit
            }
            _ = try first.effective.equals(first.effective,limits:domainLimits,using:&admission)
            _ = try second.effective.equals(second.effective,limits:domainLimits,using:&admission)
            _ = try first.space.frame.scalarField.sign(of:second.space.frame.scalarField.integer(0,using:&admission),using:&admission)
            let scalarDepth = try first.space.frame.scalarField.integer(0,using:&admission).depth
            var valueDepth = scalarDepth.value,coefficientDepth = scalarDepth.coefficient
            for axis in first.request.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in first.support.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in second.request.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in second.support.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            var templates: [NativeExactSymbolicRelationTemplate<First,Second>] = []
            if !first.effective.isEmpty && !second.effective.isEmpty {
                let left = try prepareFundamental(first,issuer:firstIssuer,limits:domainLimits,maximumMaps:maximumMaps,using:&admission)
                let right = try prepareFundamental(second,issuer:secondIssuer,limits:domainLimits,maximumMaps:maximumMaps,using:&admission)
                let count = left.count.multipliedReportingOverflow(by:right.count)
                guard !count.overflow else { throw ExactScalarFailure.countOverflow }
                guard count.partialValue <= maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
                try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:NativeExactSymbolicRelationTemplate<First,Second>.self))
                templates.reserveCapacity(count.partialValue)
                let domain = Domain(cells:Cells.self,topology:.init(cells:Cells.self))
                for (i,a) in left.enumerated() {
                    for (j,b) in right.enumerated() {
                        try admission.consumeWork(1)
                        let source = try domain.compile(kind:kind,first:a.map,second:b.map,using:&admission)
                        let relation = try domain.resolve(source,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
                        valueDepth=max(valueDepth,relation.components.depth.value)
                        coefficientDepth=max(coefficientDepth,relation.components.depth.coefficient)
                        templates.append(.init(firstTemplate:i,secondTemplate:j,
                            fundamental:.init(first:a.chart,second:b.chart,relation:relation)))
                    }
                }
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:NativeExactSymbolicRelationFamily<First,Second>.self))
            let result = NativeExactSymbolicRelationFamily(first:first,second:second,templates:templates,depth:try ExactScalarDepth(value:valueDepth,coefficient:coefficientDepth))
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    private func prepareFundamental<S: OriginalBSplineSourceReading,I: OriginalDomainBoundRationalChartIssuing,
        A: ExactScalarAdmission & ~Copyable>(_ cover: OriginalBSplineDomainCover<S,Field>,issuer: I,
        limits: OriginalDomainIdentityLimits,maximumMaps: Int,using admission: inout A
    ) throws -> [(chart: OriginalDomainBoundRationalChart<S,Field>,map: ExactParametricMap<ExactRationalScalarDomain>)]
        where I.Source == S,I.Field == Field {
        guard cover.templateCount <= maximumMaps else { throw OriginalDomainIdentityFailure.chartLimit }
        let request = try cover.space.frame.fullSelection(limits:limits,using:&admission)
        let whole = try DefaultOriginalBSplineDomainIssuer<S,Field>().issue(space:cover.space,request:request,limits:limits,using:&admission)
        let zero = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(0,using:&admission),using:&admission)
        try admission.retainStorage(bytes:exactScalarPayloadBytes(count:cover.space.frame.arity,of:OriginalParameterCycle.self))
        let cycles = [OriginalParameterCycle](repeating:zero,count:cover.space.frame.arity)
        var prepared: [(chart: OriginalDomainBoundRationalChart<S,Field>,map: ExactParametricMap<ExactRationalScalarDomain>)] = []
        for index in 0..<cover.templateCount {
            try admission.consumeWork(1)
            let chart = try issuer.issue(cover:whole,template:index,cycles:cycles,limits:limits,using:&admission)
            let expected = try whole.member(template:index,cycles:cycles,limits:limits,using:&admission)
            guard cover.source.owns(chart.law.chart),cover.source.owns(chart.occurrence.sourceChart),
                chart.law.chart.selection.spans == expected.sourceChart.selection.spans,
                chart.occurrence.sourceChart.selection.spans == expected.sourceChart.selection.spans,
                try chart.occurrence.selectedImage.equals(expected.selectedImage,limits:limits,using:&admission) else {
                throw OriginalDomainIdentityFailure.foreignOwner
            }
            try appendPrepared(chart,field:cover.space.frame.scalarField,maximumMaps:maximumMaps,to:&prepared,using:&admission)
            guard prepared.count == index+1 else { throw OriginalDomainIdentityFailure.incompleteCoverage }
        }
        return prepared
    }
}

extension DefaultNativeExactRelationFamilyResolver: NativeExactSymbolicSurfacePredicateCompiling {
    public func compileSurfacePredicates<A: ExactScalarAdmission & ~Copyable>(
        first: NativeExactSymbolicSurfacePredicateFamily.Cover,second: NativeExactSymbolicSurfacePredicateFamily.Cover,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,using a: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicSurfacePredicateFamily {
        do {
            try a.checkpoint()
            guard maximumMaps>=0,maximumPairs>=0,first.space.frame.arity==2,second.space.frame.arity==2 else {
                throw NativeExactRelationFailure.invalidDomain
            }
            guard first.templateCount<=domainLimits.maximumCharts,second.templateCount<=domainLimits.maximumCharts else {
                throw OriginalDomainIdentityFailure.chartLimit
            }
            guard first.integerFamilyRank<=domainLimits.maximumFamilies,second.integerFamilyRank<=domainLimits.maximumFamilies else {
                throw OriginalDomainIdentityFailure.familyLimit
            }
            _=try first.source.chart(0,limits:domainLimits.source,using:&a)
            _=try second.source.chart(0,limits:domainLimits.source,using:&a)
            _=try first.effective.equals(first.effective,limits:domainLimits,using:&a)
            _=try second.effective.equals(second.effective,limits:domainLimits,using:&a)
            _=try first.space.frame.scalarField.importing(second.space.frame.scalarField.integer(0,using:&a),using:&a)
            typealias Template=NativeExactSymbolicSurfacePredicateFamily.Template
            var templates:[Template]=[]
            var valueDepth=0,coefficientDepth=0
            func includeDepth(_ cover: NativeExactSymbolicSurfacePredicateFamily.Cover) throws {
                for axis in cover.request.axes { try a.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
                for axis in cover.support.axes { try a.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            }
            try includeDepth(first);try includeDepth(second)
            if !first.effective.isEmpty && !second.effective.isEmpty {
                let left=try prepareFundamental(first,issuer:DefaultOriginalDomainBoundBSplineChartIssuer<BSplineSurface3D,Field>(),
                    limits:domainLimits,maximumMaps:maximumMaps,using:&a)
                let right=try prepareFundamental(second,issuer:DefaultOriginalDomainBoundBSplineChartIssuer<BSplineSurface3D,Field>(),
                    limits:domainLimits,maximumMaps:maximumMaps,using:&a)
                let count=left.count.multipliedReportingOverflow(by:right.count)
                guard !count.overflow else { throw ExactScalarFailure.countOverflow }
                guard count.partialValue<=maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Template.self))
                templates.reserveCapacity(count.partialValue)
                let compiler=Domain(cells:Cells.self,topology:.init(cells:Cells.self))
                for (i,lhs) in left.enumerated() { for (j,rhs) in right.enumerated() {
                    try a.consumeWork(1)
                    let source=try compiler.compile(kind:.surfaceSurface,first:lhs.map,second:rhs.map,using:&a)
                    valueDepth=max(valueDepth,source.predicate.depth.value)
                    coefficientDepth=max(coefficientDepth,source.predicate.depth.coefficient)
                    for law in source.rawEquations {
                        try a.consumeWork(1);valueDepth=max(valueDepth,law.depth.value);coefficientDepth=max(coefficientDepth,law.depth.coefficient)
                    }
                    templates.append(.init(firstTemplate:i,secondTemplate:j,first:lhs.chart,second:rhs.chart,source:source))
                } }
            }
            let depth=try ExactScalarDepth(value:valueDepth,coefficient:coefficientDepth)
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:NativeExactSymbolicSurfacePredicateFamily.self))
            let result=NativeExactSymbolicSurfacePredicateFamily(first:first,second:second,templates:templates,depth:depth)
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
