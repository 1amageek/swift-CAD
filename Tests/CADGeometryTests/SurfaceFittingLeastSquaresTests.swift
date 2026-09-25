import CADCore
import CADGeometry
import Testing

@Suite("Surface fitting equality constrained least squares", .timeLimit(.minutes(1)))
struct SurfaceFittingLeastSquaresTests {
    @Test func sharedFactorizationMatchesIndependentCoordinates() throws {
        let targets = [[2.0, 0], [0, 4], [-3, 1]]
        let values = [[1.0, 2], [2, 4], [-1, -2]]
        let result = try SurfaceFittingLeastSquares.solve(
            objective: [1, 0, 0, 1], targets: targets,
            constraints: [1, 1, 2, 2], values: values, columns: 2,
            relativeRankTolerance: 1e-12, constraintTolerance: 1e-11, maximumElements: 100)
        for rhs in result.indices {
            let independent = try solve([1, 0, 0, 1], targets[rhs], [1, 1, 2, 2], values[rhs])
            for column in 0..<2 { #expect(abs(result[rhs][column] - independent[column]) < 1e-12) }
        }
        #expect(abs(result[0][0] - 1.5) < 1e-12)
        #expect(abs(result[1][1] - 3) < 1e-12)
        #expect(abs(result[2][0] + 2.5) < 1e-12)
    }

    @Test func batchedDimensionsAndStorageAreChecked() {
        func batch(_ targets: [[Double]], _ values: [[Double]], budget: Int = 100) throws {
            _ = try SurfaceFittingLeastSquares.solve(objective: [1, 0, 0, 1], targets: targets,
                constraints: [1, 1], values: values, columns: 2,
                relativeRankTolerance: 1e-12, constraintTolerance: 1e-11, maximumElements: budget)
        }
        #expect(throws: KernelError.self) { try batch([], []) }
        #expect(throws: KernelError.self) { try batch([[0, 0]], [[1], [2]]) }
        #expect(throws: KernelError.self) { try batch([[0, 0], [0]], [[1], [2]]) }
        #expect(throws: KernelError.self) { try batch([[0, 0], [0, 0]], [[1], [.nan]]) }
        #expect(throws: KernelError.self) { try batch([[0, 0], [0, 0]], [[1], [2]], budget: 15) }
    }

    private func solve(_ a: [Double], _ b: [Double], _ c: [Double], _ d: [Double],
                       columns: Int = 2, tolerance: Double = 1e-11, budget: Int = 100) throws -> [Double] {
        try SurfaceFittingLeastSquares.solve(objective: a, target: b, constraints: c, values: d,
            columns: columns, relativeRankTolerance: 1e-12, constraintTolerance: tolerance,
            maximumElements: budget)
    }

    @Test(arguments: [1e-150, 1.0, 1e150])
    func constrainedOptimumWithRedundantRows(scale: Double) throws {
        // Closest point to (2, 0) on x + y = 1 is (1.5, -0.5).
        let result = try solve([1, 0, 0, 1], [2, 0],
            [scale, scale, 2 * scale, 2 * scale], [scale, 2 * scale], tolerance: scale * 1e-11)
        #expect(abs(result[0] - 1.5) < 1e-12)
        #expect(abs(result[1] + 0.5) < 1e-12)
    }

    @Test func independentAndEmptyConstraints() throws {
        let determined = try solve([], [], [1, 0, 0, 1, 2, 2], [3, -2, 2])
        #expect(abs(determined[0] - 3) < 1e-12)
        #expect(abs(determined[1] + 2) < 1e-12)
        let unconstrained = try solve([1, 0, 0, 1], [3, -2], [], [])
        #expect(unconstrained == [3, -2])
        let zero = try solve([1, 0, 0, 1], [3, -2], [0, 0], [0])
        #expect(zero == [3, -2])
    }

    @Test func contradictoryAndNonuniqueSystemsFail() throws {
        #expect(throws: KernelError.self) { try solve([1, 0, 0, 1], [0, 0], [1, 1, 2, 2], [1, 3]) }
        #expect(throws: KernelError.self) { try solve([0, 0], [0], [1, 1], [1]) }
        #expect(throws: KernelError.self) { try solve([], [], [1, 1], [1]) }
        #expect(throws: KernelError.self) { try solve([], [], [], []) }
        #expect(throws: KernelError.self) { try solve([1, 0, 0, 1], [0, 0], [0, 0], [1]) }
    }

    @Test func malformedAndOverBudgetInputsFail() throws {
        #expect(throws: KernelError.self) { try solve([1], [0], [], []) }
        #expect(throws: KernelError.self) { try solve([1, 0], [0], [1], [1]) }
        #expect(throws: KernelError.self) { try solve([1, .nan], [0], [], []) }
        #expect(throws: KernelError.self) { try solve([1, 0, 0, 1], [0, 0], [1, 1], [1], budget: 5) }
        #expect(throws: KernelError.self) { try solve([], [], [], [], columns: Int.max) }
    }
}
