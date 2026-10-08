#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete parameter coverage relative to the declared frame, not a source-law certificate.
public struct OriginalDomainCover<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalDomainCoverQuerying {
    public typealias Source = S
    public typealias Field = F
    public let support: OriginalParameterSelection<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    let storage: [OriginalDomainChart<S,F>]
    public var charts: ArraySlice<OriginalDomainChart<S,F>> { storage[...] }
    init(support: OriginalParameterSelection<S,F>,request: OriginalParameterSelection<S,F>,
        effective: OriginalParameterSelection<S,F>,charts: [OriginalDomainChart<S,F>]) {
        self.support = support; self.request = request; self.effective = effective; storage = charts
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Int] {
        let values = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            guard storage.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            if try !effective.contains(values,limits:limits,using:&a) { return [] }
            var result: [Int] = []
            for i in storage.indices {
                try a.consumeWork(1)
                if try storage[i].selectedImage.contains(values,limits:limits,using:&a) {
                    try OriginalDomainAccess.storage(1,Int.self,&a); result.append(i)
                }
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
