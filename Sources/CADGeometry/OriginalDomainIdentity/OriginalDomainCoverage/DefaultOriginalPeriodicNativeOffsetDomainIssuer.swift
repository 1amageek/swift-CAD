#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalPeriodicNativeOffsetDomainIssuer<S: OriginalOffsetSourceReading>: OriginalPeriodicNativeOffsetDomainIssuing where S.Child: OriginalBSplineSourceReading {
    public typealias Source=S
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalPeriodicNativeOffsetLawFamily<S>,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard family.laws.count<=limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        guard family.child.periods.count<=limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    // This rebase is private and follows only the source's authored identity UV theorem.
    func intervals<T: Sendable,A: ExactScalarAdmission & ~Copyable>(_ selection: OriginalParameterSelection<T,OriginalExactScalarDomain>,
        _ a: inout A) throws -> [[ExactParameterInterval<OriginalExactScalar>]] {
        try OriginalDomainAccess.storage(selection.arity,[ExactParameterInterval<OriginalExactScalar>].self,&a)
        var result: [[ExactParameterInterval<OriginalExactScalar>]]=[];result.reserveCapacity(selection.arity)
        for axis in selection.axes {
            try a.consumeWork(1);try OriginalDomainAccess.storage(axis.intervalCount,ExactParameterInterval<OriginalExactScalar>.self,&a)
            result.append(Array(axis.intervals))
        }
        return result
    }
    public func prepare<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalPeriodicNativeOffsetLawFamily<S>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeOffsetDomainSpace<S> {
        let family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            let child=try DefaultOriginalBSplineDomainIssuer<S.Child,OriginalExactScalarDomain>().prepare(
                source:family.child.source,field:family.field,
                periodIssuer:OriginalRetainedBSplinePeriodIssuer(periods:family.child.periods),
                transporter:DefaultOriginalParameterTransporter<S.Child,OriginalExactScalarDomain>(),
                coverIssuer:DefaultOriginalDomainCoverIssuer<S.Child,OriginalExactScalarDomain>(),limits:limits,using:&a)
            guard child.sourceCharts.count==family.laws.count else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            try OriginalDomainAccess.storage(child.sourceCharts.count,Int.self,&a)
            var ordinals: [Int]=[];ordinals.reserveCapacity(child.sourceCharts.count)
            for chart in child.sourceCharts {
                var found: Int?=nil
                for index in family.laws.indices {
                    try a.consumeWork(1)
                    let candidate=family.laws[index].child.chart
                    guard child.source.owns(candidate) else { throw OriginalDomainIdentityFailure.foreignOwner }
                    if candidate.selection.spans==chart.selection.spans {
                        guard found==nil else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                        found=index
                    }
                }
                guard let found else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                ordinals.append(found)
            }
            let support=try child.frame.fullSelection(limits:limits,using:&a)
            try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            let frame=try DefaultOriginalParameterTransporter<S,OriginalExactScalarDomain>().frame(source:family.source,
                field:family.field,support:intervals(support,&a),semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPeriodicNativeOffsetDomainSpace<S>.self,&a)
            return .init(family:family,child:child,frame:frame,lawOrdinals:ordinals)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(space: borrowing OriginalPeriodicNativeOffsetDomainSpace<S>,
        request: borrowing OriginalParameterSelection<S,OriginalExactScalarDomain>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalPeriodicNativeOffsetDomainCover<S> {
        let space=copy space,request=copy request
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(space.family,limits:limits,&a)
            let support=try space.frame.fullSelection(limits:limits,using:&a)
            guard request.sharesFrame(with:support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let childRequest=try space.child.frame.selection(intervals:intervals(request,&a),limits:limits,using:&a)
            let child=try DefaultOriginalBSplineDomainIssuer<S.Child,OriginalExactScalarDomain>().issue(
                space:space.child,request:childRequest,limits:limits,using:&a)
            let effective=try request.intersection(support,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPeriodicNativeOffsetDomainCover<S>.self,&a)
            return .init(space:space,child:child,enclosingSupport:support,request:request,effectiveEnclosure:effective)
        }
    }
}
