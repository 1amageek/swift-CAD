#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalAnalyticParameterIdentityIssuing
where S: OriginalAnalyticCoordinateReading, F: ExactScalarImporting {
    public func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<S,F>,
        from selected: borrowing OriginalParameterSelection<S,F>,axis: Int,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            guard cover.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            try cover.law.admitProof(limits:limits.source,using:&a)
            var period: OriginalSourcePeriodReceipt<S,F>? = nil
            for candidate in cover.law.periods {
                try a.consumeWork(1); if candidate.axis == axis { period = candidate }
            }
            guard let period else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            return try periodicIdentity(effective:cover.effective,selected:selected,period:period,cycle:cycle,limits:limits,&a)
        }
    }
    public func collapsed<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<S,F>,
        on selected: borrowing OriginalParameterSelection<S,F>,fiber: Int,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            try cover.law.admitProof(limits:limits.source,using:&a)
            guard fiber >= 0,fiber < cover.law.collapsedFibers.count else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            let theorem = cover.law.collapsedFibers[fiber]
            let scope = try cover.effective.intersection(selected,limits:limits,using:&a)
            guard scope.arity == 2,!scope.isEmpty,theorem.fixedAxis != theorem.varyingAxis,
                scope.axes.indices.contains(theorem.fixedAxis),scope.axes.indices.contains(theorem.varyingAxis),
                scope.frame.source.owns(theorem.anchor) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            let f = scope.frame.scalarField
            for interval in scope.axes[theorem.fixedAxis].intervals {
                try a.consumeWork(1)
                guard case .finite(let lo) = interval.lower,case .finite(let hi) = interval.upper,
                    try f.compare(lo,theorem.fixedValue,using:&a) == .equal,
                    try f.compare(hi,theorem.fixedValue,using:&a) == .equal else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            }
            try OriginalDomainAccess.storage(1,OriginalSourceCollapsedFiberReceipt<S,F>.self,&a)
            return try make(kind:.collapsedSubset,left:scope,right:scope,permutation:nil,gains:[],offsets:[],
                laws:cover.law.position,fibers:[theorem],using:&a,limits:limits)
        }
    }
}
