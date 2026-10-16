import CADCore

/// Composes a conversion source with independently scaled and translated U/V charts.
public struct AffineSurfaceConversionSource: GeometrySurfaceConversionSource {
    private let source: any GeometrySurfaceConversionSource
    private let uChart: AffineConversionChart
    private let vChart: AffineConversionChart

    public init(source: any GeometrySurfaceConversionSource,
                uScale: Double, uOffset: Double, vScale: Double, vOffset: Double) throws {
        self.source = source
        uChart = try .init(scale: uScale, offset: uOffset)
        vChart = try .init(scale: vScale, offset: vOffset)
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try tolerance.validate()
        guard parameters.u.width > 0, parameters.u.width.isFinite,
              parameters.v.width > 0, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface conversion requires finite positive U/V intervals.")
        }
        try source.validate(over: image(parameters), tolerance: tolerance)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let point = try source.point(u: uChart.parameter(u), v: vChart.parameter(v), tolerance: tolerance)
        try point.validate()
        try CurrentTaskCancellationChecker().checkCancellation()
        return point
    }

    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let original = try source.enclosure(over: image(parameters), tolerance: tolerance)
        let u = OutwardScalarInterval.exact(uChart.scale), v = OutwardScalarInterval.exact(vChart.scale)
        let result = try SurfaceDifferentialEnclosure(position: original.position,
            tangentU: AffineConversionChart.multiply(original.tangentU, by: u),
            tangentV: AffineConversionChart.multiply(original.tangentV, by: v),
            secondDerivativeUU: AffineConversionChart.multiply(original.secondDerivativeUU, by: u * u),
            secondDerivativeUV: AffineConversionChart.multiply(original.secondDerivativeUV, by: u * v),
            secondDerivativeVV: AffineConversionChart.multiply(original.secondDerivativeVV, by: v * v))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try tolerance.validate()
        guard parameters.u.width > 0, parameters.u.width.isFinite,
              parameters.v.width > 0, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface conversion requires finite positive U/V intervals.")
        }
        try source.validate(over: image(parameters), tolerance: tolerance, using: &execution)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Point3D {
        let point = try source.point(u: uChart.parameter(u), v: vChart.parameter(v), tolerance: tolerance, using: &execution)
        try point.validate()
        try execution.checkpoint()
        return point
    }

    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        let original = try source.enclosure(over: image(parameters), tolerance: tolerance, using: &execution)
        let u = OutwardScalarInterval.exact(uChart.scale), v = OutwardScalarInterval.exact(vChart.scale)
        let result = try SurfaceDifferentialEnclosure(position: original.position,
            tangentU: AffineConversionChart.multiply(original.tangentU, by: u),
            tangentV: AffineConversionChart.multiply(original.tangentV, by: v),
            secondDerivativeUU: AffineConversionChart.multiply(original.secondDerivativeUU, by: u * u),
            secondDerivativeUV: AffineConversionChart.multiply(original.secondDerivativeUV, by: u * v),
            secondDerivativeVV: AffineConversionChart.multiply(original.secondDerivativeVV, by: v * v))
        try execution.checkpoint()
        return result
    }

    private func image(_ parameters: SurfaceParameterBox) throws -> SurfaceParameterBox {
        try .init(u: uChart.image(parameters.u), v: vChart.image(parameters.v))
    }
}
