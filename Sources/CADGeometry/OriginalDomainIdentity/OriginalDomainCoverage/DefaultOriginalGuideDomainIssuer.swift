#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Composes sealed source station laws through existing complete-domain contracts.
public struct DefaultOriginalGuideDomainIssuer<S: OriginalGuideSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalGuideDomainIssuing where F.Source == F.Value {
    public typealias Source=S
    public typealias ChildSelection=C
    public typealias Field=F
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteGuideChartFamily<S,C,F>,
        _ limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard family.laws.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteGuideChartFamily<S,C,F>,_ a: inout A)
        throws -> [[ExactParameterInterval<F.Value>]] {
        try OriginalDomainAccess.storage(1,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
        return [[try .checked(field:family.field,lower:.finite(family.support.lower),upper:.finite(family.support.upper),
            depth:family.proofDepth,using:&a)]]
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteGuideChartFamily<S,C,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits,&a);try OriginalDomainAccess.storage(1,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:family.source,field:family.field,
                support:intervals(family,&a),semantics:[.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,
        family: borrowing OriginalFiniteGuideChartFamily<S,C,F>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalGuideDomainCover<S,C,F> {
        let request=copy request,family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits,&a)
            let anchor=try family.source.chart(0,limits:limits.source,using:&a)
            guard request.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard request.arity == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard request.frame.coordinateSemantics[0] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let support=try request.frame.selection(intervals:intervals(family,&a),limits:limits,using:&a)
            guard try support.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else {
                throw OriginalDomainIdentityFailure.invalidDomain
            }
            let effective=try support.intersection(request,limits:limits,using:&a),t=DefaultOriginalParameterTransporter<S,F>()
            try OriginalDomainAccess.storage(family.laws.count,OriginalParameterTransport<S,F>.self,&a)
            var maps: [OriginalParameterTransport<S,F>]=[];maps.reserveCapacity(family.laws.count)
            for law in family.laws {
                try a.consumeWork(1)
                let ring=law.polynomials,f=family.field
                guard law.parameterTransport.numerators.count == 1,law.parameterTransport.denominators.count == 1 else {
                    throw OriginalDomainIdentityFailure.invalidDomain
                }
                let quotient=try ring.divided(law.parameterTransport.numerators[0],by:law.parameterTransport.denominators[0],using:&a)
                guard try ring.isZero(quotient.remainder,using:&a) else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
                var gain=try f.integer(0,using:&a),offset=gain
                for term in quotient.quotient.terms {
                    try a.consumeWork(1)
                    guard term.powers.count == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
                    switch term.powers[0] {
                    case 0: offset=try f.importing(term.coefficient,using:&a)
                    case 1: gain=try f.importing(term.coefficient,using:&a)
                    default: throw OriginalDomainIdentityFailure.unsupportedSourceProof
                    }
                }
                try OriginalDomainAccess.storage(1,[ExactParameterInterval<F.Value>].self,&a)
                try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
                try OriginalDomainAccess.storage(1,OriginalCoordinateSemantics.self,&a)
                let local=try t.frame(source:family.source,field:f,support:[[.checked(field:f,
                    lower:.finite(law.localSupport.lower),upper:.finite(law.localSupport.upper),depth:law.proofDepth,using:&a)]],
                    semantics:[.authoredScalar],limits:limits,using:&a)
                try OriginalDomainAccess.storage(1,Int.self,&a);try OriginalDomainAccess.storage(2,F.Value.self,&a)
                let map=try t.affine(from:local.fullSelection(limits:limits,using:&a),to:request.frame,
                    permutation:[0],gains:[gain],offsets:[offset],limits:limits,using:&a)
                let image=try map.image.intersection(effective,limits:limits,using:&a)
                let reverse=try t.inverse(map,limits:limits,using:&a)
                maps.append(try t.inverse(t.restrict(reverse,to:image,limits:limits,using:&a),limits:limits,using:&a))
            }
            let covered=try DefaultOriginalDomainCoverIssuer<S,F>().issue(request:request,charts:maps,limits:limits,using:&a)
            return .init(family:family,coverage:covered,maps:maps)
        }
    }
}
