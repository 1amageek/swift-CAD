#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalLinearDomainIssuer<S: OriginalLinearSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalLinearDomainIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func frame<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: F,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let source = copy source
        return try OriginalDomainAccess.run(&admission) { a in
            let whole = try ExactParameterInterval<F.Value>.checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(1,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(1,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:field,support:[[whole]],semantics:[.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalPrimitiveDomainCover<S,F,OriginalWholeLinearLawReceipt<S,F>> {
        try issue(request:request,sourceIssuer:DefaultOriginalWholeLinearLawIssuer<S,F>(),limits:limits,using:&admission)
    }
    public func issue<I: OriginalWholeLinearLawIssuing,A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,
        sourceIssuer: I,limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalPrimitiveDomainCover<S,F,OriginalWholeLinearLawReceipt<S,F>> where I.Source == S,I.Field == F {
        let r = copy request
        return try OriginalDomainAccess.run(&admission) { a in
            guard r.arity == 1,r.frame.coordinateSemantics[0] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let f = r.frame.scalarField
            let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(1,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
            let support = try r.frame.selection(intervals:[[whole]],limits:limits,using:&a)
            guard try support.equals(r.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            let law = try sourceIssuer.issue(source:r.frame.source,field:f,limits:limits.source,using:&a)
            let effective = try r.intersection(support,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalPrimitiveDomainCover<S,F,OriginalWholeLinearLawReceipt<S,F>>.self,&a)
            return .init(law:law,support:support,request:r,effective:effective)
        }
    }
}
