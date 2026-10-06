import CADCore

/// Exact original algebraic parameter pair shared by system and critical certificates.
struct ExactAlgebraicParameterPair: Sendable {
    let projectionRoot: ExactAlgebraicRealRoot
    let fiber: ExactAlgebraicFiberPolynomial
    let fiberRoot: ExactAlgebraicFiberRootIsolator.Root
    let sourceDomain: SurfaceParameterBox

    func enclosure<B: RationalAlgebraAdmitting>(usage: inout B) throws -> SurfaceParameterBox {
        let ul = try projectionRoot.isolation.lower.outwardInterval(usage: &usage)
        let uu = try projectionRoot.isolation.upper.outwardInterval(usage: &usage)
        let vl = try fiberRoot.lower.outwardInterval(usage: &usage)
        let vu = try fiberRoot.upper.outwardInterval(usage: &usage)
        return try SurfaceParameterBox(
            u: ScalarInterval(lower: max(sourceDomain.u.lower, ul.lower), upper: min(sourceDomain.u.upper, uu.upper)),
            v: ScalarInterval(lower: max(sourceDomain.v.lower, vl.lower), upper: min(sourceDomain.v.upper, vu.upper)))
    }
    func refined<B: RationalAlgebraAdmitting>(maximumUWidth: ExactRationalCoefficient,
        maximumVWidth: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Self {
        let uWidth = maximumUWidth, vWidth = maximumVWidth
        guard uWidth.isPositive, vWidth.isPositive, maximumDepth >= 0 else {
            throw rationalAlgebraFailure("Exact critical refinement needs positive original UV widths and caller depth.")
        }
        let admittedRoot = try projectionRoot.retainingDepth(max(fiberRoot.isolationDepth, projectionRoot.isolation.isolationDepth))
        let uRoot = try admittedRoot.refined(maximumWidth: uWidth, maximumDepth: maximumDepth, usage: &usage)
        let source = ExactAlgebraicFiberPolynomial(root: uRoot, coefficients: fiber.coefficients)
        let sequence = try ExactAlgebraicFiberSturmSequence(source, maximumDepth: maximumDepth, usage: &usage)
        var lower = fiberRoot.lower, upper = fiberRoot.upper
        var excludesLower = fiberRoot.excludesLower, excludesUpper = fiberRoot.excludesUpper
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        var depth = max(fiberRoot.isolationDepth, uRoot.isolation.isolationDepth)
        guard depth <= maximumDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original parameter-pair refinement has exhausted retained source depth.")
        }
        while try upper.subtracting(lower, usage: &usage).subtracting(vWidth, usage: &usage).isPositive {
            try usage.visitExactCell(depth: depth)
            guard depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original critical fiber refinement exhausted caller depth.")
            }
            let middle = try lower.adding(upper, usage: &usage).divided(by: two, usage: &usage)
            if try sequence.count(lower: middle, upper: middle, excludesLower: false, excludesUpper: false,
                maximumDepth: maximumDepth, usage: &usage) == 1 {
                lower = middle; upper = middle; excludesLower = false; excludesUpper = false; depth += 1; break
            }
            let left = try sequence.count(lower: lower, upper: middle, excludesLower: excludesLower,
                excludesUpper: false, maximumDepth: maximumDepth, usage: &usage)
            if left == 1 { upper = middle; excludesUpper = false }
            else if left == 0 { lower = middle; excludesLower = true }
            else { throw rationalAlgebraFailure("Exact critical fiber refinement lost original unique root authority.") }
            depth += 1
        }
        let retainedRoot = try uRoot.retainingDepth(depth)
        let retainedFiber = ExactAlgebraicFiberPolynomial(root: retainedRoot, coefficients: source.coefficients)
        return Self(projectionRoot: retainedRoot, fiber: retainedFiber,
            fiberRoot: ExactAlgebraicFiberRootIsolator.Root(lower: lower, upper: upper,
                excludesLower: excludesLower, excludesUpper: excludesUpper, isolationDepth: depth), sourceDomain: sourceDomain)
    }

    /// Sign at the actual original parameter pair, never at a rounded midpoint.
    func sign<B: RationalAlgebraAdmitting>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        var pair = self
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while true {
            try CurrentTaskCancellationChecker().checkCancellation()
            let value = try ExactAlgebraicFiberPolynomial(source: expression,
                at: pair.projectionRoot, maximumDepth: maximumDepth, usage: &usage)
            if value.isZero { return .zero }
            let common = try ExactAlgebraicFiberPolynomial.gcd(pair.fiber, value,
                maximumDepth: maximumDepth, usage: &usage)
            if common.degree > 0 {
                let shared = try ExactAlgebraicFiberSturmSequence(common,
                    maximumDepth: maximumDepth, usage: &usage)
                if try shared.count(lower: pair.fiberRoot.lower, upper: pair.fiberRoot.upper,
                    excludesLower: pair.fiberRoot.excludesLower, excludesUpper: pair.fiberRoot.excludesUpper,
                    maximumDepth: maximumDepth, usage: &usage) == 1 { return .zero }
            }
            if value.degree == 0 {
                guard let constant = value.coefficients[0] else {
                    throw rationalAlgebraFailure("An original nonzero constant fiber lost its coefficient.")
                }
                return try constant.sign(at: pair.projectionRoot, maximumDepth: maximumDepth, usage: &usage)
            }
            let source = try ExactAlgebraicFiberSturmSequence(value, maximumDepth: maximumDepth, usage: &usage)
            let count = try source.count(lower: pair.fiberRoot.lower, upper: pair.fiberRoot.upper,
                excludesLower: false, excludesUpper: false, maximumDepth: maximumDepth, usage: &usage)
            if count == 0 || pair.fiberRoot.lower == pair.fiberRoot.upper {
                let middle = try pair.fiberRoot.lower.adding(pair.fiberRoot.upper, usage: &usage)
                    .divided(by: two, usage: &usage)
                return try value.evaluated(at: middle, usage: &usage)
                    .sign(at: pair.projectionRoot, maximumDepth: maximumDepth, usage: &usage)
            }
            let uWidth = try pair.projectionRoot.isolation.upper.subtracting(
                pair.projectionRoot.isolation.lower, usage: &usage)
            let vWidth = try pair.fiberRoot.upper.subtracting(pair.fiberRoot.lower, usage: &usage)
            guard vWidth.isPositive else {
                throw rationalAlgebraFailure("Exact source sign refinement lost a unique nonrational fiber root.")
            }
            pair = try pair.refined(maximumUWidth: uWidth.isPositive ? uWidth : .one,
                maximumVWidth: vWidth.divided(by: two, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        }
    }

}
