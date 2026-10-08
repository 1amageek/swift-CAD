// ContinuousClock is not provided by the pinned Embedded runtime.
#if !hasFeature(Embedded)
import L0
@testable import L1

extension KernelFixtures {
    public static func pscBenchmark() throws {
        for mode in 0..<4 {
            var setup = try ledger()
            let f = Field(), d = try Domain(field:f,variableCount:1,using:&setup)
            let p: Polynomial, q: Polynomial
            if mode == 1 {
                p = try d.polynomial(terms:[.init(powers:[4],coefficient:try f.integer(1,using:&setup)),.init(powers:[0],coefficient:try f.integer(1,using:&setup))],using:&setup)
                q = try d.polynomial(terms:[.init(powers:[4],coefficient:try f.integer(1,using:&setup)),.init(powers:[0],coefficient:try f.integer(-1,using:&setup))],using:&setup)
            } else {
                let m = mode == 0 ? 4 : mode == 3 ? 1 : 2, n = mode == 0 ? 3 : 1
                p = try d.polynomial(terms:(0...m).map { .init(powers:[$0],coefficient:try f.integer($0+1,using:&setup)) },using:&setup)
                q = try d.polynomial(terms:(0...n).map { .init(powers:[$0],coefficient:try f.integer(2*$0-1,using:&setup)) },using:&setup)
            }
            let reference = try d.principalSubresultants(p,q,eliminating:0,algorithm:.determinant,using:&setup)
            let actual = try d.principalSubresultants(p,q,eliminating:0,algorithm:.prs,using:&setup)
            for index in reference.values.indices { try check(try d.equals(reference.values[index],actual.values[index],using:&setup)) }
            for iteration in 0..<3 {
                for method: ExactPolynomialSubresultantAlgorithm in (iteration % 2 == 0 ? [.determinant,.prs] : [.prs,.determinant]) {
                    var a = try ledger(); let start = ContinuousClock.now
                    for _ in 0..<5 { _ = try d.principalSubresultants(p,q,eliminating:0,algorithm:method,using:&a) }
                    let label = method == .prs ? "prs" : "determinant"
                    print("PSC mode=\(mode) iteration=\(iteration) method=\(label) elapsed=\(start.duration(to:.now)) work=\(a.work) bytes=\(a.storageBytes) count=\(actual.values.count)")
                }
            }
        }
    }
}

#endif
