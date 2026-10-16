import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

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

    public func classify(controlValues: [Double], weights: [Double], nonnegativeMargin: Double,
        tolerance: ModelingTolerance) throws -> RationalBezierHalfSpaceClassification {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try classify(controlValues: controlValues, weights: weights,
            nonnegativeMargin: nonnegativeMargin, tolerance: tolerance, using: &execution)
    }

    public func classify(
        controlValues: [Double],
        weights: [Double],
        nonnegativeMargin: Double,
        tolerance: ModelingTolerance, using admission: inout OriginalQueryExecution
    ) throws -> RationalBezierHalfSpaceClassification {
        try admission.checkpoint()
        try admission.consumeWork( 1)
        try tolerance.validate()
        guard controlValues.count == weights.count,
              controlValues.isEmpty == false,
              try allSatisfy(controlValues, using: &admission, predicate: { $0.isFinite }),
              try allSatisfy(weights, using: &admission, predicate: { $0.isFinite && $0 > Double.ulpOfOne }),
              nonnegativeMargin.isFinite,
              nonnegativeMargin >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier half-space classification requires finite scalar controls, positive weights, and a nonnegative margin."
            )
        }
        let scalarControls = try mapped(zip(controlValues, weights), using: &admission) { pair in
            let (value, weight) = pair
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
        let weightControls = try mapped(weights, using: &admission) { weight in
            ScalarBounds(lower: weight.nextDown, upper: weight.nextUp)
        }
        try RationalAlgebraStorage.retain(1, of: Cell.self, usage: &admission)
        var stack = [Cell(
            controls: scalarControls,
            weights: weightControls,
            depth: 0
        )]
        var remainingCells = maximumCellCount
        while let cell = stack.popLast() {
            try admission.checkpoint()
            try admission.visitGeometricCell(depth: cell.depth)
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational Bezier half-space classification exceeded its cell budget."
                )
            }
            remainingCells -= 1
            if try allSatisfy(cell.controls, using: &admission, predicate: { $0.lower >= 0.0 }) {
                continue
            }
            let first = 0
            let last = cell.controls.count - 1
            let violatingIndex: Int?
            try admission.consumeWork( 1)
            if cell.controls[first].upper < 0.0 { violatingIndex = first }
            else if first != last {
                try admission.consumeWork( 1)
                violatingIndex = cell.controls[last].upper < 0.0 ? last : nil
            } else { violatingIndex = nil }
            if let violatingIndex {
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
            let scalarHalves = try subdivided(cell.controls, using: &admission)
            let weightHalves = try subdivided(cell.weights, using: &admission)
            try append(Cell(
                controls: scalarHalves.upper,
                weights: weightHalves.upper,
                depth: cell.depth + 1
            ), to: &stack, using: &admission)
            try append(Cell(
                controls: scalarHalves.lower,
                weights: weightHalves.lower,
                depth: cell.depth + 1
            ), to: &stack, using: &admission)
        }
        return .nonnegative
    }

    private func subdivided<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [ScalarBounds], using admission: inout A
    ) throws -> (lower: [ScalarBounds], upper: [ScalarBounds]) {
        try RationalAlgebraStorage.retain(1, of: [ScalarBounds].self, usage: &admission)
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            try admission.checkpoint()
            try admission.consumeWork( 1)
            let next = try mapped(0..<(previous.count - 1), using: &admission) { index in
                previous[index].midpoint(with: previous[index + 1])
            }
            try append(next, to: &levels, using: &admission)
        }
        return (
            try mapped(levels, using: &admission) { $0[0] },
            try mapped(levels.reversed(), using: &admission) { $0[$0.count - 1] }
        )
    }

    private func mapped<Values: Sequence, Output, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values, using admission: inout A, transform: (Values.Element) -> Output
    ) throws -> [Output] {
        var result: [Output] = []
        try RationalAlgebraStorage.retain(values.underestimatedCount, of: Output.self, usage: &admission)
        result.reserveCapacity(values.underestimatedCount)
        for value in values {
            try admission.checkpoint()
            try admission.consumeWork( 1)
            try append(transform(value), to: &result, using: &admission)
        }
        return result
    }

    private func append<Element, A: ExactScalarAdmission & ~Copyable>(_ value: Element,
        to values: inout [Element], using admission: inout A) throws {
        if values.count == values.capacity {
            let doubled = values.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
            let capacity = max(1, doubled.partialValue)
            try RationalAlgebraStorage.retain(capacity, of: Element.self, usage: &admission)
            values.reserveCapacity(capacity)
        }
        values.append(value)
    }

    private func allSatisfy<Values: Sequence, A: ExactScalarAdmission & ~Copyable>(
        _ values: Values, using admission: inout A, predicate: (Values.Element) -> Bool
    ) throws -> Bool {
        for value in values {
            try admission.checkpoint()
            try admission.consumeWork( 1)
            if !predicate(value) { return false }
        }
        return true
    }
}
