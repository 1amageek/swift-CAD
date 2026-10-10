#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

import CADCore

/// Converts nested exact causes once at the existing numerical Geometry boundary.
enum NativeExactGeometryPublicationFailure {
    // Embedded error metadata must match the caller that boxed the incoming failure.
    @_alwaysEmitIntoClient
    static func published(_ error: any Error, tolerance: ModelingTolerance) -> any Error {
        if error is CancellationError { return error }
        if let error = error as? KernelError { return error }
        if let error = error as? ExactScalarFailure {
            if case .resourceLimit(let resource) = error {
                let name: String
                switch resource {
                case .work: name = "work"
                case .storage: name = "storage"
                case .valueDepth: name = "value depth"
                case .coefficientDepth: name = "coefficient depth"
                }
                return KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original exact geometric publication exhausted caller " + name + ".")
            }
            if case .admissionRejected(let cause) = error { return published(cause, tolerance: tolerance) }
            return GeometryExactScalarFailure.published(error)
        }
        if let error = error as? NativeExactGeometricRelationFailure {
            switch error {
            case .parameter(let cause): return published(cause, tolerance: tolerance)
            case .geometric(let cause): return published(cause, tolerance: tolerance)
            case .publication(let cause): return published(cause, tolerance: tolerance)
            }
        }
        if let error = error as? NativeExactRelationFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .root(let cause): return published(cause, tolerance: tolerance)
            case .cell(let cause): return published(cause, tolerance: tolerance)
            case .relation(let cause): return published(cause, tolerance: tolerance)
            case .geometry(let cause): return published(cause, tolerance: tolerance)
            case .domain(let cause): return published(cause, tolerance: tolerance)
            case .source(let cause): return published(cause, tolerance: tolerance)
            case .nonDiscreteIntersection: return failure(.nonDiscreteIntersection, tolerance)
            case .resultLimit: return failure(.resourceLimitExceeded, tolerance)
            case .invalidDomain: return failure(.invalidInput, tolerance)
            case .invalidDegree: return failure(.resourceLimitExceeded, tolerance)
            case .unsupportedCoverage: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? OriginalDomainIdentityFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .domain(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .source(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .sourceDepthLimit, .transportDepthLimit, .chartLimit, .familyLimit, .identityLimit, .countOverflow:
                return failure(.resourceLimitExceeded, tolerance)
            case .unsupportedSourceProof: return failure(.unsupportedCapability, tolerance)
            case .incompleteCoverage: return failure(.intersectionFailure, tolerance)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? OriginalSourceIssuanceFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .sourceRejected(let cause): return published(cause, tolerance: tolerance)
            case .sourceDepthLimit, .chartLimit, .countOverflow: return failure(.resourceLimitExceeded, tolerance)
            case .unsupportedRepresentation, .unsupportedCoefficientField: return failure(.unsupportedCapability, tolerance)
            case .unresolvedAuthority: return failure(.intersectionFailure, tolerance)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? ExactParameterDomainFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? ExactGeometricRelationFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .cell(let cause): return published(cause, tolerance: tolerance)
            case .topology(let cause): return published(cause, tolerance: tolerance)
            case .parameter(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow, .resultLimit: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactParametricRelationFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .cell(let cause): return published(cause, tolerance: tolerance)
            case .topology(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealTopologyFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .cell(let cause): return published(cause, tolerance: tolerance)
            case .root(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow, .generatedCellLimit, .closureLimit, .attachmentLimit, .componentLimit:
                return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealCellFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .root(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow, .cellLimit: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealRootFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .polynomial(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow, .resultLimit, .extensionLevelLimit: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactPolynomialFailure {
            switch error {
            case .scalar(let cause): return published(cause, tolerance: tolerance)
            case .operationRejected(let cause): return published(cause, tolerance: tolerance)
            case .countOverflow, .exponentOverflow: return failure(.resourceLimitExceeded, tolerance)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        return error
    }

    @usableFromInline
    static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance,
            message: "The original exact geometric query could not complete its required publication.")
    }
}
