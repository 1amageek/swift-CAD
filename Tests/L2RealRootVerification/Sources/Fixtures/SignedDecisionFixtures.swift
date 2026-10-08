import L0
import L1
import L2

public enum SignedDecisionFixtures {
    public static func verify() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let field = ExactRationalScalarDomain(), domain = try ExactRealRootDomain(field: field, using: &a)
        let p = domain.polynomials, x = try p.variable(0, using: &a)
        let one = try field.integer(1, using: &a), two = try field.integer(2, using: &a)
        let square = try p.multiplying(x, x, using: &a)
        let law = try p.subtracting(square, p.constant(two, using: &a), using: &a)
        let source = try domain.bind(law, using: &a)
        let selected = try domain.domain(lower: .finite(one), upper: .finite(two), using: &a)
        let root = try domain.isolate(source, in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let tiny = try field.binary64(exactly: Double.leastNonzeroMagnitude, using: &a)
        let nearLaw = try p.subtracting(law, p.constant(tiny, using: &a), using: &a)
        let near = try domain.bind(nearLaw, using: &a)
        let next = try domain.isolate(near, in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        try RootFixtures.require(domain.compare(root, next, using: &a) == .less)
        try RootFixtures.require(domain.compare(next, root, using: &a) == .greater)
        try RootFixtures.require(domain.sign(of: near, at: root, using: &a) == .negative)
        let same = try domain.bind(p.multiplying(law,
            p.subtracting(x, p.constant(field.integer(3, using: &a), using: &a), using: &a), using: &a), using: &a)
        let sameRoot = try domain.isolate(same, in: selected, limits: .init(maximumRoots: 1), using: &a).roots[0]
        try RootFixtures.require(domain.compare(root, sameRoot, using: &a) == .equal)
        let positive = try domain.bind(p.adding(p.multiplying(law, law, using: &a),
            p.constant(one, using: &a), using: &a), using: &a)
        let queries = [source, near, positive]
        let signs = try domain.signs(of: queries, at: root, using: &a)
        try RootFixtures.require(signs.values == [.zero, .negative, .positive])
        try RootFixtures.require(signs.root.ordinal == root.ordinal && signs.queries.count == 3)
        var observed = TerminalAdmission()
        _ = try domain.signs(of: queries, at: root, using: &observed)
        var cancelled = TerminalAdmission(cancelAt: observed.checkpoints)
        do {
            _ = try domain.signs(of: queries, at: root, using: &cancelled)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.cancelled) { }
        var exact = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage,
            valueDepth: 32, coefficientDepth: 32))
        try RootFixtures.require(domain.signs(of: queries, at: root, using: &exact).values == signs.values)
        var work = ExactScalarLedger(limits: try .init(work: observed.work - 1, storageBytes: observed.storage,
            valueDepth: 32, coefficientDepth: 32))
        do {
            _ = try domain.signs(of: queries, at: root, using: &work)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.work)) {
        } catch ExactRealRootFailure.polynomial(.scalar(.resourceLimit(.work))) { }
        var storage = ExactScalarLedger(limits: try .init(work: observed.work, storageBytes: observed.storage - 1,
            valueDepth: 32, coefficientDepth: 32))
        do {
            _ = try domain.signs(of: queries, at: root, using: &storage)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.storage)) {
        } catch ExactRealRootFailure.polynomial(.scalar(.resourceLimit(.storage))) { }
        let endpoints = try domain.bind(p.subtracting(square, p.constant(one, using: &a), using: &a), using: &a)
        let openClosed = try domain.domain(lower: .finite(field.negated(one, using: &a)),
            upper: .finite(one), includesLower: false, includesUpper: true, using: &a)
        let endpointRoot = try domain.isolate(endpoints, in: openClosed, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let atOther = try domain.bind(p.adding(square, x, using: &a), using: &a)
        let negative = try domain.bind(p.subtracting(p.multiplying(square, x, using: &a), p.constant(two, using: &a), using: &a), using: &a)
        try RootFixtures.require(domain.signs(of: [atOther, endpoints, negative], at: endpointRoot, using: &a).values == [.positive, .zero, .negative])
        let closedOpen = try domain.domain(lower: .finite(field.negated(one, using: &a)),
            upper: .finite(one), includesLower: true, includesUpper: false, using: &a)
        let leftRoot = try domain.isolate(endpoints, in: closedOpen, limits: .init(maximumRoots: 1), using: &a).roots[0]
        try RootFixtures.require(domain.signs(of: [atOther, endpoints, negative], at: leftRoot, using: &a).values == [.zero, .zero, .negative])
        try RootFixtures.require(domain.compare(leftRoot, endpointRoot, using: &a) == .less)
        let foreign = try ExactRealRootDomain(field: field, using: &a)
        do {
            _ = try foreign.signs(of: queries, at: root, using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.incompatibleDomain { }
        print("PASS: signed remainder, near-root order without bisection, endpoint contributions and shared admission")
    }
}
