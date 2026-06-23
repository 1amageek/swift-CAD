import CADCore

public struct SketchDimensionMeasurement: Codable, Sendable, Hashable {
    public var dimension: SketchDimension
    public var measured: Quantity
    public var target: Quantity
    public var residual: Quantity

    public init(
        dimension: SketchDimension,
        measured: Quantity,
        target: Quantity,
        residual: Quantity
    ) {
        self.dimension = dimension
        self.measured = measured
        self.target = target
        self.residual = residual
    }

    public func isSatisfied(tolerance: ModelingTolerance = .standard) throws -> Bool {
        try tolerance.validate()
        guard measured.kind == target.kind,
              target.kind == residual.kind else {
            throw UnitError.incompatibleQuantity(
                operation: "sketch.dimension.measurement",
                lhs: measured.kind,
                rhs: target.kind
            )
        }
        switch residual.kind {
        case .length:
            return abs(residual.value) <= tolerance.distance
        case .angle:
            return abs(residual.value) <= tolerance.angle
        case .scalar:
            return abs(residual.value) <= Double.ulpOfOne.squareRoot()
        }
    }
}
