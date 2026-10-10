#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
@testable import func CADGeometry.rationalAlgebraFailure
#endif

import CADCore

/// Keeps independent scalar errors behind the existing Geometry failure boundary.
enum GeometryExactScalarFailure {
    static func withPublication<Result>(_ body: () throws -> Result) throws -> Result {
        do { return try body() }
        catch let failure as ExactScalarFailure { throw published(failure) }
    }

    static func published(_ failure: ExactScalarFailure) -> any Error {
        switch failure {
        case .admissionRejected(let cause): return cause
        case .cancelled: return CancellationError()
        case .resourceLimit, .countOverflow:
            return KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original exact scalar admission exhausted its caller resource limit.")
        case .invalidSource, .divisionByZero, .incompatibleDomain:
            return KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Original exact scalar source or operation is invalid.")
        case .unresolved, .unsupportedRepresentation, .invalidEvidence:
            return rationalAlgebraFailure("Original exact scalar operation cannot certify its requested result.")
        }
    }
}
