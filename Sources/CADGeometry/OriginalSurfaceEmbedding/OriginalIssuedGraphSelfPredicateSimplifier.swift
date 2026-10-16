/// Domain-wide exact affine bounds simplify only the checked residual formula.
struct OriginalIssuedGraphSelfPredicateSimplifier {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Predicate = ExactRealCellPredicate<Base>
    struct Result {
        let predicate: Predicate
        let depth: ExactScalarDepth
    }
    private enum Node {
        case literal(Bool)
        case atom(Int, ExactRealCellSignRelation)
        case not(Int)
        case and(Int, Int)
        case or(Int, Int)
    }
    static func simplify<A: ExactScalarAdmission & ~Copyable>(_ predicate: Predicate,
        cells: ExactRealCellDomain<Base>, using admission: inout A) throws -> Result {
        try admission.withProofScope { a in
            try a.checkpoint()
            try a.admitDepth(value: predicate.depth.value, coefficient: predicate.depth.coefficient)
            let field = try cells.coefficientField(of: predicate.source, using: &a)
            let count = predicate.instructions.count
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Node.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Int.self))
            var nodes: [Node] = [], stack: [Int] = []
            nodes.reserveCapacity(count); stack.reserveCapacity(count)
            for instruction in predicate.instructions {
                try a.consumeWork(1)
                switch instruction {
                case .literal(let value):
                    nodes.append(.literal(value)); stack.append(nodes.count - 1)
                case .sign(let index, let relation):
                    guard predicate.source.polynomials.indices.contains(index) else { throw NativeExactRelationFailure.invalidDomain }
                    if let value = try truth(of: predicate.source.polynomials[index], relation: relation,
                        domains: predicate.source.domains, field: field, using: &a) {
                        nodes.append(.literal(value))
                    } else { nodes.append(.atom(index, relation)) }
                    stack.append(nodes.count - 1)
                case .not:
                    guard let child = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                    if case .literal(let value) = nodes[child] { nodes.append(.literal(!value)) }
                    else { nodes.append(.not(child)) }
                    stack.append(nodes.count - 1)
                case .and, .or:
                    guard let right = stack.popLast(), let left = stack.popLast() else { throw NativeExactRelationFailure.invalidDomain }
                    let isAnd: Bool
                    if case .and = instruction { isAnd = true } else { isAnd = false }
                    if case .literal(let value) = nodes[left] {
                        stack.append(value == isAnd ? right : left)
                    } else if case .literal(let value) = nodes[right] {
                        stack.append(value == isAnd ? left : right)
                    } else {
                        nodes.append(isAnd ? .and(left, right) : .or(left, right)); stack.append(nodes.count - 1)
                    }
                }
            }
            guard stack.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: (Int, Bool).self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: ExactRealCellInstruction.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: predicate.source.polynomials.count, of: Bool.self))
            var pending: [(Int, Bool)] = [(stack[0], false)]
            pending.reserveCapacity(count)
            var program: [ExactRealCellInstruction] = []
            program.reserveCapacity(count)
            var referenced = Array(repeating: false, count: predicate.source.polynomials.count)
            while let (index, visited) = pending.popLast() {
                try a.consumeWork(1)
                switch nodes[index] {
                case .literal(let value): program.append(.literal(value))
                case .atom(let law, let relation):
                    referenced[law] = true; program.append(.sign(polynomial: law, relation: relation))
                case .not(let child):
                    if visited { program.append(.not) }
                    else { pending.append((index, true)); pending.append((child, false)) }
                case .and(let left, let right), .or(let left, let right):
                    if visited {
                        if case .and = nodes[index] { program.append(.and) } else { program.append(.or) }
                    } else { pending.append((index, true)); pending.append((right, false)); pending.append((left, false)) }
                }
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: referenced.count, of: Int.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: referenced.count, of: ExactPolynomial<Field>.self))
            var indices = Array(repeating: -1, count: referenced.count)
            var laws: [ExactPolynomial<Field>] = []
            laws.reserveCapacity(referenced.count)
            for index in referenced.indices {
                try a.consumeWork(1)
                if referenced[index] { indices[index] = laws.count; laws.append(predicate.source.polynomials[index]) }
            }
            for index in program.indices {
                try a.consumeWork(1)
                if case .sign(let law, let relation) = program[index] {
                    program[index] = .sign(polynomial: indices[law], relation: relation)
                }
            }
            let source = try cells.bind(polynomials: laws, domains: predicate.source.domains, using: &a)
            let simplified = try cells.predicate(instructions: program, for: source, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Result.self))
            let result = Result(predicate: simplified, depth: try a.depth)
            try a.checkpoint(); return result
        }
    }
    private static func truth<A: ExactScalarAdmission & ~Copyable>(of law: ExactPolynomial<Field>,
        relation: ExactRealCellSignRelation, domains: [ExactRealRootInterval<Field.Value>],
        field: Field, using a: inout A) throws -> Bool? {
        try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        for domain in domains {
            try a.consumeWork(1)
            try a.admitDepth(value: domain.depth.value, coefficient: domain.depth.coefficient)
            if domain.isEmpty { return nil }
        }
        var lower = try field.integer(0, using: &a), upper = lower
        for term in law.terms {
            try a.consumeWork(1)
            guard term.powers.count == domains.count else { throw NativeExactRelationFailure.invalidDomain }
            var variable: Int?
            for axis in term.powers.indices {
                try a.consumeWork(1)
                if term.powers[axis] != 0 {
                    guard term.powers[axis] == 1, variable == nil else { return nil }
                    variable = axis
                }
            }
            let coefficient = try field.importing(term.coefficient, using: &a)
            let sign = try field.sign(of: coefficient, using: &a)
            if sign == .zero { continue }
            if let variable {
                guard case .finite(let lo) = domains[variable].lower,
                    case .finite(let hi) = domains[variable].upper else { return nil }
                let minimum = sign == .positive ? lo : hi, maximum = sign == .positive ? hi : lo
                lower = try field.adding(lower, field.multiplying(coefficient, field.importing(minimum, using: &a), using: &a), using: &a)
                upper = try field.adding(upper, field.multiplying(coefficient, field.importing(maximum, using: &a), using: &a), using: &a)
            } else {
                lower = try field.adding(lower, coefficient, using: &a)
                upper = try field.adding(upper, coefficient, using: &a)
            }
        }
        let lo = try field.sign(of: lower, using: &a), hi = try field.sign(of: upper, using: &a)
        switch relation {
        case .equal:
            if lo == .positive || hi == .negative { return false }
            if lo == .zero && hi == .zero { return true }
        case .notEqual:
            if lo == .positive || hi == .negative { return true }
            if lo == .zero && hi == .zero { return false }
        case .less:
            if hi == .negative { return true }; if lo != .negative { return false }
        case .lessOrEqual:
            if hi != .positive { return true }; if lo == .positive { return false }
        case .greater:
            if lo == .positive { return true }; if hi != .positive { return false }
        case .greaterOrEqual:
            if lo != .negative { return true }; if hi == .negative { return false }
        }
        return nil
    }
}
