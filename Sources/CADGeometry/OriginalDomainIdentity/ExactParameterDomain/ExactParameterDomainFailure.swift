#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public enum ExactParameterDomainFailure: Error {
    case invalidDomain, foreignOwner, invalidArity, countOverflow
    case scalar(ExactScalarFailure)
    case operationRejected(any Error)
}
