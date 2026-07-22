public enum RationalBezierHalfSpaceClassification: Sendable, Hashable {
    case nonnegative
    case violates(residual: Double)
}
