#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

public enum ExactParametricRelationFailure: Error {
    case invalidMap, invalidKind, invalidEvidence, countOverflow
    case scalar(ExactScalarFailure)
    case polynomial(ExactPolynomialFailure)
    case cell(ExactRealCellFailure)
    case topology(ExactRealTopologyFailure)
    case operationRejected(any Error)

    init(_ error: any Error) {
        switch error {
        case let value as Self: self = value
        case let value as ExactScalarFailure: self = .scalar(value)
        case let value as ExactPolynomialFailure: self = .polynomial(value)
        case let value as ExactRealCellFailure: self = .cell(value)
        case let value as ExactRealTopologyFailure: self = .topology(value)
        default: self = .operationRejected(error)
        }
    }
}
