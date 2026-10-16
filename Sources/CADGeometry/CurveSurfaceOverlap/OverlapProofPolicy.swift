import CADCore

/// Invocation-local accounting shared by regular graph discovery and clipping.
struct OverlapProofPolicy {
    let options: CurveSurfaceIntersectionOptions
    let tolerance: ModelingTolerance
    private let contribution: OriginalQueryContributionHandle

    init(options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        self.options = options
        self.tolerance = tolerance
        contribution = try execution.makeContributionHandle(workLimit: options.maximumSubdivisionCells,
            recordLimit: options.maximumCandidateCount, allocationPolicy: execution.effectiveAllocationPolicy)
    }

    func work(_ count: Int = 1, using execution: inout OriginalQueryExecution) throws {
        guard count >= 0 else { throw failure("Regular overlap work must be nonnegative.") }
        do {
            try execution.withContributionScope(contribution) { execution in
                try execution.consumeWork(count)
            }
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    func storage(_ count: Int = 1, using execution: inout OriginalQueryExecution) throws {
        guard count >= 0 else { throw failure("Regular overlap retained count must be nonnegative.") }
        do {
            try execution.withContributionScope(contribution) { execution in
                // Preserve the original work-before-retained-record ordering.
                // One scope avoids billing nested-scope metadata to proof fees.
                try execution.consumeWork(count)
                try execution.consumeRecords(count)
            }
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    func depth(_ value: Int, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        guard value >= 0, value <= options.maximumSubdivisionDepth else {
            throw failure("Regular overlap exhausted its subdivision depth.")
        }
        try execution.visitCertificationCell(depth: value)
    }

    func preparation(curve: BSplineCurve3D, surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws {
        guard max(curve.degree, max(surface.uDegree, surface.vDegree)) <= options.maximumPolynomialDegree else {
            throw failure("Regular overlap exceeds its rational degree budget.")
        }
        let surfaceCount = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
        let sourceCount = curve.controlPointCount.multipliedReportingOverflow(by: curve.degree + 1)
        let targetCount = surfaceCount.partialValue.multipliedReportingOverflow(by: (surface.uDegree + 1) * (surface.vDegree + 1))
        let total = sourceCount.partialValue.addingReportingOverflow(targetCount.partialValue)
        guard !surfaceCount.overflow, !sourceCount.overflow, !targetCount.overflow, !total.overflow else {
            throw failure("Regular overlap preparation storage count overflowed.")
        }
        // Charge representation workspace before either prepared owner decomposes it.
        try work(total.partialValue, using: &execution)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
