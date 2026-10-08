import L0
import L1
import L2

public enum SeparationFixtures {
    private typealias Field = ExactRationalScalarDomain
    private typealias Root = ExactRealRoot<Field>

    private static func prepared(_ a: inout ExactScalarLedger) throws -> (
        domain: ExactRealRootDomain<Field>, left: Root, right: Root, same: Root,
        one: Root, two: Root, union: [Root]
    ) {
        let field = Field(), domain = try ExactRealRootDomain(field: field, variableCount: 2, using: &a)
        let p = domain.polynomials, x = try p.variable(1, using: &a)
        let square = try p.multiplying(x, x, using: &a)
        let quadratic = try p.subtracting(square, p.constant(field.integer(2, using: &a), using: &a), using: &a)
        let other = try p.subtracting(square, p.constant(field.integer(3, using: &a), using: &a), using: &a)
        let source = try domain.bind(quadratic, variable: 1, refinementAxis: .coefficient, using: &a)
        let otherSource = try domain.bind(other, variable: 1, refinementAxis: .value, using: &a)
        let one = try field.integer(1, using: &a), two = try field.integer(2, using: &a)
        let interval = try domain.domain(lower: .finite(one), upper: .finite(two), using: &a)
        let left = try domain.isolate(source, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let right = try domain.isolate(otherSource, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let differentLaw = try domain.bind(p.multiplying(quadratic,
            p.subtracting(x, p.constant(field.integer(3, using: &a), using: &a), using: &a), using: &a),
            variable: 1, using: &a)
        let same = try domain.isolate(differentLaw, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let oneLaw = try domain.bind(p.subtracting(x, p.constant(one, using: &a), using: &a), variable: 1, using: &a)
        let twoLinear = try p.subtracting(x, p.constant(two, using: &a), using: &a)
        let twoLaw = try domain.bind(p.multiplying(twoLinear, twoLinear, using: &a), variable: 1, using: &a)
        let oneRoot = try domain.isolate(oneLaw,
            in: domain.domain(lower: .finite(one), upper: .finite(one), using: &a),
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let twoRoot = try domain.isolate(twoLaw,
            in: domain.domain(lower: .finite(two), upper: .finite(two), using: &a),
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let union = try domain.isolate(domain.bind(p.multiplying(quadratic, other, using: &a), variable: 1, using: &a),
            in: domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a),
            limits: .init(maximumRoots: 4), using: &a).roots
        return (domain, left, right, same, oneRoot, twoRoot, union)
    }

    private static func verify(_ receipt: ExactRealRootSeparation<Field>, originalLeft: Root,
        originalRight: Root, _ a: inout ExactScalarLedger) throws {
        let domain = try ExactRealRootDomain(retaining: receipt.left.source, using: &a)
        let field = Field(), p = domain.polynomials
        for (root, original) in [(receipt.left, originalLeft), (receipt.right, originalRight)] {
            try RootFixtures.require(root.ordinal == original.ordinal && root.multiplicity == original.multiplicity)
            try RootFixtures.require(root.source.variable == original.source.variable
                && root.source.refinementAxis == original.source.refinementAxis)
            try RootFixtures.require(p.equals(root.source.original, original.source.original, using: &a))
            try RootFixtures.require(domain.compare(root, original, using: &a) == .equal)
            try RootFixtures.require(root.depth.value >= original.depth.value && root.depth.coefficient >= original.depth.coefficient)
            try RootFixtures.require(receipt.depth.value >= root.depth.value && receipt.depth.coefficient >= root.depth.coefficient)
            guard case .finite(let lo) = root.isolation.lower, case .finite(let hi) = root.isolation.upper,
                case .finite(let beforeLo) = original.isolation.lower,
                case .finite(let beforeHi) = original.isolation.upper else { throw ExactRealRootFailure.invalidEvidence }
            try RootFixtures.require(field.compare(lo, beforeLo, using: &a) != .less
                && field.compare(hi, beforeHi, using: &a) != .greater)
        }
        let query = try domain.bind(p.subtracting(p.variable(receipt.left.source.variable, using: &a),
            p.constant(receipt.value, using: &a), using: &a), variable: receipt.left.source.variable, using: &a)
        try RootFixtures.require(domain.sign(of: query, at: receipt.left, using: &a) == .negative)
        try RootFixtures.require(domain.sign(of: query, at: receipt.right, using: &a) == .positive)
    }

    public static func verify() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let inputs = try prepared(&a), domain = inputs.domain
        let separated = try domain.separate(inputs.left, inputs.right, using: &a)
        try verify(separated, originalLeft: inputs.left, originalRight: inputs.right, &a)
        try RootFixtures.require(separated.left.depth.coefficient > inputs.left.depth.coefficient
            && separated.right.depth.value > inputs.right.depth.value)
        let leftSingleton = try domain.separate(inputs.one, inputs.left, using: &a)
        try verify(leftSingleton, originalLeft: inputs.one, originalRight: inputs.left, &a)
        try RootFixtures.require(leftSingleton.left.depth.value == inputs.one.depth.value
            && leftSingleton.left.depth.coefficient == inputs.one.depth.coefficient)
        let rightSingleton = try domain.separate(inputs.right, inputs.two, using: &a)
        try verify(rightSingleton, originalLeft: inputs.right, originalRight: inputs.two, &a)
        try RootFixtures.require(rightSingleton.right.depth.value == inputs.two.depth.value
            && rightSingleton.right.depth.coefficient == inputs.two.depth.coefficient)
        let singletons = try domain.separate(inputs.one, inputs.two, using: &a)
        try verify(singletons, originalLeft: inputs.one, originalRight: inputs.two, &a)
        try RootFixtures.require(singletons.right.multiplicity == 2)

        for pair in [(inputs.left, inputs.same), (inputs.left, inputs.left), (inputs.right, inputs.left)] {
            do {
                _ = try domain.separate(pair.0, pair.1, using: &a)
                throw ExactRealRootFailure.invalidEvidence
            } catch ExactRealRootFailure.invalidDomain { }
        }
        let foreign = try ExactRealRootDomain(field: Field(), variableCount: 2, using: &a)
        do {
            _ = try foreign.separate(inputs.left, inputs.right, using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.incompatibleDomain { }
        try RootFixtures.require(inputs.union.count == 4)
        for index in 1..<inputs.union.count {
            let sector = try domain.separate(inputs.union[index - 1], inputs.union[index], using: &a)
            try verify(sector, originalLeft: inputs.union[index - 1], originalRight: inputs.union[index], &a)
            try RootFixtures.require(sector.left.ordinal == index - 1 && sector.right.ordinal == index)
        }

        var observed = TerminalAdmission()
        _ = try domain.separate(inputs.left, inputs.right, using: &observed)
        var cancelled = TerminalAdmission(cancelAt: observed.checkpoints)
        do {
            _ = try domain.separate(inputs.left, inputs.right, using: &cancelled)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.cancelled) { }
        var exact = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage,
            valueDepth: 32, coefficientDepth: 32))
        _ = try domain.separate(inputs.left, inputs.right, using: &exact)
        var storage = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage - 1,
            valueDepth: 32, coefficientDepth: 32))
        do {
            _ = try domain.separate(inputs.left, inputs.right, using: &storage)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.storage)) {
        } catch ExactRealRootFailure.polynomial(.scalar(.resourceLimit(.storage))) { }
        var work = ExactScalarLedger(limits: try .init(work: observed.work - 1, storageBytes: observed.storage,
            valueDepth: 32, coefficientDepth: 32))
        do {
            _ = try domain.separate(inputs.left, inputs.right, using: &work)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.work)) {
        } catch ExactRealRootFailure.polynomial(.scalar(.resourceLimit(.work))) { }
        var depth = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage,
            valueDepth: 0, coefficientDepth: 32))
        do {
            _ = try domain.separate(inputs.left, inputs.right, using: &depth)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.valueDepth)) { }
        // A rejected later query cannot change already issued immutable separation evidence.
        try verify(separated, originalLeft: inputs.left, originalRight: inputs.right, &a)
        let retained = try lifetime(&a)
        try verify(retained, originalLeft: retained.left, originalRight: retained.right, &a)
        print("PASS: strict separation, singleton endpoints, original identities, union sectors, lifetime and atomic resource failures")
    }

    private static func lifetime(_ a: inout ExactScalarLedger) throws -> ExactRealRootSeparation<Field> {
        let inputs = try prepared(&a)
        return try inputs.domain.separate(inputs.left, inputs.right, using: &a)
    }
}
