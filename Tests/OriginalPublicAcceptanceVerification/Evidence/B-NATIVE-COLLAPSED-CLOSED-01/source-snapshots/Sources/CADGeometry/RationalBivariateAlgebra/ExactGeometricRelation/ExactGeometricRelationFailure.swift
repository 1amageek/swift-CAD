#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Explicit geometric interpretation failures preserving their original causes.
public enum ExactGeometricRelationFailure: Error {
    case invalidSourceBinding, invalidStation, foreignHandle, invalidCoverage, countOverflow, resultLimit
    case scalar(ExactScalarFailure), polynomial(ExactPolynomialFailure), cell(ExactRealCellFailure)
    case topology(ExactRealTopologyFailure), parameter(ExactParametricRelationFailure)
    case operationRejected(any Error)
    static func preserving(_ error: any Error) -> Self {
        switch error {
        case let e as Self: return e
        case let e as ExactScalarFailure: return .scalar(e)
        case let e as ExactPolynomialFailure: return .polynomial(e)
        case let e as ExactRealCellFailure: return .cell(e)
        case let e as ExactRealTopologyFailure: return .topology(e)
        case let e as ExactParametricRelationFailure: return .parameter(e)
        default: return .operationRejected(error)
        }
    }
}
