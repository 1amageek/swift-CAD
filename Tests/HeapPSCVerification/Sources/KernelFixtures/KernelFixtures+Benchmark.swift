// ContinuousClock is not provided by the pinned Embedded runtime.
#if !hasFeature(Embedded)
import L0
@testable import L1

extension KernelFixtures {
    static func expanded(_ d: Domain, _ p: Polynomial, _ q: Polynomial,
        _ a: inout ExactScalarLedger) throws -> Polynomial {
        try d.query(&a, p, q) { usage in
            let count = try ExactPolynomialAccess.count(p.termCount, q.termCount, multiply: true)
            try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Field.Value>.self, &usage)
            var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(count)
            for left in p.terms { for right in q.terms {
                var powers = try d.powers(&usage)
                for axis in powers.indices { powers[axis] = try ExactPolynomialAccess.exponent(left.powers[axis], right.powers[axis]) }
                terms.append(.init(powers: powers, coefficient: try d.field.multiplying(left.coefficient, right.coefficient, using: &usage)))
            } }
            return try d.canonical(terms, &usage)
        }
    }
    public static func benchmark() throws {
        for mode in 0..<3 {
            var setup = try ledger()
            let f = Field(), d = try Domain(field: f, variableCount: 2, using: &setup)
            let one = try f.integer(1, using: &setup), minus = try f.integer(-1, using: &setup)
            let p = try d.polynomial(terms: (0..<32).map { .init(powers: [$0,0], coefficient: one) }, using: &setup)
            let q = try d.polynomial(terms: (0..<32).map {
                .init(powers: mode == 1 ? [0,$0] : [$0,0], coefficient: mode == 2 && $0 % 2 == 1 ? minus : one)
            }, using: &setup)
            var reference = try ledger(), heap = try ledger()
            let old = try expanded(d,p,q,&reference), new = try d.multiplying(p,q,using:&heap)
            try check(try d.equals(old,new,using:&setup))
            try check(heap.storageBytes < reference.storageBytes)
            for iteration in 0..<3 {
                for label in (iteration % 2 == 0 ? ["expanded","heap"] : ["heap","expanded"]) {
                    var a = try ledger(); let start = ContinuousClock.now
                    for _ in 0..<5 { _ = try label == "heap" ? d.multiplying(p,q,using:&a) : expanded(d,p,q,&a) }
                    print("multiply mode=\(mode) iteration=\(iteration) algorithm=\(label) elapsed=\(start.duration(to:.now)) work=\(a.work) bytes=\(a.storageBytes) output=\(new.termCount)")
                }
            }
        }
    }
}

#endif
