#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<S: OriginalLiftSourceReading>: Sendable {
    public typealias Source=S
    public init() {}
    private func prepared<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        surface: OriginalBSplineFundamentalCharts<S.Surface>,pcurveSource: OriginalSourceBinding<S.Pcurve>,
        pcurveField: OriginalExactScalarDomain,pcurveSupport: [OriginalSourceParameterInterval<OriginalExactScalar>],
        pcurveLaws: [OriginalRationalChartReceipt<S.Pcurve,S.PcurveSelection,OriginalExactScalarDomain>],
        pcurveDimension: Int,normalized: Bool,pcurveDepth: ExactScalarDepth?,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<S> {
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try source.require(limits)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard source.original.originalSurface.owner === surface.source.owner,
                    source.original.originalPcurve.owner === pcurveSource.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try surface.source.require(childLimits);try pcurveSource.require(childLimits)
                if let pcurveDepth { try a.admitDepth(value:pcurveDepth.value,coefficient:pcurveDepth.coefficient) }
                guard surface.support.count==2,pcurveSupport.count==1,
                    surface.source.original.parameterCount==2,pcurveDimension==1,
                    !surface.periods.isEmpty,!surface.laws.isEmpty,!pcurveLaws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                let count=surface.laws.count.multipliedReportingOverflow(by:pcurveLaws.count)
                guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                guard maximumCharts>=0,count.partialValue<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                let hostingField=surface.field
                func validate<C: Sendable,K: Sendable>(_ law: OriginalRationalChartReceipt<C,K,OriginalExactScalarDomain>,
                    owner: OriginalSourceBinding<C>,arity: Int) throws {
                    try a.consumeWork(1);try law.admitProof(using:&a)
                    guard owner.owns(law.chart),law.polynomials.variableCount==arity,law.support.count==arity,
                        law.homogeneous.count==4,law.parameterTransport.numerators.count==arity,
                        law.parameterTransport.denominators.count==arity else { throw OriginalSourceIssuanceFailure.invalidChart }
                    func coefficients(_ polynomial: ExactPolynomial<OriginalExactScalarDomain>) throws {
                        for term in polynomial.terms { try a.consumeWork(1);_=try hostingField.importing(term.coefficient,using:&a) }
                    }
                    for polynomial in law.homogeneous { try coefficients(polynomial) }
                    for polynomial in law.parameterTransport.numerators { try coefficients(polynomial) }
                    for polynomial in law.parameterTransport.denominators { try coefficients(polynomial) }
                    for bound in law.support {
                        try a.consumeWork(1)
                        _=try hostingField.importing(bound.lower,using:&a);_=try hostingField.importing(bound.upper,using:&a)
                    }
                    for axis in 0..<arity {
                        try a.consumeWork(1)
                        let r=law.polynomials,d=law.parameterTransport.denominators[axis]
                        guard try !r.isZero(d,using:&a),try r.isZero(r.subtracting(law.parameterTransport.numerators[axis],
                            r.multiplying(r.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    }
                }
                for law in surface.laws { try validate(law,owner:surface.source,arity:2) }
                for law in pcurveLaws { try validate(law,owner:pcurveSource,arity:1) }
                for period in surface.periods {
                    try a.consumeWork(1);try period.source.require(childLimits)
                    guard surface.source.owns(period.anchor) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                    _=try surface.field.sign(of:period.period,using:&a)
                    _=try surface.field.sign(of:period.lower,using:&a);_=try surface.field.sign(of:period.upper,using:&a)
                }
                let f=surface.field,lower=try f.importing(pcurveSupport[0].lower,using:&a)
                if normalized {
                    guard try f.compare(lower,f.integer(0,using:&a),using:&a) == .equal,
                        try f.compare(f.importing(pcurveSupport[0].upper,using:&a),f.integer(1,using:&a),using:&a) == .equal else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                }
                let span=try f.subtracting(f.importing(pcurveSupport[0].upper,using:&a),lower,using:&a)
                guard try f.sign(of:span,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPeriodicNativeSurfaceLiftGraphs<S>.self))
                let result=OriginalPeriodicNativeSurfaceLiftGraphs(source:source,surface:surface,pcurveLaws:pcurveLaws,
                    pcurveField:pcurveField,pcurveSupport:pcurveSupport,
                    count:count.partialValue,proofDepth:try a.depth,support:[.init(lower:zero,upper:one)],offset:lower,span:span)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}

extension DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer: OriginalPeriodicNativeSurfaceLiftGraphPreparing
    where S: OriginalSurfaceLiftSourceReading {
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalBSplineFundamentalCharts<S.Surface>,
        pcurve: borrowing OriginalFiniteBSplineCharts<S.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<S> {
        try prepared(source:copy source,surface:copy surface,pcurveSource:pcurve.source,
            pcurveField:pcurve.field,pcurveSupport:pcurve.support,pcurveLaws:pcurve.laws,
            pcurveDimension:pcurve.source.original.parameterCount,normalized:false,pcurveDepth:nil,
            maximumCharts:maximumCharts,limits:limits,using:&admission)
    }
}

extension DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer: OriginalPeriodicRetainedSurfaceLiftGraphPreparing
    where S: OriginalRetainedSurfaceLiftSourceReading {
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalBSplineFundamentalCharts<S.Surface>,
        pcurve: borrowing OriginalFiniteRetainedCurveCharts<S.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<S> {
        do {
            try admission.checkpoint()
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
            return try prepared(source:copy source,surface:copy surface,pcurveSource:pcurve.source,
                pcurveField:pcurve.field,pcurveSupport:[pcurve.support],pcurveLaws:pcurve.laws,
                pcurveDimension:1,normalized:true,pcurveDepth:pcurve.proofDepth,
                maximumCharts:maximumCharts,limits:limits,using:&admission)
        } catch { throw .init(preserving:error) }
    }
}
