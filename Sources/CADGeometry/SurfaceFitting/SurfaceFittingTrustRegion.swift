import CADCore
import Foundation

package enum SurfaceFittingTrustRegion {
  package struct Evaluation: Sendable {
    package let residuals: [Double]
    package let jacobian: [Double]
    package init(residuals: [Double], jacobian: [Double]) {
      self.residuals = residuals
      self.jacobian = jacobian
    }
  }

  package enum Termination: Sendable { case residualSatisfied, stationary }
  package struct Result: Sendable {
    package let parameters: [Double]
    package let evaluation: Evaluation
    package let termination: Termination
    package let evaluations: Int
  }

  package static func solve(
    initial: [Double], initialRadius: Double, maximumRadius: Double,
    residualTolerance: Double, relativeGradientTolerance: Double,
    relativeRankTolerance: Double, maximumEvaluations: Int, maximumElements: Int,
    evaluate: ([Double]) throws -> Evaluation
  ) throws -> Result {
    guard !initial.isEmpty, initial.allSatisfy(\.isFinite),
      initialRadius.isFinite, initialRadius > 0,
      maximumRadius.isFinite, maximumRadius >= initialRadius,
      residualTolerance.isFinite, residualTolerance >= 0,
      relativeGradientTolerance.isFinite, relativeGradientTolerance > 0,
      relativeGradientTolerance < 1, relativeRankTolerance.isFinite,
      relativeRankTolerance > 0, relativeRankTolerance < 1
    else {
      throw failure(
        .invalidInput,
        "Surface fitting trust region requires finite parameters, radii and tolerances.")
    }
    guard maximumEvaluations > 0, maximumElements >= initial.count else {
      throw failure(
        .resourceLimitExceeded,
        "Surface fitting trust region has insufficient evaluation or storage budget.")
    }
    var parameters = initial
    var current = try evaluate(parameters)
    let rows = current.residuals.count
    try validate(current, rows: rows, columns: initial.count, budget: maximumElements)
    var evaluations = 1
    var radius = initialRadius
    while true {
      let residualNorm = norm(current.residuals)
      guard residualNorm.isFinite else {
        throw failure(
          .resourceLimitExceeded, "Surface fitting residual norm exceeds finite arithmetic range.")
      }
      if residualNorm <= residualTolerance {
        return Result(
          parameters: parameters, evaluation: current,
          termination: .residualSatisfied, evaluations: evaluations)
      }
      let scale = max(
        current.residuals.reduce(0.0) { max($0, abs($1)) },
        current.jacobian.reduce(0.0) { max($0, abs($1)) })
      let residuals = current.residuals.map { $0 / scale }
      let jacobian = current.jacobian.map { $0 / scale }
      let qr = try SurfaceFittingQR(
        coefficients: jacobian, rows: rows, columns: initial.count,
        relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
      guard qr.rank == initial.count else {
        throw failure(.singularSystem, "Surface fitting nonlinear Jacobian is rank deficient.")
      }
      var gradient = Array(repeating: 0.0, count: initial.count)
      for row in 0..<rows {
        for column in gradient.indices {
          gradient[column] += jacobian[row * gradient.count + column] * residuals[row]
        }
      }
      let gradientNorm = norm(gradient)
      let normalizedResidualNorm = norm(residuals)
      let relativeGradient = (gradientNorm / norm(jacobian)) / normalizedResidualNorm
      guard relativeGradient.isFinite else {
        throw failure(
          .resourceLimitExceeded, "Surface fitting gradient exceeds finite arithmetic range.")
      }
      if relativeGradient <= relativeGradientTolerance {
        return Result(
          parameters: parameters, evaluation: current,
          termination: .stationary, evaluations: evaluations)
      }
      let newton = try qr.solveFullRankLeastSquares(residuals.map { -$0 })
      // Rejected trials reuse the accepted iterate's factorization and Newton step.
      while true {
        guard evaluations < maximumEvaluations else {
          throw failure(
            .resourceLimitExceeded, "Surface fitting exhausted its nonlinear evaluation budget.")
        }
        var step = newton
        if norm(newton) > radius {
          let direction = gradient.map { -$0 / gradientNorm }
          let imageNorm = norm(product(jacobian, rows: rows, vector: direction))
          let cauchyLength = (gradientNorm / imageNorm) / imageNorm
          guard cauchyLength.isFinite, cauchyLength > 0 else {
            throw failure(
              .resourceLimitExceeded, "Surface fitting Cauchy step exceeds finite arithmetic range."
            )
          }
          let cauchy = direction.map { $0 * min(radius, cauchyLength) }
          step = cauchy
          if cauchyLength < radius {
            var lower = 0.0
            var upper = 1.0
            for _ in 0..<64 {
              let t = (lower + upper) * 0.5
              var length = 0.0
              for index in step.indices {
                length = hypot(length, (1 - t) * cauchy[index] + t * newton[index])
              }
              if length <= radius { lower = t } else { upper = t }
            }
            for index in step.indices {
              step[index] = (1 - lower) * cauchy[index] + lower * newton[index]
            }
          }
        }
        let candidate = zip(parameters, step).map(+)
        guard candidate.allSatisfy(\.isFinite) else {
          throw failure(
            .resourceLimitExceeded, "Surface fitting trial exceeds finite parameter range.")
        }
        guard candidate != parameters else {
          throw failure(
            .classificationFailure,
            "Surface fitting stagnated before meeting its stopping conditions.")
        }
        let linearChange = product(jacobian, rows: rows, vector: step)
        let predictedNorm = norm(zip(residuals, linearChange).map(+)) / normalizedResidualNorm
        let predictedDecrease = 1 - predictedNorm * predictedNorm
        guard predictedDecrease.isFinite, predictedDecrease > 0 else {
          throw failure(.classificationFailure, "Surface fitting has no predicted descent.")
        }
        let trial = try evaluate(candidate)
        evaluations += 1
        try validate(trial, rows: rows, columns: initial.count, budget: maximumElements)
        let trialRatio = norm(trial.residuals) / residualNorm
        let ratio = (1 - trialRatio * trialRatio) / predictedDecrease
        guard ratio.isFinite else {
          throw failure(
            .resourceLimitExceeded,
            "Surface fitting trial reduction exceeds finite arithmetic range.")
        }
        if ratio < 0.25 {
          radius = 0.25 * min(radius, norm(step))
        } else if ratio > 0.75, norm(step) >= 0.9 * radius {
          radius = min(maximumRadius, radius <= maximumRadius * 0.5 ? radius * 2 : maximumRadius)
        }
        if ratio > 0.1 {
          parameters = candidate
          current = trial
          break
        }
        guard radius > 0 else {
          throw failure(
            .classificationFailure, "Surface fitting trust radius underflowed without convergence.")
        }
      }
    }
  }

  private static func product(_ matrix: [Double], rows: Int, vector: [Double]) -> [Double] {
    var result = Array(repeating: 0.0, count: rows)
    for row in 0..<rows {
      for column in vector.indices {
        result[row] += matrix[row * vector.count + column] * vector[column]
      }
    }
    return result
  }

  private static func norm(_ vector: [Double]) -> Double { vector.reduce(0.0) { hypot($0, $1) } }

  private static func validate(_ value: Evaluation, rows: Int, columns: Int, budget: Int) throws {
    let count = rows.multipliedReportingOverflow(by: columns)
    guard rows > 0, !count.overflow, value.residuals.count == rows,
      value.jacobian.count == count.partialValue,
      value.residuals.allSatisfy(\.isFinite), value.jacobian.allSatisfy(\.isFinite)
    else {
      throw failure(
        .invalidInput, "Surface fitting evaluator returned invalid dimensions or nonfinite values.")
    }
    guard value.jacobian.count <= budget else {
      throw failure(
        .resourceLimitExceeded, "Surface fitting evaluator exceeded the matrix element budget.")
    }
  }

  private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
    KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
  }
}
