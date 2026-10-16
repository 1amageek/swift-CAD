import CADCore

/// Composes actual original native source validators without a private allowance.
package struct OriginalGeometrySourceValidation: Sendable {
    package static func validate(_ curve: BSplineCurve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try curve.validate(tolerance: tolerance, using: &execution)
    }

    package static func validate(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try surface.validate(tolerance: tolerance, using: &execution)
    }
}
