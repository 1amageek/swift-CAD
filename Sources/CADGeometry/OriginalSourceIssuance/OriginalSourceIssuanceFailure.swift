#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public enum OriginalSourceIssuanceFailure: Error {
    case invalidSource, invalidChart, foreignBinding, unsupportedRepresentation
    case unresolvedAuthority, sourceDepthLimit, chartLimit, countOverflow
    case scalar(ExactScalarFailure)
    case polynomial(ExactPolynomialFailure)
    case sourceRejected(any Error)

    init(preserving error: any Error) {
        switch error {
        case let failure as Self: self = failure
        case let failure as ExactScalarFailure: self = .scalar(failure)
        case let failure as ExactPolynomialFailure: self = .polynomial(failure)
        default: self = .sourceRejected(error)
        }
    }
}
