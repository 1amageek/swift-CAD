/// Geometric enclosure of an existing original exact scalar pair.
struct ExactAlgebraicParameterPair: Sendable {
    let projectionRoot: ExactAlgebraicRealRoot
    let fiber: ExactAlgebraicFiberPolynomial
    let fiberRoot: ExactAlgebraicFiberRootIsolator.Root
    let sourceDomain: SurfaceParameterBox
    var scalarAuthority: ExactAlgebraicPairAuthority {
        .init(projectionRoot: projectionRoot, fiber: fiber, fiberRoot: fiberRoot)
    }

    func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> SurfaceParameterBox {
        let ul = try projectionRoot.isolation.lower.outwardInterval(usage: &usage)
        let uu = try projectionRoot.isolation.upper.outwardInterval(usage: &usage)
        let vl = try fiberRoot.lower.outwardInterval(usage: &usage)
        let vu = try fiberRoot.upper.outwardInterval(usage: &usage)
        return try SurfaceParameterBox(
            u: ScalarInterval(lower: max(sourceDomain.u.lower, ul.lower), upper: min(sourceDomain.u.upper, uu.upper)),
            v: ScalarInterval(lower: max(sourceDomain.v.lower, vl.lower), upper: min(sourceDomain.v.upper, vu.upper)))
    }
    func refined<B: ExactScalarAdmission & ~Copyable>(maximumUWidth: ExactRationalCoefficient,
        maximumVWidth: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Self {
        let result = try scalarAuthority.refined(maximumUWidth: maximumUWidth,
            maximumVWidth: maximumVWidth, maximumDepth: maximumDepth, usage: &usage)
        return Self(projectionRoot: result.projectionRoot, fiber: result.fiber,
            fiberRoot: result.fiberRoot, sourceDomain: sourceDomain)
    }
    func sign<B: ExactScalarAdmission & ~Copyable>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try scalarAuthority.sign(of: expression, maximumDepth: maximumDepth, usage: &usage)
    }
}
