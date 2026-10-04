import CADCore

struct OriginalCorrespondenceBudget {
    let maximumWork: Int
    let maximumDepth: Int
    let tolerance: ModelingTolerance
    private(set) var consumedCellCount = 0
    private(set) var sourceScalarCount = 0

    init(options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance) throws {
        try options.validate(tolerance: tolerance)
        guard options.maximumCellCount <= 65_536, options.maximumSubdivisionDepth <= 32 else {
            throw Self.failure(.invalidInput, tolerance,
                "Original correspondence requires at most 65536 aggregate work records and depth 32.")
        }
        maximumWork = options.maximumCellCount
        maximumDepth = options.maximumSubdivisionDepth
        self.tolerance = tolerance
    }

    mutating func charge(_ count: Int = 1) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let next = consumedCellCount.addingReportingOverflow(count)
        guard count >= 0, !next.overflow, next.partialValue <= maximumWork else {
            throw Self.failure(.resourceLimitExceeded, tolerance,
                "Original correspondence exhausted its aggregate preparation and traversal work.")
        }
        consumedCellCount = next.partialValue
    }

    mutating func admitSources(curve: Curve3D, surface: Surface3D,
                              parameterCurve: SurfaceParameterCurve) throws {
        // Scalars and proof cells are distinct quantities with the same caller ceiling.
        guard case let .bSpline(spatial) = curve else { throw unsupported() }
        try scalarProduct(spatial.controlPoints.count, 3)
        try scalarCharge(spatial.knots.count)
        try scalarCharge(spatial.weights.count)
        switch parameterCurve {
        case let .bSpline(value):
            try scalarProduct(value.controlPoints.count, 2)
            try scalarCharge(value.knots.count)
            try scalarCharge(value.weights.count)
        case .affine: try scalarCharge(6)
        case .constantU, .constantV: try scalarCharge(3)
        default: throw unsupported()
        }
        switch surface {
        case .plane: try scalarCharge(6)
        case let .bSpline(value):
            // Row counts are charged before scanning row lengths.
            try scalarCharge(value.controlPoints.count)
            for row in value.controlPoints { try scalarProduct(row.count, 3) }
            try scalarCharge(value.weights.count)
            for row in value.weights { try scalarCharge(row.count) }
            try scalarCharge(value.uKnots.count)
            try scalarCharge(value.vKnots.count)
        default: throw unsupported()
        }
    }

    private mutating func scalarCharge(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let total = sourceScalarCount.addingReportingOverflow(count)
        guard count >= 0, !total.overflow, total.partialValue <= maximumWork else {
            throw Self.failure(.resourceLimitExceeded, tolerance,
                "Original correspondence exhausted its original-source scalar admission ceiling.")
        }
        sourceScalarCount = total.partialValue
    }

    private mutating func scalarProduct(_ count: Int, _ factor: Int) throws {
        let total = count.multipliedReportingOverflow(by: factor)
        guard !total.overflow else {
            throw Self.failure(.resourceLimitExceeded, tolerance, "Original correspondence dimensions overflowed.")
        }
        try scalarCharge(total.partialValue)
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
