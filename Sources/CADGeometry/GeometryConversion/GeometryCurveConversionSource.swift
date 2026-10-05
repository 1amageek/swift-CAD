import CADCore

/// Owns a source chart and continuous, outward bounds on its derivatives.
public protocol GeometryCurveConversionSource: Sendable {
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D)
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure
}
