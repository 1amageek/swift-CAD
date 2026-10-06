import CADCore

/// An immutable sign program whose operands belong to one original polynomial list.
package struct ExactIntersectionBooleanProgram: Sendable {
    package enum Instruction: Sendable {
        case literal(Bool)
        case atom(Int, ExactAlgebraicRealRoot.Sign)
        case not
        case and
        case or
    }
    package let polynomialCount: Int
    package let instructions: [Instruction]
    package let maximumStackCount: Int

    package init<B: RationalAlgebraAdmitting>(polynomialCount: Int,
        instructions: [Instruction], usage: inout B) throws {
        guard polynomialCount >= 0 else { throw rationalAlgebraFailure("A sign program requires a bound source list.") }
        var depth = 0, maximum = 0
        for instruction in instructions {
            try intersectionAlgebraStep(&usage)
            switch instruction {
            case .literal: depth = try rationalAlgebraCount(depth, 1)
            case .atom(let index, _):
                guard index >= 0, index < polynomialCount else {
                    throw rationalAlgebraFailure("A sign program atom is outside its original source list.")
                }
                depth = try rationalAlgebraCount(depth, 1)
            case .not:
                guard depth > 0 else { throw rationalAlgebraFailure("A sign program has no negation operand.") }
            case .and, .or:
                guard depth >= 2 else { throw rationalAlgebraFailure("A sign program has incomplete binary operands.") }
                depth -= 1
            }
            maximum = max(maximum, depth)
        }
        guard depth == 1 else { throw rationalAlgebraFailure("A sign program must publish exactly one truth value.") }
        try RationalAlgebraStorage.retain(instructions.count, of: Instruction.self, usage: &usage)
        self.polynomialCount = polynomialCount
        self.instructions = instructions
        maximumStackCount = maximum
    }

    /// Scratch is owned and admitted once by the composing truth traversal.
    package func evaluate<B: RationalAlgebraAdmitting>(signs: [ExactAlgebraicRealRoot.Sign],
        scratch: inout [Bool], usage: inout B) throws -> Bool {
        guard signs.count >= polynomialCount, scratch.capacity >= maximumStackCount else {
            throw rationalAlgebraFailure("Sign evaluation lost original sources or admitted scratch.")
        }
        scratch.removeAll(keepingCapacity: true)
        for instruction in instructions {
            try intersectionAlgebraStep(&usage)
            switch instruction {
            case .literal(let value): scratch.append(value)
            case .atom(let index, let sign): scratch.append(signs[index] == sign)
            case .not: scratch[scratch.count - 1].toggle()
            case .and:
                let right = scratch.removeLast()
                scratch[scratch.count - 1] = scratch[scratch.count - 1] && right
            case .or:
                let right = scratch.removeLast()
                scratch[scratch.count - 1] = scratch[scratch.count - 1] || right
            }
        }
        guard let value = scratch.first, scratch.count == 1 else {
            throw rationalAlgebraFailure("An issued sign program lost its unique truth value.")
        }
        return value
    }

    /// Unknown atoms remain unknown; only Boolean consequences may close a suffix.
    package func partialValue<B: RationalAlgebraAdmitting>(signs: [ExactAlgebraicRealRoot.Sign?],
        scratch: inout [Bool?], usage: inout B) throws -> Bool? {
        guard signs.count == polynomialCount, scratch.capacity >= maximumStackCount else {
            throw rationalAlgebraFailure("Partial sign evaluation lost its original atoms or admitted scratch.")
        }
        scratch.removeAll(keepingCapacity: true)
        for instruction in instructions {
            try intersectionAlgebraStep(&usage)
            switch instruction {
            case .literal(let value): scratch.append(value)
            case .atom(let index, let sign): scratch.append(signs[index].map { $0 == sign })
            case .not:
                if let value = scratch[scratch.count - 1] { scratch[scratch.count - 1] = !value }
            case .and:
                let right = scratch.removeLast(), left = scratch[scratch.count - 1]
                if left == false || right == false { scratch[scratch.count - 1] = false }
                else if left == true && right == true { scratch[scratch.count - 1] = true }
                else { scratch[scratch.count - 1] = nil }
            case .or:
                let right = scratch.removeLast(), left = scratch[scratch.count - 1]
                if left == true || right == true { scratch[scratch.count - 1] = true }
                else if left == false && right == false { scratch[scratch.count - 1] = false }
                else { scratch[scratch.count - 1] = nil }
            }
        }
        guard scratch.count == 1 else { throw rationalAlgebraFailure("Partial sign evaluation has no unique logical result.") }
        return scratch[0]
    }
}
