import CADCore
import CADIR

public struct SelectionDimensionMeasurement: Codable, Sendable, Hashable {
    public var dimension: SelectionDimension
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var measured: Quantity
    public var target: Quantity
    public var residual: Quantity

    public init(
        dimension: SelectionDimension,
        first: SelectionMeasurementPoint,
        second: SelectionMeasurementPoint,
        measured: Quantity,
        target: Quantity,
        residual: Quantity
    ) {
        self.dimension = dimension
        self.first = first
        self.second = second
        self.measured = measured
        self.target = target
        self.residual = residual
    }

    public func isSatisfied(tolerance: ModelingTolerance) throws -> Bool {
        try tolerance.validate()
        switch residual.kind {
        case .length:
            return abs(residual.value) <= tolerance.distance
        case .angle:
            return abs(residual.value) <= tolerance.angle
        case .scalar:
            return abs(residual.value) <= tolerance.distance
        }
    }
}
