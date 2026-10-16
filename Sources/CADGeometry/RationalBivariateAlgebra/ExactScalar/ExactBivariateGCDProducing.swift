/// Injected exact GCD authority; generic callers retain a concrete admitted budget.
public protocol ExactBivariateGCDProducing: Sendable {
    func greatestCommonDivisor<B: ExactScalarAdmission & ~Copyable>(
        _ first: ExactBivariatePolynomial, _ second: ExactBivariatePolynomial,
        usage: inout B) throws -> ExactBivariatePolynomial
}
