import CADCore

public protocol IndependentShapeSourceValidating: Sendable {
    /// The caller supplies its existing operation deadline; no nested deadline is reset.
    func validate(_ source: IndependentShapeSource, tolerance: ModelingTolerance, limits: IndependentShapeSourceLimits, bodySourceGraph: DesignGraph?, check: @escaping @Sendable () throws -> Void) throws -> IndependentShapeSourceValidation
}
