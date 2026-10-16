import CADCore

/// Projects the original curve law without fitting or tessellation.
public struct DefaultOrthographicCurveProjector: OrthographicCurveProjecting {
    public init() {}

    public func project(
        _ curve: Curve3D,
        onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance
    ) throws -> OrthographicProjectedCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try project(curve, onto: frame, tolerance: tolerance, using: &execution)
    }

    public func project(_ curve: Curve3D, onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OrthographicProjectedCurve {
        try execution.consumeWork(1)
        try CurrentTaskCancellationChecker().checkCancellation()
        let source = try ValidatedCurve3D(curve, tolerance: tolerance, using: &execution)
        try CurrentTaskCancellationChecker().checkCancellation()
        return OrthographicProjectedCurve(source: source, frame: frame)
    }
}
