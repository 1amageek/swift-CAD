import CADCore

package enum SurfaceFittingLeastSquares {
    package static func solve(
        objective: [Double], target: [Double],
        constraints: [Double], values: [Double], columns: Int,
        relativeRankTolerance: Double, constraintTolerance: Double,
        maximumElements: Int
    ) throws -> [Double] {
        try solve(objective: objective, targets: [target], constraints: constraints,
            values: [values], columns: columns, relativeRankTolerance: relativeRankTolerance,
            constraintTolerance: constraintTolerance, maximumElements: maximumElements)[0]
    }

    /// Right-hand sides share both QR factorizations, including XYZ surface coordinates.
    package static func solve(
        objective: [Double], targets: [[Double]],
        constraints: [Double], values: [[Double]], columns: Int,
        relativeRankTolerance: Double, constraintTolerance: Double,
        maximumElements: Int
    ) throws -> [[Double]] {
        guard columns > 0, let firstTarget = targets.first, let firstValue = values.first,
              targets.count == values.count,
              relativeRankTolerance.isFinite, relativeRankTolerance > 0,
              relativeRankTolerance < 1, constraintTolerance.isFinite, constraintTolerance >= 0 else {
            throw failure(.invalidInput, "Surface fitting requires matching finite objective and equality inputs.")
        }
        let rows = firstTarget.count
        let equalityRows = firstValue.count
        let objectiveCount = rows.multipliedReportingOverflow(by: columns)
        let constraintCount = equalityRows.multipliedReportingOverflow(by: columns)
        guard !objectiveCount.overflow, !constraintCount.overflow,
              objectiveCount.partialValue == objective.count,
              constraintCount.partialValue == constraints.count,
              targets.allSatisfy({ $0.count == rows }),
              values.allSatisfy({ $0.count == equalityRows }) else {
            throw failure(.invalidInput, "Surface fitting right-hand side dimensions do not match.")
        }
        let outputCount = columns.multipliedReportingOverflow(by: targets.count)
        guard maximumElements > 0, !outputCount.overflow,
              outputCount.partialValue <= maximumElements else {
            throw failure(.resourceLimitExceeded, "Surface fitting exceeded its solution storage budget.")
        }
        var remaining = maximumElements - outputCount.partialValue
        func charge(_ count: Int) throws {
            guard count <= remaining else {
                throw failure(.resourceLimitExceeded, "Surface fitting exceeded its matrix element budget.")
            }
            remaining -= count
        }
        try charge(objective.count)
        try charge(constraints.count)
        for rhs in targets { try charge(rhs.count) }
        for rhs in values { try charge(rhs.count) }
        guard objective.allSatisfy(\.isFinite), constraints.allSatisfy(\.isFinite),
              targets.allSatisfy({ $0.allSatisfy(\.isFinite) }),
              values.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw failure(.invalidInput, "Surface fitting requires finite matrix and right-hand side coefficients.")
        }
        guard equalityRows > 0 else {
            guard rows > 0 else {
                throw failure(.singularSystem, "Surface fitting has no determining equations.")
            }
            let qr = try SurfaceFittingQR(coefficients: objective, rows: rows, columns: columns,
                relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
            return try targets.map { try qr.solveFullRankLeastSquares($0) }
        }

        var transpose = Array(repeating: 0.0, count: constraints.count)
        for row in 0..<equalityRows {
            for column in 0..<columns {
                transpose[column * equalityRows + row] = constraints[row * columns + column]
            }
        }
        let equality = try SurfaceFittingQR(coefficients: transpose, rows: columns, columns: equalityRows,
            relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
        let freeCount = columns - equality.rank
        guard rows >= freeCount else {
            throw failure(.singularSystem, "Surface fitting objective does not determine the free coordinates.")
        }
        let magnitude = max(objective.reduce(0.0) { max($0, abs($1)) },
            targets.reduce(0.0) { max($0, $1.reduce(0.0) { max($0, abs($1)) }) })
        let scale = magnitude == 0 ? 1 : magnitude
        let reducedQR: SurfaceFittingQR?
        if freeCount > 0 {
            var reduced = Array(repeating: 0.0, count: rows * freeCount)
            for free in 0..<freeCount {
                var unit = Array(repeating: 0.0, count: columns)
                unit[equality.rank + free] = 1
                let direction = try equality.applyingQ(to: unit)
                for row in 0..<rows {
                    var coefficient = 0.0
                    for column in 0..<columns {
                        coefficient += (objective[row * columns + column] / scale) * direction[column]
                    }
                    reduced[row * freeCount + free] = coefficient
                }
            }
            guard reduced.allSatisfy(\.isFinite) else {
                throw failure(.resourceLimitExceeded, "Surface fitting reduced objective exceeded finite arithmetic range.")
            }
            reducedQR = try SurfaceFittingQR(coefficients: reduced, rows: rows, columns: freeCount,
                relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
        } else {
            reducedQR = nil
        }

        return try targets.indices.map { rhs in
            var coordinates = Array(repeating: 0.0, count: columns)
            for row in 0..<equality.rank {
                var value = values[rhs][equality.permutation[row]] / equality.scale
                for column in 0..<row {
                    value -= try equality.upperCoefficient(row: column, column: row) * coordinates[column]
                }
                coordinates[row] = value / (try equality.upperCoefficient(row: row, column: row))
            }
            guard coordinates.allSatisfy(\.isFinite) else {
                throw failure(.resourceLimitExceeded, "Surface fitting equality solve exceeded finite arithmetic range.")
            }
            let particular = try equality.applyingQ(to: coordinates)
            try verify(particular, constraints: constraints, values: values[rhs], tolerance: constraintTolerance)
            guard let reducedQR else { return particular }
            var residual = targets[rhs].map { $0 / scale }
            for row in 0..<rows {
                for column in 0..<columns {
                    residual[row] -= (objective[row * columns + column] / scale) * particular[column]
                }
            }
            guard residual.allSatisfy(\.isFinite) else {
                throw failure(.resourceLimitExceeded, "Surface fitting reduced target exceeded finite arithmetic range.")
            }
            let free = try reducedQR.solveFullRankLeastSquares(residual)
            for index in free.indices { coordinates[equality.rank + index] = free[index] }
            let result = try equality.applyingQ(to: coordinates)
            try verify(result, constraints: constraints, values: values[rhs], tolerance: constraintTolerance)
            return result
        }
    }

    private static func verify(_ solution: [Double], constraints: [Double], values: [Double],
                               tolerance: Double) throws {
        for row in values.indices {
            var scale = max(1, abs(values[row]))
            for column in solution.indices { scale = max(scale, abs(constraints[row * solution.count + column])) }
            var residual = -values[row] / scale
            for column in solution.indices {
                residual += (constraints[row * solution.count + column] / scale) * solution[column]
            }
            guard residual.isFinite else {
                throw failure(.resourceLimitExceeded, "Surface fitting equality residual exceeded finite arithmetic range.")
            }
            guard abs(residual) <= tolerance / scale else {
                throw failure(.conflictingConstraints, "Surface fitting cannot satisfy every equality within its residual tolerance.")
            }
        }
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}
