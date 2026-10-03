import CADCore

public struct NativeSurfaceConversionSource: GeometrySurfaceConversionSource {
    public let surface: Surface3D
    private let prepared: PreparedSurfaceDifferentialEncloser

    public init(_ surface: Surface3D, tolerance: ModelingTolerance) throws {
        self.surface = surface
        // Preserve the source chart while avoiding subtraction of correlated boundary jets.
        if case .procedural(.ruled(let ruled)) = surface,
           case .bSpline = ruled.startBoundary, case .bSpline = ruled.endBoundary,
           let exact = try ruled.exactBSplineRepresentation(tolerance: tolerance) {
            prepared = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(exact), tolerance: tolerance)
        } else {
            prepared = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        }
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
        try prepared.enclosure(over: parameters, tolerance: tolerance)
    }
}
