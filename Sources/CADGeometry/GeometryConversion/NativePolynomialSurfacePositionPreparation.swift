import CADCore

/// Selected-original polynomial coefficients, without a rounded replacement surface.
struct NativePolynomialSurfacePositionPreparation {
    typealias Net = PolynomialSurfacePositionDifferenceNet
    typealias Budget = Net.Budget
    typealias Coefficient = Net.Coefficient
    typealias Interval = OutwardScalarInterval

    struct AxisCell {
        let lower: Double
        let upper: Double
        let sourceSpan: Int
        let candidateSpan: Int
    }

    fileprivate struct AxisOperator {
        let start: Int
        let inputCount: Int
        let outputCount: Int
        let values: [Interval]
    }

    struct Section {
        fileprivate let uCount: Int
        fileprivate let inputVCount: Int
        fileprivate let intermediate: [Coefficient]
        fileprivate let vOperators: [AxisOperator]

        func net(vIndex: Int, budget: inout Budget) throws -> Net {
            let op = vOperators[vIndex]
            let count = try Budget.multiply(uCount, op.outputCount)
            let terms = try Budget.multiply(count, op.inputCount)
            try budget.coefficients(count)
            try budget.charge(scalars: (MemoryLayout<Net>.stride + 7) / 8, work: 4)
            // Three scalar interval products per vector term allocate 12 doubles.
            try budget.charge(scalars: Budget.multiply(terms, 12),
                work: Budget.add(Budget.multiply(terms, 3 * 12 + 3 * 4 + 12), Budget.multiply(count, 8)))
            var values = Array(repeating: Self.zero, count: count)
            for v in 0..<op.outputCount {
                try Task.checkCancellation()
                for u in 0..<uCount {
                    var value = Self.zero
                    for i in 0..<op.inputCount {
                        value = NativePolynomialSurfacePositionPreparation.add(value, intermediate[(op.start + i) * uCount + u] * op.values[v * op.inputCount + i])
                    }
                    values[v * uCount + u] = value
                }
            }
            return Net(prechargedUCount: uCount, vCount: op.outputCount, values: values)
        }

        private static var zero: Coefficient { .init(x: .exact(0), y: .exact(0), z: .exact(0)) }
    }

    private let surface: BSplineSurface3D
    private let origin: Point3D
    private let uOperators: [AxisOperator]
    private let vOperators: [AxisOperator]

    static func hasCommonWeight(_ surface: BSplineSurface3D,
        budget: inout PreparedBSplineSurfaceDifferentialCost.Budget) throws -> Bool {
        let count = try PreparedBSplineSurfaceDifferentialCost.Budget.product(
            surface.uControlPointCount, surface.vControlPointCount)
        try budget.charge(work: PreparedBSplineSurfaceDifferentialCost.Budget.sum(count, surface.weights.count, 4))
        let weight = surface.weights[0][0]
        for row in surface.weights {
            try Task.checkCancellation()
            for value in row where value != weight { return false }
        }
        return true
    }

    /// A cursor merge retains exact original spans, including both closed knot sides.
    static func commonCells(sourceKnots: [Double], sourceDegree: Int, sourceCount: Int,
        candidateKnots: [Double], candidateDegree: Int, candidateCount: Int,
        interval: ScalarInterval, budget: inout Budget) throws -> [AxisCell] {
        var source = sourceDegree, candidate = candidateDegree
        var lower = interval.lower
        var cells: [AxisCell] = []
        while lower < interval.upper {
            while source < sourceCount {
                try budget.charge(work: 4)
                if sourceKnots[source + 1] > lower { break }
                source += 1
            }
            while candidate < candidateCount {
                try budget.charge(work: 4)
                if candidateKnots[candidate + 1] > lower { break }
                candidate += 1
            }
            try budget.charge(work: 12)
            guard source < sourceCount, candidate < candidateCount,
                  sourceKnots[source] <= lower, candidateKnots[candidate] <= lower else { throw Budget.exhausted() }
            let upper = min(interval.upper, sourceKnots[source + 1], candidateKnots[candidate + 1])
            guard upper > lower, upper.isFinite else { throw Budget.exhausted() }
            // Four fields with fourfold cumulative backing-growth reservation.
            try budget.charge(scalars: 16, work: 4)
            cells.append(AxisCell(lower: lower, upper: upper, sourceSpan: source, candidateSpan: candidate))
            lower = upper
        }
        return cells
    }

    init(surface: BSplineSurface3D, origin: Point3D, uCells: [AxisCell], vCells: [AxisCell],
        candidate: Bool, uDegree: Int, vDegree: Int, tolerance: ModelingTolerance,
        budget: inout Budget) throws {
        self.surface = surface
        self.origin = origin
        // COW source buffers are retained; concrete owner payload and axis-array owners are paid.
        try budget.charge(scalars: (MemoryLayout<Self>.stride + 7) / 8, work: 8)
        uOperators = try Self.operators(cells: uCells, candidate: candidate, knots: surface.uKnots,
            degree: surface.uDegree, count: surface.uControlPointCount, targetDegree: uDegree,
            tolerance: tolerance, budget: &budget)
        vOperators = try Self.operators(cells: vCells, candidate: candidate, knots: surface.vKnots,
            degree: surface.vDegree, count: surface.vControlPointCount, targetDegree: vDegree,
            tolerance: tolerance, budget: &budget)
    }

    func section(uIndex: Int, budget: inout Budget) throws -> Section {
        let op = uOperators[uIndex]
        let count = try Budget.multiply(op.outputCount, surface.vControlPointCount)
        let terms = try Budget.multiply(count, op.inputCount)
        try budget.coefficients(count)
        try budget.charge(scalars: Budget.multiply(terms, 12),
            work: Budget.add(Budget.multiply(terms, 3 * 4 + 3 * 12 + 3 * 4 + 12), Budget.multiply(count, 8)))
        try budget.charge(scalars: (MemoryLayout<Section>.stride + 7) / 8, work: 4)
        var values = Array(repeating: Coefficient(x: .exact(0), y: .exact(0), z: .exact(0)), count: count)
        for row in 0..<surface.vControlPointCount {
            try Task.checkCancellation()
            for u in 0..<op.outputCount {
                var value = Coefficient(x: .exact(0), y: .exact(0), z: .exact(0))
                for i in 0..<op.inputCount {
                    let point = surface.controlPoints[row][op.start + i]
                    // BOTH inputs use the same original source origin, preserving translation correlation.
                    let relative = Coefficient(x: .exact(point.x) - .exact(origin.x),
                        y: .exact(point.y) - .exact(origin.y), z: .exact(point.z) - .exact(origin.z))
                    value = Self.add(value, relative * op.values[u * op.inputCount + i])
                }
                values[row * op.outputCount + u] = value
            }
        }
        return Section(uCount: op.outputCount, inputVCount: surface.vControlPointCount,
            intermediate: values, vOperators: vOperators)
    }

    private static func add(_ a: Coefficient, _ b: Coefficient) -> Coefficient {
        Coefficient(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }

    private static func operators(cells: [AxisCell], candidate: Bool, knots: [Double],
        degree: Int, count: Int, targetDegree: Int, tolerance: ModelingTolerance,
        budget: inout Budget) throws -> [AxisOperator] {
        let words = (MemoryLayout<AxisOperator>.stride + 7) / 8
        try budget.charge(scalars: Budget.multiply(cells.count, words), work: Budget.multiply(cells.count, 4))
        var operators: [AxisOperator] = []
        operators.reserveCapacity(cells.count)
        let n = try Budget.add(degree, 1), outputCount = try Budget.add(targetDegree, 1)
        let matrixCount = try Budget.multiply(n, outputCount)
        for cell in cells {
            try Task.checkCancellation()
            // Selected basis recurrence owns all previous/next rows, COW row writes,
            // two divisions per side and every interval multiply scratch array.
            var basisScalars = try Budget.multiply(n, 2)
            var basisWork = try Budget.add(Budget.multiply(knots.count, 3), 64)
            if degree > 0 {
                for p in 1...degree {
                    let columns = try Budget.add(p, 1)
                    let rowStorage = try Budget.multiply(try Budget.multiply(2, n), columns)
                    let sideScratch = try Budget.multiply(try Budget.multiply(2, columns), try Budget.add(12, Budget.multiply(4, columns)))
                    basisScalars = try Budget.add(basisScalars, Budget.add(rowStorage, sideScratch))
                    let sideWork = try Budget.multiply(try Budget.multiply(2, columns), try Budget.add(48, Budget.multiply(columns, 16)))
                    basisWork = try Budget.add(basisWork, sideWork)
                }
            }
            // Returned basis-row owners retain their existing coefficient buffers.
            basisScalars = try Budget.add(basisScalars, Budget.multiply(n, (MemoryLayout<BSplineBasis.NonzeroIntervalValues>.stride + 7) / 8))
            // Initial and each recurrence's outer row-owner array are distinct buffers.
            let rowOwnerWords = (MemoryLayout<[Interval]>.stride + 7) / 8
            basisScalars = try Budget.add(basisScalars, Budget.multiply(try Budget.multiply(n, n), rowOwnerWords))
            try budget.charge(scalars: basisScalars, work: basisWork)
            let span = candidate ? cell.candidateSpan : cell.sourceSpan
            let derivatives = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: cell.lower,
                degree: degree, throughDerivativeOrder: degree, knots: knots, count: count,
                owningSpan: span, tolerance: tolerance)
            // One scale table and one operator table, each with two fields per interval.
            try budget.charge(scalars: Budget.multiply(matrixCount, 4), work: Budget.multiply(matrixCount, 4))
            var scales = Array(repeating: Interval.exact(0), count: matrixCount)
            let width = Interval.exact(cell.upper) - .exact(cell.lower)
            for j in 0..<outputCount {
                scales[j * n] = .exact(1)
                let order = min(j, degree)
                if order > 0 {
                    for p in 1...order {
                        // Three products create 12 scratch doubles; division creates six.
                        try budget.charge(scalars: 18, work: 3 * 12 + 20 + 8)
                        let numerator = scales[j * n + p - 1] * .exact(Double(j - p + 1)) * width
                        let denominator = Interval.exact(Double(p)) * .exact(Double(targetDegree - p + 1))
                        guard let scale = numerator.divided(by: denominator), scale.isFinite else { throw Budget.exhausted() }
                        scales[j * n + p] = scale
                    }
                }
            }
            var values = Array(repeating: Interval.exact(0), count: matrixCount)
            for j in 0..<outputCount {
                for i in 0..<n {
                    let orders = try Budget.add(min(j, degree), 1)
                    try budget.charge(scalars: Budget.multiply(orders, 4), work: Budget.multiply(orders, 12 + 4 + 8))
                    var value = Interval.exact(0)
                    for p in 0..<orders { value = value + derivatives[p].values[i] * scales[j * n + p] }
                    guard value.isFinite else { throw Budget.exhausted() }
                    values[j * n + i] = value
                }
            }
            operators.append(AxisOperator(start: span - degree, inputCount: n, outputCount: outputCount, values: values))
        }
        return operators
    }
}
