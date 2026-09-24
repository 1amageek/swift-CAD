import CADIR

/// Exact section boundaries and optional support used to locate guide contacts.
package struct ExactLoftGuideSection: Sendable {
    package let loops: [[ExactBSplineCurveSpan]]
    package let plane: SketchPlane?

    package init(loops: [[ExactBSplineCurveSpan]], plane: SketchPlane?) {
        self.loops = loops
        self.plane = plane
    }
}
