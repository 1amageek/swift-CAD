/// Independently retained causal depths; neither axis substitutes for the other.
public struct ExactScalarDepth: Sendable, Equatable {
    public let value: Int
    public let coefficient: Int
    public init(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        guard value >= 0, coefficient >= 0 else { throw .invalidSource }
        self.value = value; self.coefficient = coefficient
    }
    static let zero = Self(uncheckedValue: 0, coefficient: 0)
    init(uncheckedValue: Int, coefficient: Int) {
        self.value = uncheckedValue; self.coefficient = coefficient
    }
}
