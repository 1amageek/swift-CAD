#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalRetainedSurfaceLiftDomainIssuer<S: OriginalRetainedPcurveLiftSourceReading>: OriginalRetainedSurfaceLiftDomainIssuing {
    public typealias Source = S
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteRetainedSurfaceLiftGraphs<S>,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard family.graphs.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ bounds: [OriginalSourceParameterInterval<OriginalExactScalar>],
        field: OriginalExactScalarDomain,depth: ExactScalarDepth,_ a: inout A)
        throws -> [[ExactParameterInterval<OriginalExactScalar>]] {
        guard bounds.count == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(1,[ExactParameterInterval<OriginalExactScalar>].self,&a)
        try OriginalDomainAccess.storage(1,ExactParameterInterval<OriginalExactScalar>.self,&a)
        var result: [[ExactParameterInterval<OriginalExactScalar>]] = [];result.reserveCapacity(1)
        for bound in bounds {
            try a.consumeWork(1)
            result.append([try .checked(field:field,lower:.finite(bound.lower),upper:.finite(bound.upper),depth:depth,using:&a)])
        }
        return result
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRetainedSurfaceLiftGraphs<S>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,OriginalExactScalarDomain> {
        let family = copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            try OriginalDomainAccess.storage(1,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,OriginalExactScalarDomain>().frame(source:family.source,
                field:family.field,support:intervals(family.enclosingSupport,field:family.field,depth:family.proofDepth,&a),
                semantics:[.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,OriginalExactScalarDomain>,
        family: borrowing OriginalFiniteRetainedSurfaceLiftGraphs<S>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalRetainedSurfaceLiftDomainCover<S> {
        let request = copy request,family = copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,&a)
            let anchor = try family.source.chart(0,limits:limits.source,using:&a)
            guard request.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard request.arity == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard request.frame.coordinateSemantics[0] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let enclosure = try request.frame.selection(intervals:intervals(family.enclosingSupport,
                field:family.field,depth:family.proofDepth,&a),limits:limits,using:&a)
            guard try enclosure.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            return .init(family:family,enclosingSupport:enclosure,request:request,
                effectiveEnclosure:try enclosure.intersection(request,limits:limits,using:&a))
        }
    }
}
