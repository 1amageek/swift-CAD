import CADCore

/// Geometry-issued authority for a one-sided native span integration domain.
/// Index and source identity cannot be authored by another module.
package struct SurfaceAreaNativeSpanDomain: Sendable {
    package let rectangle: SurfaceParameterBox
    package let radialRange: ScalarInterval?
    let index: Int
    let source: Surface3D
    let curve: SurfaceParameterCurve?
    let anchor: SurfaceParameter?
}
