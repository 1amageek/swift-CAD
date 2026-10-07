#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public struct ExactRealCellDomain<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: ExactRealCellPreparing where Base.Source == Base.Value {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public typealias Polynomial = ExactPolynomial<Field>
    let context: ExactRealCellContext<Base>
    public var polynomials: ExactPolynomialDomain<Field> { context.polynomials }
    public init<A: ExactScalarAdmission & ~Copyable>(field: Field, variableCount: Int,
        using admission: inout A) throws(ExactRealCellFailure) {
        context = try ExactCellAccess.run(&admission) { a in
            guard variableCount >= 0 else { throw ExactRealCellFailure.invalidVariable }
            let p = try ExactPolynomialDomain(field: field, variableCount: variableCount, using: &a)
            try ExactCellAccess.owner((Field, ExactPolynomialDomain<Field>, ExactScalarDepth).self, &a)
            return ExactRealCellContext(field: field, polynomials: p, depth: a.depth)
        }
    }
    public init<A: ExactScalarAdmission & ~Copyable>(retaining source: borrowing ExactRealCellSource<Base>,
        using admission: inout A) throws(ExactRealCellFailure) {
        let source = copy source
        context = try ExactCellAccess.run(&admission, inherited: source.depth) { _ in source.owner.context }
    }
    func require(_ source: ExactRealCellSource<Base>, _ a: inout ExactCellBorrowedAdmission) throws {
        guard source.owner.context === context else { throw ExactRealCellFailure.incompatibleDomain }
        try ExactCellAccess.admit(source.depth, &a)
    }
    public func bind<A: ExactScalarAdmission & ~Copyable>(polynomials laws: [Polynomial],
        domains: [ExactRealRootInterval<Field.Value>], using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellSource<Base> {
        try ExactCellAccess.run(&admission, inherited: context.depth) { a in
            guard domains.count == polynomials.variableCount else { throw ExactRealCellFailure.invalidDomain }
            for law in laws { _ = try polynomials.isZero(law, using: &a); try ExactCellAccess.admit(law.depth, &a) }
            for domain in domains {
                try ExactCellAccess.admit(domain.depth, &a)
                if case .finite(let x) = domain.lower { _ = try context.field.sign(of: x, using: &a) }
                if case .finite(let x) = domain.upper { _ = try context.field.sign(of: x, using: &a) }
                if case .positiveInfinity = domain.lower { throw ExactRealCellFailure.invalidDomain }
                if case .negativeInfinity = domain.upper { throw ExactRealCellFailure.invalidDomain }
                if case .finite(let l) = domain.lower, case .finite(let h) = domain.upper {
                    guard try context.field.compare(l, h, using: &a) != .greater else { throw ExactRealCellFailure.invalidDomain }
                }
            }
            try ExactCellAccess.owner((ExactRealCellContext<Base>, [Polynomial], [ExactRealRootInterval<Field.Value>], ExactScalarDepth).self, &a)
            return ExactRealCellSource(owner: ExactRealCellSourceStorage(context: context, laws: laws, domains: domains, depth: a.depth))
        }
    }
    public func predicate<A: ExactScalarAdmission & ~Copyable>(instructions: [ExactRealCellInstruction],
        for source: borrowing ExactRealCellSource<Base>, using admission: inout A
    ) throws(ExactRealCellFailure) -> ExactRealCellPredicate<Base> {
        let source = copy source
        return try ExactCellAccess.run(&admission, inherited: context.depth) { a in
            try require(source, &a)
            var count = 0
            for instruction in instructions {
                try a.consumeWork(1)
                switch instruction {
                case .literal: count = try ExactCellAccess.add(count, 1)
                case .sign(let index, _):
                    guard index >= 0, index < source.polynomials.count else { throw ExactRealCellFailure.invalidPredicate }
                    count = try ExactCellAccess.add(count, 1)
                case .not: guard count >= 1 else { throw ExactRealCellFailure.invalidPredicate }
                case .and, .or:
                    guard count >= 2 else { throw ExactRealCellFailure.invalidPredicate }; count -= 1
                }
            }
            guard count == 1 else { throw ExactRealCellFailure.invalidPredicate }
            return ExactRealCellPredicate(source: source, instructions: instructions, depth: a.depth)
        }
    }
}
