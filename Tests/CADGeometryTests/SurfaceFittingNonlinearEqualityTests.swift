import CADCore
import CADGeometry
import Testing

@Suite("Nonlinear hard surface constraints", .timeLimit(.minutes(1)))
struct SurfaceFittingNonlinearEqualityTests {
    typealias Evaluation = SurfaceFittingNonlinearEquality.Evaluation

    private func solve(_ initial: [Double], evaluations: Int = 300, elements: Int = 1_000,
                       evaluate: ([Double]) throws -> Evaluation) throws -> SurfaceFittingNonlinearEquality.Result {
        try SurfaceFittingNonlinearEquality.solve(initial: initial, maximumStep: 1,
            constraintTolerance: 1e-10, relativeGradientTolerance: 1e-8,
            relativeRankTolerance: 1e-12, maximumEvaluations: evaluations,
            maximumElements: elements, evaluate: evaluate)
    }

    @Test func curvedConstraintConvergesToConstrainedStationarity() throws {
        let result = try solve([0.8, 0.6]) { x in
            Evaluation(objective: .init(residuals: [x[0] - 2, x[1]], jacobian: [1, 0, 0, 1]),
                constraints: .init(residuals: [x[0] * x[0] + x[1] * x[1] - 1], jacobian: [2 * x[0], 2 * x[1]]))
        }
        #expect(abs(result.parameters[0] - 1) < 1e-8)
        #expect(abs(result.parameters[1]) < 1e-8)
        #expect(abs(result.evaluation.constraints.residuals[0]) <= 1e-10)
        #expect(abs(result.evaluation.objective.residuals[0]) > 0.9)
        #expect(result.evaluations <= 300)
    }

    @Test(arguments: [1.0, 1_000.0])
    func objectiveWeightNeverRelaxesRedundantHardConstraints(weight: Double) throws {
        let result = try solve([0.5]) { x in
            let c = x[0] * x[0] - 1
            return Evaluation(objective: .init(residuals: [weight * (x[0] - 3)], jacobian: [weight]),
                constraints: .init(residuals: [c, 2 * c], jacobian: [2 * x[0], 4 * x[0]]))
        }
        #expect(abs(result.parameters[0] - 1) < 1e-9)
        #expect(result.evaluation.constraints.residuals.allSatisfy { abs($0) <= 1e-10 })
    }

    @Test func contradictoryLinearizationsAndUnderdeterminedObjectivesFail() throws {
        #expect(throws: KernelError.self) {
            try solve([0.0]) { x in
                Evaluation(objective: .init(residuals: [x[0]], jacobian: [1]),
                    constraints: .init(residuals: [x[0] - 1, x[0] - 2], jacobian: [1, 1]))
            }
        }
        #expect(throws: KernelError.self) {
            try solve([0.0, 0.0]) { x in
                Evaluation(objective: .init(residuals: [x[0] + x[1] - 1], jacobian: [1, 1]),
                    constraints: .init(residuals: [], jacobian: []))
            }
        }
    }

    @Test func stationarityRequiresFeasibilityAndUnconstrainedInputWorks() throws {
        let result = try solve([0.0]) { x in
            Evaluation(objective: .init(residuals: [x[0] - 2], jacobian: [1]),
                constraints: .init(residuals: [], jacobian: []))
        }
        #expect(abs(result.parameters[0] - 2) < 1e-10)
        #expect(throws: KernelError.self) {
            try solve([0.0]) { _ in
                Evaluation(objective: .init(residuals: [0], jacobian: [1]),
                    constraints: .init(residuals: [1], jacobian: [0]))
            }
        }
    }

    @Test func trialBudgetAndCancellationPropagateWithoutReturningAnIterate() throws {
        var calls = 0
        #expect(throws: KernelError.self) {
            try solve([0.0], evaluations: 1) { x in
                calls += 1
                return Evaluation(objective: .init(residuals: [x[0] - 2], jacobian: [1]),
                    constraints: .init(residuals: [], jacobian: []))
            }
        }
        #expect(calls == 1)
        #expect(throws: CancellationError.self) {
            try solve([0.0]) { _ in throw CancellationError() }
        }
        #expect(throws: KernelError.self) {
            try solve([0.0], elements: 1) { x in
                Evaluation(objective: .init(residuals: [x[0]], jacobian: [1]),
                    constraints: .init(residuals: [], jacobian: []))
            }
        }
    }

    @Test func malformedAndNonfiniteEvaluationsFail() throws {
        for invalid in [Evaluation(objective: .init(residuals: [1], jacobian: []),
                                  constraints: .init(residuals: [], jacobian: [])),
                        Evaluation(objective: .init(residuals: [.infinity], jacobian: [1]),
                                  constraints: .init(residuals: [], jacobian: []))] {
            #expect(throws: KernelError.self) { try solve([0.0]) { _ in invalid } }
        }
    }
}
