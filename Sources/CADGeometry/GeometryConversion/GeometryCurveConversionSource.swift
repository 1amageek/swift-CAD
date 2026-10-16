import CADCore

/// Owns a source chart and continuous, outward bounds on its derivatives.
public protocol GeometryCurveConversionSource: Sendable {
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D)
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D)
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure
}

public extension GeometryCurveConversionSource {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct candidate sampling requires the
    // source's actual original point/derivative path under the caller execution.
    // An ordinary query with a separate execution cannot authorize this witness.
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (point: Point3D, derivative: Vector3D) {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve source has no direct point/derivative witness.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Caller-owned final candidate
    // certification requires the conformer's actual paid source preparation and
    // queries. Legacy validation cannot stand in for this bounded witness.
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve source has no caller-admitted validation witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Caller-owned final candidate
    // certification cannot use a legacy private source allowance or unmetered
    // query scratch. Supply the actual original bounded enclosure witness.
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CurveDifferentialEnclosure {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This curve source has no caller-admitted enclosure witness.")
    }
}
