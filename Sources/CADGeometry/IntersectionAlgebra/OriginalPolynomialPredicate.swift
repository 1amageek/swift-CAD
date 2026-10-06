/// A validated original sign predicate, in postfix order, bound to its law list.
public struct OriginalPolynomialPredicate: Sendable {
    public enum Sign: Int, Sendable {
        case negative = -1, zero = 0, positive = 1
        package var original: ExactAlgebraicRealRoot.Sign {
            switch self { case .negative: return .negative; case .zero: return .zero; case .positive: return .positive }
        }
    }
    public enum Instruction: Sendable {
        case literal(Bool)
        case sign(polynomial: Int, Sign)
        case not, and, or
    }
    package let original: ExactIntersectionBooleanProgram
    public var polynomialCount: Int { original.polynomialCount }

    public init<B: RationalAlgebraAdmitting>(polynomialCount: Int,
        instructions: [Instruction], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(instructions.count, of: ExactIntersectionBooleanProgram.Instruction.self, usage: &usage)
        var program: [ExactIntersectionBooleanProgram.Instruction] = []; program.reserveCapacity(instructions.count)
        for instruction in instructions {
            try intersectionAlgebraStep(&usage)
            switch instruction {
            case .literal(let value): program.append(.literal(value))
            case .sign(let index, let sign): program.append(.atom(index, sign.original))
            case .not: program.append(.not)
            case .and: program.append(.and)
            case .or: program.append(.or)
            }
        }
        original = try .init(polynomialCount: polynomialCount, instructions: program, usage: &usage)
    }
}
