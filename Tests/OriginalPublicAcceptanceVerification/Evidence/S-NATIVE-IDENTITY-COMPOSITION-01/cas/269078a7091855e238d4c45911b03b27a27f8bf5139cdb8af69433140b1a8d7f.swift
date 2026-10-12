#if L1_ISOLATED_VERIFICATION
import L0
#endif

public enum ExactPolynomialFailure: Error {
    case invalidVariableCount, invalidVariable, invalidExponent, incompatibleDomain
    case exponentOverflow, countOverflow, zeroDivisor, notDivisible
    case undefinedMultiplicity, invalidCertificate
    case scalar(ExactScalarFailure)
    case operationRejected(any Error)
}
