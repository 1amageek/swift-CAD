import CADCore

/// Complete finite-ideal lifting; positive-dimensional real loci retain explicit refusal.
package struct ExactBivariateSystemSolver {
    package static func isolatedRoots<B: RationalAlgebraAdmitting>(
        of equations: [ExactBivariatePolynomial], over domain: SurfaceParameterBox,
        maximumDepth: Int, usage: inout B) throws -> [ExactBivariateSystemRoot] {
        guard !equations.isEmpty, maximumDepth >= 0, domain.u.width > 0, domain.v.width > 0 else {
            throw rationalAlgebraFailure("Exact source system solving requires all equations and a positive original rectangle.")
        }
        let basis = try ExactBivariateGroebnerBasis.reducedBasis(equations, usage: &usage)
        if basis.contains(where: { !$0.isZero && $0.uDegree == 0 && $0.vDegree == 0 }) { return [] }
        var candidate: ExactBivariatePolynomial?
        var pureVLeadingPower = false
        for value in basis {
            try usage.consumeExactWork(1)
            guard let leading = value.leading else { continue }
            if leading.key.v == 0, leading.key.u > 0 { candidate = value }
            if leading.key.u == 0, leading.key.v > 0 { pureVLeadingPower = true }
        }
        guard let projection = candidate, pureVLeadingPower else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Production native curve-pair
            // and silhouette paths require complete real positive-dimensional
            // decomposition, including isolated real points and vertical loci.
            // Exact complex dimension classification is not a real atlas and
            // cannot publish empty or partial finite-root success.
            throw ExactBivariateSystemClassification.positiveDimensionalOriginalIdeal(
                equations: equations, reducedBasis: basis)
        }
        let lowerU = try ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage)
        let upperU = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &usage)
        let lowerV = try ExactRationalCoefficient.originalDouble(domain.v.lower, usage: &usage)
        let upperV = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &usage)
        let stations = try ExactUnivariateRootIsolator().isolate(projection,
            lower: lowerU, upper: upperU, maximumDepth: maximumDepth, usage: &usage)
        var result: [ExactBivariateSystemRoot] = []
        for station in stations {
            let root = try ExactAlgebraicRealRoot(polynomial: projection, isolation: station, usage: &usage)
            var common = try ExactAlgebraicFiberPolynomial(source: .zero, at: root,
                maximumDepth: maximumDepth, usage: &usage)
            for equation in equations {
                let fiber = try ExactAlgebraicFiberPolynomial(source: equation, at: root,
                    maximumDepth: maximumDepth, usage: &usage)
                common = try ExactAlgebraicFiberPolynomial.gcd(common, fiber,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            guard !common.isZero else {
                throw ExactBivariateSystemClassification.positiveDimensionalOriginalIdeal(
                    equations: equations, reducedBasis: basis)
            }
            if common.degree == 0 { continue }
            let fibers = try ExactAlgebraicFiberRootIsolator.isolate(common,
                lower: lowerV, upper: upperV, maximumDepth: maximumDepth, usage: &usage)
            let projectionMultiplicity = try multiplicity(projection, at: root,
                maximumDepth: maximumDepth, usage: &usage)
            for fiberRoot in fibers {
                let fiberMultiplicity = try multiplicity(common, at: fiberRoot,
                    maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: ExactBivariateSystemRoot.self, usage: &usage)
                result.append(ExactBivariateSystemRoot(equations: equations, projectionRoot: root,
                    fiber: common, fiberRoot: fiberRoot, sourceDomain: domain,
                    projectionMultiplicity: projectionMultiplicity, fiberMultiplicity: fiberMultiplicity))
            }
        }
        return result
    }

    private static func multiplicity<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        at root: ExactAlgebraicRealRoot, maximumDepth: Int, usage: inout B) throws -> Int {
        var value = source, result = 0
        while !value.isZero {
            if case .zero = try root.sign(of: value, maximumDepth: maximumDepth, usage: &usage) {
                result = try rationalAlgebraCount(result, 1)
                value = try value.differentiated(alongU: true, usage: &usage)
            } else { break }
        }
        guard result > 0 else { throw rationalAlgebraFailure("Original projection root has no source multiplicity.") }
        return result
    }

    static func multiplicity<B: RationalAlgebraAdmitting>(_ source: ExactAlgebraicFiberPolynomial,
        at root: ExactAlgebraicFiberRootIsolator.Root, maximumDepth: Int, usage: inout B) throws -> Int {
        var value = source, result = 0
        while !value.isZero {
            let shared = try ExactAlgebraicFiberPolynomial.gcd(source, value,
                maximumDepth: maximumDepth, usage: &usage)
            if shared.degree <= 0 { break }
            let sequence = try ExactAlgebraicFiberSturmSequence(shared, maximumDepth: maximumDepth, usage: &usage)
            if try sequence.count(lower: root.lower, upper: root.upper, excludesLower: root.excludesLower,
                excludesUpper: root.excludesUpper, maximumDepth: maximumDepth, usage: &usage) != 1 { break }
            result = try rationalAlgebraCount(result, 1)
            value = try value.differentiated(usage: &usage)
        }
        guard result > 0 else { throw rationalAlgebraFailure("Original algebraic fiber root has no source multiplicity.") }
        return result
    }
}
