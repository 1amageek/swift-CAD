import CADCore
import Foundation

public struct DefaultRationalBezierHalfSpaceClassifier: RationalBezierHalfSpaceClassifying {
    private struct ScalarBounds {
        let lower: Double
        let upper: Double

        func midpoint(with other: ScalarBounds) -> ScalarBounds {
            ScalarBounds(
                lower: ((lower + other.lower) * 0.5).nextDown,
                upper: ((upper + other.upper) * 0.5).nextUp
            )
        }
    }

    private struct Cell {
        let controls: [ScalarBounds]
        let weights: [ScalarBounds]
        let depth: Int
    }

    private let maximumSubdivisionDepth = 32
    private let maximumCellCount = 65_536

    public init() {}

    public func classify(
        controlValues: [Double],
        weights: [Double],
        nonnegativeMargin: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierHalfSpaceClassification {
        try tolerance.validate()
        guard controlValues.count == weights.count,
              controlValues.isEmpty == false,
              controlValues.allSatisfy(\.isFinite),
              weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
              nonnegativeMargin.isFinite,
              nonnegativeMargin >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier half-space classification requires finite scalar controls, positive weights, and a nonnegative margin."
            )
        }
        let scalarControls = zip(controlValues, weights).map { value, weight in
            let arithmeticError = Double.ulpOfOne
                * max(abs(value), nonnegativeMargin, 1.0)
                * 128.0
            let shiftedLower = (value - arithmeticError + nonnegativeMargin)
                .nextDown
            let shiftedUpper = (value + arithmeticError + nonnegativeMargin)
                .nextUp
            return ScalarBounds(
                lower: (shiftedLower * weight).nextDown,
                upper: (shiftedUpper * weight).nextUp
            )
        }
        let weightControls = weights.map { weight in
            ScalarBounds(lower: weight.nextDown, upper: weight.nextUp)
        }
        var stack = [Cell(
            controls: scalarControls,
            weights: weightControls,
            depth: 0
        )]
        var remainingCells = maximumCellCount
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational Bezier half-space classification exceeded its cell budget."
                )
            }
            remainingCells -= 1
            if cell.controls.allSatisfy({ $0.lower >= 0.0 }) {
                continue
            }
            let endpointIndices = cell.controls.count == 1
                ? [0]
                : [0, cell.controls.count - 1]
            if let violatingIndex = endpointIndices.first(where: {
                cell.controls[$0].upper < 0.0
            }) {
                return .violates(
                    residual: (
                        -cell.controls[violatingIndex].upper
                            / cell.weights[violatingIndex].upper
                    ).nextDown
                )
            }
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Rational Bezier half-space classification could not separate the boundary within tolerance."
                )
            }
            let scalarHalves = subdivided(cell.controls)
            let weightHalves = subdivided(cell.weights)
            stack.append(Cell(
                controls: scalarHalves.upper,
                weights: weightHalves.upper,
                depth: cell.depth + 1
            ))
            stack.append(Cell(
                controls: scalarHalves.lower,
                weights: weightHalves.lower,
                depth: cell.depth + 1
            ))
        }
        return .nonnegative
    }

    private func subdivided(
        _ controls: [ScalarBounds]
    ) -> (lower: [ScalarBounds], upper: [ScalarBounds]) {
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].midpoint(with: previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }
}
