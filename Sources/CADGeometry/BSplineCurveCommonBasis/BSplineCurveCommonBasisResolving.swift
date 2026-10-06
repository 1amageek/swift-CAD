import CADCore

public protocol BSplineCurveCommonBasisResolving: Sendable {
    func resolve(
        first: BSplineCurve3D,
        second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurveCommonBasisPair

    /// Reserves numeric work and storage in the caller's cumulative allowance.
    func resolve(first: BSplineCurve3D, second: BSplineCurve3D,
                 tolerance: ModelingTolerance,
                 consumeWork: (_ count: Int) throws -> Void) throws -> BSplineCurveCommonBasisPair
}

extension BSplineCurveCommonBasisResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected implementations expose
    // only the unbounded entry point. Bounded Loft preparation must use an actual
    // callback-aware implementation; an uncharged legacy call is not completion.
    public func resolve(first: BSplineCurve3D, second: BSplineCurve3D,
                        tolerance: ModelingTolerance,
                        consumeWork: (_ count: Int) throws -> Void) throws -> BSplineCurveCommonBasisPair {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This common-basis resolver does not supply caller-paid preparation.")
    }
}
