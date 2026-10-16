import CADCore

/// Immutable original correspondence policy and attribution on the caller's budget.
struct OriginalCorrespondencePolicy {
    private let proofWork: OriginalQueryContributionHandle
    private let sourceScalars: OriginalQueryContributionHandle
    let maximumWork: Int
    let maximumDepth: Int
    let tolerance: ModelingTolerance
    var consumedCellCount: Int { proofWork.snapshot.work }
    var sourceScalarCount: Int { sourceScalars.snapshot.work }

    init(options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try options.validate(tolerance: tolerance)
        guard options.maximumCellCount <= 65_536, options.maximumSubdivisionDepth <= 32 else {
            throw Self.failure(.invalidInput, tolerance,
                "Original correspondence requires at most 65536 aggregate work records and depth 32.")
        }
        maximumWork = options.maximumCellCount
        maximumDepth = options.maximumSubdivisionDepth
        self.tolerance = tolerance
        let allocationPolicy = execution.effectiveAllocationPolicy
        proofWork = try execution.makeContributionHandle(workLimit: options.maximumCellCount,
            allocationPolicy: allocationPolicy)
        sourceScalars = try execution.makeContributionHandle(workLimit: options.maximumCellCount,
            allocationPolicy: allocationPolicy)
    }

    func admitTemporaryScalars(_ count: Int, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        let total = sourceScalarCount.addingReportingOverflow(count)
        guard count >= 0, !total.overflow, total.partialValue <= maximumWork else {
            throw Self.failure(.resourceLimitExceeded, tolerance,
                "Original correspondence exhausted its bounded source and temporary numeric storage.")
        }
    }

    func charge(_ count: Int = 1, using execution: inout OriginalQueryExecution) throws {
        guard count >= 0 else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Original correspondence work must be nonnegative.")
        }
        try execution.withContributionScope(proofWork) { execution in
            try execution.consumeWork(count)
        }
    }

    func admitSources(curve: Curve3D, surface: Surface3D,
                              parameterCurve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution) throws {
        // Scalars and proof cells are distinct quantities with the same caller ceiling.
        guard case let .bSpline(spatial) = curve else { throw unsupported() }
        try scalarProduct(spatial.controlPoints.count, 3, using: &execution)
        try scalarCharge(spatial.knots.count, using: &execution)
        try scalarCharge(spatial.weights.count, using: &execution)
        switch parameterCurve {
        case let .bSpline(value):
            try scalarProduct(value.controlPoints.count, 2, using: &execution)
            try scalarCharge(value.knots.count, using: &execution)
            try scalarCharge(value.weights.count, using: &execution)
        case .affine: try scalarCharge(6, using: &execution)
        case .constantU, .constantV: try scalarCharge(3, using: &execution)
        default: throw unsupported()
        }
        switch surface {
        case .plane: try scalarCharge(6, using: &execution)
        case let .bSpline(value):
            // Row counts are charged before scanning row lengths.
            try scalarCharge(value.controlPoints.count, using: &execution)
            for row in value.controlPoints { try scalarProduct(row.count, 3, using: &execution) }
            try scalarCharge(value.weights.count, using: &execution)
            for row in value.weights { try scalarCharge(row.count, using: &execution) }
            try scalarCharge(value.uKnots.count, using: &execution)
            try scalarCharge(value.vKnots.count, using: &execution)
        default: throw unsupported()
        }
    }

    private func scalarCharge(_ count: Int, using execution: inout OriginalQueryExecution) throws {
        guard count >= 0 else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Original correspondence source scalar count must be nonnegative.")
        }
        try execution.withContributionScope(sourceScalars) { execution in
            try execution.consumeWork(count)
        }
    }

    private func scalarProduct(_ count: Int, _ factor: Int, using execution: inout OriginalQueryExecution) throws {
        let total = count.multipliedReportingOverflow(by: factor)
        guard !total.overflow else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Original correspondence dimensions overflowed.")
        }
        try scalarCharge(total.partialValue, using: &execution)
    }

    func unsupported() -> KernelError {
        // FIXME(INCOMPLETE_IMPLEMENTATION): General curve/surface families lack an
        // original whole-use proof. The public original-correspondence factory
        // refuses them until original coefficient, chart and budget authority exist.
        Self.failure(.unsupportedCapability, tolerance,
            "Original correspondence has no coefficient proof for this geometry family.")
    }

    static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                        _ message: String, residual: Double? = nil) -> KernelError {
        KernelError(phase: .geometry, code: code, residual: residual,
            tolerance: tolerance, message: message)
    }
}
