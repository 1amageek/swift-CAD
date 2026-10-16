import CADCore

/// Original native source equations and denominator guards, without a real-coverage claim.
package struct OriginalRationalIntersectionSystem: Sendable {
    private enum Sources: Sendable {
        case curveSurface(OriginalRationalCurvePolynomial, OriginalRationalSurfacePolynomial)
        case surfaceSurface(OriginalRationalSurfacePolynomial, OriginalRationalSurfacePolynomial)
    }

    private let sources: Sources
    package let variableCount: Int
    package let equations: [ExactIntersectionPolynomial]
    package let denominatorGuards: [ExactIntersectionPolynomial]

    package init<B: ExactScalarAdmission & ~Copyable>(curve: OriginalRationalCurvePolynomial,
        surface: OriginalRationalSurfacePolynomial, usage: inout B) throws {
        guard curve.homogeneous.count == 4, surface.homogeneous.count == 4,
              curve.homogeneous.allSatisfy({ $0.vDegree <= 0 }) else {
            throw rationalAlgebraFailure("CS equations require original one-parameter and two-parameter homogeneous laws.")
        }
        sources = .curveSurface(curve, surface)
        variableCount = 3
        let first = try Self.embedding(curve.homogeneous, variableCount: 3,
            uCoordinate: 0, vCoordinate: 1, usage: &usage)
        let second = try Self.embedding(surface.homogeneous, variableCount: 3,
            uCoordinate: 1, vCoordinate: 2, usage: &usage)
        equations = try Self.coincidenceEquations(first, second, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
        denominatorGuards = [first[3], second[3]]
    }

    package init<B: ExactScalarAdmission & ~Copyable>(first: OriginalRationalSurfacePolynomial,
        second: OriginalRationalSurfacePolynomial, usage: inout B) throws {
        guard first.homogeneous.count == 4, second.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("SSI equations require both original homogeneous surface laws.")
        }
        sources = .surfaceSurface(first, second)
        variableCount = 4
        let a = try Self.embedding(first.homogeneous, variableCount: 4,
            uCoordinate: 0, vCoordinate: 1, usage: &usage)
        let b = try Self.embedding(second.homogeneous, variableCount: 4,
            uCoordinate: 2, vCoordinate: 3, usage: &usage)
        equations = try Self.coincidenceEquations(a, b, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
        denominatorGuards = [a[3], b[3]]
    }

    package var curveSource: OriginalRationalCurvePolynomial? {
        if case .curveSurface(let curve, _) = sources { return curve }
        return nil
    }

    package var firstSurfaceSource: OriginalRationalSurfacePolynomial {
        switch sources {
        case .curveSurface(_, let surface): return surface
        case .surfaceSurface(let first, _): return first
        }
    }

    package var secondSurfaceSource: OriginalRationalSurfacePolynomial? {
        if case .surfaceSurface(_, let second) = sources { return second }
        return nil
    }

    /// A fresh inverse coordinate excludes both denominator-zero loci exactly.
    /// This prepares an ideal; complete real lifting remains a separate obligation.
    package func saturatedIdeal<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> ExactIntersectionIdeal {
        try intersectionAlgebraStep(&usage)
        let count = try rationalAlgebraCount(variableCount, 1)
        try RationalAlgebraStorage.retain(4, of: ExactIntersectionPolynomial.self, usage: &usage)
        var generators: [ExactIntersectionPolynomial] = []
        for equation in equations { generators.append(try equation.lifted(to: count, usage: &usage)) }
        let first = try denominatorGuards[0].lifted(to: count, usage: &usage)
        let second = try denominatorGuards[1].lifted(to: count, usage: &usage)
        let inverse = try ExactIntersectionPolynomial.coordinate(variableCount: count,
            at: variableCount, usage: &usage)
        let one = try ExactIntersectionPolynomial.constant(variableCount: count, value: .one, usage: &usage)
        generators.append(try first.multiplied(by: second, usage: &usage)
            .multiplied(by: inverse, usage: &usage).subtracting(one, usage: &usage))
        return try ExactIntersectionIdeal.prepare(equations: generators, variableCount: count, usage: &usage)
    }

    private static func embedding<B: ExactScalarAdmission & ~Copyable>(_ source: [ExactBivariatePolynomial],
        variableCount: Int, uCoordinate: Int, vCoordinate: Int, usage: inout B)
        throws -> [ExactIntersectionPolynomial] {
        try RationalAlgebraStorage.retain(4, of: ExactIntersectionPolynomial.self, usage: &usage)
        var result: [ExactIntersectionPolynomial] = []
        for coordinate in source {
            try intersectionAlgebraStep(&usage)
            result.append(try .embedding(coordinate, variableCount: variableCount,
                uCoordinate: uCoordinate, vCoordinate: vCoordinate, usage: &usage))
        }
        return result
    }

    private static func coincidenceEquations<B: ExactScalarAdmission & ~Copyable>(
        _ first: [ExactIntersectionPolynomial], _ second: [ExactIntersectionPolynomial],
        usage: inout B) throws -> [ExactIntersectionPolynomial] {
        try RationalAlgebraStorage.retain(3, of: ExactIntersectionPolynomial.self, usage: &usage)
        var result: [ExactIntersectionPolynomial] = []
        for axis in 0..<3 {
            try intersectionAlgebraStep(&usage)
            result.append(try first[axis].multiplied(by: second[3], usage: &usage)
                .subtracting(second[axis].multiplied(by: first[3], usage: &usage), usage: &usage))
        }
        return result
    }
}
