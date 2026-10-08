import L0
import L1
import L2

public enum RootFixtures {
    public static func require(_ condition: Bool) throws {
        if !condition { throw ExactRealRootFailure.invalidEvidence }
    }
    public static func definingDivisorRefinement() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let field = ExactRationalScalarDomain(), domain = try ExactRealRootDomain(field: field, using: &a)
        let p = domain.polynomials, x = try p.variable(0, using: &a)
        let quadratic = try p.subtracting(p.multiplying(x, x, using: &a), p.constant(field.integer(2, using: &a), using: &a), using: &a)
        let linear = try p.subtracting(x, p.constant(field.integer(1, using: &a), using: &a), using: &a)
        let source = try domain.bind(p.multiplying(quadratic, linear, using: &a), using: &a)
        let all = try domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let root = try domain.isolate(source, in: all, limits: .init(maximumRoots: 3), using: &a).roots[2]
        let refined = try domain.refine(root, usingDefiningDivisor: domain.bind(quadratic, using: &a), using: &a)
        try require(refined.ordinal == root.ordinal && refined.multiplicity == root.multiplicity)
        try require(p.equals(refined.source.original, root.source.original, using: &a))
        try require(domain.compare(root, refined, using: &a) == .equal)
        try require(domain.sign(of: source, at: refined, using: &a) == .zero)
        do {
            _ = try domain.refine(root, usingDefiningDivisor: domain.bind(linear, using: &a), using: &a)
            throw ExactRealRootFailure.invalidSource
        } catch ExactRealRootFailure.invalidEvidence { }
        let unrelated = try p.subtracting(x, p.constant(field.integer(3, using: &a), using: &a), using: &a)
        do {
            _ = try domain.refine(root, usingDefiningDivisor: domain.bind(unrelated, using: &a), using: &a)
            throw ExactRealRootFailure.invalidSource
        } catch ExactRealRootFailure.invalidEvidence { }
    }

    public static func exactCandidateCompletion() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let field = ExactRationalScalarDomain(), domain = try ExactRealRootDomain(field: field, using: &a)
        let p = domain.polynomials, x = try p.variable(0, using: &a)
        let zero = try field.integer(0, using: &a), one = try field.integer(1, using: &a)
        let factor = try p.subtracting(x, p.constant(one, using: &a), using: &a)
        let source = try domain.bind(p.multiplying(x, p.multiplying(factor, factor, using: &a), using: &a), using: &a)
        let result = try domain.isolate(source, fromSortedExactCandidates: [zero, one],
            limits: .init(maximumRoots: 2), using: &a)
        try require(result.classification == .finite(distinct: 2, totalMultiplicity: 3))
        try require(result.roots.map { $0.ordinal } == [0, 1] && result.roots.map { $0.multiplicity } == [1, 2])
        for root in result.roots {
            try require(domain.sign(of: source, at: root, using: &a) == .zero)
            guard case .finite(let lower) = root.isolation.lower, case .finite(let upper) = root.isolation.upper else {
                throw ExactRealRootFailure.invalidEvidence
            }
            try require(field.compare(lower, upper, using: &a) == .equal)
        }
        for invalid in [[zero], [zero, zero], [one, zero], [zero, try field.integer(2, using: &a)]] {
            do {
                _ = try domain.isolate(source, fromSortedExactCandidates: invalid, limits: .init(maximumRoots: 2), using: &a)
                throw ExactRealRootFailure.invalidSource
            } catch ExactRealRootFailure.invalidEvidence { }
        }
        do {
            _ = try domain.isolate(source, fromSortedExactCandidates: [zero, one], limits: .init(maximumRoots: 1), using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.resultLimit { }
        let absent = try domain.bind(p.adding(p.multiplying(x, x, using: &a), p.constant(one, using: &a), using: &a), using: &a)
        try require(domain.isolate(absent, fromSortedExactCandidates: [], limits: .init(maximumRoots: 0), using: &a).roots.isEmpty)
        let mixed = try domain.bind(p.multiplying(absent.original,
            p.multiplying(factor, factor, using: &a), using: &a), using: &a)
        let mixedRoots = try domain.isolate(mixed, fromSortedExactCandidates: [one],
            limits: .init(maximumRoots: 1), using: &a)
        try require(mixedRoots.classification == .finite(distinct: 1, totalMultiplicity: 2))
        try require(mixedRoots.roots[0].ordinal == 0 && mixedRoots.roots[0].multiplicity == 2)
    }

    public static func rational() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let f = ExactRationalScalarDomain()
        let d = try ExactRealRootDomain(field: f, using: &a)
        let p = d.polynomials
        let x = try p.variable(0, using: &a)
        let one = try p.constant(f.integer(1, using: &a), using: &a)
        let factor = try p.subtracting(x, one, using: &a)
        let cubic = try p.multiplying(p.multiplying(factor, factor, using: &a), x, using: &a)
        let source = try d.bind(cubic, using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let result = try d.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &a)
        try require(result.classification == .finite(distinct: 2, totalMultiplicity: 3))
        try require(result.roots.map { $0.multiplicity } == [1, 2])
        try require(result.roots.map { $0.ordinal } == [0, 1])
        try require(d.compare(result.roots[0], result.roots[1], using: &a) == .less)
        let bound = try d.bind(x, using: &a)
        try require(d.sign(of: bound, at: result.roots[0], using: &a) == .zero)
        try require(d.sign(of: bound, at: result.roots[1], using: &a) == .positive)
        let width = try f.dividing(f.integer(1, using: &a), f.integer(100, using: &a), using: &a)
        let refined = try d.refine(result.roots[1], maximumWidth: width, using: &a)
        try require(d.compare(refined, result.roots[1], using: &a) == .equal)
    }

    public static func domains() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let p = d.polynomials, x = try p.variable(0, using: &a)
        let z = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let source = try d.bind(p.multiplying(x, p.subtracting(x, p.constant(one, using: &a), using: &a), using: &a), using: &a)
        for il in [false, true] {
            for iu in [false, true] {
                let selected = try d.domain(lower: .finite(z), upper: .finite(one), includesLower: il, includesUpper: iu, using: &a)
                let expected = (il ? 1 : 0) + (iu ? 1 : 0)
                try require(d.count(source, in: selected, using: &a).classification == .finite(distinct: expected, totalMultiplicity: expected))
                let result = try d.isolate(source, in: selected, limits: .init(maximumRoots: 2), using: &a)
                try require(result.roots.count == expected)
                if il { try require(result.roots.first?.ordinal == 0) }
                if iu { try require(result.roots.last?.ordinal == 1) }
            }
        }
        let singleton = try d.domain(lower: .finite(one), upper: .finite(one), using: &a)
        try require(d.isolate(source, in: singleton, limits: .init(maximumRoots: 1), using: &a).roots[0].ordinal == 1)
        let empty = try d.emptyDomain(using: &a)
        let zero = try d.bind(p.zero(using: &a), using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        try require(d.count(zero, in: all, using: &a).classification == .wholeDomain)
        try require(d.count(zero, in: empty, using: &a).classification == .finite(distinct: 0, totalMultiplicity: 0))
        let constant = try d.bind(p.constant(one, using: &a), using: &a)
        try require(d.isolate(constant, in: all, limits: .init(maximumRoots: 0), using: &a).roots.isEmpty)
        let noRoot = try d.bind(p.adding(p.multiplying(x, x, using: &a), p.constant(one, using: &a), using: &a), using: &a)
        try require(d.count(noRoot, in: all, using: &a).classification == .finite(distinct: 0, totalMultiplicity: 0))
        let ray = try d.domain(lower: .finite(one), upper: .positiveInfinity, includesLower: false, using: &a)
        try require(d.count(source, in: ray, using: &a).classification == .finite(distinct: 0, totalMultiplicity: 0))
    }
    public static func exactQueries() throws {
        var a = ExactScalarLedger(limits: try .init(work: 30_000_000, storageBytes: 70_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let p = d.polynomials, x = try p.variable(0, using: &a)
        let two = try p.constant(f.integer(2, using: &a), using: &a)
        let quadratic = try p.subtracting(p.multiplying(x, x, using: &a), two, using: &a)
        let source = try d.bind(quadratic, using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let roots = try d.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &a).roots
        try require(d.compare(roots[0], roots[1], using: &a) == .less)
        let cubic = try d.bind(p.multiplying(quadratic, x, using: &a), using: &a)
        let other = try d.isolate(cubic, in: all, limits: .init(maximumRoots: 3), using: &a).roots
        try require(d.compare(roots[1], other[2], using: &a) == .equal)
        let minusThree = try d.bind(p.subtracting(p.multiplying(x, x, using: &a), p.constant(f.integer(3, using: &a), using: &a), using: &a), using: &a)
        try require(d.sign(of: minusThree, at: roots[1], using: &a) == .negative)
        let tiny = try f.dividing(f.integer(1, using: &a), f.integer(1_000_000, using: &a), using: &a)
        let near = try d.bind(p.multiplying(x, p.subtracting(x, p.constant(tiny, using: &a), using: &a), using: &a), using: &a)
        let pair = try d.isolate(near, in: all, limits: .init(maximumRoots: 2), using: &a).roots
        try require(pair.count == 2 && pair[0].ordinal != pair[1].ordinal)
        try require(d.compare(pair[0], pair[1], using: &a) == .less)
        let refined = try d.refine(roots[1], maximumWidth: tiny, using: &a)
        if case .finite(let lo) = refined.isolation.lower, case .finite(let hi) = refined.isolation.upper {
            try require(f.compare(f.subtracting(hi, lo, using: &a), tiny, using: &a) != .greater)
        } else { throw ExactRealRootFailure.invalidEvidence }
    }
    public static func failures() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let x = try d.polynomials.variable(0, using: &a), source = try d.bind(x, using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        do { _ = try d.isolate(source, in: all, limits: .init(maximumRoots: 0), using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.resultLimit {}
        let root = try d.isolate(source, in: all, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let zero = try f.integer(0, using: &a)
        do { _ = try d.refine(root, maximumWidth: zero, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.invalidDomain {}
        let foreign = try ExactRealRootDomain(field: f, using: &a)
        do { _ = try foreign.count(source, in: all, using: &a); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.incompatibleDomain {}
        var work = ExactScalarLedger(limits: try .init(work: 0, storageBytes: 10_000, valueDepth: 100, coefficientDepth: 100))
        do { _ = try d.count(source, in: all, using: &work); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.resourceLimit(.work)) {}
        var storage = ExactScalarLedger(limits: try .init(work: 10_000, storageBytes: 0, valueDepth: 100, coefficientDepth: 100))
        do { _ = try d.count(source, in: all, using: &storage); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.resourceLimit(.storage)) {}
        var cancelled = ExactScalarLedger(limits: try .init(work: 10_000, storageBytes: 10_000, valueDepth: 100, coefficientDepth: 100))
        cancelled.cancel()
        do { _ = try d.count(source, in: all, using: &cancelled); throw ExactRealRootFailure.invalidEvidence }
        catch ExactRealRootFailure.scalar(.cancelled) {}
        let tiny = try f.dividing(f.integer(1, using: &a), f.integer(100, using: &a), using: &a)
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            let s = try d.bind(x, refinementAxis: axis, using: &a)
            let r = try d.isolate(s, in: all, limits: .init(maximumRoots: 1), using: &a).roots[0]
            var depth = ExactScalarLedger(limits: try .init(work: 10_000_000, storageBytes: 20_000_000,
                valueDepth: axis == .value ? 0 : 100, coefficientDepth: axis == .coefficient ? 0 : 100))
            do { _ = try d.refine(r, maximumWidth: tiny, using: &depth); throw ExactRealRootFailure.invalidEvidence }
            catch ExactRealRootFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
    }

    public static func exactCandidateRefinement() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let f = ExactRationalScalarDomain(), d = try ExactRealRootDomain(field: f, using: &a)
        let p = d.polynomials, x = try p.variable(0, using: &a)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let tiny = try f.binary64(exactly: Double.leastNonzeroMagnitude, using: &a)
        let factor = try p.subtracting(x, p.constant(tiny, using: &a), using: &a)
        let source = try d.bind(p.multiplying(x, p.multiplying(factor, factor, using: &a), using: &a), using: &a)
        let all = try d.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        let roots = try d.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &a).roots
        try require(roots.count == 2)
        for index in roots.indices {
            let value = index == 0 ? zero : tiny
            let refined = try d.refine(roots[index], toExactValue: value, using: &a)
            try require(refined.ordinal == roots[index].ordinal && refined.multiplicity == roots[index].multiplicity)
            guard case .finite(let lo) = refined.isolation.lower, case .finite(let hi) = refined.isolation.upper else {
                throw ExactRealRootFailure.invalidEvidence
            }
            try require(f.compare(lo, value, using: &a) == .equal && f.compare(hi, value, using: &a) == .equal)
            try require(d.compare(refined, roots[index], using: &a) == .equal)
        }
        let half = try f.dividing(one, f.integer(2, using: &a), using: &a)
        for candidate in [half, one, try f.negated(one, using: &a)] {
            var rejected = false
            do { _ = try d.refine(roots[1], toExactValue: candidate, using: &a) }
            catch ExactRealRootFailure.invalidEvidence { rejected = true }
            try require(rejected)
        }
        var cancelled = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        cancelled.cancel()
        var rejectedCancellation = false
        do { _ = try d.refine(roots[1], toExactValue: tiny, using: &cancelled) }
        catch ExactRealRootFailure.scalar(.cancelled) { rejectedCancellation = true }
        try require(rejectedCancellation)
    }
}
