import L0
import L1

@main
struct L1ZeroProductBenchmark {
    static func benchmark() throws {
        let f = ExactRationalScalarDomain()
        var preparation = ExactScalarLedger(limits: try .init(work: 500_000_000, storageBytes: 1_000_000_000, valueDepth: 0, coefficientDepth: 0))
        let domain = try ExactPolynomialDomain(field: f, variableCount: 1, using: &preparation)
        let zero = try domain.zero(using: &preparation)
        for count in [1_000, 50_000] {
            let terms = (0..<count).map { ExactPolynomialTerm(powers: [$0], coefficient: ExactRationalCoefficient.one) }
            let polynomial = try domain.polynomial(terms: terms, using: &preparation)
            var measurements: [Double] = []
            for _ in 0..<5 {
                var admission = ExactScalarLedger(limits: try .init(work: 600, storageBytes: 0, valueDepth: 0, coefficientDepth: 0))
                let clock = ContinuousClock()
                let start = clock.now
                for _ in 0..<200 {
                    let result = try domain.multiplying(polynomial, zero, using: &admission)
                    precondition(result.termCount == 0)
                }
                let elapsed = start.duration(to: clock.now).components
                measurements.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                precondition(admission.work == 600 && admission.storageBytes == 0)
            }
            print("BENCHMARK: terms=\(count) repetitions=200 medianSeconds=\(measurements.sorted()[2])")
        }
    }
    static func main() throws { try benchmark() }
}
