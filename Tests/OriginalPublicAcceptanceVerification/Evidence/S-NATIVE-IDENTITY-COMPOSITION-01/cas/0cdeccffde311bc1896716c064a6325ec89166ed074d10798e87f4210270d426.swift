/// Word-based admission consumed by the existing exact numeric algorithms.
public protocol RationalAlgebraAdmitting {
    var exactDepthResource: ExactResource { get }
    mutating func visitExactCell(depth: Int) throws
    mutating func visitCoefficientCell(depth: Int) throws
    mutating func consumeExactWork(_ count: Int) throws
    mutating func retainExactStorage(_ count: Int) throws
}

public extension RationalAlgebraAdmitting {
    var exactDepthResource: ExactResource { .valueDepth }
    /// A caller with independent depth axes supplies its own requirement witness.
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
}
