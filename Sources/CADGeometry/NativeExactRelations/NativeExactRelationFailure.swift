public enum NativeExactRelationFailure: Error {
    case unsupportedCoverage, invalidDomain, invalidDegree
    case scalar(ExactScalarFailure)
    case root(ExactRealRootFailure)
    case cell(ExactRealCellFailure)
    case relation(ExactParametricRelationFailure)
    case geometry(any Error)

    static func preserving(_ error: any Error) -> Self {
        switch error {
        case let value as Self: return value
        case let value as ExactScalarFailure:
            if case .admissionRejected(let cause) = value, let native = cause as? Self { return native }
            return .scalar(value)
        case let value as OriginalSourceIssuanceFailure:
            switch value {
            case .scalar(let cause): return .preserving(cause)
            case .sourceRejected(let cause): return .preserving(cause)
            case .polynomial(let cause): return .preserving(cause)
            default: return .geometry(value)
            }
        case let value as ExactPolynomialFailure:
            switch value {
            case .scalar(let cause): return .preserving(cause)
            case .operationRejected(let cause): return .preserving(cause)
            default: return .geometry(value)
            }
        case let value as ExactRealRootFailure: return .root(value)
        case let value as ExactRealCellFailure: return .cell(value)
        case let value as ExactParametricRelationFailure: return .relation(value)
        default: return .geometry(error)
        }
    }
}
