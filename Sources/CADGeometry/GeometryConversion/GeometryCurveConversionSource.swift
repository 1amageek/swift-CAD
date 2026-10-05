import CADCore

/// Owns a source chart and continuous, outward bounds on its derivatives.
public protocol GeometryCurveConversionSource: Sendable {
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D)
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure
}

public extension GeometryCurveConversionSource {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Caller-owned final candidate
    // certification requires the conformer's actual paid source preparation and
    // queries. Legacy validation cannot stand in for this bounded witness.
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve source has no caller-admitted validation witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Caller-owned final candidate
    // certification cannot use a legacy private source allowance or unmetered
    // query scratch. Supply the actual original bounded enclosure witness.
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve source has no caller-admitted enclosure witness.")
    }
}
