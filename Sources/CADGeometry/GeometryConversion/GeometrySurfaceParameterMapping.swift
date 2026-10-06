import CADCore

/// Owns the entire original UV image and its chain-rule derivatives.
public protocol GeometrySurfaceParameterMapping: Sendable {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws
    func parameter(u: Double, v: Double, tolerance: ModelingTolerance) throws -> SurfaceParameter
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceParameterMapEnclosure
}
