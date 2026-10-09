#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalPlaneDomainIssuer<S: OriginalPlaneSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalPlaneDomainIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func frame<A: ExactScalarAdmission & ~Copyable>(basis: borrowing OriginalPlaneBasisReceipt<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let basis = copy basis
        return try OriginalDomainAccess.run(&admission) { a in
            // Reading the whole basis admits its retained coefficient owners/depth.
            _ = try basis.position(u:basis.field.integer(0,using:&a),v:basis.field.integer(0,using:&a),limits:limits,using:&a)
            let whole = try ExactParameterInterval<F.Value>.checked(field:basis.field,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:basis.source,field:basis.field,support:[[whole],[whole]],semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,basis: borrowing OriginalPlaneBasisReceipt<S,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalPrimitiveDomainCover<S,F,OriginalPlaneBasisReceipt<S,F>> {
        let r = copy request,basis = copy basis
        return try OriginalDomainAccess.run(&admission) { a in
            guard try r.frame.source.owns(basis.source.chart(0,limits:limits.source,using:&a)) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard r.arity == 2,r.frame.coordinateSemantics[0] == .authoredScalar,r.frame.coordinateSemantics[1] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let f = r.frame.scalarField
            for vector in [basis.origin,basis.normal,basis.u,basis.v] { for value in vector { try a.consumeWork(1); _ = try f.sign(of:value,using:&a) } }
            let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
            let support = try r.frame.selection(intervals:[[whole],[whole]],limits:limits,using:&a)
            guard try support.equals(r.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            let effective = try r.intersection(support,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPrimitiveDomainCover<S,F,OriginalPlaneBasisReceipt<S,F>>.self,&a)
            return .init(law:basis,support:support,request:r,effective:effective)
        }
    }
}
