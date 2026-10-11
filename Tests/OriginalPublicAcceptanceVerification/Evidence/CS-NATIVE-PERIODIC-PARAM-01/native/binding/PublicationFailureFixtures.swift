import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import NativeDomainAdapters
import SourceGeometryAdapters
import CADCore
@testable import NativeDomainAdapters

/// Verifies the production geometry boundary's nested failure normalization.
public enum PublicationFailureFixtures {
    public static func verifyBudgetFailure(_ cause: NativeExactRelationFailure,cancellation: Bool) throws {
        let error = NativeExactGeometryPublicationFailure.published(cause,tolerance:.standard)
        if cancellation {
            guard error is CancellationError else { throw ExactScalarFailure.invalidEvidence }
        } else {
            guard let actual = error as? KernelError,actual.code == .resourceLimitExceeded else {
                throw ExactScalarFailure.invalidEvidence
            }
        }
    }
    public static func verify() throws {
        let cases: [(NativeExactRelationFailure, KernelErrorCode)] = [
            (.nonDiscreteIntersection, .nonDiscreteIntersection),
            (.resultLimit, .resourceLimitExceeded),
            (.domain(.chartLimit), .resourceLimitExceeded),
            (.domain(.familyLimit), .resourceLimitExceeded),
            (.domain(.sourceDepthLimit), .resourceLimitExceeded),
            (.domain(.scalar(.resourceLimit(.work))), .resourceLimitExceeded),
            (.domain(.domain(.scalar(.resourceLimit(.storage)))), .resourceLimitExceeded),
            (.domain(.foreignOwner), .invalidInput),
            (.domain(.outsideSupport), .invalidInput),
            (.domain(.incompleteCoverage), .intersectionFailure),
            (.domain(.unsupportedSourceProof), .unsupportedCapability),
            (.source(.invalidSource), .invalidInput),
            (.source(.unsupportedCoefficientField), .unsupportedCapability),
            (.source(.sourceDepthLimit), .resourceLimitExceeded)
        ]
        for (cause, expected) in cases {
            let error = NativeExactGeometryPublicationFailure.published(cause, tolerance: .standard)
            guard let actual = error as? KernelError, actual.code == expected else {
                throw ExactScalarFailure.invalidEvidence
            }
        }
        for cause in [NativeExactRelationFailure.domain(.scalar(.cancelled)),
            .source(.sourceRejected(ExactScalarFailure.cancelled))] {
            guard NativeExactGeometryPublicationFailure.published(cause, tolerance: .standard) is CancellationError else {
                throw ExactScalarFailure.invalidEvidence
            }
        }
        print("PASS M2 nested publication failures retain cancellation, resource and domain meaning")
    }
}
