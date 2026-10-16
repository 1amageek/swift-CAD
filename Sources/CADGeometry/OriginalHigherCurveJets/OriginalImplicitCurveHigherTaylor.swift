import CADCore

/// Original implicit chart coefficients from the retained root cover and source Jacobian.
struct OriginalImplicitCurveHigherTaylor {
    static func parameterJets(of curve: CertifiedImplicitIntersectionCurve,
        over range: ScalarInterval, order: Int, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        selectedOwningCellIndex: Int? = nil,
        preparedLocalizer: ImplicitCurveIntervalJetEncloser? = nil, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaIntervalTaylorScalarJet] {
        guard order >= 0, range.lower >= 0, range.upper <= 1, !curve.cells.isEmpty else {
            throw GeometryConversionError.invalidInput("Original higher implicit range must belong to its normalized retained graph.")
        }
        if let index = selectedOwningCellIndex {
            guard index >= 0, index < curve.cells.count else {
                throw GeometryConversionError.invalidInput("Original implicit owning cell index is outside its retained source graph.")
            }
        }
        let prepared = try preparedLocalizer ?? ImplicitCurveIntervalJetEncloser(localizing: curve,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        var aggregate: [SurfaceAreaIntervalTaylorScalarJet]?
        var visited = 0
        var retainedCell: Int?
        let selectedIndices = selectedOwningCellIndex.map { $0..<($0 + 1) } ?? curve.cells.indices
        for index in selectedIndices {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            let n = OutwardScalarInterval.exact(Double(curve.cells.count))
            let fraction = OutwardScalarInterval(lower: range.lower, upper: range.upper)
                * n - .exact(Double(index))
            guard let clipped = fraction.intersection(with: .init(lower: 0, upper: 1)),
                range.lower == range.upper || clipped.lower < clipped.upper else { continue }
            if let retainedCell, retainedCell != index {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Cross-cell implicit normalized
                // charts need exact common-root and requested-order chart-transition
                // receipts. Silhouette/contact callers may localize one retained cell;
                // one-sided derivative hulls cannot prove smooth global joins.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original implicit higher query crosses an uncertified smooth chart join.")
            }
            retainedCell = index
            visited += 1
            guard visited <= maximumSpanCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original higher implicit graph cover exhausted caller span admission.")
            }
            struct Cell { let range: ScalarInterval; let depth: Int }
            try OriginalCoefficientAllocation.reserve(count: 1, of: Cell.self, using: &execution)
            var pending = [Cell(range: try ScalarInterval(lower: clipped.lower, upper: clipped.upper), depth: 0)]
            var capacity = 1
            while let cell = pending.popLast() {
                try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
                var state = try prepared.prepareParameterEnclosure(of: curve, cellIndex: index,
                    overClosedInterval: cell.range, tolerance: tolerance, using: &execution)
                var localized: CertifiedImplicitParameterIntervalJet?
                var divide = false
                while localized == nil && !divide {
                    try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
                    switch try prepared.advanceParameterEnclosure(state, tolerance: tolerance,
                        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth - cell.depth,
                        remainingSourceDepth: remainingSourceDepth, using: &execution) {
                    case .enclosed(let jet): localized = jet
                    case .contracted(let next): state = next
                    case .subdivisionRequired: divide = true
                    }
                }
                guard let localized else {
                    guard cell.depth < maximumSubdivisionDepth, cell.range.lower < cell.range.midpoint,
                          cell.range.midpoint < cell.range.upper else {
                        throw GeometryConversionError.resourceLimitExceeded("Original higher implicit root localization exhausted caller depth.")
                    }
                    let required = pending.count.addingReportingOverflow(2)
                    guard !required.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original localization stack size overflows.") }
                    if required.partialValue > capacity {
                        let grown = capacity.multipliedReportingOverflow(by: 2)
                        guard !grown.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original localization stack capacity overflows.") }
                        capacity = max(required.partialValue, grown.partialValue)
                        try OriginalCoefficientAllocation.reserve(count: capacity, of: Cell.self, using: &execution)
                        pending.reserveCapacity(capacity)
                    }
                    pending.append(Cell(range: try ScalarInterval(lower: cell.range.midpoint, upper: cell.range.upper), depth: cell.depth + 1))
                    pending.append(Cell(range: try ScalarInterval(lower: cell.range.lower, upper: cell.range.midpoint), depth: cell.depth + 1))
                    continue
                }
                let jets = try solve(curve: curve, cellIndex: index, localized: localized,
                    order: order, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth - cell.depth, remainingSourceDepth: remainingSourceDepth, using: &execution, maximumAlgebraicDepth: maximumAlgebraicDepth)
                if let previous = aggregate {
                    try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceAreaIntervalTaylorScalarJet.self, using: &execution)
                    var next: [SurfaceAreaIntervalTaylorScalarJet] = []; next.reserveCapacity(4)
                    for coordinate in 0..<4 {
                        var value = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                            tolerance: tolerance, using: &execution)
                        for k in 0...order {
                            try execution.consumeWork(1)
                            try value.set(previous[coordinate].coefficient(k, 0).union(jets[coordinate].coefficient(k, 0)), k, 0)
                        }
                        next.append(value)
                    }
                    aggregate = next
                } else { aggregate = jets }
            }
        }
        guard let aggregate else { throw GeometryConversionError.invalidInput("Original higher implicit query has no retained root cover.") }
        return aggregate
    }

    private static func solve(curve: CertifiedImplicitIntersectionCurve, cellIndex: Int,
        localized: CertifiedImplicitParameterIntervalJet, order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution,
        maximumAlgebraicDepth: Int?) throws -> [SurfaceAreaIntervalTaylorScalarJet] {
        try OriginalCoefficientAllocation.reserve(count: localized.coordinates.count, of: SurfaceAreaIntervalTaylorScalarJet.self, using: &execution)
        var q: [SurfaceAreaIntervalTaylorScalarJet] = []; q.reserveCapacity(localized.coordinates.count)
        for coordinate in localized.coordinates {
            var field = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            for k in 0...min(order, 3) {
                let derivative: ScalarInterval
                switch k {
                case 0: derivative = coordinate.value
                case 1: derivative = coordinate.firstDerivative
                case 2: derivative = coordinate.secondDerivative
                default: derivative = coordinate.thirdDerivative
                }
                var value = OutwardScalarInterval(lower: derivative.lower, upper: derivative.upper)
                if k > 1 { for i in 2...k {
                    guard let scaled = value.divided(by: .exact(Double(i))) else {
                        throw GeometryConversionError.resourceLimitExceeded("Original implicit factorial scaling failed.")
                    }
                    value = scaled
                } }
                try execution.consumeWork(1); try field.set(value, k, 0)
            }
            q.append(field)
        }
        if order <= 3 { return q }
        func interval(_ coordinate: Int) throws -> ScalarInterval {
            let value = try q[coordinate].coefficient(0, 0)
            return try .init(lower: value.lower, upper: value.upper)
        }
        let first = try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: curve.firstSurface,
            over: SurfaceParameterBox(u: interval(0), v: interval(1)), tolerance: tolerance,
            throughOrder: order, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32, using: &execution)
        let second = try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: curve.secondSurface,
            over: SurfaceParameterBox(u: interval(2), v: interval(3)), tolerance: tolerance,
            throughOrder: order, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32, using: &execution)
        func vector(_ source: SurfaceAreaIntervalTaylorVectorJet, _ u: Int, _ v: Int)
            throws -> IntervalVector3DBounds {
            try .init(x: source.x.coefficient(u, v), y: source.y.coefficient(u, v), z: source.z.coefficient(u, v))
        }
        try OriginalCoefficientAllocation.reserve(count: 4, of: IntervalVector3DBounds.self, using: &execution)
        let columns = try [vector(first, 1, 0), vector(first, 0, 1),
            vector(second, 1, 0) * .exact(-1), vector(second, 0, 1) * .exact(-1)]
        let free = curve.cells[cellIndex].freeParameter.rawValue
        try OriginalCoefficientAllocation.reserve(count: 3, of: Int.self, using: &execution)
        var dependent: [Int] = []; dependent.reserveCapacity(3)
        for index in 0..<4 { try execution.consumeWork(1); if index != free { dependent.append(index) } }
        let a = columns[dependent[0]], b = columns[dependent[1]], c = columns[dependent[2]]
        let determinant = a.dot(b.cross(c))
        guard determinant.excludesZero else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Original higher implicit Jacobian is not certified invertible on its retained root box.")
        }
        for k in 4...order {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            let lhs = try OriginalCurveTaylorComposition.compose(surface: first, u: q[0], v: q[1],
                order: order, using: &execution)
            let rhs = try OriginalCurveTaylorComposition.compose(surface: second, u: q[2], v: q[3],
                order: order, using: &execution)
            let residual = try IntervalVector3DBounds(x: rhs.x.coefficient(k, 0) - lhs.x.coefficient(k, 0),
                y: rhs.y.coefficient(k, 0) - lhs.y.coefficient(k, 0),
                z: rhs.z.coefficient(k, 0) - lhs.z.coefficient(k, 0))
            try OriginalCoefficientAllocation.reserve(count: 3, of: OutwardScalarInterval.self, using: &execution)
            let numerators = [residual.dot(b.cross(c)), a.dot(residual.cross(c)), a.dot(b.cross(residual))]
            for i in 0..<3 {
                try execution.consumeWork(1)
                guard let solution = numerators[i].divided(by: determinant), solution.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original higher implicit coefficient solve exceeded finite arithmetic.")
                }
                try q[dependent[i]].set(solution, k, 0)
            }
            try q[free].set(.exact(0), k, 0)
        }
        return q
    }
}
