import CADCore

/// Mapped sources must enclose their complete map, including derivative chain rules.
public protocol GeometrySurfaceConversionSource: Sendable {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure
}
