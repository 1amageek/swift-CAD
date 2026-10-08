import L0
import DI0

public enum DomainFixtures {
    static func limits(work: Int = 100_000_000, storage: Int = 400_000_000,
        valueDepth: Int = 12, coefficientDepth: Int = 12) throws -> ExactScalarLimits {
        try .init(work: work, storageBytes: storage, valueDepth: valueDepth, coefficientDepth: coefficientDepth)
    }
    static func require(_ value: Bool) throws {
        guard value else { throw ExactScalarFailure.invalidEvidence }
    }
    static func v(_ n: Int, field: Int = 0) -> TestOrderedValue { .init(number: n, field: field) }
    static func depth() throws -> ExactScalarDepth { try .init(value: 0, coefficient: 0) }
    static func bound(_ index: Int) -> ExactParameterBound<TestOrderedValue> {
        if index == 0 { return .negativeInfinity }; if index == 4 { return .positiveInfinity }
        return .finite(v((index - 2) * 2))
    }
    static func oracle(_ n: Int, _ lo: Int, _ hi: Int, _ il: Bool, _ iu: Bool) -> Bool {
        let lower = lo == 0 || n > (lo - 2) * 2 || (il && n == (lo - 2) * 2)
        let upper = hi == 4 || n < (hi - 2) * 2 || (iu && n == (hi - 2) * 2)
        return lower && upper
    }
    public static func endpointAlgebra() throws {
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactParameterDomain(field: TestOrdering(), depth: depth(), using: &a)
        var cases: [(Int, Int, Bool, Bool, ExactParameterSet<TestOrdering>)] = []
        for lo in 0...3 { for hi in max(1,lo)...4 { for il in [false,true] { for iu in [false,true] {
            let i = try d.interval(lower: bound(lo), upper: bound(hi), includesLower: il, includesUpper: iu, using: &a)
            let s = try d.set(intervals: [i], using: &a)
            cases.append((lo,hi,il,iu,s))
            if lo == hi { try require(s.isEmpty == !(il && iu)) }
            if lo == 0 { try require(!i.includesLower) }; if hi == 4 { try require(!i.includesUpper) }
        } } } }
        // All endpoint cells and every open sector, including both infinite sectors.
        for x in cases { for y in cases {
            let u = try d.union(x.4, y.4, using: &a)
            let i = try d.intersection(x.4, y.4, using: &a)
            let s = try d.difference(x.4, y.4, using: &a)
            var equal = true
            for n in -3...3 {
                let left = oracle(n,x.0,x.1,x.2,x.3), right = oracle(n,y.0,y.1,y.2,y.3)
                try require(d.contains(v(n), in: x.4, using: &a) == left)
                try require(d.contains(v(n), in: u, using: &a) == (left || right))
                try require(d.contains(v(n), in: i, using: &a) == (left && right))
                try require(d.contains(v(n), in: s, using: &a) == (left && !right))
                equal = equal && left == right
            }
            try require(d.setEqual(x.4, y.4, using: &a) == equal)
        } }
    }
    public static func canonicalAndDisconnected() throws {
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactParameterDomain(field: TestOrdering(), depth: depth(), using: &a)
        func interval(_ l: Int, _ h: Int, _ il: Bool = true, _ iu: Bool = true) throws -> ExactParameterInterval<TestOrderedValue> {
            try d.interval(lower: .finite(v(l)), upper: .finite(v(h)), includesLower: il, includesUpper: iu, using: &a)
        }
        for end in [false,true] { for start in [false,true] {
            let s = try d.set(intervals: [interval(0,2,start),interval(-2,0,true,end)], using: &a)
            try require(s.intervalCount == (end || start ? 1 : 2))
            try require(d.contains(v(0), in: s, using: &a) == (end || start))
        } }
        let all = try d.set(intervals: [d.interval(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)], using: &a)
        let cuts = try d.set(intervals: [interval(1,1),interval(-2,-1,false,true)], using: &a)
        let rest = try d.difference(all,cuts,using:&a)
        try require(rest.intervalCount == 3)
        for n in -4...4 { try require(d.contains(v(n),in:rest,using:&a) == (n != -1 && n != 1)) }
        let split = try d.set(intervals: [interval(4,6),interval(-6,-4),interval(-2,2)],using:&a)
        let broad = try d.set(intervals: [interval(-5,5,false,false)],using:&a)
        let edges = try d.difference(split,broad,using:&a)
        try require(edges.intervalCount == 2)
        for n in -7...7 {
            try require(d.contains(v(n),in:edges,using:&a) == ([-6,-5,5,6].contains(n)))
        }
        let canonical = try d.set(intervals: [interval(-6,-5),interval(5,6)],using:&a)
        try require(d.setEqual(edges,canonical,using:&a))
        let duplicate = try d.set(intervals: [interval(-2,2,false,false),interval(-2,2),interval(0,1)],using:&a)
        try require(duplicate.intervalCount == 1 && duplicate.intervals.first!.includesLower && duplicate.intervals.first!.includesUpper)
    }
    public static func productsAndLifetime() throws {
        var a = ExactScalarLedger(limits: try limits())
        let d = try ExactParameterDomain(field: TestOrdering(), depth: depth(), using: &a)
        let e = try d.empty(using:&a)
        let point = try d.set(intervals:[d.interval(lower:.finite(v(1)),upper:.finite(v(1)),using:&a)],using:&a)
        let zero = try d.product(axes:[],using:&a)
        try require(zero.arity == 0 && !zero.isEmpty && d.contains(tuple:[],in:zero,using:&a))
        let empty = try d.product(axes:[point,e],using:&a)
        try require(empty.arity == 2 && empty.isEmpty && !d.contains(tuple:[v(1),v(1)],in:empty,using:&a))
        let otherAxis = try ExactParameterDomain(field:TestOrdering(field:1),depth:depth(),using:&a)
        let other = try otherAxis.set(intervals:[otherAxis.interval(lower:.finite(v(2,field:1)),upper:.finite(v(3,field:1)),using:&a)],using:&a)
        let product = try d.product(axes:[point,other],using:&a)
        try require(d.contains(tuple:[v(1),v(2,field:1)],in:product,using:&a))
        do { _ = try d.contains(tuple:[v(1)],in:product,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.invalidArity {}
        do { _ = try d.contains(tuple:[v(1),v(2)],in:product,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.incompatibleDomain) {}
        // A raw scalar's large numerator and its ordering owner survive the original scope.
        func retained() throws -> ExactParameterSet<ExactRationalScalarDomain> {
            var a = ExactScalarLedger(limits:try limits())
            let f = ExactRationalScalarDomain()
            let d = try ExactParameterDomain(field:f,depth:depth(),using:&a)
            let large = try f.canonical(sign:1,numerator:[1,0,0,1],denominator:[1],using:&a)
            return try d.set(intervals:[d.interval(lower:.finite(large),upper:.finite(large),using:&a)],using:&a)
        }
        let result = try retained()
        let view = result.intervals
        let restored = try ExactParameterDomain(retaining:result,using:&a)
        guard case .finite(let value) = view[0].lower else { throw ExactScalarFailure.invalidEvidence }
        try require(restored.contains(value,in:result,using:&a))
        var noStorage = ExactScalarLedger(limits:try limits(storage:0))
        _ = try ExactParameterDomain(retaining:result,using:&noStorage)
        let secondView = result.intervals
        let sameBuffer = view.withUnsafeBufferPointer { first in
            secondView.withUnsafeBufferPointer { second in first.baseAddress == second.baseAddress }
        }
        try require(sameBuffer && noStorage.storageBytes == 0)
    }
    public static func rejectionAndBudgets() throws {
        var a = ExactScalarLedger(limits:try limits())
        let d = try ExactParameterDomain(field:TestOrdering(),depth:depth(),using:&a)
        let other = try ExactParameterDomain(field:TestOrdering(),depth:depth(),using:&a)
        let e = try d.empty(using:&a), foreign = try other.empty(using:&a)
        do { _ = try d.union(e,foreign,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.foreignOwner {}
        do { _ = try d.contains(v(1),in:foreign,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.foreignOwner {}
        let invalid: [(ExactParameterBound<TestOrderedValue>, ExactParameterBound<TestOrderedValue>)] = [(.positiveInfinity,.positiveInfinity),(.negativeInfinity,.negativeInfinity),(.finite(v(2)),.finite(v(1)))]
        for (lo,hi) in invalid {
            do { _ = try d.interval(lower:lo,upper:hi,using:&a); throw ExactScalarFailure.invalidEvidence }
            catch ExactParameterDomainFailure.invalidDomain {}
        }
        do { _ = try d.interval(lower:.finite(v(0,field:1)),upper:.positiveInfinity,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.incompatibleDomain) {}
        let unknown = try ExactParameterDomain(field:TestOrdering(unresolved:true),depth:depth(),using:&a)
        do { _ = try unknown.interval(lower:.finite(v(0)),upper:.finite(v(1)),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.unresolved) {}
        var work = ExactScalarLedger(limits:try limits(work:0))
        do { _ = try d.empty(using:&work); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.resourceLimit(.work)) {}
        var storage = ExactScalarLedger(limits:try limits(storage:0))
        let raw = try d.interval(lower:.finite(v(0)),upper:.finite(v(1)),using:&a)
        do { _ = try d.set(intervals:[raw],using:&storage); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.resourceLimit(.storage)) {}
        var cancelled = ExactScalarLedger(limits:try limits()); cancelled.cancel()
        do { _ = try d.empty(using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.cancelled) {}
        for coefficient in [false,true] {
            let deep = try ExactScalarDepth(value:coefficient ? 0 : 2,coefficient:coefficient ? 2 : 0)
            let deepRaw = try raw.retainingDepth(deep,using:&a)
            let retained = try d.set(intervals:[deepRaw],using:&a)
            try require(retained.intervals[0].depth == deep)
            var shallow = ExactScalarLedger(limits:try limits(valueDepth:coefficient ? 12 : 0,coefficientDepth:coefficient ? 0 : 12))
            do { _ = try d.contains(v(0),in:retained,using:&shallow); throw ExactScalarFailure.invalidEvidence }
            catch ExactParameterDomainFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (coefficient ? .coefficientDepth : .valueDepth))
            }
        }
        var baseline = try TerminalAdmission()
        _ = try d.set(intervals:[raw],using:&baseline)
        try require(baseline.maxStorageRequest >= MemoryLayout<ExactParameterInterval<TestOrderedValue>>.stride)
        var terminal = try TerminalAdmission(); terminal.cancelAt = baseline.checks
        do { _ = try d.set(intervals:[raw],using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.cancelled) {}
        var overflow = ExactScalarLedger(limits:try limits(work:Int.max))
        try overflow.consumeWork(Int.max)
        do { _ = try d.empty(using:&overflow); throw ExactScalarFailure.invalidEvidence }
        catch ExactParameterDomainFailure.scalar(.countOverflow) {}
    }
    #if !hasFeature(Embedded)
    public static func concurrentReadersAndTaskCancel() async throws {
        var preparation = ExactScalarLedger(limits:try limits())
        let d = try ExactParameterDomain(field:TestOrdering(),depth:depth(),using:&preparation)
        let set = try d.set(intervals:[d.interval(lower:.finite(v(-2)),upper:.finite(v(2)),using:&preparation)],using:&preparation)
        try await withThrowingTaskGroup(of:Bool.self) { tasks in
            for n in -4...4 {
                tasks.addTask {
                    var a = ExactScalarLedger(limits:try limits())
                    return try d.contains(v(n),in:set,using:&a) == (-2...2).contains(n)
                }
            }
            for try await valid in tasks { try require(valid) }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var a = ExactScalarLedger(limits:try limits())
            do { _ = try d.empty(using:&a); return false }
            catch ExactParameterDomainFailure.scalar(.cancelled) { return true }
        }
        try require(await task.value)
    }
    #endif
    public static func runAll() throws {
        try endpointAlgebra(); try canonicalAndDisconnected(); try productsAndLifetime(); try rejectionAndBudgets()
    }
}
