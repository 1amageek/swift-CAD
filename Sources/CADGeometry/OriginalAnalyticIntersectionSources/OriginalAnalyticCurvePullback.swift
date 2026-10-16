import CADCore

/// Raw direct plane/cylinder/torus source law on one retained native curve span.
package struct OriginalAnalyticCurvePullback: Sendable {
    package let surface: AnalyticSurface3D
    package let curve: OriginalRationalCurvePolynomial
    package let domain: OriginalRationalParameterDomain
    package let equation: ExactBivariatePolynomial
    package let denominator: ExactBivariatePolynomial
    package let originalFrame: AffineTransform3D?
    package let exactInverseFrame: [ExactRationalCoefficient]?

    package init<B: ExactScalarAdmission & ~Copyable>(surface: AnalyticSurface3D,
        curve: OriginalRationalCurvePolynomial, tolerance: ModelingTolerance,
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        try surface.validate(tolerance: tolerance, using: &usage)
        switch surface {
        case .plane, .cylinder, .torus: break
        case .cone:
            // FIXME(INCOMPLETE_IMPLEMENTATION): This callable Native analytic
            // pullback path lacks an exact coefficient issuer for the cone's
            // authored physical-radian halfAngle slope. CS composition must not
            // count it as complete until that original transcendental coefficient
            // and its whole-domain relation are represented and verified.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original cone pullback requires its authored physical-angle coefficient authority.")
        case .sphere:
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Direct sphere pullback uses its original sphere source issuer.")
        }
        guard curve.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("Original analytic pullback requires four retained homogeneous curve laws.")
        }
        for polynomial in curve.homogeneous {
            for term in try polynomial.orderedTerms(usage: &usage) {
                try intersectionAlgebraStep(&usage)
                guard term.key.v == 0 else {
                    throw rationalAlgebraFailure("Original analytic pullback requires one original curve parameter.")
                }
            }
        }
        let weight = curve.homogeneous[3]
        guard !weight.isZero else {
            throw rationalAlgebraFailure("Original analytic pullback cannot issue a zero denominator.")
        }
        let raw: ExactBivariatePolynomial
        let frame: AffineTransform3D?, inverse: [ExactRationalCoefficient]?
        switch surface {
        case .plane:
            let original = try OriginalSupportingPlaneEquation.prepared(source: .analytic(surface),
                tolerance: tolerance, remainingSourceDepth: 0, usage: &usage)
            raw = try original.polynomial(curve.homogeneous, includeOffset: true, usage: &usage)
            frame = nil; inverse = nil
        case .cylinder(let origin, _, let radius), .torus(let origin, _, let radius, _):
            let identity = try AffineTransform3D(basisX: .unitX, basisY: .unitY,
                basisZ: .unitZ, translation: .zero)
            let word = try OriginalAffineOperationWord(operation: .forward(identity),
                tolerance: tolerance, maximumDepth: 0, usage: &usage).prepared(usage: &usage)
            guard let harmonic = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(
                source: .analytic(surface), word: word, tolerance: tolerance,
                usage: &usage, admitPhysicalMetric: false) else {
                throw rationalAlgebraFailure("Direct analytic pullback lost its original harmonic frame authority.")
            }
            let gauge = harmonic.originalNormalGauge
            let retained = try AffineTransform3D(basisX: gauge.firstDirection,
                basisY: gauge.secondDirection, basisZ: gauge.axisDirection,
                translation: .init(x: origin.x, y: origin.y, z: origin.z))
            let matrix = try OriginalAffineRationalMatrix.original(retained, usage: &usage)
            let determinant = try OriginalAffineRationalMatrix.determinant(matrix, usage: &usage)
            guard !determinant.isZero else {
                throw rationalAlgebraFailure("Original analytic chart frame is exactly singular.")
            }
            let inverseFrame = try OriginalAffineRationalMatrix.inverse(matrix,
                determinant: determinant, usage: &usage)
            frame = retained; inverse = inverseFrame
            try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
            var local: [ExactBivariatePolynomial] = []; local.reserveCapacity(3)
            for row in 0..<3 {
                var coordinate = try weight.scaled(by: inverseFrame[row * 4 + 3], usage: &usage)
                for column in 0..<3 {
                    try intersectionAlgebraStep(&usage)
                    coordinate = try coordinate.adding(curve.homogeneous[column]
                        .scaled(by: inverseFrame[row * 4 + column], usage: &usage), usage: &usage)
                }
                local.append(coordinate)
            }
            let radial = try local[0].multiplied(by: local[0], usage: &usage)
                .adding(local[1].multiplied(by: local[1], usage: &usage), usage: &usage)
            let w2 = try weight.multiplied(by: weight, usage: &usage)
            let r = try ExactRationalCoefficient.originalDouble(radius, usage: &usage)
            let r2 = try r.multiplied(by: r, usage: &usage)
            if case .cylinder = surface {
                raw = try radial.subtracting(w2.scaled(by: r2, usage: &usage), usage: &usage)
            } else if case .torus(_, _, _, let minorRadius) = surface {
                let minor = try ExactRationalCoefficient.originalDouble(minorRadius, usage: &usage)
                let delta = try r2.subtracting(minor.multiplied(by: minor, usage: &usage), usage: &usage)
                let total = try radial.adding(local[2].multiplied(by: local[2], usage: &usage), usage: &usage)
                    .adding(w2.scaled(by: delta, usage: &usage), usage: &usage)
                let fourR2 = try r2.multiplied(by: .originalDouble(4, usage: &usage), usage: &usage)
                raw = try total.multiplied(by: total, usage: &usage)
                    .subtracting(radial.multiplied(by: w2, usage: &usage)
                        .scaled(by: fourR2, usage: &usage), usage: &usage)
            } else {
                throw rationalAlgebraFailure("Original analytic pullback lost its admitted primitive kind.")
            }
        case .cone, .sphere:
            throw rationalAlgebraFailure("Original analytic pullback reached an unadmitted source kind.")
        }
        let domain = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.surface = surface; self.curve = curve; self.domain = domain
        equation = raw; denominator = weight; originalFrame = frame; exactInverseFrame = inverse
    }

    /// Retains the original multiplicity and explicit W!=0 source guard.
    package func relation<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> OriginalPolynomialRelation {
        try intersectionAlgebraStep(&usage)
        let equation = try originalPolynomial(self.equation, usage: &usage)
        let denominator = try originalPolynomial(self.denominator, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalRationalPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 2,
            instructions: [.sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero), .not, .and], usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalPolynomialRelation(variableCount: 1,
            polynomials: [equation, denominator], predicate: predicate, domains: [domain], usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return relation
    }

    private func originalPolynomial<B: ExactScalarAdmission & ~Copyable>(_ source: ExactBivariatePolynomial,
        usage: inout B) throws -> OriginalRationalPolynomial {
        let ordered = try source.orderedTerms(usage: &usage)
        try RationalAlgebraStorage.retain(ordered.count, of: OriginalRationalPolynomial.Term.self, usage: &usage)
        var terms: [OriginalRationalPolynomial.Term] = []; terms.reserveCapacity(ordered.count)
        for term in ordered {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            terms.append(.init(coefficient: term.value, powers: [term.key.u]))
        }
        return try .init(variableCount: 1, terms: terms, usage: &usage)
    }
}
