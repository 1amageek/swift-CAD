import CADCore
import CADGeometry
import Testing

@Suite("Surface fitting trust region", .timeLimit(.minutes(1)))
struct SurfaceFittingTrustRegionTests {
  private func solve(
    _ initial: [Double], radius: Double = 1, budget: Int = 100,
    evaluate: ([Double]) throws -> SurfaceFittingTrustRegion.Evaluation
  ) throws -> SurfaceFittingTrustRegion.Result {
    try SurfaceFittingTrustRegion.solve(
      initial: initial, initialRadius: radius, maximumRadius: 100,
      residualTolerance: 1e-10, relativeGradientTolerance: 1e-12,
      relativeRankTolerance: 1e-12, maximumEvaluations: budget, maximumElements: 100,
      evaluate: evaluate)
  }

  @Test func nonlinearRootRejectsAnOvershootingTrial() throws {
    var visited: [Double] = []
    let result = try solve([0.1], radius: 100) { x in
      visited.append(x[0])
      return .init(residuals: [x[0] * x[0] - 2], jacobian: [2 * x[0]])
    }
    #expect(result.termination == .residualSatisfied)
    #expect(abs(result.parameters[0] * result.parameters[0] - 2) < 1e-10)
    #expect(visited[1] > 9)
    #expect(visited[2] < visited[1])
    #expect(result.evaluations == visited.count)
  }

  @Test func rosenbrockResidualUsesMultidimensionalDogleg() throws {
    let result = try solve([-1.2, 1]) { x in
      .init(
        residuals: [10 * (x[1] - x[0] * x[0]), 1 - x[0]],
        jacobian: [-20 * x[0], 10, -1, 0])
    }
    #expect(result.termination == .residualSatisfied)
    #expect(abs(result.parameters[0] - 1) < 1e-9)
    #expect(abs(result.parameters[1] - 1) < 1e-9)
  }

  @Test func stationarityDoesNotClaimResidualSatisfaction() throws {
    let result = try solve([0]) { x in
      .init(residuals: [x[0] - 1, x[0] + 1], jacobian: [1, 1])
    }
    #expect(result.termination == .stationary)
    #expect(result.evaluations == 1)
    #expect(result.evaluation.residuals == [-1, 1])
  }

  @Test func exhaustionInvalidEvaluationAndEvaluatorErrorsDoNotReturnSuccess() throws {
    var calls = 0
    #expect(throws: KernelError.self) {
      try solve([0], budget: 1) { x in
        calls += 1
        return .init(residuals: [x[0] - 2], jacobian: [1])
      }
    }
    #expect(calls == 1)
    #expect(throws: KernelError.self) {
      try solve([0]) { _ in .init(residuals: [1], jacobian: [0]) }
    }
    #expect(throws: KernelError.self) {
      try solve([0]) { _ in .init(residuals: [.nan], jacobian: [1]) }
    }
    #expect(throws: KernelError.self) {
      try solve([0]) { _ in .init(residuals: [1], jacobian: []) }
    }
    enum EvaluationFailure: Error { case cancelled }
    #expect(throws: EvaluationFailure.self) {
      try solve([0]) { _ in throw EvaluationFailure.cancelled }
    }
  }
}
