import CADCore

/// Immutable original native-span selection for a finite polynomial continuation law.
struct PreparedPolynomialSurfaceContinuationLaw: Sendable {
    typealias Preparation = NativePolynomialSurfacePositionPreparation
    typealias Budget = PolynomialSurfacePositionDifferenceNet.Budget

    struct Span: Sendable {
        let index: Int
        let lower: Double
        let upper: Double
    }

    struct Cell {
        let lower: Double
        let upper: Double
        let sourceIndex: Int
        let candidateSpan: Int
    }

    let uSpans: [Span]
    let vSpans: [Span]

    init(validated surface: BSplineSurface3D, budget: inout Budget) throws {
        try budget.charge(scalars: (MemoryLayout<Self>.stride + 7) / 8, work: 4)
        uSpans = try Self.spans(knots: surface.uKnots, degree: surface.uDegree,
            count: surface.uControlPointCount, budget: &budget)
        vSpans = try Self.spans(knots: surface.vKnots, degree: surface.vDegree,
            count: surface.vControlPointCount, budget: &budget)
    }

    func originalCells(u: Bool, budget: inout Budget) throws -> [Preparation.AxisCell] {
        let spans = u ? uSpans : vSpans
        let words = (MemoryLayout<Preparation.AxisCell>.stride + 7) / 8
        try budget.charge(scalars: Budget.multiply(spans.count, words), work: Budget.multiply(spans.count, 8))
        var result: [Preparation.AxisCell] = []
        result.reserveCapacity(spans.count)
        for span in spans {
            try Task.checkCancellation()
            result.append(.init(lower: span.lower, upper: span.upper,
                sourceSpan: span.index, candidateSpan: span.index))
        }
        return result
    }

    func commonCells(candidate: Self, u: Bool, interval: ScalarInterval,
        budget: inout Budget) throws -> [Cell] {
        let original = u ? uSpans : vSpans, target = u ? candidate.uSpans : candidate.vSpans
        var sourceIndex = 0, candidateIndex = 0, lower = interval.lower
        var cells: [Cell] = []
        while lower < interval.upper {
            try budget.charge(work: 12)
            while sourceIndex + 1 < original.count {
                try budget.charge(work: 4)
                if original[sourceIndex].upper > lower { break }
                sourceIndex += 1
            }
            while candidateIndex + 1 < target.count {
                try budget.charge(work: 4)
                if target[candidateIndex].upper > lower { break }
                candidateIndex += 1
            }
            guard target[candidateIndex].lower <= lower, target[candidateIndex].upper > lower else {
                throw Budget.exhausted()
            }
            // The first/last polynomial continues beyond its support; only genuine
            // internal source boundaries partition that law. Candidate stays contained.
            let sourceUpper = sourceIndex + 1 < original.count
                ? original[sourceIndex].upper : interval.upper
            let upper = min(interval.upper, sourceUpper, target[candidateIndex].upper)
            guard upper.isFinite, upper > lower else { throw Budget.exhausted() }
            let words = (MemoryLayout<Cell>.stride + 7) / 8
            try budget.charge(scalars: Budget.multiply(words, 4), work: 4)
            cells.append(Cell(lower: lower, upper: upper, sourceIndex: sourceIndex,
                candidateSpan: target[candidateIndex].index))
            lower = upper
        }
        return cells
    }

    func candidateCells(_ cells: [Cell], u: Bool, budget: inout Budget) throws -> [Preparation.AxisCell] {
        let spans = u ? uSpans : vSpans
        let words = (MemoryLayout<Preparation.AxisCell>.stride + 7) / 8
        try budget.charge(scalars: Budget.multiply(cells.count, words), work: Budget.multiply(cells.count, 8))
        var result: [Preparation.AxisCell] = []
        result.reserveCapacity(cells.count)
        for cell in cells {
            try Task.checkCancellation()
            result.append(.init(lower: cell.lower, upper: cell.upper,
                sourceSpan: spans[cell.sourceIndex].index, candidateSpan: cell.candidateSpan))
        }
        return result
    }

    static func ratios(cell: Cell, span: Span, budget: inout Budget) throws
        -> (OutwardScalarInterval, OutwardScalarInterval) {
        try budget.charge(scalars: 12, work: 64)
        let lower = OutwardScalarInterval.exact(span.lower)
        let width = OutwardScalarInterval.exact(span.upper) - lower
        guard let a = (OutwardScalarInterval.exact(cell.lower) - lower).divided(by: width),
              let b = (OutwardScalarInterval.exact(cell.upper) - lower).divided(by: width),
              a.isFinite, b.isFinite else { throw Budget.exhausted() }
        return (a, b)
    }

    private static func spans(knots: [Double], degree: Int, count: Int,
        budget: inout Budget) throws -> [Span] {
        var result: [Span] = []
        for index in degree..<count {
            try budget.charge(work: 4)
            if knots[index + 1] > knots[index] {
                let words = (MemoryLayout<Span>.stride + 7) / 8
                try budget.charge(scalars: Budget.multiply(words, 4), work: 4)
                result.append(Span(index: index, lower: knots[index], upper: knots[index + 1]))
            }
        }
        guard !result.isEmpty else { throw Budget.exhausted() }
        return result
    }
}
