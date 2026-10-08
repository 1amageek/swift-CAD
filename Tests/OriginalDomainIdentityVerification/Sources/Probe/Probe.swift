import L0
import DI0

@main struct DomainDependencyProbe {
    static func main() throws {
        var admission = ExactScalarLedger(limits: try .init(work: 10_000,
            storageBytes: 100_000, valueDepth: 8, coefficientDepth: 8))
        let field = ExactRationalScalarDomain()
        let zero = try field.integer(0, using: &admission)
        let one = try field.integer(1, using: &admission)
        guard try field.compare(zero, one, using: &admission) == .less else {
            throw ExactParameterDomainFailure.invalidDomain
        }
        print("PASS dependency boundary: L0 + DI0 only; no set-behavior claim")
    }
}
