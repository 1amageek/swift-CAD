import CADCore

/// One exact root of every supplied original equation, retaining both source fibers.
package struct ExactBivariateSystemRoot: Sendable {
    package let equations: [ExactBivariatePolynomial]
    package let projectionRoot: ExactAlgebraicRealRoot
    let fiber: ExactAlgebraicFiberPolynomial
    let fiberRoot: ExactAlgebraicFiberRootIsolator.Root
    package let sourceDomain: SurfaceParameterBox
    package let projectionMultiplicity: Int
    package let fiberMultiplicity: Int
    package var uExcludesLowerEndpoint: Bool { projectionRoot.isolation.excludesLowerEndpoint }
    package var uExcludesUpperEndpoint: Bool { projectionRoot.isolation.excludesUpperEndpoint }
    package var vExcludesLowerEndpoint: Bool { fiberRoot.excludesLower }
    package var vExcludesUpperEndpoint: Bool { fiberRoot.excludesUpper }

    package func retainingDepth<B: RationalAlgebraAdmitting>(_ depth: Int,
        usage: inout B) throws -> Self {
        guard depth >= projectionRoot.isolation.isolationDepth,
            depth >= fiberRoot.isolationDepth else {
            throw rationalAlgebraFailure("Original pair causal depth cannot move backwards.")
        }
        try usage.retainExactStorage(2)
        let projected = try projectionRoot.retainingDepth(depth)
        let retainedFiber = ExactAlgebraicFiberPolynomial(root: projected, coefficients: fiber.coefficients)
        let retainedRoot = ExactAlgebraicFiberRootIsolator.Root(lower: fiberRoot.lower, upper: fiberRoot.upper,
            excludesLower: fiberRoot.excludesLower, excludesUpper: fiberRoot.excludesUpper, isolationDepth: depth)
        return Self(equations: equations, projectionRoot: projected, fiber: retainedFiber,
            fiberRoot: retainedRoot, sourceDomain: sourceDomain,
            projectionMultiplicity: projectionMultiplicity, fiberMultiplicity: fiberMultiplicity)
    }

    package func enclosure<B: RationalAlgebraAdmitting>(usage: inout B) throws -> SurfaceParameterBox {
        try ExactAlgebraicParameterPair(projectionRoot: projectionRoot, fiber: fiber,
            fiberRoot: fiberRoot, sourceDomain: sourceDomain).enclosure(usage: &usage)
    }

    package func refined<B: RationalAlgebraAdmitting>(maximumUWidth: ExactRationalCoefficient,
        maximumVWidth: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Self {
        let pair = try ExactAlgebraicParameterPair(projectionRoot: projectionRoot, fiber: fiber,
            fiberRoot: fiberRoot, sourceDomain: sourceDomain).refined(maximumUWidth: maximumUWidth,
                maximumVWidth: maximumVWidth, maximumDepth: maximumDepth, usage: &usage)
        return Self(equations: equations, projectionRoot: pair.projectionRoot, fiber: pair.fiber,
            fiberRoot: pair.fiberRoot, sourceDomain: sourceDomain,
            projectionMultiplicity: projectionMultiplicity, fiberMultiplicity: fiberMultiplicity)
    }
    package func sign<B: RationalAlgebraAdmitting>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try ExactAlgebraicParameterPair(projectionRoot: projectionRoot, fiber: fiber,
            fiberRoot: fiberRoot, sourceDomain: sourceDomain).sign(of: expression,
                maximumDepth: maximumDepth, usage: &usage)
    }

}
