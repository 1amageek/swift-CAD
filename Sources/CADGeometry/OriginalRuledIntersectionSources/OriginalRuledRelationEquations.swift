import CADCore

/// Exact ring embedding and equality assembly; it performs no root search.
package enum OriginalRuledRelationEquations {
    static func requireContained<B: RationalAlgebraAdmitting>(_ requested: OriginalRationalParameterDomain,
        in original: OriginalRationalParameterDomain, tolerance: ModelingTolerance?, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard let a = requested.lower, let b = requested.upper,
            let lower = original.lower, let upper = original.upper,
            try !a.subtracting(lower, usage: &usage).isNegative,
            try !upper.subtracting(b, usage: &usage).isNegative else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original ruled relation requires exact finite closed-domain containment.")
        }
    }

    static func lift<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial,
        variableCount: Int, uAxis: Int, vAxis: Int?, usage: inout B) throws -> OriginalRationalPolynomial {
        let ordered = try source.orderedTerms(usage: &usage)
        try RationalAlgebraStorage.retain(ordered.count, of: OriginalRationalPolynomial.Term.self, usage: &usage)
        var terms: [OriginalRationalPolynomial.Term] = []; terms.reserveCapacity(ordered.count)
        for term in ordered {
            try intersectionAlgebraStep(&usage)
            guard vAxis != nil || term.key.v == 0 else {
                throw rationalAlgebraFailure("An original curve law cannot carry a second parameter.")
            }
            try RationalAlgebraStorage.retain(variableCount, of: Int.self, usage: &usage)
            var powers = [Int](repeating: 0, count: variableCount)
            powers[uAxis] = term.key.u
            if let vAxis { powers[vAxis] = term.key.v }
            terms.append(.init(coefficient: term.value, powers: powers))
        }
        return try .init(variableCount: variableCount, terms: terms, usage: &usage)
    }

    static func relation<B: RationalAlgebraAdmitting>(first: [ExactBivariatePolynomial],
        second: [ExactBivariatePolynomial], variableCount: Int, firstU: Int, firstV: Int?,
        secondU: Int, secondV: Int?, domains: [OriginalRationalParameterDomain],
        usage: inout B) throws -> OriginalPolynomialRelation {
        try intersectionAlgebraStep(&usage)
        guard first.count == 4, second.count == 4 else {
            throw rationalAlgebraFailure("Original ruled equality requires both complete homogeneous laws.")
        }
        let aW = try lift(first[3], variableCount: variableCount, uAxis: firstU, vAxis: firstV, usage: &usage)
        let bW = try lift(second[3], variableCount: variableCount, uAxis: secondU, vAxis: secondV, usage: &usage)
        try RationalAlgebraStorage.retain(5, of: OriginalRationalPolynomial.self, usage: &usage)
        var laws: [OriginalRationalPolynomial] = []; laws.reserveCapacity(5)
        for axis in 0..<3 {
            let a = try lift(first[axis], variableCount: variableCount, uAxis: firstU, vAxis: firstV, usage: &usage)
            let b = try lift(second[axis], variableCount: variableCount, uAxis: secondU, vAxis: secondV, usage: &usage)
            laws.append(try a.multiplied(by: bW, usage: &usage)
                .subtracting(b.multiplied(by: aW, usage: &usage), usage: &usage))
        }
        laws.append(aW); laws.append(bW)
        try RationalAlgebraStorage.retain(11, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 5, instructions: [
            .sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero), .and,
            .sign(polynomial: 2, .zero), .and,
            .sign(polynomial: 3, .zero), .not, .and,
            .sign(polynomial: 4, .zero), .not, .and], usage: &usage)
        let result = try OriginalPolynomialRelation(variableCount: variableCount,
            polynomials: laws, predicate: predicate, domains: domains, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}

extension OriginalRuledSurfacePolynomial {
    /// CS variable order is (native curve t, original ruled u, original ruled v).
    package func curveRelation<B: RationalAlgebraAdmitting>(curve: OriginalRationalCurvePolynomial,
        curveDomain: OriginalRationalParameterDomain, usage: inout B) throws -> OriginalRuledIntersectionRelation {
        let native = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try OriginalRuledRelationEquations.requireContained(curveDomain, in: native, tolerance: nil, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalRuledRelationEquations.relation(first: curve.homogeneous, second: homogeneous,
            variableCount: 3, firstU: 0, firstV: nil, secondU: 1, secondV: 2,
            domains: [curveDomain, uDomain, vDomain], usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalRuledIntersectionRelation.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(ruled: self, target: .curve(curve), relation: relation)
    }

    /// SSI variable order is (original ruled u/v, native surface s/t).
    package func surfaceRelation<B: RationalAlgebraAdmitting>(surface: OriginalRationalSurfacePolynomial,
        usage: inout B) throws -> OriginalRuledIntersectionRelation {
        let s = try OriginalRationalParameterDomain(surface.domain.u, usage: &usage)
        let t = try OriginalRationalParameterDomain(surface.domain.v, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalRuledRelationEquations.relation(first: homogeneous, second: surface.homogeneous,
            variableCount: 4, firstU: 0, firstV: 1, secondU: 2, secondV: 3,
            domains: [uDomain, vDomain, s, t], usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalRuledIntersectionRelation.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(ruled: self, target: .surface(surface), relation: relation)
    }
}
