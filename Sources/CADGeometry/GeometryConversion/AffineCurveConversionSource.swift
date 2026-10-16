import CADCore

/// Composes a continuous conversion source with t = scale * s + offset.
public struct AffineCurveConversionSource: GeometryCurveConversionSource {
    private let source: any GeometryCurveConversionSource
    private let chart: AffineConversionChart

    public init(source: any GeometryCurveConversionSource, scale: Double, offset: Double) throws {
        self.source = source
        chart = try .init(scale: scale, offset: offset)
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        guard parameters.width > 0, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Curve conversion requires a finite positive interval.")
        }
        try source.validate(over: chart.image(parameters), tolerance: tolerance)
    }

    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws
        -> (point: Point3D, derivative: Vector3D) {
        let value = try source.pointAndDerivative(at: chart.parameter(parameter), tolerance: tolerance)
        let derivative = value.derivative * chart.scale
        try value.point.validate()
        try derivative.validate()
        try CurrentTaskCancellationChecker().checkCancellation()
        return (value.point, derivative)
    }

    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let original = try source.enclosure(over: chart.image(parameters), tolerance: tolerance)
        let scale = OutwardScalarInterval.exact(chart.scale)
        let result = try CurveDifferentialEnclosure(position: original.position,
            firstDerivative: AffineConversionChart.multiply(original.firstDerivative, by: scale),
            secondDerivative: AffineConversionChart.multiply(original.secondDerivative, by: scale * scale))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try tolerance.validate()
        guard parameters.width > 0, parameters.width.isFinite else {
            throw GeometryConversionError.invalidInput("Curve conversion requires a finite positive interval.")
        }
        try source.validate(over: chart.image(parameters), tolerance: tolerance, using: &execution)
    }

    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
        -> (point: Point3D, derivative: Vector3D) {
        let value = try source.pointAndDerivative(at: chart.parameter(parameter), tolerance: tolerance, using: &execution)
        let derivative = value.derivative * chart.scale
        try value.point.validate()
        try derivative.validate()
        try execution.checkpoint()
        return (value.point, derivative)
    }

    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        let original = try source.enclosure(over: chart.image(parameters), tolerance: tolerance, using: &execution)
        let scale = OutwardScalarInterval.exact(chart.scale)
        let result = try CurveDifferentialEnclosure(position: original.position,
            firstDerivative: AffineConversionChart.multiply(original.firstDerivative, by: scale),
            secondDerivative: AffineConversionChart.multiply(original.secondDerivative, by: scale * scale))
        try execution.checkpoint()
        return result
    }
}
