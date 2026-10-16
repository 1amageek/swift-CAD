import CADCore

/// Original curvature numerators after exact removal of the native collapsed metric.
struct OriginalNativeParallelMetric: Sendable {
    struct Admission: Sendable {
        let displacement: ExactRationalCoefficient
        let orientation: Int
    }
    private let original: OriginalRationalSurfacePolynomial
    private let normal: [ExactBivariatePolynomial]
    private let meanNumerator: ExactBivariatePolynomial
    private let gaussianNumerator: ExactBivariatePolynomial
    private let normalSquare: ExactBivariatePolynomial

    init<B: ExactScalarAdmission & ~Copyable>(original: OriginalRationalSurfacePolynomial,
        normal: [ExactBivariatePolynomial], usage: inout B) throws {
        guard normal.count == 3 else { throw rationalAlgebraFailure("Original parallel metric requires three normal coefficients.") }
        self.original = original; self.normal = normal
        var factor: ExactBivariatePolynomial?
        for axis in 0..<3 where !normal[axis].isZero {
            factor = try original.normalNumerators[axis].dividedExactly(by: normal[axis], usage: &usage)
            break
        }
        guard let factor, !factor.isZero else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: nil,
                message: "Original parallel metric has no nonzero normal factor.")
        }
        for axis in 0..<3 {
            let difference = try factor.multiplied(by: normal[axis], usage: &usage)
                .subtracting(original.normalNumerators[axis], usage: &usage)
            guard difference.isZero else {
                throw rationalAlgebraFailure("Original parallel metric normal factor does not bind all three coefficients.")
            }
        }
        let law = try OriginalRationalSurfaceDerivativeLaw(original: original, throughOrder: 2, usage: &usage)
        func partial(_ u: Int, _ v: Int, usage: inout B) throws -> [ExactBivariatePolynomial] {
            for value in law.partials {
                try usage.consumeWork(1)
                if value.uOrder == u && value.vOrder == v { return value.numerators }
            }
            throw rationalAlgebraFailure("Original parallel metric lost a source partial.")
        }
        func dot(_ a: [ExactBivariatePolynomial], _ b: [ExactBivariatePolynomial],
            usage: inout B) throws -> ExactBivariatePolynomial {
            var value = ExactBivariatePolynomial.zero
            for axis in 0..<3 { value = try value.adding(a[axis].multiplied(by: b[axis], usage: &usage), usage: &usage) }
            return value
        }
        let su = try partial(1, 0, usage: &usage), sv = try partial(0, 1, usage: &usage)
        let e = try dot(su, su, usage: &usage), f = try dot(su, sv, usage: &usage), g = try dot(sv, sv, usage: &usage)
        let l = try dot(partial(2, 0, usage: &usage), normal, usage: &usage)
        let m = try dot(partial(1, 1, usage: &usage), normal, usage: &usage)
        let n = try dot(partial(0, 2, usage: &usage), normal, usage: &usage)
        let metricSquare = try factor.multiplied(by: factor, usage: &usage)
        let weight = original.homogeneous[3]
        let mean = try e.multiplied(by: n, usage: &usage)
            .subtracting(f.multiplied(by: m, usage: &usage).scaled(by: .natural(2, usage: &usage), usage: &usage), usage: &usage)
            .adding(g.multiplied(by: l, usage: &usage), usage: &usage)
            .multiplied(by: weight, usage: &usage)
        let gaussian = try l.multiplied(by: n, usage: &usage)
            .subtracting(m.multiplied(by: m, usage: &usage), usage: &usage)
            .multiplied(by: weight.multiplied(by: weight, usage: &usage), usage: &usage)
        meanNumerator = try mean.dividedExactly(by: metricSquare, usage: &usage)
        gaussianNumerator = try gaussian.dividedExactly(by: metricSquare, usage: &usage)
        normalSquare = try dot(normal, normal, usage: &usage)
    }

    func admission<B: ExactScalarAdmission & ~Copyable>(over box: SurfaceParameterBox,
        distances: [Double], usage: inout B) throws -> Admission? {
        guard box.u.lower >= original.domain.u.lower, box.u.upper <= original.domain.u.upper,
              box.v.lower >= original.domain.v.lower, box.v.upper <= original.domain.v.upper else {
            throw GeometryConversionError.invalidInput("Original parallel metric query escaped its retained native source.")
        }
        let bounds = try IntervalVector3DBounds(x: normal[0].enclosure(over: box, usage: &usage),
            y: normal[1].enclosure(over: box, usage: &usage), z: normal[2].enclosure(over: box, usage: &usage))
        let norm = OutwardScalarInterval(lower: bounds.lengthLowerBound, upper: bounds.lengthUpperBound)
        guard norm.lower > 0, norm.isFinite else { return nil }
        guard let square = try normalSquare.enclosure(over: box, usage: &usage).intersection(with: norm * norm),
              square.lower > 0, square.isFinite else { return nil }
        let meanDenominator = .exact(2) * square * norm
        let gaussianDenominator = square * square
        guard let mean = try meanNumerator.enclosure(over: box, usage: &usage).divided(by: meanDenominator),
              let gaussian = try gaussianNumerator.enclosure(over: box, usage: &usage).divided(by: gaussianDenominator),
              mean.isFinite, gaussian.isFinite else { return nil }
        var effective = ExactRationalCoefficient.zero, orientation = 1
        for distance in distances {
            try usage.consumeWork(1)
            let authored = try ExactRationalCoefficient.originalDouble(distance, usage: &usage)
            effective = try effective.adding(orientation > 0 ? authored : authored.negated, usage: &usage)
            let d = try effective.outwardInterval(usage: &usage)
            let determinant = .exact(1) - .exact(2) * d * mean + d * d * gaussian
            guard determinant.isFinite, determinant.excludesZero else { return nil }
            orientation = determinant.lower > 0 ? 1 : -1
        }
        return Admission(displacement: effective, orientation: orientation)
    }
}
