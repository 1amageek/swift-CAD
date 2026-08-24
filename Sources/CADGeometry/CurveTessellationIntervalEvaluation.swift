import CADCore

/// A certified interval result paired with the midpoint position already
/// computed while establishing its derivative bounds.
package struct CurveTessellationIntervalEvaluation: Sendable {
    package let bounds: CurveTessellationIntervalBounds
    package let midpointPoint: Point3D
}
