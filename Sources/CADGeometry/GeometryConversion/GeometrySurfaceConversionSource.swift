import CADCore

/// Mapped sources must enclose their complete map, including derivative chain rules.
public protocol GeometrySurfaceConversionSource: Sendable {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws
    func point(u: Double, v: Double, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Point3D
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> SurfaceDifferentialEnclosure
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure
}

public extension GeometrySurfaceConversionSource {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded converter callers require actual
    // source validation, proposal and enclosure witnesses on injected sources.
    // Legacy conformers cannot authorize success under a fresh hidden allowance.
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        throw GeometryConversionError.invalidInput("Surface source has no caller-admitted validation witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded fitting calls this requirement;
    // original source proposal work/bytes must be provided before use succeeds.
    func point(u: Double, v: Double, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Point3D {
        throw GeometryConversionError.invalidInput("Surface source has no caller-admitted point witness.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded final surface certification needs
    // the original whole source differential law under the composing allowance.
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> SurfaceDifferentialEnclosure {
        throw GeometryConversionError.invalidInput("Surface source has no caller-admitted enclosure witness.")
    }
}
