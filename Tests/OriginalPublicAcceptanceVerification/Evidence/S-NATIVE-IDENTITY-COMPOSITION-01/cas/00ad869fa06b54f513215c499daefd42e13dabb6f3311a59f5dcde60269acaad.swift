#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalDomainCoverIssuer<Source: Sendable,Field: ExactScalarArithmetic & ExactScalarOrdering>: OriginalDomainCoverIssuing {
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,Field>,
        charts: borrowing [OriginalParameterTransport<Source,Field>], limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalDomainCover<Source,Field> {
        let r = copy request, maps = copy charts
        return try OriginalDomainAccess.run(&admission) { a in
            guard maps.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            let support = try r.frame.fullSelection(limits:limits,using:&a)
            let effective = try r.intersection(support,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalParameterSelection<Source,Field>.self,&a)
            var remaining = effective.isEmpty ? [] : [effective]
            var selected: [OriginalDomainChart<Source,Field>] = []
            for map in maps {
                try a.consumeWork(1)
                try DefaultOriginalParameterTransporter<Source,Field>().admitted(map,limits:limits,using:&a)
                guard r.sharesFrame(with:map.image) else { throw OriginalDomainIdentityFailure.foreignOwner }
                let image = try map.image.intersection(effective,limits:limits,using:&a)
                if image.isEmpty { continue }
                try OriginalDomainAccess.storage(1,OriginalDomainChart<Source,Field>.self,&a)
                selected.append(.init(transport:map,selectedImage:image))
                var next: [OriginalParameterSelection<Source,Field>] = []
                for part in remaining {
                    try a.consumeWork(1)
                    let pieces = try part.difference(image,limits:limits,using:&a)
                    let count = try OriginalDomainAccess.add(next.count,pieces.count)
                    guard count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                    try OriginalDomainAccess.storage(pieces.count,OriginalParameterSelection<Source,Field>.self,&a)
                    next.append(contentsOf:pieces)
                }
                remaining = next
            }
            guard remaining.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return .init(support:support,request:r,effective:effective,charts:selected)
        }
    }
}
