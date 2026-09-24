/// Exact section boundaries used to locate guide contacts.
package struct ExactLoftGuideSection: Sendable {
    package let loops: [[ExactBSplineCurveSpan]]
    package init(loops: [[ExactBSplineCurveSpan]]) {
        self.loops = loops
    }
}
