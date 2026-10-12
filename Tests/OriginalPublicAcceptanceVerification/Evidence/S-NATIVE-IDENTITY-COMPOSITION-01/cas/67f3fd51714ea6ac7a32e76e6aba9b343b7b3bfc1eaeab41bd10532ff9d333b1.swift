#if L1_ISOLATED_VERIFICATION
import L0
#endif

/// An authored term; the domain constructor validates powers and coefficient ownership.
public struct ExactPolynomialTerm<C: Sendable>: Sendable {
    public let powers: [Int]
    public let coefficient: C
    public init(powers: [Int], coefficient: C) { self.powers = powers; self.coefficient = coefficient }
}
