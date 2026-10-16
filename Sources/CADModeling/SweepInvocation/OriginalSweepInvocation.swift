import CADCore
import CADGeometry

/// Original source carriers retained through a nested Sweep evaluation.
package struct OriginalSweepInvocation: Sendable {
    package let section: ResolvedModelingSection?
    package let pathSpans: [ExactBSplineCurveSpan]
    package let pathIsClosed: Bool
    package let sourceBudget: CurvedSweepSourceBudget

    package init(section: ResolvedModelingSection? = nil, pathSpans: [ExactBSplineCurveSpan],
        pathIsClosed: Bool, sourceBudget: CurvedSweepSourceBudget, using execution: inout OriginalQueryExecution) throws {
        guard !pathSpans.isEmpty else {
            throw GeometryConversionError.invalidInput("An original Sweep invocation needs retained directed path spans.")
        }
        for span in pathSpans {
            try execution.consumeWork(1)
            guard span.correspondence.candidate == span.curve else {
                throw GeometryConversionError.invalidInput("A nested Sweep path candidate must retain its own original correspondence.")
            }
        }
        self.section = section; self.pathSpans = pathSpans
        self.pathIsClosed = pathIsClosed; self.sourceBudget = sourceBudget
    }
}
