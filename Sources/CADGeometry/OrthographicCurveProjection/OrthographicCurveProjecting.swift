import CADCore

/// Creates a geometric curve with the original source parameterization.
public protocol OrthographicCurveProjecting: Sendable {
    func project(
        _ curve: Curve3D,
        onto frame: OrthographicProjectionFrame,
        tolerance: ModelingTolerance
    ) throws -> OrthographicProjectedCurve
}
