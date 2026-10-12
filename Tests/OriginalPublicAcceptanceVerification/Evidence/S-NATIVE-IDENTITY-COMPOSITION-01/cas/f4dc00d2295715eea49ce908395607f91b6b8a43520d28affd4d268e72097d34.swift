#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalIntrinsicParameterIdentityIssuing where S: OriginalIntrinsicSphereSourceReading {
    public func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalIntrinsicSphereDomainCover<S,F>,
        from selected: borrowing OriginalParameterSelection<S,F>,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
            return try orbit(period:cover.period,from:selected,effective:cover.effective,cycle:cycle,limits:limits,&a)
        }
    }
    public func intrinsicPole<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalIntrinsicSphereDomainCover<S,F>,
        on selected: borrowing OriginalParameterSelection<S,F>,latitude: F.Value,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover, selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            let scope = try cover.effective.intersection(selected,limits:limits,using:&a)
            guard scope.arity == 2,!scope.isEmpty,scope.frame.coordinateSemantics[0] == .intrinsicAngularLabel,
                scope.frame.coordinateSemantics[1] == .intrinsicAngularLabel else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            let law = try DefaultOriginalIntrinsicSphereLawIssuer<S,F>().pole(source:scope.frame.source,latitude:latitude,field:scope.frame.scalarField,limits:limits.source,using:&a)
            let f = scope.frame.scalarField
            for interval in scope.axes[1].intervals {
                try a.consumeWork(1)
                guard case .finite(let lo) = interval.lower,case .finite(let hi) = interval.upper,
                    try f.compare(lo,law.latitude,using:&a) == .equal,try f.compare(hi,law.latitude,using:&a) == .equal else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            }
            try OriginalDomainAccess.storage(1,OriginalSourcePoleReceipt<S,F>.self,&a)
            return try make(kind:.collapsedSubset,left:scope,right:scope,permutation:nil,gains:[],offsets:[],poles:[law],using:&a,limits:limits)
        }
    }
}
