#if L1_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactPolynomialDomain<F: ExactScalarArithmetic & ExactScalarOrdering>:
    ExactPolynomialConstructing, ExactPolynomialArithmetic, ExactPolynomialDeciding, ExactPolynomialCalculus {
    public typealias Coefficient = F.Value
    public typealias Polynomial = ExactPolynomial<F>
    public typealias Evaluation = ExactPolynomialEvaluation<F>
    let context: ExactPolynomialContext<F>
    public var variableCount: Int { context.variableCount }
    var field: F { context.field }

    public init<A: ExactScalarAdmission & ~Copyable>(field: F, variableCount: Int,
        using admission: inout A) throws(ExactPolynomialFailure) {
        context = try ExactPolynomialAccess.query(&admission, inherited: ExactPolynomialAccess.zeroDepth()) { usage in
            guard variableCount >= 0 else { throw ExactPolynomialFailure.invalidVariableCount }
            try usage.consumeWork(variableCount)
            let zero = try field.integer(0, using: &usage)
            let one = try field.integer(1, using: &usage)
            let payload = try ExactPolynomialAccess.count(MemoryLayout<F>.stride,
                ExactPolynomialAccess.count(MemoryLayout<Int>.stride,
                    ExactPolynomialAccess.count(MemoryLayout<ExactScalarDepth>.stride,
                        ExactPolynomialAccess.count(2, MemoryLayout<F.Value>.stride, multiply: true))))
            let header = try ExactPolynomialAccess.count(2, MemoryLayout<UnsafeRawPointer>.stride, multiply: true)
            try usage.retainStorage(bytes: ExactPolynomialAccess.count(header, payload))
            return ExactPolynomialContext(field: field, variableCount: variableCount,
                zero: zero, one: one, depth: try usage.depth)
        }
    }
    /// Retains the identical polynomial basis after the creating domain leaves scope.
    public init<A: ExactScalarAdmission & ~Copyable>(retaining value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) {
        context = try ExactPolynomialAccess.query(&admission, inherited: value.depth) { _ in value.context }
    }
    func query<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        _ first: Polynomial? = nil, _ second: Polynomial? = nil, _ body: (inout ExactPolynomialAdmission<A>) throws -> R
    ) throws(ExactPolynomialFailure) -> R {
        try ExactPolynomialAccess.query(&admission, inherited: context.depth) { usage in
            if let input = first {
                try usage.consumeWork(1); try require(input)
                try usage.admitDepth(value: input.depth.value, coefficient: input.depth.coefficient)
            }
            if let input = second {
                try usage.consumeWork(1); try require(input)
                try usage.admitDepth(value: input.depth.value, coefficient: input.depth.coefficient)
            }
            return try body(&usage)
        }
    }
    func require(_ value: borrowing Polynomial) throws(ExactPolynomialFailure) {
        guard value.context === context else { throw .incompatibleDomain }
    }
    func requireVariable(_ index: Int) throws(ExactPolynomialFailure) {
        guard index >= 0, index < variableCount else { throw .invalidVariable }
    }
    func wrap<A: ExactScalarAdmission & ~Copyable>(_ terms: [ExactPolynomialTerm<Coefficient>],
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        Polynomial(context: context, terms: terms, depth: try usage.depth)
    }
    func powers<A: ExactScalarAdmission & ~Copyable>(_ usage: inout ExactPolynomialAdmission<A>) throws -> [Int] {
        try usage.consumeWork(variableCount)
        try ExactPolynomialAccess.storage(variableCount, Int.self, &usage)
        return [Int](repeating: 0, count: variableCount)
    }
    func canonical<A: ExactScalarAdmission & ~Copyable>(_ terms: [ExactPolynomialTerm<Coefficient>],
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        for term in terms {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            guard term.powers.count == variableCount else { throw ExactPolynomialFailure.invalidExponent }
            for exponent in term.powers { guard exponent >= 0 else { throw ExactPolynomialFailure.invalidExponent } }
            _ = try field.sign(of: term.coefficient, using: &usage)
        }
        // Admit sorted output, sorting workspace and canonical output payloads.
        try ExactPolynomialAccess.storage(ExactPolynomialAccess.count(terms.count, 3, multiply: true),
            ExactPolynomialTerm<Coefficient>.self, &usage)
        let sorted = try terms.sorted { try ExactPolynomialAccess.order($0.powers, $1.powers, &usage) > 0 }
        var result: [ExactPolynomialTerm<Coefficient>] = []; result.reserveCapacity(terms.count)
        for term in sorted {
            try usage.consumeWork(1)
            if let last = result.last, try ExactPolynomialAccess.order(last.powers, term.powers, &usage) == 0 {
                let sum = try field.adding(last.coefficient, term.coefficient, using: &usage)
                result.removeLast()
                if try field.sign(of: sum, using: &usage) != .zero {
                    result.append(.init(powers: term.powers, coefficient: sum))
                }
            } else if try field.sign(of: term.coefficient, using: &usage) != .zero { result.append(term) }
        }
        return try wrap(result, &usage)
    }
    public func polynomial<A: ExactScalarAdmission & ~Copyable>(terms: [ExactPolynomialTerm<Coefficient>],
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission) { try canonical(terms, &$0) }
    }
    public func zero<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission) { try wrap([], &$0) }
    }
    func constant<A: ExactScalarAdmission & ~Copyable>(_ coefficient: borrowing Coefficient,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        // Ownership and depth are checked even if the coefficient is zero.
        if try field.sign(of: coefficient, using: &usage) == .zero { return try wrap([], &usage) }
        try ExactPolynomialAccess.storage(1, ExactPolynomialTerm<Coefficient>.self, &usage)
        return try wrap([.init(powers: powers(&usage), coefficient: copy coefficient)], &usage)
    }
    public func constant<A: ExactScalarAdmission & ~Copyable>(_ coefficient: borrowing Coefficient,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        let retained = copy coefficient
        return try query(&admission) { try constant(retained, &$0) }
    }
    public func variable<A: ExactScalarAdmission & ~Copyable>(_ index: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission) { usage in
            try requireVariable(index)
            var exponent = try powers(&usage); exponent[index] = 1
            try ExactPolynomialAccess.storage(1, ExactPolynomialTerm<Coefficient>.self, &usage)
            return try wrap([.init(powers: exponent, coefficient: context.one)], &usage)
        }
    }
    public func isZero<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Bool {
        try query(&admission, copy value) { _ in value.terms.isEmpty }
    }
    public func equals<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial,
        _ rhs: borrowing Polynomial, using admission: inout A) throws(ExactPolynomialFailure) -> Bool {
        try query(&admission, copy lhs, copy rhs) { usage in
            guard lhs.terms.count == rhs.terms.count else { return false }
            for i in lhs.terms.indices {
                guard try ExactPolynomialAccess.order(lhs.terms[i].powers, rhs.terms[i].powers, &usage) == 0 else { return false }
                guard try field.compare(lhs.terms[i].coefficient, rhs.terms[i].coefficient, using: &usage) == .equal else { return false }
            }
            return true
        }
    }
    func degree<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ variable: Int,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Int? {
        try requireVariable(variable)
        var result: Int? = nil
        for term in value.terms { try usage.consumeWork(1); result = max(result ?? 0, term.powers[variable]) }
        return result
    }
    public func degree<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Polynomial, in variable: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Int? {
        try query(&admission, copy value) { try degree(copy value, variable, &$0) }
    }
}
