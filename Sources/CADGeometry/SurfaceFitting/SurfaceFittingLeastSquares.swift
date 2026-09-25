import CADCore

package enum SurfaceFittingLeastSquares {
    package static func solve(
        objective: [Double], target: [Double],
        constraints: [Double], values: [Double], columns: Int,
        relativeRankTolerance: Double, constraintTolerance: Double,
        maximumElements: Int
    ) throws -> [Double] {
        let objectiveCount = target.count.multipliedReportingOverflow(by: columns)
        let constraintCount = values.count.multipliedReportingOverflow(by: columns)
        let combined = objective.count.addingReportingOverflow(constraints.count)
        guard columns > 0, !objectiveCount.overflow, !constraintCount.overflow,
              objectiveCount.partialValue == objective.count,
              constraintCount.partialValue == constraints.count,
              relativeRankTolerance.isFinite, relativeRankTolerance > 0,
              relativeRankTolerance < 1, constraintTolerance.isFinite,
              constraintTolerance >= 0,
              objective.allSatisfy(\.isFinite), target.allSatisfy(\.isFinite),
              constraints.allSatisfy(\.isFinite), values.allSatisfy(\.isFinite) else {
            throw failure(.invalidInput, "Surface fitting requires finite matching objective and equality matrices.")
        }
        guard maximumElements > 0, columns <= maximumElements,
              !combined.overflow, combined.partialValue <= maximumElements else {
            throw failure(.resourceLimitExceeded, "Surface fitting exceeded its matrix element budget.")
        }
        guard !values.isEmpty else {
            guard !target.isEmpty else {
                throw failure(.singularSystem, "Surface fitting has no determining equations.")
            }
            return try SurfaceFittingQR(coefficients: objective, rows: target.count, columns: columns,
                relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
                .solveFullRankLeastSquares(target)
        }

        var transpose = Array(repeating: 0.0, count: constraints.count)
        for row in values.indices {
            for column in 0..<columns {
                transpose[column * values.count + row] = constraints[row * columns + column]
            }
        }
        let equality = try SurfaceFittingQR(coefficients: transpose, rows: columns, columns: values.count,
            relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
        var coordinates = Array(repeating: 0.0, count: columns)
        for row in 0..<equality.rank {
            var value = values[equality.permutation[row]] / equality.scale
            for column in 0..<row {
                value -= try equality.upperCoefficient(row: column, column: row) * coordinates[column]
            }
            coordinates[row] = value / (try equality.upperCoefficient(row: row, column: row))
        }
        guard coordinates.allSatisfy(\.isFinite) else {
            throw failure(.resourceLimitExceeded, "Surface fitting equality solve exceeded finite arithmetic range.")
        }
        let particular = try equality.applyingQ(to: coordinates)
        try verify(particular, constraints: constraints, values: values, tolerance: constraintTolerance)
        let freeCount = columns - equality.rank
        guard freeCount > 0 else { return particular }
        guard target.count >= freeCount else {
            throw failure(.singularSystem, "Surface fitting objective does not determine the free coordinates.")
        }

        // Normalize both objective and target together; equality accuracy is not relaxed.
        let magnitude = max(objective.reduce(0.0) { max($0, abs($1)) },
                            target.reduce(0.0) { max($0, abs($1)) })
        let scale = magnitude == 0 ? 1 : magnitude
        var reduced = Array(repeating: 0.0, count: target.count * freeCount)
        var residual = target.map { $0 / scale }
        for row in target.indices {
            for column in 0..<columns {
                residual[row] -= (objective[row * columns + column] / scale) * particular[column]
            }
        }
        for free in 0..<freeCount {
            var unit = Array(repeating: 0.0, count: columns)
            unit[equality.rank + free] = 1
            let direction = try equality.applyingQ(to: unit)
            for row in target.indices {
                var coefficient = 0.0
                for column in 0..<columns {
                    coefficient += (objective[row * columns + column] / scale) * direction[column]
                }
                reduced[row * freeCount + free] = coefficient
            }
        }
        guard residual.allSatisfy(\.isFinite), reduced.allSatisfy(\.isFinite) else {
            throw failure(.resourceLimitExceeded, "Surface fitting reduced objective exceeded finite arithmetic range.")
        }
        let free = try SurfaceFittingQR(coefficients: reduced, rows: target.count, columns: freeCount,
            relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
            .solveFullRankLeastSquares(residual)
        for index in free.indices { coordinates[equality.rank + index] = free[index] }
        let result = try equality.applyingQ(to: coordinates)
        try verify(result, constraints: constraints, values: values, tolerance: constraintTolerance)
        return result
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
