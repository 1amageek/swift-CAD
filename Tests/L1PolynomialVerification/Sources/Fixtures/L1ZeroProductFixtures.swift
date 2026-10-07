import L0
import L1

public enum L1ZeroProductFixtures {
    public static func run() throws {
        var preparation = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits())
        let field = ExactRationalScalarDomain()
        let domain = try ExactPolynomialDomain(field: field, variableCount: 1, using: &preparation)
        let terms = (0..<5_000).map { ExactPolynomialTerm(powers: [$0], coefficient: ExactRationalCoefficient.one) }
        let polynomial = try domain.polynomial(terms: terms, using: &preparation)
        let zero = try domain.zero(using: &preparation)
        let other = try ExactPolynomialDomain(field: field, variableCount: 1, using: &preparation)
        let foreignZero = try other.zero(using: &preparation)
        for reverse in [false, true] {
            let first = reverse ? zero : polynomial, second = reverse ? polynomial : zero
            var constrained = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits(work: 3, storage: 0))
            let result = try domain.multiplying(first, second, using: &constrained)
            precondition(result.terms.isEmpty && result.depth == polynomial.depth)
            precondition(constrained.work == 3 && constrained.storageBytes == 0)
            _ = try domain.isZero(result, using: &preparation)
            try L1PrimitiveFixtures.rejected("domain") {
                _ = try domain.multiplying(reverse ? foreignZero : polynomial,
                    reverse ? polynomial : foreignZero, using: &preparation)
            }
            var baseline = try L1PrimitiveFixtures.CallbackAdmission()
            _ = try domain.multiplying(first, second, using: &baseline)
            var terminal = try L1PrimitiveFixtures.CallbackAdmission()
            terminal.cancelCheckpoint = baseline.checkpoints
            try L1PrimitiveFixtures.rejected("cancelled") {
                _ = try domain.multiplying(first, second, using: &terminal)
            }
            var finalWork = try L1PrimitiveFixtures.CallbackAdmission()
            finalWork.cancelWork = baseline.workCalls
            try L1PrimitiveFixtures.rejected("cancelled") {
                _ = try domain.multiplying(first, second, using: &finalWork)
            }
            var entry = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits())
            entry.cancel()
            try L1PrimitiveFixtures.rejected("cancelled") {
                _ = try domain.multiplying(first, second, using: &entry)
            }
            precondition(entry.work == 0 && entry.storageBytes == 0)
        }
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            let scalar = try L1PrimitiveFixtures.scalarField(axis: axis, degree: 3, refine: false)
            let d = try ExactPolynomialDomain(field: scalar, variableCount: 1, using: &preparation)
            let alpha = try scalar.generator(using: &preparation)
            let coefficient = try scalar.subtracting(scalar.multiplying(alpha, alpha, using: &preparation),
                scalar.integer(3, using: &preparation), using: &preparation)
            let p = try d.constant(coefficient, using: &preparation)
            let z = try d.zero(using: &preparation)
            precondition(axis == .value ? p.depth.value > z.depth.value : p.depth.coefficient > z.depth.coefficient)
            for reverse in [false, true] {
                let result = try d.multiplying(reverse ? z : p, reverse ? p : z, using: &preparation)
                precondition(result.terms.isEmpty && result.depth == p.depth)
                var shallow = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits(
                    valueDepth: axis == .value ? 0 : 32, coefficientDepth: axis == .coefficient ? 0 : 24))
                try L1PrimitiveFixtures.rejected(axis == .value ? "valueDepth" : "coefficientDepth") {
                    _ = try d.isZero(result, using: &shallow)
                }
            }
        }
    }
}
