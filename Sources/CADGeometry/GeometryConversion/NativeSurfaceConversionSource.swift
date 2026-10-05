import CADCore

public struct NativeSurfaceConversionSource: GeometrySurfaceConversionSource {
    public let surface: Surface3D
    private enum EnclosureStorage: Sendable {
        case originalPolynomialRuled(OriginalPolynomialRuledConversionSource)
        case originalNative(PreparedSurfaceDifferentialEncloser)
    }
    private let prepared: EnclosureStorage

    public init(_ surface: Surface3D, tolerance: ModelingTolerance) throws {
        try Task.checkCancellation()
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        if case .procedural(.ruled(let ruled)) = surface,
           OriginalPolynomialRuledConversionSource.accepts(ruled) {
            prepared = .originalPolynomialRuled(try OriginalPolynomialRuledConversionSource(ruled, tolerance: tolerance))
        } else {
            prepared = .originalNative(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
        }
        try Task.checkCancellation()
    }
    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        guard parameters.u.width.isFinite, parameters.v.width.isFinite else {
            throw GeometryConversionError.invalidInput("Surface conversion requires finite parameter extents.")
        }
        try parameters.validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
    }
    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try surface.point(u: u, v: v, tolerance: tolerance)
    }
    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try Task.checkCancellation()
        let result: SurfaceDifferentialEnclosure
        switch prepared {
        case .originalPolynomialRuled(let original): result = try original.enclosure(over: parameters, tolerance: tolerance)
        case .originalNative(let original): result = try original.enclosure(over: parameters, tolerance: tolerance)
        }
        try Task.checkCancellation()
        return result
    }
}
