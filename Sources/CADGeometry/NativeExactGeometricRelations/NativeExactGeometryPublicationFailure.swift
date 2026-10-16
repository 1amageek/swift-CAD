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
    @usableFromInline
    enum Resolution {
        case classified(KernelError, OriginalQueryResourceAxis?)
        case retained(OriginalQueryFailure)
        case cancelled(any Error)
        case foreign(any Error)
    }

    // Embedded error metadata must match the caller that boxed the incoming failure.
    @_alwaysEmitIntoClient
    static func published(_ error: any Error, tolerance: ModelingTolerance?,
        context: OriginalQueryFailureContext = .unspecified) -> any Error {
        switch resolve(error, tolerance: tolerance) {
        case .cancelled(let cancellation): return cancellation
        case .retained(let failure):
            return OriginalQueryFailure(originalError: failure.originalError, kernelFailure: failure.kernelFailure,
                context: failure.context.fillingMissing(from: context))
        case .classified(let classification, let axis):
            let observed: OriginalQueryFailureContext
            if context.resource == nil, let axis { observed = context.recording(resource: .init(axis: axis)) }
            else { observed = context }
            return OriginalQueryFailure(originalError: error, kernelFailure: classification, context: observed)
        case .foreign(let cause):
            let classification = KernelError.wrapping(cause, phase: .geometry, tolerance: tolerance)
            return OriginalQueryFailure(originalError: error, kernelFailure: classification, context: context)
        }
    }

    @usableFromInline
    static func resolve(_ error: any Error, tolerance: ModelingTolerance?) -> Resolution {
        if let error = error as? OriginalQueryFailure { return .retained(error) }
        if error is CancellationError { return .cancelled(error) }
        if let error = error as? KernelError { return .classified(error, nil) }
        if let error = error as? GeometryConversionError {
            let code: KernelErrorCode
            let message: String
            switch error {
            case .invalidInput(let detail): code = .invalidInput; message = detail
            case .resourceLimitExceeded(let detail): code = .resourceLimitExceeded; message = detail
            case .toleranceRejected:
                code = .approximationToleranceRejected
                message = "Original geometry conversion cannot certify the requested approximation tolerance."
            }
            return .classified(.init(phase: .geometry, code: code, tolerance: tolerance, message: message), nil)
        }
        if let error = error as? ExactScalarFailure {
            switch error {
            case .resourceLimit(let resource):
                let axis: OriginalQueryResourceAxis
                switch resource {
                case .work: axis = .work
                case .storage: axis = .storageBytes
                case .valueDepth: axis = .valueDepth
                case .coefficientDepth: axis = .coefficientDepth
                }
                return failure(.resourceLimitExceeded, tolerance, axis: axis)
            case .admissionRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .cancelled: return .cancelled(CancellationError())
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .invalidSource, .divisionByZero, .incompatibleDomain: return failure(.invalidInput, tolerance)
            case .unresolved, .unsupportedRepresentation, .invalidEvidence: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? NativeExactGeometricRelationFailure {
            switch error {
            case .parameter(let cause): return resolve(cause, tolerance: tolerance)
            case .geometric(let cause): return resolve(cause, tolerance: tolerance)
            case .publication(let cause): return resolve(cause, tolerance: tolerance)
            }
        }
        if let error = error as? NativeExactRelationFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .root(let cause): return resolve(cause, tolerance: tolerance)
            case .cell(let cause): return resolve(cause, tolerance: tolerance)
            case .relation(let cause): return resolve(cause, tolerance: tolerance)
            case .geometry(let cause): return resolve(cause, tolerance: tolerance)
            case .domain(let cause): return resolve(cause, tolerance: tolerance)
            case .source(let cause): return resolve(cause, tolerance: tolerance)
            case .nonDiscreteIntersection: return failure(.nonDiscreteIntersection, tolerance)
            case .resultLimit: return failure(.resourceLimitExceeded, tolerance, axis: .results)
            case .invalidDomain: return failure(.invalidInput, tolerance)
            case .invalidDegree: return failure(.resourceLimitExceeded, tolerance, axis: .polynomialDegree)
            case .unsupportedCoverage: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? OriginalDomainIdentityFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .domain(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .source(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .sourceDepthLimit: return failure(.resourceLimitExceeded, tolerance, axis: .sourceDepth)
            case .transportDepthLimit: return failure(.resourceLimitExceeded, tolerance, axis: .transportDepth)
            case .chartLimit: return failure(.resourceLimitExceeded, tolerance, axis: .charts)
            case .familyLimit: return failure(.resourceLimitExceeded, tolerance, axis: .families)
            case .identityLimit: return failure(.resourceLimitExceeded, tolerance, axis: .identities)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .unsupportedSourceProof: return failure(.unsupportedCapability, tolerance)
            case .incompleteCoverage: return failure(.intersectionFailure, tolerance)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? OriginalSourceIssuanceFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .sourceRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .sourceDepthLimit: return failure(.resourceLimitExceeded, tolerance, axis: .sourceDepth)
            case .chartLimit: return failure(.resourceLimitExceeded, tolerance, axis: .charts)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .unsupportedRepresentation, .unsupportedCoefficientField: return failure(.unsupportedCapability, tolerance)
            case .unresolvedAuthority: return failure(.intersectionFailure, tolerance)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? ExactParameterDomainFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            default: return failure(.invalidInput, tolerance)
            }
        }
        if let error = error as? ExactGeometricRelationFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .cell(let cause): return resolve(cause, tolerance: tolerance)
            case .topology(let cause): return resolve(cause, tolerance: tolerance)
            case .parameter(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .resultLimit: return failure(.resourceLimitExceeded, tolerance, axis: .results)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactParametricRelationFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .cell(let cause): return resolve(cause, tolerance: tolerance)
            case .topology(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealTopologyFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .cell(let cause): return resolve(cause, tolerance: tolerance)
            case .root(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .generatedCellLimit: return failure(.resourceLimitExceeded, tolerance, axis: .cells)
            case .closureLimit: return failure(.resourceLimitExceeded, tolerance, axis: .closures)
            case .attachmentLimit: return failure(.resourceLimitExceeded, tolerance, axis: .attachments)
            case .componentLimit: return failure(.resourceLimitExceeded, tolerance, axis: .results)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealCellFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .root(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .cellLimit: return failure(.resourceLimitExceeded, tolerance, axis: .cells)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactRealRootFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .polynomial(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            case .resultLimit: return failure(.resourceLimitExceeded, tolerance, axis: .results)
            case .extensionLevelLimit: return failure(.resourceLimitExceeded, tolerance, axis: .extensionLevel)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        if let error = error as? ExactPolynomialFailure {
            switch error {
            case .scalar(let cause): return resolve(cause, tolerance: tolerance)
            case .operationRejected(let cause): return resolve(cause, tolerance: tolerance)
            case .countOverflow, .exponentOverflow: return failure(.resourceLimitExceeded, tolerance, axis: .countOverflow)
            default: return failure(.intersectionFailure, tolerance)
            }
        }
        return .foreign(error)
    }

    @usableFromInline
    static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance?,
        axis: OriginalQueryResourceAxis? = nil) -> Resolution {
        .classified(.init(phase: .geometry, code: code, tolerance: tolerance,
            message: "The original exact geometric query could not complete its required publication."), axis)
    }
}
