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
            try issuer.admitted(root, &a)
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
        return Value(context: context, storage: value.storage, depth: a.depth, calculation: value.calculation)
    }
    func polynomialSource(_ polynomial: ExactPolynomial<Self>, root: ExactRealRoot<Self>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootSource<Self> {
        return try ExactRealRootDomain<Self>(context: root.source.context).sourceForLaw(polynomial,
            variable: root.source.variable, axis: root.source.refinementAxis, &a)
    }

    func polynomialSign(_ polynomial: ExactPolynomial<Self>, at selected: ExactRealRoot<Self>? = nil, _ a: inout ExactRootBorrowedAdmission) throws -> ExactSign {
        guard let root = selected ?? context.root else { throw ExactScalarFailure.invalidEvidence }
        try ExactRootAccess.admit(root.depth, &a)
        let p = root.source.context.univariate
        // Degree admits the issued polynomial owner and depth before the constant path.
        let degree = try p.degree(of: polynomial, in: 0, using: &a)
        guard let degree else { return .zero }
        if degree == 0 {
            return try root.source.context.field.sign(of: polynomial.terms[0].coefficient, using: &a)
        }
        if degree == 1, let sign=try linearSquareRootSign(polynomial,root:root,&a) { return sign }
        let source = try polynomialSource(polynomial, root: root, &a)
        return try ExactRealRootDomain<Self>(context: root.source.context).sign(of: source, at: root, using: &a)
    }
    private func linearSquareRootSign(_ polynomial:ExactPolynomial<Self>,root:ExactRealRoot<Self>,
        _ a:inout ExactRootBorrowedAdmission) throws -> ExactSign? {
        let law=root.proof.polynomial,parent=root.source.context.field
        _=try root.source.context.univariate.degree(of:law,in:0,using:&a)
        guard law.variableCount==1,law.termCount==2,law.terms[0].powers[0]==2,law.terms[1].powers[0]==0,
            try parent.compare(law.terms[0].coefficient,parent.integer(1,using:&a),using:&a) == .equal,
            try parent.sign(of:law.terms[1].coefficient,using:&a) == .negative else { return nil }
        let positive:Bool
        if case .finite(let lower)=root.isolation.lower,try parent.sign(of:lower,using:&a) != .negative {
            positive=true
        } else if case .finite(let upper)=root.isolation.upper,try parent.sign(of:upper,using:&a) != .positive {
            positive=false
        } else { return nil }
        let slope=polynomial.terms[0].coefficient
        let constant=try polynomial.termCount==1 ? parent.integer(0,using:&a):polynomial.terms[1].coefficient
        let raw=try parent.sign(of:slope,using:&a)
        let b=positive ? raw:(raw == .positive ? ExactSign.negative:raw == .negative ? .positive:.zero)
        let c=try parent.sign(of:constant,using:&a)
        if b == .zero { return c }
        if c == .zero || b == c { return b }
        let radicand=try parent.negated(law.terms[1].coefficient,using:&a)
        let difference=try parent.subtracting(parent.multiplying(parent.multiplying(slope,slope,using:&a),radicand,using:&a),
            parent.multiplying(constant,constant,using:&a),using:&a)
        let sign=try parent.sign(of:difference,using:&a)
        return sign == .zero ? .zero:sign == .positive ? b:c
    }
    func calculation(_ selected: ExactRealRoot<Self>, _ a: inout ExactRootBorrowedAdmission) throws -> ExactAlgebraicCalculation<Base> {
        guard let original = context.root else { throw ExactScalarFailure.invalidEvidence }
        let defining = try polynomialSource(selected.proof.polynomial, root: original, &a)
        try ExactRootAccess.owner((ExactRealRoot<Self>, ExactRealRoot<Self>, ExactRealRootSource<Self>, ExactScalarDepth).self, &a)
        return .init(originalRoot: original, selectedRoot: selected, definingSource: defining, depth: a.depth)
    }
    func commonCalculation(_ lhs: Value, _ rhs: Value, _ a: inout ExactRootBorrowedAdmission) throws -> ExactAlgebraicCalculation<Base>? {
        guard let l = lhs.calculation else { return rhs.calculation }
        guard let r = rhs.calculation else { return l }
        try ExactRootAccess.admit(l.depth, &a); try ExactRootAccess.admit(r.depth, &a)
        if l.selectedRoot.proof === r.selectedRoot.proof { return l }
        guard let original = context.root else { throw ExactScalarFailure.invalidEvidence }
        let p = original.source.context.univariate
        if try p.equals(l.selectedRoot.proof.polynomial, r.selectedRoot.proof.polynomial, using: &a) { return l }
        let common = try p.greatestCommonDivisor(l.selectedRoot.proof.polynomial, r.selectedRoot.proof.polynomial, using: &a)
        let source = try polynomialSource(common, root: original, &a)
        let root = try ExactRealRootDomain<Self>(context: original.source.context).refine(original,
            usingDefiningDivisor: source, using: &a)
        return try calculation(root, &a)
    }
    func fraction(_ numerator: ExactPolynomial<Self>, _ denominator: ExactPolynomial<Self>,
        calculation inherited: ExactAlgebraicCalculation<Base>? = nil,
        _ a: inout ExactRootBorrowedAdmission) throws -> Value {
        guard let original = context.root else { throw ExactScalarFailure.invalidEvidence }
        if let inherited { try ExactRootAccess.admit(inherited.depth, &a) }
        var selected = inherited?.selectedRoot ?? original, receipt = inherited
        let p = original.source.context.univariate
        guard let degree = try p.degree(of: selected.proof.polynomial, in: 0, using: &a) else {
            throw ExactScalarFailure.invalidEvidence
        }
        var n = try (p.degree(of: numerator, in: 0, using: &a) ?? -1) < degree
            ? numerator : p.divided(numerator, by: selected.proof.polynomial, using: &a).remainder
        var d = try (p.degree(of: denominator, in: 0, using: &a) ?? -1) < degree
            ? denominator : p.divided(denominator, by: selected.proof.polynomial, using: &a).remainder
        guard try !p.isZero(d, using: &a) else { throw ExactScalarFailure.divisionByZero }
        if let denominatorDegree = try p.degree(of: d, in: 0, using: &a), denominatorDegree > 0 {
            var inverse = try unitInverse(d, modulo: selected.proof.polynomial, &a)
            if inverse == nil {
                // Validate the uncancelled denominator before excluding conjugate factors.
                guard try polynomialSign(d, at: selected, &a) != .zero else { throw ExactScalarFailure.divisionByZero }
                let common = try p.greatestCommonDivisor(selected.proof.polynomial, d, using: &a)
                let quotient = try p.dividedExactly(selected.proof.polynomial, by: common, using: &a)
                let divisor = try polynomialSource(quotient, root: original, &a)
                selected = try ExactRealRootDomain<Self>(context: original.source.context).refine(selected,
                    usingDefiningDivisor: divisor, using: &a)
                receipt = try calculation(selected, &a)
                d = try p.divided(d, by: selected.proof.polynomial, using: &a).remainder
                inverse = try unitInverse(d, modulo: selected.proof.polynomial, &a)
            }
            guard let inverse else { throw ExactScalarFailure.invalidEvidence }
            n = try p.divided(p.multiplying(n, inverse, using: &a), by: selected.proof.polynomial, using: &a).remainder
            guard let parent = context.parent else { throw ExactScalarFailure.invalidEvidence }
            d = try p.constant(Self(context: parent).integer(1, using: &a), using: &a)
        }
        guard let leading = d.terms.first, let parentContext = context.parent else { throw ExactScalarFailure.invalidEvidence }
        let parent = Self(context: parentContext), one = try parent.integer(1, using: &a)
        if try parent.compare(leading.coefficient, one, using: &a) != .equal {
            let inverse = try parent.dividing(one, leading.coefficient, using: &a)
            n = try p.scaled(n, by: inverse, using: &a); d = try p.scaled(d, by: inverse, using: &a)
        }
        return Value(context: context, storage: .fraction(n, d), depth: a.depth, calculation: receipt)
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
