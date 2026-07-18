import Foundation
import CADCore
import CADIR

public struct SelectionDimensionEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let measurementEvaluator: SelectionMeasurementEvaluator

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.measurementEvaluator = SelectionMeasurementEvaluator(tolerance: tolerance)
    }

    public func evaluate(
        _ document: EvaluatedDocument
    ) throws -> SelectionDimensionEvaluation {
        try tolerance.validate()
        var measurements: [SelectionDimensionMeasurement] = []
        measurements.reserveCapacity(document.document.selectionDimensions.count)
        for dimension in document.document.selectionDimensions {
            measurements.append(try measure(dimension, in: document))
        }
        return SelectionDimensionEvaluation(measurements: measurements)
    }

    public func measure(
        _ dimension: SelectionDimension,
        in document: EvaluatedDocument
    ) throws -> SelectionDimensionMeasurement {
        try dimension.validate(parameters: document.document.parameters, tolerance: tolerance)
        let first = try measurementEvaluator.point(for: dimension.first, in: document)
        let second = try measurementEvaluator.point(for: dimension.second, in: document)
        let target = try document.document.parameters.resolvedValue(for: dimension.target)
        let measured: Quantity
        switch dimension.kind {
        case .distance:
            let distance = try SelectionDistanceMeasurement(first: first, second: second)
            measured = .length(distance.distance, unit: .meter)
        case .angle:
            let angle = try SelectionAngleMeasurement(first: first, second: second, tolerance: tolerance)
            measured = .angle(angle.angleRadians, unit: .radian)
        }
        guard measured.kind == target.kind else {
            throw UnitError.expectedQuantity(
                operation: "selection.dimension.target",
                expected: measured.kind,
                actual: target.kind
            )
        }
        return SelectionDimensionMeasurement(
            dimension: dimension,
            first: first,
            second: second,
            measured: measured,
            target: target,
            residual: residualQuantity(measured: measured, target: target)
        )
    }

    private func residualQuantity(measured: Quantity, target: Quantity) -> Quantity {
        switch measured.kind {
        case .angle:
            return Quantity(value: normalizedSignedAngle(measured.value - target.value), kind: .angle)
        case .length, .scalar:
            return Quantity(value: measured.value - target.value, kind: measured.kind)
        }
    }

    private func normalizedSignedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        var result = angle.truncatingRemainder(dividingBy: period)
        if result > Double.pi {
            result -= period
        } else if result < -Double.pi {
            result += period
        }
        return result
    }
}
