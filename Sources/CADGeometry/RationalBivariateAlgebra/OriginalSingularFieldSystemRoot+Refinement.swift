/// Causal enclosure/refinement of a retained original ordered-field parameter pair.
package extension OriginalSingularFieldSystemRoot {
    func hasSameValue<B: ExactScalarAdmission & ~Copyable>(as other: Self,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        guard projectionRoot.polynomial.context === other.projectionRoot.polynomial.context else {
            throw rationalAlgebraFailure("Original field point comparison needs identical original coefficient authority.")
        }
        var first = OriginalSingularFieldEndpoint.algebraic(projectionRoot)
        var second = OriginalSingularFieldEndpoint.algebraic(other.projectionRoot)
        if try OriginalSingularFieldEndpoint.compare(&first, &second, maximumDepth: maximumDepth, usage: &usage) != 0 { return false }
        if fiberRoot.polynomial.context === other.fiberRoot.polynomial.context {
            var a = OriginalSingularFieldEndpoint.algebraic(fiberRoot)
            var b = OriginalSingularFieldEndpoint.algebraic(other.fiberRoot)
            return try OriginalSingularFieldEndpoint.compare(&a, &b, maximumDepth: maximumDepth, usage: &usage) == 0
        }
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(other.v.context, into: v.context,
            maximumDepth: maximumDepth, usage: &usage)
        let a = try v.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        let b = try transport.applying(to: other.v, in: context, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = try a.subtracting(b, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return true }
        return false
    }
    func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> SurfaceParameterBox {
        let first = try projectionRoot.isolation.lower.outwardInterval(usage: &usage)
        let second = try projectionRoot.isolation.upper.outwardInterval(usage: &usage)
        let third = try fiberRoot.isolation.lower.outwardInterval(usage: &usage)
        let fourth = try fiberRoot.isolation.upper.outwardInterval(usage: &usage)
        return try SurfaceParameterBox(u: ScalarInterval(lower: max(sourceDomain.u.lower, first.lower),
            upper: min(sourceDomain.u.upper, second.upper)),
            v: ScalarInterval(lower: max(sourceDomain.v.lower, third.lower), upper: min(sourceDomain.v.upper, fourth.upper)))
    }

    func refined<B: ExactScalarAdmission & ~Copyable>(maximumUWidth: ExactRationalCoefficient,
        maximumVWidth: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumUWidth.isPositive, maximumVWidth.isPositive, !equations.isEmpty else {
            throw rationalAlgebraFailure("Original field pair refinement needs positive widths and retained original equations.")
        }
        let projection = try projectionRoot.refined(maximumWidth: maximumUWidth,
            maximumDepth: maximumDepth, usage: &usage)
        let first = try projection.value(maximumDepth: maximumDepth, usage: &usage)
        // The projection is a refinement of the same unique original root.
        // Reevaluate original equations at that retained root; no elimination or
        // new root isolation is performed, and the old transverse interval is
        // retained only after its exact count remains one.
        var common = try OriginalSingularFieldPolynomial(context: first.context, coefficients: [],
            maximumDepth: maximumDepth, usage: &usage)
        for equation in equations {
            let fiber = try OriginalSingularFieldSystemSolver.fiber(equation, at: first,
                maximumDepth: maximumDepth, usage: &usage)
            common = try OriginalSingularFieldPolynomial.gcd(common, fiber, maximumDepth: maximumDepth, usage: &usage)
        }
        guard !common.isZero else { throw rationalAlgebraFailure("Original field pair refinement lost finite fiber authority.") }
        let depth = max(projection.isolation.depth, fiberRoot.isolation.depth)
        guard depth <= maximumDepth else { throw rationalAlgebraFailure("Original field pair refinement exceeds causal caller depth.") }
        try usage.visitCell(axis: .value, depth: depth)
        let sequence = try OriginalSingularFieldSturm(common, maximumDepth: maximumDepth, usage: &usage)
        let bounds = fiberRoot.isolation
        guard try sequence.count(lower: bounds.lower, upper: bounds.upper,
            excludesLower: bounds.excludesLower, excludesUpper: bounds.excludesUpper,
            maximumDepth: maximumDepth, usage: &usage) == 1 else {
            throw rationalAlgebraFailure("Original field pair refinement lost its unique transverse source root.")
        }
        let retained = OriginalSingularFieldRoot(polynomial: sequence.source, isolation: .init(lower: bounds.lower,
            upper: bounds.upper, excludesLower: bounds.excludesLower, excludesUpper: bounds.excludesUpper, depth: depth))
        let transverse = try retained.refined(maximumWidth: maximumVWidth, maximumDepth: maximumDepth, usage: &usage)
        let second = try transverse.value(maximumDepth: maximumDepth, usage: &usage)
        let result = Self(equations: equations, projectionRoot: projection, fiberRoot: transverse,
            u: first, v: second, sourceDomain: sourceDomain)
        for equation in equations {
            guard case .zero = try result.sign(of: equation, maximumDepth: maximumDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Refined original field pair is not a zero of every retained equation.")
            }
        }
        return result
    }
}
