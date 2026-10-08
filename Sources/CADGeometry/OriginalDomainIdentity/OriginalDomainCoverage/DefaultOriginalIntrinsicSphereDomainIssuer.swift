#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalIntrinsicSphereDomainIssuer<S: OriginalIntrinsicSphereSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalIntrinsicSphereDomainIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func frame<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: F,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let source = copy source
        return try OriginalDomainAccess.run(&admission) { a in
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            let quarter = try field.binary64(exactly:Double.pi * 0.5,using:&a)
            let depth = try ExactScalarDepth(value:0,coefficient:0)
            let u = try ExactParameterInterval.checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:depth,using:&a)
            let v = try ExactParameterInterval.checked(field:field,lower:.finite(field.negated(quarter,using:&a)),upper:.finite(quarter),depth:depth,using:&a)
            try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:field,support:[[u],[v]],
                semantics:[.intrinsicAngularLabel,.intrinsicAngularLabel],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalIntrinsicSphereDomainCover<S,F> {
        let request = copy request
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
            guard request.arity == 2,request.frame.coordinateSemantics[0] == .intrinsicAngularLabel,
                request.frame.coordinateSemantics[1] == .intrinsicAngularLabel else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let f = request.frame.scalarField
            let authoritative = try frame(source:request.frame.source,field:f,limits:limits,using:&a)
            let full = try authoritative.fullSelection(limits:limits,using:&a)
            // Rebind only the exact source-derived sets into the retained request frame.
            try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
            var intervals: [[ExactParameterInterval<F.Value>]] = []
            for axis in full.axes { try a.consumeWork(1); try OriginalDomainAccess.storage(axis.intervalCount,ExactParameterInterval<F.Value>.self,&a); intervals.append(Array(axis.intervals)) }
            let support = try request.frame.selection(intervals:intervals,limits:limits,using:&a)
            guard try support.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else {
                throw OriginalDomainIdentityFailure.invalidDomain
            }
            let effective = try request.intersection(support,limits:limits,using:&a)
            let period = try DefaultOriginalIntrinsicSphereLawIssuer<S,F>().period(source:request.frame.source,field:f,limits:limits.source,using:&a)
            return .init(frame:request.frame,request:request,effective:effective,period:period)
        }
    }
}
