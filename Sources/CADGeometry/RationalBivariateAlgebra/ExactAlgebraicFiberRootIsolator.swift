import CADCore

/// Original v-root isolation above one certified algebraic original u station.
struct ExactAlgebraicFiberRootIsolator {
    struct Root: Sendable {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let excludesLower: Bool
        let excludesUpper: Bool
        let isolationDepth: Int
    }
    private struct Pending {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let excludesLower: Bool
        let excludesUpper: Bool
        let count: Int
        let depth: Int
    }
    static func isolate<B: RationalAlgebraAdmitting>(_ source: ExactAlgebraicFiberPolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, maximumDepth: Int,
        usage: inout B) throws -> [Root] {
        guard maximumDepth >= source.root.isolation.isolationDepth, try upper.subtracting(lower, usage: &usage).isPositive else {
            throw rationalAlgebraFailure("Exact fiber isolation needs increasing rational bounds and caller depth.")
        }
        let sturm = try ExactAlgebraicFiberSturmSequence(source, maximumDepth: maximumDepth, usage: &usage)
        var roots: [Root] = []
        for station in [lower, upper] {
            if try sturm.count(lower: station, upper: station, excludesLower: false, excludesUpper: false,
                maximumDepth: maximumDepth, usage: &usage) == 1 {
                try usage.retainExactStorage(1)
                roots.append(Root(lower: station, upper: station, excludesLower: false, excludesUpper: false, isolationDepth: source.root.isolation.isolationDepth))
            }
        }
        let count = try sturm.count(lower: lower, upper: upper, excludesLower: true, excludesUpper: true,
            maximumDepth: maximumDepth, usage: &usage)
        try usage.retainExactStorage(1)
        var pending = [Pending(lower: lower, upper: upper, excludesLower: true,
            excludesUpper: true, count: count, depth: source.root.isolation.isolationDepth)]
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while let cell = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: cell.depth)
            if cell.count == 0 { continue }
            if cell.count == 1 {
                try usage.retainExactStorage(1)
                roots.append(Root(lower: cell.lower, upper: cell.upper,
                    excludesLower: cell.excludesLower, excludesUpper: cell.excludesUpper, isolationDepth: cell.depth)); continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Exact original algebraic fiber isolation exhausted caller depth.")
            }
            let middle = try cell.lower.adding(cell.upper, usage: &usage).divided(by: two, usage: &usage)
            let left = try sturm.count(lower: cell.lower, upper: middle, excludesLower: cell.excludesLower,
                excludesUpper: false, maximumDepth: maximumDepth, usage: &usage)
            let right = try sturm.count(lower: middle, upper: cell.upper, excludesLower: true,
                excludesUpper: cell.excludesUpper, maximumDepth: maximumDepth, usage: &usage)
            guard left + right == cell.count else { throw rationalAlgebraFailure("Exact fiber subdivision lost root coverage.") }
            try usage.retainExactStorage(2)
            pending.append(Pending(lower: middle, upper: cell.upper, excludesLower: true,
                excludesUpper: cell.excludesUpper, count: right, depth: cell.depth + 1))
            pending.append(Pending(lower: cell.lower, upper: middle, excludesLower: cell.excludesLower,
                excludesUpper: false, count: left, depth: cell.depth + 1))
        }
        return roots
    }
}
