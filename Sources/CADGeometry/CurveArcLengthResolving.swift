import CADCore

/// A reusable certified arc-length representation for one bounded curve span.
public protocol CurveArcLengthParameterization: Sendable {
    var lengthEnclosure: CurveArcLengthEnclosure { get }

    /// Reuses original preparation for an admitted native subinterval.
    func enclosure(over interval: ScalarInterval) throws -> CurveArcLengthEnclosure

    /// Original owning-span bounds; their union does not establish join smoothness.
    func differentialEnclosure(over interval: ScalarInterval) throws -> CurveDifferentialEnclosure

    /// Admits one-sided original native smoothness; unknown joins return false.
    func hasSmoothNativeInterval(over interval: ScalarInterval) throws -> Bool

    /// Localizes original inverse arc stations without replacing their source law.
    func parameterBounds(atFraction fraction: ScalarInterval,
        maximumParameterWidth: Double) throws -> ScalarInterval

    func parameterEnclosure(
        atArcLengthFraction fraction: Double
    ) throws -> CurveArcLengthParameterEnclosure
}

public protocol CurveArcLengthResolving: Sendable {
    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any CurveArcLengthParameterization

    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> CurveArcLengthEnclosure

    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization

    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure

    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization

    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure

    func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure

    func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure

    func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization
}

public extension CurveArcLengthResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy providers lack independently
    // retained source/algebra capabilities for selected Arc/Sweep preparation.
    // Their spatial-only facade cannot issue this original receipt.
    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> any CurveArcLengthParameterization {
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "This arc provider lacks independent original source and algebra admission.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy providers do not implement the
    // selected independent source/algebra Arc/Sweep reach proof. Publication
    // requires actual original preparation and queries under the supplied caps.
    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws -> CurveArcLengthEnclosure {
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "This arc provider lacks independent original source and algebra integration.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): A legacy arc provider has no actual
    // original allocation witness. Caller-admitted retained preparation must
    // consume coefficient and partition bytes before it may publish a receipt.
    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization {
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "This arc provider lacks original retained-byte admission.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This legacy provider does not forward
    // actual source/integration allocations. A work-only wrapper cannot prove
    // the caller's complete byte allowance for a bounded original length query.
    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure {
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "This arc provider lacks original integration-byte admission.")
    }

    func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy providers lack immutable same-ledger
        // original preparation for S5/S6 total/prefix reuse. Actual bounded source/partition
        // authority must be supplied before a prepared result may be published.
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "The arc-length provider has no bounded original preparation.")
    }

    func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure {
        // FIXME(INCOMPLETE_IMPLEMENTATION): A legacy provider has no same-invocation
        // original source validation/preparation/integration accounting. Bounded E6/S5/S6
        // publication requires its actual original-law producer to implement this witness.
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "The arc-length provider does not expose bounded original integration.")
    }

    func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try enclosure(
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }

    func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        try parameterEnclosure(
            atArcLengthFraction: fraction,
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }

    func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization {
        try parameterization(
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }
}

public extension CurveArcLengthParameterization {
    func parameterBounds(atFraction fraction: ScalarInterval,
        maximumParameterWidth: Double) throws -> ScalarInterval {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy receipts do not retain the
        // original paid partition and invocation needed by curved sweep endpoint
        // laws. A numeric inverse station cannot authorize source localization.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
            message: "This arc-length receipt lacks original inverse interval authority.")
    }

    func hasSmoothNativeInterval(over interval: ScalarInterval) throws -> Bool {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy receipts lack source-owning native
        // smoothness authority for the sweep remainder law. Original family and
        // positive-width owning chart admission must precede a smoothness result.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
            message: "This arc-length receipt has no original native smoothness authority.")
    }

    func differentialEnclosure(over interval: ScalarInterval) throws -> CurveDifferentialEnclosure {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy arc-length receipts do not retain
        // caller-paid original native jets for the production sweep remainder law.
        // Actual original preparation and owning-span hulls must precede publication.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
            message: "This arc-length receipt cannot expose original differential bounds.")
    }

    func enclosure(over interval: ScalarInterval) throws -> CurveArcLengthEnclosure {
        // FIXME(INCOMPLETE_IMPLEMENTATION): A legacy parameterization lacks native
        // subinterval proof reuse. Production bounded sweep station law must consume an
        // original prepared partition under its caller allowance, never a numeric inverse.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
            message: "This arc-length parameterization cannot prove native subinterval lengths.")
    }
}
