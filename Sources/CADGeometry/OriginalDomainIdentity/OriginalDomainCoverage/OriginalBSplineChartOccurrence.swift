#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// An unreduced family member. Neither chart side nor integer lift is quotiented.
public struct OriginalBSplineChartOccurrence<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let sourceChart: OriginalSourceChart<S,OriginalBSplineChartSelection>
    public let cycles: [OriginalParameterCycle]
    public let correspondence: OriginalParameterTransport<S,F>
    public let selectedImage: OriginalParameterSelection<S,F>
    init(sourceChart: OriginalSourceChart<S,OriginalBSplineChartSelection>,cycles: [OriginalParameterCycle],
        correspondence: OriginalParameterTransport<S,F>,selectedImage: OriginalParameterSelection<S,F>) {
        self.sourceChart = sourceChart; self.cycles = cycles; self.correspondence = correspondence; self.selectedImage = selectedImage
    }
}
