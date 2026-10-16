import CADCore

/// Exact simultaneous P=Pu=Pv=0 retained by the original critical producer.
package struct ExactBivariateCriticalPoint: Sendable {
    package let original: ExactBivariatePolynomial
    private let parameters: ExactAlgebraicParameterPair
    var retainedOriginalParameters: ExactAlgebraicParameterPair { parameters }
    package var projectionRoot: ExactAlgebraicRealRoot { parameters.projectionRoot }
    package var sourceDomain: SurfaceParameterBox { parameters.sourceDomain }

    init(original: ExactBivariatePolynomial, projectionRoot: ExactAlgebraicRealRoot,
         fiber: ExactAlgebraicFiberPolynomial, fiberRoot: ExactAlgebraicFiberRootIsolator.Root,
         sourceDomain: SurfaceParameterBox) {
        self.original = original
        parameters = ExactAlgebraicParameterPair(projectionRoot: projectionRoot,
            fiber: fiber, fiberRoot: fiberRoot, sourceDomain: sourceDomain)
    }
    private init(original: ExactBivariatePolynomial, parameters: ExactAlgebraicParameterPair) {
        self.original = original; self.parameters = parameters
    }
    /// Publishes critical authority only after all three actual source equations vanish.
    package static func proven<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        at root: ExactBivariateSystemRoot, maximumDepth: Int, usage: inout B) throws -> Self? {
        guard !original.isZero else { return nil }
        let pu = try original.differentiated(alongU: true, usage: &usage)
        let pv = try original.differentiated(alongU: false, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        for equation in [original, pu, pv] {
            guard case .zero = try root.sign(of: equation, maximumDepth: maximumDepth, usage: &usage) else {
                return nil
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(original: original, projectionRoot: root.projectionRoot, fiber: root.fiber,
            fiberRoot: root.fiberRoot, sourceDomain: root.sourceDomain)
    }

    package func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> SurfaceParameterBox {
        try parameters.enclosure(usage: &usage)
    }
    package func refined<B: ExactScalarAdmission & ~Copyable>(maximumUWidth: Double, maximumVWidth: Double,
        maximumDepth: Int, usage: inout B) throws -> Self {
        let u = try ExactRationalCoefficient.originalDouble(maximumUWidth, usage: &usage)
        let v = try ExactRationalCoefficient.originalDouble(maximumVWidth, usage: &usage)
        return try Self(original: original, parameters: parameters.refined(maximumUWidth: u,
            maximumVWidth: v, maximumDepth: maximumDepth, usage: &usage))
    }
    package func sign<B: ExactScalarAdmission & ~Copyable>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try parameters.sign(of: expression, maximumDepth: maximumDepth, usage: &usage)
    }

}
