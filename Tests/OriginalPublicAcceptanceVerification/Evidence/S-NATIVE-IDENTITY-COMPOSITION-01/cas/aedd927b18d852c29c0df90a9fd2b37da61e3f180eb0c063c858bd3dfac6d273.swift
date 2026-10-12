#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public enum OriginalDomainIdentityFailure: Error {
    case invalidDomain, foreignOwner, incompatibleCoordinateSemantics, singularTransport
    case outsideSupport, incompleteCoverage, unsupportedSourceProof, invalidIdentityProof
    case sourceDepthLimit, transportDepthLimit, chartLimit, familyLimit, identityLimit, countOverflow
    case scalar(ExactScalarFailure), domain(ExactParameterDomainFailure)
    case polynomial(ExactPolynomialFailure), source(OriginalSourceIssuanceFailure)
    case operationRejected(any Error)
    init(preserving error: any Error) {
        switch error {
        case let e as Self: self = e
        case let e as ExactScalarFailure: self = .scalar(e)
        case let e as ExactParameterDomainFailure: self = .domain(e)
        case let e as ExactPolynomialFailure: self = .polynomial(e)
        case let e as OriginalSourceIssuanceFailure: self = .source(e)
        default: self = .operationRejected(error)
        }
    }
}
