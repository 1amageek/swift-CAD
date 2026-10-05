import CADCore

/// Consumes exact original edge sectors to retain partial regular correspondence.
struct OriginalNativeCurveCurveClippedCorrespondence {
    func certificate(common: OriginalNativeCurveCurveCommonFactor, graph: ExactMonotoneRectangleGraph,
                     firstNativeSpan: Int, secondNativeSpan: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveAlgebraicCorrespondence? {
        try budget.work(graph.spans.count)
        for span in graph.spans {
            let lower = try graph.stations[span.lowerStation].endpoint.upper.outwardInterval(usage: &budget).upper
            let upper = try graph.stations[span.upperStation].endpoint.lower.outwardInterval(usage: &budget).lower
            guard lower.isFinite, upper.isFinite, lower < upper else { continue }
            let free = graph.freeAlongU ? graph.sourceDomain.u : graph.sourceDomain.v
            guard lower >= free.lower, upper <= free.upper else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: budget.tolerance,
                    message: "An original clipped graph sector escaped its authored native domain.")
            }
            let interval = try ScalarInterval(lower: lower, upper: upper)
            let parameters = graph.freeAlongU ? SurfaceParameterBox(u: interval, v: graph.sourceDomain.v)
                : SurfaceParameterBox(u: graph.sourceDomain.u, v: interval)
            try budget.retainExactStorage(1)
            return NativeCurveCurveAlgebraicCorrespondence(parameters: parameters, commonFactor: common.factor,
                originalEquationQuotients: common.quotients,
                dependentParameter: graph.freeAlongU ? .second : .first,
                firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan, originalMonotoneGraph: graph)
        }
        return nil
    }
}
