import CADCore
import CADGeometry

/// Original directed axis endpoints, bound to the retained chart source.
package struct ExactRectangularPcurveAxisEndpoints: Sendable {
    package let curve: SurfaceParameterCurve
    package let surface: Surface3D
    package let tolerance: ModelingTolerance
    package let start: SurfaceParameter
    package let end: SurfaceParameter
}
