/// Preserves lower exact causes and the geometry publication failure boundary.
public enum NativeExactGeometricRelationFailure: Error {
    case parameter(NativeExactRelationFailure)
    case geometric(ExactGeometricRelationFailure)
    case publication(any Error)

    static func preserving(_ error: any Error) -> Self {
        switch error {
        case let value as Self: return value
        case let value as NativeExactRelationFailure: return .parameter(value)
        case let value as ExactGeometricRelationFailure: return .geometric(value)
        default: return .publication(error)
        }
    }
}
