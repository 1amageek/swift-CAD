#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct ExactAlgebraicScalarDomain<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:
    ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting, ExactAlgebraicExtending where Base.Source == Base.Value {
    public typealias Value = ExactAlgebraicScalar<Base>
    public typealias Source = Value
    let context: ExactAlgebraicContext<Base>
    public var extensionLevel: Int { context.level }
    public var maximumExtensionLevel: Int { context.maximumExtensionLevel }
    init(context: ExactAlgebraicContext<Base>) { self.context = context }
    public init<A: ExactScalarAdmission & ~Copyable>(retaining value: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) {
        let retained = copy value
        do { context = try ExactRootAccess.run(&admission, inherited: retained.depth) { _ in retained.context } }
        catch { if case .scalar(let failure) = error { throw failure }; throw .admissionRejected(error) }
    }
    public static func base<A: ExactScalarAdmission & ~Copyable>(field: Base, maximumExtensionLevel: Int,
        using admission: inout A) throws(ExactRealRootFailure) -> Self {
        try ExactRootAccess.run(&admission) { a in
            guard maximumExtensionLevel >= 0 else { throw ExactRealRootFailure.invalidDomain }
            _ = try field.integer(0, using: &a)
            try ExactRootAccess.owner((Base, ExactAlgebraicContext<Base>?, ExactRealRoot<Self>?, Int, Int, ExactScalarDepth).self, &a)
            return Self(context: ExactAlgebraicContext(base: field, parent: nil, root: nil,
                level: 0, maximumExtensionLevel: maximumExtensionLevel, depth: a.depth))
        }
    }
    public func adjoin<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<Self>,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactAlgebraicExtension<Base> {
        let root = copy root
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            guard root.source.context.field.context === context else { throw ExactRealRootFailure.incompatibleDomain }
            try ExactRootAccess.admit(root.depth, &a)
            let level = try ExactRootAccess.add(context.level, 1)
            guard level <= context.maximumExtensionLevel else { throw ExactRealRootFailure.extensionLevelLimit }
            let issuer = ExactRealRootDomain<Self>(context: root.source.context)
            guard try issuer.roots(root.proof, root.isolation, &a) == 1 else { throw ExactRealRootFailure.invalidEvidence }
            try ExactRootAccess.owner((Base, ExactAlgebraicContext<Base>?, ExactRealRoot<Self>?, Int, Int, ExactScalarDepth).self, &a)
            let child = Self(context: ExactAlgebraicContext(base: context.base, parent: context, root: root,
                level: level, maximumExtensionLevel: context.maximumExtensionLevel, depth: a.depth))
            let p = root.source.context.univariate
            let n = try p.variable(0, using: &a), d = try p.constant(integer(1, using: &a), using: &a)
            let generator = try child.fraction(n, d, &a)
            return ExactAlgebraicExtension(domain: child, generator: generator,
                embedding: ExactAlgebraicEmbedding(parent: self, child: child))
        }
    }
    func scalarQuery<A: ExactScalarAdmission & ~Copyable, R>(_ admission: inout A,
        _ body: (inout ExactRootBorrowedAdmission) throws -> R) throws(ExactScalarFailure) -> R {
        do { return try ExactRootAccess.run(&admission, inherited: context.depth, body) }
        catch {
            switch error {
            case .scalar(let f): throw f
            case .polynomial(.scalar(let f)): throw f
            case .polynomial(.zeroDivisor): throw .divisionByZero
            case .incompatibleDomain, .polynomial(.incompatibleDomain): throw .incompatibleDomain
            case .countOverflow, .polynomial(.countOverflow): throw .countOverflow
            case .invalidEvidence, .polynomial(.invalidCertificate): throw .invalidEvidence
            case .invalidSource, .invalidDomain, .invalidVariable: throw .invalidSource
            case .unresolved: throw .unresolved
            default: throw .admissionRejected(error)
            }
        }
    }
    public func importingBase<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Base.Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let value = copy value
        return try scalarQuery(&admission) { a in
            var base = context
            while let parent = base.parent { try a.consumeWork(1); base = parent }
            let retained = try base.base.importing(value, using: &a)
            let source = Value(context: base, storage: .base(retained), depth: a.depth)
            return try embedded(source, &a)
        }
    }
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let source = copy source
        return try scalarQuery(&admission) { try embedded(source, &$0) }
    }
    func embedded(_ source: Value, _ a: inout ExactRootBorrowedAdmission) throws -> Value {
        try ExactRootAccess.admit(source.depth, &a)
        var target = context
        var path: [ExactAlgebraicContext<Base>] = []
        while target !== source.context {
            try a.consumeWork(1)
            guard let parent = target.parent else { throw ExactScalarFailure.incompatibleDomain }
            try ExactRootAccess.storage(1, ExactAlgebraicContext<Base>.self, &a)
            path.append(target); target = parent
        }
        var value = source
        for child in path.reversed() {
            try a.consumeWork(1)
            guard let root = child.root else { throw ExactScalarFailure.invalidEvidence }
            let p = root.source.context.univariate
            let n = try p.constant(value, using: &a)
            let parent = Self(context: child.parent!)
            let d = try p.constant(parent.integer(1, using: &a), using: &a)
            value = try Self(context: child).fraction(n, d, &a)
        }
        return Value(context: context, storage: value.storage, depth: a.depth)
    }
    func polynomialSource(_ polynomial: ExactPolynomial<Self>, root: ExactRealRoot<Self>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootSource<Self> {
        _ = try root.source.context.univariate.isZero(polynomial, using: &a)
        return ExactRealRootSource(context: root.source.context, original: polynomial, variable: 0,
            refinementAxis: root.source.refinementAxis, law: polynomial, depth: a.depth)
    }
    func polynomialSign(_ polynomial: ExactPolynomial<Self>, _ a: inout ExactRootBorrowedAdmission) throws -> ExactSign {
        guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
        let source = try polynomialSource(polynomial, root: root, &a)
        return try ExactRealRootDomain<Self>(context: root.source.context).sign(of: source, at: root, using: &a)
    }
    func fraction(_ numerator: ExactPolynomial<Self>, _ denominator: ExactPolynomial<Self>,
        _ a: inout ExactRootBorrowedAdmission) throws -> Value {
        guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
        let p = root.source.context.univariate
        _ = try p.isZero(numerator, using: &a)
        guard try polynomialSign(denominator, &a) != .zero else { throw ExactScalarFailure.divisionByZero }
        // Selected-root nonzero evidence precedes exact reduction; a reducible law is valid.
        guard let rootDegree = try p.degree(of: root.proof.polynomial, in: 0, using: &a) else {
            throw ExactScalarFailure.invalidEvidence
        }
        var n = try (p.degree(of: numerator, in: 0, using: &a) ?? -1) < rootDegree
            ? numerator : p.divided(numerator, by: root.proof.polynomial, using: &a).remainder
        var d = try (p.degree(of: denominator, in: 0, using: &a) ?? -1) < rootDegree
            ? denominator : p.divided(denominator, by: root.proof.polynomial, using: &a).remainder
        if let denominatorDegree = try p.degree(of: d, in: 0, using: &a), denominatorDegree > 0 {
            let common = try p.greatestCommonDivisor(n, d, using: &a)
            n = try p.dividedExactly(n, by: common, using: &a)
            d = try p.dividedExactly(d, by: common, using: &a)
        }
        guard let leading = d.terms.first, let parentContext = context.parent else { throw ExactScalarFailure.invalidEvidence }
        let parent = Self(context: parentContext)
        let one = try parent.integer(1, using: &a)
        if try parent.compare(leading.coefficient, one, using: &a) != .equal {
            let inverse = try parent.dividing(one, leading.coefficient, using: &a)
            n = try p.scaled(n, by: inverse, using: &a)
            d = try p.scaled(d, by: inverse, using: &a)
        }
        return Value(context: context, storage: .fraction(n, d), depth: a.depth)
    }
    public func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try scalarQuery(&admission) { a in
            var base = context
            while let parent = base.parent { try a.consumeWork(1); base = parent }
            let value = try base.base.integer(source, using: &a)
            return try embedded(Value(context: base, storage: .base(value), depth: a.depth), &a)
        }
    }
    public func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try scalarQuery(&admission) { a in
            var base = context
            while let parent = base.parent { try a.consumeWork(1); base = parent }
            let value = try base.base.binary64(exactly: source, using: &a)
            return try embedded(Value(context: base, storage: .base(value), depth: a.depth), &a)
        }
    }
}
