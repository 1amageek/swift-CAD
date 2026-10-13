import CADCore

/// Complete original exclusion from checked symbolic projection equality and scoped identity.
package struct OriginalDraftedSelfExclusion: Sendable {
    package typealias Source=OriginalDraftedProjectionSnapshot
    package typealias Base=OriginalExactScalarDomain
    package typealias Evidence=OriginalRationalChartReceipt<Source,Int,Base>
    package typealias Cover=OriginalIssuedDomainCover<Source,Int,Base>
    package typealias Family=OriginalIssuedGraphFamily<Source,Evidence,Cover>
    package let original:OriginalDraftedRuledSurface3D
    package let family:Family
    package let raw:[ExactParametricGraphRelationSource<Base>]
    package let diagonal:OriginalParameterIdentity<Source,Base>

    package static func prepare<A: ExactScalarAdmission & ~Copyable>(
        _ wall:OriginalDraftedRuledSurface3D,limits:OriginalDomainIdentityLimits,
        maximumPairs:Int,
        using a:inout A
    ) throws -> Self {
        try a.checkpoint()
        let projection=try OriginalDraftedCoordinateProjection.prepare(wall,limits:limits.source,using:&a)
        let field=try Base(maximumValueDepth:limits.maximumTransportDepth,
            maximumCoefficientDepth:limits.maximumTransportDepth,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalDraftedProjectionSnapshotProvider(field:field))
            .bind(projection,limits:limits.source,using:&a)
        let charts=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source:source,maximumCharts:limits.maximumCharts,limits:limits.source,using:&a)
        let frame=try DefaultOriginalRetainedSurfaceDomainIssuer<Source>().frame(family:charts,limits:limits,using:&a)
        let request=try frame.fullSelection(limits:limits,using:&a)
        let cover=try DefaultOriginalIssuedDomainBinder().bind(laws:charts.laws,request:request,limits:limits,using:&a)
        let algebraic=try ExactAlgebraicScalarDomain.base(field:field,
            maximumExtensionLevel:limits.maximumTransportDepth,using:&a)
        let family=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover,
            field:algebraic,maximumGraphs:limits.maximumCharts,limits:limits,using:&a)
        try family.admitProof(limits:limits,using:&a)
        let one=try field.integer(1,using:&a),zero=try field.integer(0,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Base.Value.self))
        let map=try DefaultOriginalParameterTransporter<Source,Base>().affine(from:request,to:frame,
            permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
        let issuer=DefaultOriginalParameterIdentityIssuer<Source,Base>()
        let diagonal=try issuer.authored(left:map,right:map,limits:limits,using:&a)
        _ = try issuer.relation(of:diagonal,limits:limits,using:&a)
        let count=family.graphs.count.multipliedReportingOverflow(by:family.graphs.count)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        guard count.partialValue<=maximumPairs else { throw OriginalDomainIdentityFailure.chartLimit }
        for prepared in family.graphs {
            let graph=prepared.original.graph,ring=graph.polynomials
            guard graph.layout.parameters.count==2,graph.layout.auxiliaries.isEmpty else { throw unsupported(wall) }
            for axis in 0..<2 {
                try a.consumeWork(1)
                let expected=try ring.multiplying(graph.parameterTransport.denominators[axis],ring.variable(axis,using:&a),using:&a)
                guard try ring.equals(expected,graph.parameterTransport.numerators[axis],using:&a) else { throw unsupported(wall) }
            }
        }
        typealias Cells=ExactRealCellDomain<Base>
        let domain=ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:ExactParametricGraphRelationSource<Base>.self))
        var raw:[ExactParametricGraphRelationSource<Base>]=[];raw.reserveCapacity(count.partialValue)
        for first in family.graphs { for second in family.graphs {
            try a.consumeWork(1)
            let input=try domain.compile(kind:.surfaceSurface,first:first.graph,second:second.graph,using:&a)
            let cells=try Cells(retaining:input.predicate.source,using:&a),ring=cells.polynomials
            let f=try cells.coefficientField(of:input.predicate.source,using:&a)
            for axis in 0..<2 {
                let difference=try ring.subtracting(ring.variable(input.firstCoordinates[axis],using:&a),
                    ring.variable(input.secondCoordinates[axis],using:&a),using:&a)
                let equation=input.predicate.source.polynomials[input.equationIndices.lowerBound+axis]
                let division=try ring.divided(equation,by:difference,using:&a)
                guard try ring.isZero(division.remainder,using:&a),division.quotient.terms.count==1,
                    division.quotient.terms[0].powers.allSatisfy({$0==0}),
                    try f.sign(of:division.quotient.terms[0].coefficient,using:&a) != .zero else { throw unsupported(wall) }
            }
            raw.append(input)
        } }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
        let result=Self(original:wall,family:family,raw:raw,diagonal:diagonal)
        try a.checkpoint();return result
    }
    private static func unsupported(_ wall:OriginalDraftedRuledSurface3D)->KernelError {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General original drafted callers need
        // complete XYZ relations when projected equality does not imply the scoped
        // diagonal. Neither original contact nor absence is inferred on refusal.
        .init(phase:.topology,code:.unsupportedCapability,tolerance:wall.certificationTolerance,
            message:"Drafted projection requires original contact authority outside its proved diagonal.")
    }
    private init(original:OriginalDraftedRuledSurface3D,family:Family,
        raw:[ExactParametricGraphRelationSource<Base>],diagonal:OriginalParameterIdentity<Source,Base>) {
        self.original=original;self.family=family;self.raw=raw;self.diagonal=diagonal
    }
}
