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
        case let value as ExactRealRootFailure: return .root(value)
        case let value as ExactRealCellFailure: return .cell(value)
        case let value as ExactParametricRelationFailure: return .relation(value)
        default: return .geometry(error)
        }
    }
}
