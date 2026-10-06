import CADCore

/// Bounded local coefficient changes between two containing native spline spaces.
struct PolynomialSurfaceContinuationAxisConstruction {
    typealias Budget = PolynomialSurfacePositionDifferenceNet.Budget

    private struct Cell {
        let lower: Double
        let upper: Double
        let sourceSpan: Int
        let newCount: Int
    }

    private struct Operator {
        let sourceStart: Int
        let targetStart: Int
        let newCount: Int
        let original: [Double]
        let target: [Double]
    }

    let knots: [Double]
    let controlCount: Int
    private let degree: Int
    private let originalDegree: Int
    private let operators: [Operator]

    init(knots originalKnots: [Double], degree originalDegree: Int, count: Int,
        targetDegree: Int, interval: ScalarInterval,
        maximumSpanCount: Int, maximumControlPointCount: Int,
        tolerance: ModelingTolerance, budget: inout Budget) throws {
        self.degree = targetDegree
        self.originalDegree = originalDegree
        try budget.charge(scalars: (MemoryLayout<Self>.stride + 7) / 8, work: 4)
        var first: Int?, last: Int?
        for span in originalDegree..<count {
            try budget.charge(work: 4)
            if originalKnots[span] < originalKnots[span + 1] {
                if first == nil { first = span }
                last = span
            }
        }
        guard let first, let last else {
            throw GeometryConversionError.invalidInput("A continuation axis requires positive original spans.")
        }
        var cells: [Cell] = []
        var outputCount = 0
        for span in originalDegree..<count {
            try budget.charge(work: 12)
            guard originalKnots[span] < originalKnots[span + 1] else { continue }
            let lower = span == first ? interval.lower : max(interval.lower, originalKnots[span])
            let upper = span == last ? interval.upper : min(interval.upper, originalKnots[span + 1])
            guard lower < upper else { continue }
            var multiplicity = 0
            if !cells.isEmpty {
                var index = span
                while index >= 0 {
                    try budget.charge(work: 4)
                    if originalKnots[index] != lower { break }
                    multiplicity += 1
                    index -= 1
                }
                guard multiplicity > 0, multiplicity <= originalDegree else {
                    throw GeometryConversionError.invalidInput("Continuation partitions require the original C0 knot boundary.")
                }
            }
            let added = cells.isEmpty ? targetDegree + 1 : multiplicity + targetDegree - originalDegree
            let nextCount = try Budget.add(outputCount, added)
            let nextSpans = try Budget.add(cells.count, 1)
            guard nextSpans <= maximumSpanCount, nextCount <= maximumControlPointCount else {
                throw GeometryConversionError.resourceLimitExceeded("Native-knot continuation exceeds its caller span or control ceiling.")
            }
            try budget.charge(scalars: Budget.multiply((MemoryLayout<Cell>.stride + 7) / 8, 4), work: 4)
            cells.append(Cell(lower: lower, upper: upper, sourceSpan: span, newCount: added))
            outputCount = nextCount
        }
        guard !cells.isEmpty else {
            throw GeometryConversionError.invalidInput("Continuation has no finite requested polynomial cells.")
        }
        controlCount = outputCount
        let knotCount = try Budget.add(outputCount, targetDegree + 1)
        try budget.charge(scalars: knotCount, work: Budget.multiply(knotCount, 2))
        var targetKnots: [Double] = []
        targetKnots.reserveCapacity(knotCount)
        for _ in 0...targetDegree { targetKnots.append(interval.lower) }
        for cell in cells.dropFirst() {
            for _ in 0..<cell.newCount { targetKnots.append(cell.lower) }
        }
        for _ in 0...targetDegree { targetKnots.append(interval.upper) }
        knots = targetKnots
        try budget.charge(scalars: Budget.multiply(cells.count, (MemoryLayout<Operator>.stride + 7) / 8),
            work: Budget.multiply(cells.count, 4))
        var result: [Operator] = []
        result.reserveCapacity(cells.count)
        var targetSpan = targetDegree
        for (index, cell) in cells.enumerated() {
            if index > 0 { targetSpan += cell.newCount }
            let original = try Self.extraction(knots: originalKnots, degree: originalDegree,
                count: count, span: cell.sourceSpan, originalLower: originalKnots[cell.sourceSpan],
                lower: cell.lower, upper: cell.upper, targetDegree: targetDegree,
                tolerance: tolerance, budget: &budget)
            let target = try Self.extraction(knots: targetKnots, degree: targetDegree,
                count: outputCount, span: targetSpan, originalLower: cell.lower,
                lower: cell.lower, upper: cell.upper, targetDegree: targetDegree,
                tolerance: tolerance, budget: &budget)
            result.append(Operator(sourceStart: cell.sourceSpan - originalDegree,
                targetStart: targetSpan - targetDegree, newCount: cell.newCount,
                original: original, target: target))
        }
        operators = result
    }

    func construct(budget: inout Budget, original: (Int) -> SIMD3<Double>) throws -> [SIMD3<Double>] {
        // SIMD3 occupies four double words including alignment padding.
        let vectorWords = (MemoryLayout<SIMD3<Double>>.stride + 7) / 8
        let n = degree + 1, inputCount = originalDegree + 1
        try budget.charge(scalars: Budget.multiply(controlCount, vectorWords), work: controlCount)
        var result = Array(repeating: SIMD3<Double>.zero, count: controlCount)
        for op in operators {
            try CurrentTaskCancellationChecker().checkCancellation()
            try budget.charge(scalars: Budget.multiply(n, vectorWords),
                work: Budget.add(Budget.multiply(try Budget.multiply(n, inputCount), 16), n))
            var bernstein = Array(repeating: SIMD3<Double>.zero, count: n)
            for row in 0..<n {
                for column in 0..<inputCount {
                    bernstein[row] += original(op.sourceStart + column) * op.original[row * inputCount + column]
                }
            }
            let overlap = n - op.newCount
            for row in overlap..<n {
                // Known overlap and preceding new controls are the only nonzero
                // columns before this triangular pivot. No whole-domain dense solve.
                try budget.charge(work: Budget.add(Budget.multiply(row, 12), 16))
                var value = bernstein[row]
                for column in 0..<row {
                    value -= result[op.targetStart + column] * op.target[row * n + column]
                }
                let pivot = op.target[row * n + row]
                guard pivot.isFinite, pivot != 0 else { throw GeometryConversionError.toleranceRejected }
                value /= pivot
                guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                    throw GeometryConversionError.toleranceRejected
                }
                result[op.targetStart + row] = value
            }
        }
        return result
    }

    private static func extraction(knots: [Double], degree: Int, count: Int, span: Int,
        originalLower: Double, lower: Double, upper: Double, targetDegree: Int,
        tolerance: ModelingTolerance, budget: inout Budget) throws -> [Double] {
        let n = degree + 1
        // The selected-basis implementation retains basis/derivative/workspace
        // rows, COW row writes, and a replacement workspace row per derivative.
        let rowWords = (MemoryLayout<[Double]>.stride + 7) / 8
        let returnedWords = (MemoryLayout<BSplineBasis.NonzeroValues>.stride + 7) / 8
        let squares = try Budget.multiply(n, n)
        let replacements = try Budget.multiply(squares, degree)
        let ownerWords = try Budget.add(Budget.multiply(3 * n + 2, rowWords), Budget.multiply(n, returnedWords))
        try budget.charge(scalars: Budget.add(Budget.add(Budget.multiply(squares, 4), replacements),
            Budget.add(Budget.multiply(n, 4), ownerWords)),
            work: Budget.add(Budget.multiply(knots.count, 4),
                Budget.add(Budget.multiply(squares, 24), Budget.multiply(replacements, 24))))
        let derivatives = try BSplineBasis.nonzeroDerivativeValues(parameter: originalLower,
            degree: degree, throughDerivativeOrder: degree, knots: knots,
            count: count, owningSpan: span, tolerance: tolerance)
        let size = try Budget.multiply(targetDegree + 1, n)
        try budget.charge(scalars: size, work: size)
        var values = Array(repeating: 0.0, count: size)
        let delta = lower - originalLower, width = upper - lower
        guard delta.isFinite, width.isFinite, width > 0 else { throw GeometryConversionError.toleranceRejected }
        for row in 0...targetDegree {
            for column in 0..<n {
                var coefficient = 0.0
                for order in 0...min(row, degree) {
                    var translatedPower = 0.0
                    for originalOrder in order...degree {
                        try budget.charge(work: 16 + 2 * (originalOrder - order) + 2 * originalOrder)
                        translatedPower += derivatives[originalOrder].values[column]
                            / factorial(originalOrder) * choose(originalOrder, order)
                            * power(delta, originalOrder - order)
                    }
                    try budget.charge(work: 12 + 2 * order)
                    coefficient += translatedPower * power(width, order)
                        * choose(row, order) / choose(targetDegree, order)
                }
                guard coefficient.isFinite else { throw GeometryConversionError.toleranceRejected }
                values[row * n + column] = coefficient
            }
        }
        return values
    }

    private static func power(_ value: Double, _ order: Int) -> Double {
        var result = 1.0
        for _ in 0..<order { result *= value }
        return result
    }

    private static func factorial(_ order: Int) -> Double {
        var result = 1.0
        if order > 1 { for index in 2...order { result *= Double(index) } }
        return result
    }

    private static func choose(_ n: Int, _ k: Int) -> Double {
        if k == 0 || k == n { return 1 }
        // Every supported order is at most three.
        return Double(n)
    }
}
