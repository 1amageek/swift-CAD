import CADCore
import Foundation

package enum SurfaceFittingNonlinearEquality {
    package struct Evaluation: Sendable {
        package let objective: SurfaceFittingTrustRegion.Evaluation
        package let constraints: SurfaceFittingTrustRegion.Evaluation

        package init(objective: SurfaceFittingTrustRegion.Evaluation,
                     constraints: SurfaceFittingTrustRegion.Evaluation) {
            self.objective = objective
            self.constraints = constraints
        }
    }

    package struct Result: Sendable {
        package let parameters: [Double]
        package let evaluation: Evaluation
        package let evaluations: Int
    }

    /// Returns only feasible, first-order stationary iterates; this is not a geometric certificate.
    package static func solve(
        initial: [Double], maximumStep: Double, constraintTolerance: Double,
        relativeGradientTolerance: Double, relativeRankTolerance: Double,
        maximumEvaluations: Int, maximumElements: Int,
        evaluate: ([Double]) throws -> Evaluation
    ) throws -> Result {
        guard !initial.isEmpty, initial.allSatisfy(\.isFinite),
              maximumStep.isFinite, maximumStep > 0,
              constraintTolerance.isFinite, constraintTolerance > 0,
              relativeGradientTolerance.isFinite, relativeGradientTolerance > 0,
              relativeGradientTolerance < 1, relativeRankTolerance.isFinite,
              relativeRankTolerance > 0, relativeRankTolerance < 1 else {
            throw failure(.invalidInput, "Nonlinear equality fitting requires finite parameters and positive tolerances.")
        }
        guard maximumEvaluations > 0, maximumElements >= initial.count else {
            throw failure(.resourceLimitExceeded, "Nonlinear equality fitting has insufficient storage or evaluation budget.")
        }
        var parameters = initial
        var current = try evaluate(parameters)
        let rows = current.objective.residuals.count
        let equalities = current.constraints.residuals.count
        let columns = initial.count
        try validate(current, rows: rows, equalities: equalities, columns: columns, budget: maximumElements)
        var evaluations = 1
        var penalty = 1.0
        var radius = maximumStep
        while true {
            var gradient = Array(repeating: 0.0, count: columns)
            for row in 0..<rows {
                for column in 0..<columns {
                    gradient[column] += current.objective.jacobian[row * columns + column]
                        * current.objective.residuals[row]
                }
            }
            guard gradient.allSatisfy(\.isFinite), norm(gradient).isFinite else {
                throw failure(.resourceLimitExceeded, "Nonlinear equality gradient exceeded finite arithmetic range.")
            }
            var projected = gradient
            if equalities > 0 {
                var transpose = Array(repeating: 0.0, count: current.constraints.jacobian.count)
                for row in 0..<equalities {
                    for column in 0..<columns {
                        transpose[column * equalities + row] = current.constraints.jacobian[row * columns + column]
                    }
                }
                let qr = try SurfaceFittingQR(coefficients: transpose, rows: columns, columns: equalities,
                    relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements)
                projected = try qr.applyingQ(to: gradient, transpose: true)
                for index in 0..<qr.rank { projected[index] = 0 }
            }
            if current.constraints.residuals.allSatisfy({ abs($0) <= constraintTolerance }),
               norm(projected) / max(1, norm(gradient)) <= relativeGradientTolerance {
                return Result(parameters: parameters, evaluation: current, evaluations: evaluations)
            }

            let step = try SurfaceFittingLeastSquares.solve(
                objective: current.objective.jacobian, target: current.objective.residuals.map { -$0 },
                constraints: current.constraints.jacobian, values: current.constraints.residuals.map { -$0 },
                columns: columns, relativeRankTolerance: relativeRankTolerance,
                constraintTolerance: constraintTolerance, maximumElements: maximumElements)
            let length = norm(step)
            let directional = zip(gradient, step).reduce(0.0) { $0 + $1.0 * $1.1 }
            let violation = current.constraints.residuals.reduce(0.0) { $0 + abs($1) }
            guard length.isFinite, length > 0, directional.isFinite, violation.isFinite else {
                throw failure(.classificationFailure, "Nonlinear equality fitting has no finite nonzero step.")
            }
            // The L1 term steers trials; only the separate equality check permits a result.
            if violation > 0 {
                penalty = max(penalty, 1 + 2 * max(0, directional) / violation)
            }
            let slope = directional - penalty * violation
            let objectiveNorm = norm(current.objective.residuals)
            let merit = 0.5 * objectiveNorm * objectiveNorm + penalty * violation
            guard penalty.isFinite, slope.isFinite, merit.isFinite else {
                throw failure(.resourceLimitExceeded, "Nonlinear equality merit exceeded finite arithmetic range.")
            }
            guard slope < 0 else {
                throw failure(.classificationFailure, "Nonlinear equality fitting has no merit descent direction.")
            }
            var fraction = min(1, radius / length)
            while true {
                guard evaluations < maximumEvaluations else {
                    throw failure(.resourceLimitExceeded, "Nonlinear equality fitting exhausted its evaluation budget.")
                }
                let candidate = zip(parameters, step).map { $0 + fraction * $1 }
                guard candidate.allSatisfy(\.isFinite) else {
                    throw failure(.resourceLimitExceeded, "Nonlinear equality trial exceeded finite parameter range.")
                }
                guard candidate != parameters else {
                    throw failure(.classificationFailure, "Nonlinear equality fitting stagnated before feasibility and stationarity.")
                }
                let trial = try evaluate(candidate)
                evaluations += 1
                try validate(trial, rows: rows, equalities: equalities, columns: columns, budget: maximumElements)
                let trialViolation = trial.constraints.residuals.reduce(0.0) { $0 + abs($1) }
                // Difference of squares preserves small improvements near a nonzero-residual optimum.
                let objectiveChange = zip(current.objective.residuals, trial.objective.residuals)
                    .reduce(0.0) { $0 + (0.5 * ($1.1 - $1.0)) * ($1.1 + $1.0) }
                let meritChange = objectiveChange + penalty * (trialViolation - violation)
                guard meritChange.isFinite else {
                    throw failure(.resourceLimitExceeded, "Nonlinear equality trial merit exceeded finite arithmetic range.")
                }
                if meritChange <= 1e-4 * fraction * slope {
                    let ratio = meritChange / (fraction * slope)
                    guard ratio.isFinite else {
                        throw failure(.resourceLimitExceeded, "Nonlinear equality reduction exceeded finite arithmetic range.")
                    }
                    if ratio < 0.25 {
                        radius = 0.25 * min(radius, fraction * length)
                    } else if ratio > 0.75, fraction * length >= 0.9 * radius {
                        radius = radius <= maximumStep * 0.5 ? radius * 2 : maximumStep
                    }
                    parameters = candidate
                    current = trial
                    break
                }
                fraction *= 0.5
            }
        }
    }

    private static func validate(_ value: Evaluation, rows: Int, equalities: Int,
                                 columns: Int, budget: Int) throws {
        var remaining = budget - columns
        for (part, count) in [(value.objective, rows), (value.constraints, equalities)] {
            let size = count.multipliedReportingOverflow(by: columns)
            guard !size.overflow, part.residuals.count == count, part.jacobian.count == size.partialValue,
                  part.residuals.allSatisfy(\.isFinite), part.jacobian.allSatisfy(\.isFinite) else {
                throw failure(.invalidInput, "Nonlinear equality evaluator returned invalid dimensions or values.")
            }
            guard part.jacobian.count <= remaining else {
                throw failure(.resourceLimitExceeded, "Nonlinear equality Jacobian exceeded its storage budget.")
            }
            remaining -= part.jacobian.count
            guard part.residuals.count <= remaining else {
                throw failure(.resourceLimitExceeded, "Nonlinear equality residuals exceeded their storage budget.")
            }
            remaining -= part.residuals.count
        }
    }

    private static func norm(_ values: [Double]) -> Double { values.reduce(0.0) { hypot($0, $1) } }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}
