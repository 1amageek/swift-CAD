import CADCore

/// Certifies that a surface parameterization has a non-degenerate tangent
/// frame throughout a bounded parameter box.
public protocol SurfaceRegularityValidating: Sendable {
    func validate(
        _ surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws
    func validate(_ surface: Surface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
}

extension SurfaceRegularityValidating {
    public func validate(_ surface: Surface3D, over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Custom regularity conformers remain
        // reachable from composing geometry queries. They must implement the
        // same-execution proof before they may publish bounded regularity.
        throw KernelError(phase: .geometry, code: .unsupportedCapability,
            tolerance: tolerance, message: "Surface regularity conformer has no direct proof producer.")
    }
}

