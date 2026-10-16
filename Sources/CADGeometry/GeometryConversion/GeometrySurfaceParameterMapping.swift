import CADCore

/// Owns the entire original UV image and its chain-rule derivatives.
public protocol GeometrySurfaceParameterMapping: Sendable {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws
    func parameter(u: Double, v: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterMapEnclosure
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws
    func parameter(u: Double, v: Double, tolerance: ModelingTolerance) throws -> SurfaceParameter
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceParameterMapEnclosure
}

public extension GeometrySurfaceParameterMapping {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct mapped conversion consumes the
    // original complete chart under its caller execution. A legacy map needs
    // direct validation, point and enclosure witnesses before it can publish.
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        throw GeometryConversionError.invalidInput("Mapping has no direct validation witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct mapped candidate construction
    // needs the map owner's actual caller-admitted parameter evaluation.
    func parameter(u: Double, v: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        throw GeometryConversionError.invalidInput("Mapping has no direct parameter witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct whole-domain conversion requires
    // complete chart derivative enclosures on the same caller execution.
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterMapEnclosure {
        throw GeometryConversionError.invalidInput("Mapping has no direct enclosure witness.")
    }
}
