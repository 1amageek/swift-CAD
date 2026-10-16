import CADCore
import CADGeometry
import CADIR

/// Retains original section parameter authority independently of its construction image.
package struct OriginalLoftCurveSection: Sendable {
    package let source: OriginalCurveContactSource
    package let imageSpans: [ExactBSplineCurveSpan]
    package let isClosed: Bool
    package let isReversed: Bool

    package init(reference: CurveSectionReference, curves: [EvaluatedCurve]?,
                 using execution: inout OriginalQueryExecution,
                 tolerance: ModelingTolerance) throws {
        // Select the authored original trim before constructing a geometric image.
        // Shared resolution with a forward reference preserves the source law;
        // its reverse branch deliberately constructs an image and is not used.
        let forward = CurveSectionReference(featureID: reference.featureID,
            parameterDomain: reference.parameterDomain, isReversed: false)
        let selected = try ResolvedModelingSection.resolveCurve(forward, from: curves, tolerance: tolerance, using: &execution)
        guard let original = selected.exactCurve else {
            throw KernelError(phase: .geometry, code: .missingReference, tolerance: tolerance,
                message: "A Loft curve section requires its original exact curve law.")
        }
        let range: ScalarInterval
        switch selected.parameterDomain {
        case .closed(let lower, let upper):
            range = try ScalarInterval(lower: lower, upper: upper)
        case .periodic(let period) where selected.isClosed:
            range = try ScalarInterval(lower: 0, upper: period)
        default:
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original Loft section contacts require a bounded authored trim or one closed native period.")
        }
        try execution.consumeWork(1)
        source = OriginalCurveContactSource(curve: original, parameters: range)
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, using: &execution).sectionSpans(from: selected, using: &execution)
        try execution.consumeWork(spans.count)
        if reference.isReversed {
            imageSpans = try spans.reversed().map {
                try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: tolerance), tolerance: tolerance,
                    originalChart: $0.originalChart.reversed(), using: &execution)
            }
        } else {
            imageSpans = spans
        }
        isClosed = selected.isClosed
        isReversed = reference.isReversed
    }
}
