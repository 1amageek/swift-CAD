#if L1_ISOLATED_VERIFICATION
import L0
#endif

public protocol ExactPolynomialCalculus: Sendable {
    associatedtype Polynomial: Sendable
    associatedtype Coefficient: Sendable
    associatedtype Evaluation: Sendable
    func evaluated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, at coordinates: [Coefficient], using admission: inout A) throws(ExactPolynomialFailure) -> Evaluation
    func differentiated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, in variable: Int, using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
    func substituted<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, with replacements: [Polynomial], using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
}
