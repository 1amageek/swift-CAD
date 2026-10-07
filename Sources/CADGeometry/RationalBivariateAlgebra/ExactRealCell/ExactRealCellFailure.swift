#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public enum ExactRealCellFailure: Error {
    case invalidSource, invalidDomain, invalidVariable, invalidPredicate, incompatibleDomain
    case invalidCell, invalidCoverage, countOverflow, cellLimit, unresolved
    case scalar(ExactScalarFailure), polynomial(ExactPolynomialFailure), root(ExactRealRootFailure)
    case operationRejected(any Error)
}
