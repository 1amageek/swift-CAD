import CADCore

public protocol SurfaceSurfaceIntersecting: Sendable {
    func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult
    func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> SurfaceSurfaceIntersectionResult
    func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> SurfaceSurfaceIntersectionResult
    func intersections(
        first: Surface3D,
        second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]
    func intersections(
        first: Surface3D,
        second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        maximumSpanCount: Int,
        maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?
    ) throws -> [SurfaceSurfaceIntersection]
    func intersections(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> [SurfaceSurfaceIntersection]

    func prepareOriginalPair(first: Surface3D, second: Surface3D,
        tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> any OriginalSurfacePairIntersecting

    func prepareOriginalSelf(surface: Surface3D, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> any OriginalSurfacePairIntersecting

}

public extension SurfaceSurfaceIntersecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must implement rich
    // original coverage before this public witness may return a complete receipt.
    func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance) throws -> SurfaceSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no rich original result producer.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must forward the
    // caller ledger through rich publication; array replay is not that witness.
    func intersectionResult(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no admitted rich result producer.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom SSI conformers must retain selected
    // original domain-pair coverage before publishing this rich public result.
    func intersectionResult(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> SurfaceSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no rich original domain-pair producer.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected surface-pair conformer
    // must forward every original work/storage visit before bounded callers can
    // consume its results. The legacy requirement cannot supply that witness.
    func intersections(first: Surface3D, second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> [SurfaceSurfaceIntersection] {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no caller-admitted original producer.")
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
    // the same original-domain pair producer and forward every caller visit;
    // no legacy restricted-surface conversion establishes this witness.
    func intersections(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> [SurfaceSurfaceIntersection] {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer has no original domain-pair producer.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
    // retained original support preparation under the supplied invocation.
    // A legacy per-box intersection replay cannot establish this session.
    func prepareOriginalPair(first: Surface3D, second: Surface3D,
        tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> any OriginalSurfacePairIntersecting {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer cannot prepare a caller-admitted original session.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected conformers must implement
    // one retained original support aliased for both self-query roles under
    // this invocation; replaying independent legacy preparation is not a witness.
    func prepareOriginalSelf(surface: Surface3D, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> any OriginalSurfacePairIntersecting {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This surface-pair conformer cannot prepare an original self-query session.")
    }

}
