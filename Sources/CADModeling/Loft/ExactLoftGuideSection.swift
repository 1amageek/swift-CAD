import CADCore
import CADGeometry

/// Construction images and independently retained original section contact laws.
package struct ExactLoftGuideSection: Sendable {
    package let loops: [[ExactBSplineCurveSpan]]
    package let originalContactLoops: [[OriginalCurveContactSource]]?

    package init(loops: [[ExactBSplineCurveSpan]],
                 originalContactLoops: [[OriginalCurveContactSource]]? = nil) {
        self.loops = loops
        self.originalContactLoops = originalContactLoops
    }
}
