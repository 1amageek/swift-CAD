import CADCore

/// Original endpoint normal cone after exact coefficient collapse admission.
package struct OriginalBSplinePoleNormalReceipt: Sendable {
    package let surface: BSplineSurface3D
    package let parameter: SurfaceParameter
    package let normal: Vector3D
    package let angularDeviationUpperBound: Double
    package let coefficientBounds: IntervalVector3DBounds
    package let tolerance: ModelingTolerance
}
