import CADCore

/// Invocation-local accounting shared by regular graph discovery and clipping.
struct OverlapProofBudget {
    let options: CurveSurfaceIntersectionOptions
    let tolerance: ModelingTolerance
    private var remainingWork: Int
    private var remainingStorage: Int

    init(options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance) {
        self.options = options
        self.tolerance = tolerance
        remainingWork = options.maximumSubdivisionCells
        remainingStorage = options.maximumCandidateCount
    }

    mutating func work(_ count: Int = 1) throws {
        try Task.checkCancellation()
        guard count >= 0, count <= remainingWork else { throw failure("Regular overlap exhausted its cumulative work budget.") }
        remainingWork -= count
    }

    mutating func storage(_ count: Int = 1) throws {
        try work(count)
        guard count >= 0, count <= remainingStorage else { throw failure("Regular overlap exhausted its retained-cell and cut storage budget.") }
        remainingStorage -= count
    }

    func depth(_ value: Int) throws {
        guard value <= options.maximumSubdivisionDepth else { throw failure("Regular overlap exhausted its subdivision depth.") }
    }

    mutating func preparation(curve: BSplineCurve3D, surface: BSplineSurface3D) throws {
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
        try work(total.partialValue)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
