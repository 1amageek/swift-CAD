import CADCore

/// Whole original native panel with an exact endpoint-factor normal authority.
package struct OriginalBSplinePoleNormalPanel: Sendable {
    package let surface: BSplineSurface3D
    package let parameters: SurfaceParameterBox
    package let span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let direction: OriginalBSplinePoleNormal.Direction
    package let factorBounds: IntervalVector3DBounds
    package let tolerance: ModelingTolerance
    package let differentialBounds: SurfaceTessellationDifferentialBounds
}
