import L0
import L1
import L2

public enum CountReuseFixtures {
    public static func verify() throws {
        var a = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 200_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let field = ExactRationalScalarDomain(), domain = try ExactRealRootDomain(field: field, using: &a)
        let p = domain.polynomials, x = try p.variable(0, using: &a)
        let left = try p.adding(x, p.constant(field.integer(1, using: &a), using: &a), using: &a)
        let right = try p.subtracting(x, p.constant(field.integer(1, using: &a), using: &a), using: &a)
        let original = try p.multiplying(p.multiplying(left, left, using: &a), right, using: &a)
        let source = try domain.bind(original, using: &a)
        let all = try domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let count = try domain.count(source, in: all, using: &a)
        var reused = TerminalAdmission(), fresh = TerminalAdmission()
        let retained = try domain.isolate(count, limits: .init(maximumRoots: 2), using: &reused)
        let direct = try domain.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &fresh)
        try RootFixtures.require(reused.work < fresh.work && reused.storage < fresh.storage)
        try RootFixtures.require(retained.roots.map { $0.ordinal } == [0, 1] && retained.roots.map { $0.multiplicity } == [2, 1])
        for index in retained.roots.indices {
            try RootFixtures.require(domain.compare(retained.roots[index], direct.roots[index], using: &a) == .equal)
        }
        let singleton = try domain.domain(lower: .finite(field.integer(1, using: &a)),
            upper: .finite(field.integer(1, using: &a)), using: &a)
        let singleCount = try domain.count(source, in: singleton, using: &a)
        let single = try domain.isolate(singleCount, limits: .init(maximumRoots: 1), using: &a)
        try RootFixtures.require(single.roots.count == 1 && single.roots[0].ordinal == 1)
        let candidates = try domain.isolate(source, fromSortedExactCandidates: [field.integer(-1, using: &a), field.integer(1, using: &a)],
            limits: .init(maximumRoots: 2), using: &a)
        let candidateCount = try domain.isolate(candidates.count, limits: .init(maximumRoots: 2), using: &a)
        try RootFixtures.require(candidateCount.roots.map { $0.multiplicity } == [2, 1])
        let zero = try domain.bind(p.constant(field.integer(0, using: &a), using: &a), using: &a)
        let zeroCount = try domain.count(zero, in: all, using: &a)
        try RootFixtures.require(domain.isolate(zeroCount, limits: .init(maximumRoots: 0), using: &a).count.classification == .wholeDomain)
        let constant = try domain.bind(p.constant(field.integer(7, using: &a), using: &a), using: &a)
        let exclusion = try domain.count(constant, in: all, using: &a)
        try RootFixtures.require(domain.isolate(exclusion, limits: .init(maximumRoots: 0), using: &a).roots.isEmpty)
        let foreign = try ExactRealRootDomain(field: field, using: &a)
        do { _ = try foreign.isolate(count, limits: .init(maximumRoots: 2), using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.incompatibleDomain { }
        do { _ = try domain.isolate(count, limits: .init(maximumRoots: 1), using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.resultLimit { }
        var cancelled = TerminalAdmission(cancelAt: reused.checkpoints)
        do { _ = try domain.isolate(count, limits: .init(maximumRoots: 2), using: &cancelled); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.cancelled) { }
        var exact = ExactScalarLedger(limits: try .init(work: reused.work, storageBytes: reused.storage,
            valueDepth: 32, coefficientDepth: 32))
        try RootFixtures.require(domain.isolate(count, limits: .init(maximumRoots: 2), using: &exact).roots.count == 2)
        print("PASS: count reuse reduces admitted work/storage while preserving original global ordinal and multiplicity")
    }
    public static func factored() throws {
        var a = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 200_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let p = d.polynomials, x = try p.variable(0, using: &a)
        let linear = try p.subtracting(x, p.constant(f.integer(1, using: &a), using: &a), using: &a)
        let quadratic = try p.subtracting(p.multiplying(x, x, using: &a),
            p.constant(f.integer(2, using: &a), using: &a), using: &a)
        let repeated = try p.multiplying(linear, linear, using: &a)
        let source = try d.bind(p.scaled(p.multiplying(repeated, quadratic, using: &a),
            by: f.integer(-3, using: &a), using: &a), using: &a)
        let factors = [try d.bind(repeated, using: &a), try d.bind(quadratic, using: &a)]
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        var measured = TerminalAdmission()
        let count = try d.count(source, in: all, factoredBy: factors, using: &measured)
        let result = try d.isolate(count, limits: .init(maximumRoots: 3), using: &a)
        let direct = try d.isolate(source, in: all, limits: .init(maximumRoots: 3), using: &a)
        try RootFixtures.require(count.classification == .finite(distinct: 3, totalMultiplicity: 4))
        try RootFixtures.require(result.roots.map { $0.ordinal } == [0, 1, 2]
            && result.roots.map { $0.multiplicity } == [1, 2, 1])
        for index in result.roots.indices {
            try RootFixtures.require(try d.compare(result.roots[index], direct.roots[index], using: &a) == .equal)
            try RootFixtures.require(try p.equals(result.roots[index].source.original, source.original, using: &a))
        }
        let singleton = try d.domain(lower: .finite(f.integer(1, using: &a)),
            upper: .finite(f.integer(1, using: &a)), using: &a)
        let one = try d.isolate(d.count(source, in: singleton, factoredBy: factors, using: &a),
            limits: .init(maximumRoots: 1), using: &a)
        try RootFixtures.require(one.roots.count == 1 && one.roots[0].ordinal == 1 && one.roots[0].multiplicity == 2)
        for invalid in [[factors[0]], [factors[0], factors[0]],
            [try d.bind(linear, using: &a), factors[0], factors[1]],
            [try d.bind(p.adding(x, p.constant(f.integer(3, using: &a), using: &a), using: &a), using: &a)]] {
            do {
                _ = try d.count(source, in: all, factoredBy: invalid, using: &a)
            } catch { continue }
            throw ExactRealRootFailure.invalidEvidence
        }
        let other = try ExactRealRootDomain(field: f, using: &a)
        do {
            _ = try d.count(source, in: all, factoredBy: [other.bind(other.polynomials.variable(0, using: &a), using: &a)], using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.incompatibleDomain { }
        var exact = ExactScalarLedger(limits: try .init(work: measured.work, storageBytes: measured.storage,
            valueDepth: 32, coefficientDepth: 32))
        try RootFixtures.require(try d.count(source, in: all, factoredBy: factors, using: &exact).classification == count.classification)
        for storage in [false, true] {
            var refused = ExactScalarLedger(limits: try .init(work: measured.work - (storage ? 0 : 1),
                storageBytes: measured.storage - (storage ? 1 : 0), valueDepth: 32, coefficientDepth: 32))
            do { _ = try d.count(source, in: all, factoredBy: factors, using: &refused) }
            catch { continue }
            throw ExactRealRootFailure.invalidEvidence
        }
        var terminal = TerminalAdmission(cancelAt: measured.checkpoints)
        do {
            _ = try d.count(source, in: all, factoredBy: factors, using: &terminal)
        } catch ExactRealRootFailure.scalar(.cancelled) { return }
        throw ExactRealRootFailure.invalidEvidence
    }
}
