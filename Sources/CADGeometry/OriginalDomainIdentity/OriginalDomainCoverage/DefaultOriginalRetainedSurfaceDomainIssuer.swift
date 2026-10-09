#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Clips sealed original surface cells through existing complete-cover contracts.
public struct DefaultOriginalRetainedSurfaceDomainIssuer<S: OriginalRetainedSurfaceSourceReading>: OriginalRetainedSurfaceDomainIssuing {
    public typealias Source=S
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteRetainedSurfaceCharts<S>,
        _ limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard family.laws.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ bounds: [OriginalSourceParameterInterval<S.Field.Value>],
        _ family: OriginalFiniteRetainedSurfaceCharts<S>,_ a: inout A) throws -> [[ExactParameterInterval<S.Field.Value>]] {
        guard bounds.count == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(2,[ExactParameterInterval<S.Field.Value>].self,&a)
        try OriginalDomainAccess.storage(2,ExactParameterInterval<S.Field.Value>.self,&a)
        var result: [[ExactParameterInterval<S.Field.Value>]]=[];result.reserveCapacity(2)
        for bound in bounds {
            try a.consumeWork(1)
            result.append([try .checked(field:family.field,lower:.finite(bound.lower),upper:.finite(bound.upper),
                depth:family.proofDepth,using:&a)])
        }
        return result
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRetainedSurfaceCharts<S>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,S.Field> {
        let family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits,&a);try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,S.Field>().frame(source:family.source,field:family.field,
                support:intervals(family.support,family,&a),semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,S.Field>,
        family: borrowing OriginalFiniteRetainedSurfaceCharts<S>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalRetainedSurfaceDomainCover<S> {
        let request=copy request,family=copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits,&a)
            let anchor=try family.source.chart(0,limits:limits.source,using:&a)
            guard request.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard request.arity == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard request.frame.coordinateSemantics == [.authoredScalar,.authoredScalar] else {
                throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics
            }
            let support=try request.frame.selection(intervals:intervals(family.support,family,&a),limits:limits,using:&a)
            guard try support.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else {
                throw OriginalDomainIdentityFailure.invalidDomain
            }
            let effective=try support.intersection(request,limits:limits,using:&a),t=DefaultOriginalParameterTransporter<S,S.Field>()
            let zero=try family.field.integer(0,using:&a),one=try family.field.integer(1,using:&a)
            try OriginalDomainAccess.storage(family.laws.count,OriginalParameterTransport<S,S.Field>.self,&a)
            var maps: [OriginalParameterTransport<S,S.Field>]=[];maps.reserveCapacity(family.laws.count)
            for law in family.laws {
                try a.consumeWork(1)
                try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
                let local=try t.frame(source:family.source,field:family.field,support:intervals(law.support,family,&a),
                    semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
                try OriginalDomainAccess.storage(2,Int.self,&a);try OriginalDomainAccess.storage(4,S.Field.Value.self,&a)
                let map=try t.affine(from:local.fullSelection(limits:limits,using:&a),to:request.frame,
                    permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
                let image=try map.image.intersection(effective,limits:limits,using:&a)
                let reverse=try t.inverse(map,limits:limits,using:&a)
                maps.append(try t.inverse(t.restrict(reverse,to:image,limits:limits,using:&a),limits:limits,using:&a))
            }
            let covered=try DefaultOriginalDomainCoverIssuer<S,S.Field>().issue(request:request,charts:maps,limits:limits,using:&a)
            return .init(family:family,coverage:covered,maps:maps)
        }
    }
}
