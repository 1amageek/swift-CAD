#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalRevolutionParameterIdentityIssuing
where S: OriginalRevolutionSourceReading,F: ExactScalarImporting,F.Source == F.Value {
    public func periodic<C: Sendable,A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalRevolutionDomainCover<S,C,F>,
        from selected: borrowing OriginalParameterSelection<S,F>,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            guard cover.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            guard cover.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try cover.family.admitProof(limits:limits.source,using:&a)
            return try periodicIdentity(effective:cover.effective,selected:selected,period:cover.family.period,cycle:cycle,limits:limits,&a)
        }
    }
}
