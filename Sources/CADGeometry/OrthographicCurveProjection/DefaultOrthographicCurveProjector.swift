import CADCore

/// Projects the original curve law without fitting or tessellation.
public struct DefaultOrthographicCurveProjector: OrthographicCurveProjecting {
    public init() {}

    public func project(
        _ curve: Curve3D,
        onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance
    ) throws -> OrthographicProjectedCurve {
        try CurrentTaskCancellationChecker().checkCancellation()
        let source = try ValidatedCurve3D(curve, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return OrthographicProjectedCurve(source: source, frame: frame)
    }
}
