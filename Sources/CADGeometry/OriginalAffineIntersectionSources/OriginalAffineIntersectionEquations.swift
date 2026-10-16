import CADCore

/// Raw original affine-image equations and source binding, without a coverage claim.
package struct OriginalAffineIntersectionEquations: Sendable {
    private enum Sources: Sendable {
        case curveSurface(OriginalRationalCurvePolynomial, OriginalAffineSurfaceIntersectionSource)
        case surfaceSurface(OriginalAffineSurfaceIntersectionSource, OriginalRationalSurfacePolynomial)
    }
    private let sources: Sources
    package let variableCount: Int
    package let equations: [ExactIntersectionPolynomial]
    package let denominatorGuards: [ExactIntersectionPolynomial]
    package let domains: [OriginalRationalParameterDomain]
    package var affineSurface: OriginalAffineSurfaceIntersectionSource {
        switch sources { case .curveSurface(_, let surface): surface
        case .surfaceSurface(let surface, _): surface }
    }
    package var curve: OriginalRationalCurvePolynomial? {
        if case .curveSurface(let curve, _) = sources { return curve }; return nil
    }
    package var otherSurface: OriginalRationalSurfacePolynomial? {
        if case .surfaceSurface(_, let surface) = sources { return surface }; return nil
    }

    package init<B: ExactScalarAdmission & ~Copyable>(curve: OriginalRationalCurvePolynomial,
        surface: OriginalAffineSurfaceIntersectionSource, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard curve.homogeneous.count == 4, curve.homogeneous.allSatisfy({ $0.vDegree <= 0 }),
            !curve.homogeneous[3].isZero else {
            throw rationalAlgebraFailure("Affine CS requires original one-parameter homogeneous curve authority.")
        }
        let a = try Self.embedding(curve.homogeneous, variables: 3, u: 0, v: 1, usage: &usage)
        let b = try Self.embedding(surface.homogeneous, variables: 3, u: 1, v: 2, usage: &usage)
        let equations = try Self.equations(a, b, usage: &usage)
        let t = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try usage.consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        sources = .curveSurface(curve, surface); variableCount = 3
        self.equations = equations; denominatorGuards = [a[3], b[3]]
        domains = [t, surface.uDomain, surface.vDomain]
    }

    package init<B: ExactScalarAdmission & ~Copyable>(first: OriginalAffineSurfaceIntersectionSource,
        second: OriginalRationalSurfacePolynomial, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard second.homogeneous.count == 4, !second.homogeneous[3].isZero else {
            throw rationalAlgebraFailure("Affine SSI requires original Native homogeneous surface authority.")
        }
        let a = try Self.embedding(first.homogeneous, variables: 4, u: 0, v: 1, usage: &usage)
        let b = try Self.embedding(second.homogeneous, variables: 4, u: 2, v: 3, usage: &usage)
        let equations = try Self.equations(a, b, usage: &usage)
        let u = try OriginalRationalParameterDomain(second.domain.u, usage: &usage)
        let v = try OriginalRationalParameterDomain(second.domain.v, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try usage.consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        sources = .surfaceSurface(first, second); variableCount = 4
        self.equations = equations; denominatorGuards = [a[3], b[3]]
        domains = [first.uDomain, first.vDomain, u, v]
    }

    private static func embedding<B: ExactScalarAdmission & ~Copyable>(_ source: [ExactBivariatePolynomial],
        variables: Int, u: Int, v: Int, usage: inout B) throws -> [ExactIntersectionPolynomial] {
        try RationalAlgebraStorage.retain(4, of: ExactIntersectionPolynomial.self, usage: &usage)
        var result: [ExactIntersectionPolynomial] = []; result.reserveCapacity(4)
        for polynomial in source {
            try intersectionAlgebraStep(&usage)
            result.append(try .embedding(polynomial, variableCount: variables,
                uCoordinate: u, vCoordinate: v, usage: &usage))
        }
        return result
    }
    private static func equations<B: ExactScalarAdmission & ~Copyable>(_ first: [ExactIntersectionPolynomial],
        _ second: [ExactIntersectionPolynomial], usage: inout B) throws -> [ExactIntersectionPolynomial] {
        try RationalAlgebraStorage.retain(3, of: ExactIntersectionPolynomial.self, usage: &usage)
        var result: [ExactIntersectionPolynomial] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            try intersectionAlgebraStep(&usage)
            result.append(try first[axis].multiplied(by: second[3], usage: &usage)
                .subtracting(second[axis].multiplied(by: first[3], usage: &usage), usage: &usage))
        }
        return result
    }
}
