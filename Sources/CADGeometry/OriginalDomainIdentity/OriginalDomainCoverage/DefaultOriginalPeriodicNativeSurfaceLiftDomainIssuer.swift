#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S: OriginalLiftSourceReading>: OriginalPeriodicNativeSurfaceLiftDomainIssuing {
    public typealias Source=S
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard family.integerFamilyRank<=limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
        try family.admitProof(maximumCharts:limits.maximumCharts,limits:limits.source,using:&a)
    }
    func support<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        _ a: inout A) throws -> [[ExactParameterInterval<OriginalExactScalar>]] {
        guard family.enclosingSupport.count==1 else { throw OriginalDomainIdentityFailure.invalidDomain }
        let bound=family.enclosingSupport[0]
        try OriginalDomainAccess.storage(1,[ExactParameterInterval<OriginalExactScalar>].self,&a)
        try OriginalDomainAccess.storage(1,ExactParameterInterval<OriginalExactScalar>.self,&a)
        return [[try .checked(field:family.field,lower:.finite(bound.lower),upper:.finite(bound.upper),
            depth:family.proofDepth,using:&a)]]
    }
    public func prepare<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeSurfaceLiftDomainSpace<S> {
        let family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            let issuer=DefaultOriginalBSplineDomainIssuer<S.Surface,OriginalExactScalarDomain>()
            let native=try issuer.prepare(source:family.surface.source,field:family.field,
                periodIssuer:OriginalRetainedBSplinePeriodIssuer(periods:family.surface.periods),
                transporter:DefaultOriginalParameterTransporter<S.Surface,OriginalExactScalarDomain>(),
                coverIssuer:DefaultOriginalDomainCoverIssuer<S.Surface,OriginalExactScalarDomain>(),limits:limits,using:&a)
            guard native.sourceCharts.count==family.surface.laws.count else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            try OriginalDomainAccess.storage(native.sourceCharts.count,Int.self,&a)
            var ordinals:[Int]=[];ordinals.reserveCapacity(native.sourceCharts.count)
            for chart in native.sourceCharts {
                var found:Int?=nil
                for index in family.surface.laws.indices {
                    try a.consumeWork(1)
                    let candidate=family.surface.laws[index].chart
                    guard native.source.owns(candidate) else { throw OriginalDomainIdentityFailure.foreignOwner }
                    if candidate.selection.spans==chart.selection.spans {
                        guard found==nil else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                        found=index
                    }
                }
                guard let found else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                ordinals.append(found)
            }
            let surface=try issuer.issue(space:native,request:native.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalCoordinateSemantics.self,&a)
            let frame=try DefaultOriginalParameterTransporter<S,OriginalExactScalarDomain>().frame(source:family.source,
                field:family.field,support:support(family,&a),semantics:[.authoredScalar],limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPeriodicNativeSurfaceLiftDomainSpace<S>.self,&a)
            return .init(family:family,frame:frame,surface:surface,lawOrdinals:ordinals)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalPeriodicNativeSurfaceLiftDomainSpace<S>,
        request: borrowing OriginalParameterSelection<S,OriginalExactScalarDomain>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeSurfaceLiftDomainCover<S> {
        let space=copy space,request=copy request
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(space.family,limits:limits,&a)
            let support=try space.frame.fullSelection(limits:limits,using:&a)
            guard request.sharesFrame(with:support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let effective=try support.intersection(request,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPeriodicNativeSurfaceLiftDomainCover<S>.self,&a)
            return .init(space:space,enclosingSupport:support,request:request,effectiveEnclosure:effective)
        }
    }
}
