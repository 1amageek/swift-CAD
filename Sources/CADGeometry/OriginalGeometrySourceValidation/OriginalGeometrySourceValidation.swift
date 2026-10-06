import CADCore

/// Composes actual original native source validators without a private allowance.
package struct OriginalGeometrySourceValidation: Sendable {
    package static func validate(_ curve: BSplineCurve3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws {
        try curve.validate(tolerance: tolerance, consumeWork: consumeWork)
    }

    package static func validate(_ surface: BSplineSurface3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws {
        try surface.validate(tolerance: tolerance, consumeWork: consumeWork)
    }
}
