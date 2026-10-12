#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public enum ExactRealRootFailure: Error {
    case invalidSource, invalidVariable, invalidDomain, incompatibleDomain, invalidEvidence
    case unresolved, countOverflow, resultLimit, extensionLevelLimit
    case scalar(ExactScalarFailure), polynomial(ExactPolynomialFailure)
    case operationRejected(any Error)
}
