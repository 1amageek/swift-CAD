import CADCore

/// Exact oriented projective partial equality of admitted nonzero original normal fields.
struct OriginalNativeNormalHigherContinuity {
    static func prove<B: ExactScalarAdmission & ~Copyable>(spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        fields: [[ExactBivariatePolynomial]], over query: SurfaceParameterBox,
        throughOrder: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        guard fields.count == spans.count, fields.allSatisfy({ $0.count == 3 }) else {
            throw rationalAlgebraFailure("Original normal join needs all selected three-component fields.")
        }
        for first in spans.indices {
            for second in spans.indices where second > first {
                try usage.consumeWork(1)
                let a = spans[first], b = spans[second]
                for alongU in [true, false] {
                    let aa = alongU ? a.uBounds : a.vBounds, bb = alongU ? b.uBounds : b.vBounds
                    let station: Double
                    if aa.upper == bb.lower { station = aa.upper }
                    else if bb.upper == aa.lower { station = bb.upper }
                    else { continue }
                    let range = alongU ? query.u : query.v
                    if station < range.lower || station > range.upper { continue }
                    let at = alongU ? a.vBounds : a.uBounds, bt = alongU ? b.vBounds : b.uBounds
                    let transverse = alongU ? query.v : query.u
                    let lower = max(at.lower, max(bt.lower, transverse.lower))
                    let upper = min(at.upper, min(bt.upper, transverse.upper))
                    if lower > upper { continue }
                    try usage.visitCell(axis: .value, depth: 0)
                    try edge(first: fields[first], second: fields[second], alongU: alongU,
                        station: station, lower: lower, upper: upper, throughOrder: throughOrder,
                        maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
                }
            }
        }
    }

    private static func edge<B: ExactScalarAdmission & ~Copyable>(first: [ExactBivariatePolynomial],
        second: [ExactBivariatePolynomial], alongU: Bool, station: Double, lower: Double,
        upper: Double, throughOrder: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        let fixed = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
        let lo = try ExactRationalCoefficient.originalDouble(lower, usage: &usage)
        let hi = try ExactRationalCoefficient.originalDouble(upper, usage: &usage)
        func restrict(_ polynomial: ExactBivariatePolynomial, usage: inout B) throws -> ExactBivariatePolynomial {
            try polynomial.restricted(alongU: alongU, station: fixed, usage: &usage)
        }
        func zero(_ polynomial: ExactBivariatePolynomial, usage: inout B) throws -> Bool {
            let restricted = try restrict(polynomial, usage: &usage)
            if lower == upper { return try restricted.evaluated(atU: lo, v: .zero, usage: &usage).isZero }
            return restricted.isZero
        }
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            let cross = try first[b].multiplied(by: second[c], usage: &usage)
                .subtracting(first[c].multiplied(by: second[b], usage: &usage), usage: &usage)
            guard try zero(cross, usage: &usage) else { throw discontinuity(tolerance) }
        }
        var dot = ExactBivariatePolynomial.zero
        for axis in 0..<3 {
            dot = try dot.adding(first[axis].multiplied(by: second[axis], usage: &usage), usage: &usage)
        }
        dot = try restrict(dot, usage: &usage)
        guard !dot.isZero else { throw discontinuity(tolerance) }
        if lower < upper {
            guard try ExactUnivariateRootIsolator().isolate(dot, lower: lo, upper: hi,
                maximumDepth: maximumSubdivisionDepth, usage: &usage).isEmpty else { throw discontinuity(tolerance) }
        }
        let mid = try lo.adding(hi, usage: &usage).divided(by: .natural(2, usage: &usage), usage: &usage)
        guard try dot.evaluated(atU: mid, v: .zero, usage: &usage).isPositive else { throw discontinuity(tolerance) }
        var anchor: Int?
        for axis in 0..<3 {
            let value = try restrict(first[axis], usage: &usage)
            let nonzero = lower == upper
                ? try !value.evaluated(atU: lo, v: .zero, usage: &usage).isZero : !value.isZero
            if nonzero { anchor = axis; break }
        }
        guard let anchor else { throw discontinuity(tolerance) }
        try RationalAlgebraStorage.retain(8, of: UInt32.self, usage: &usage)
        var h1 = first, h2 = second
        h1.append(first[anchor]); h2.append(second[anchor])
        let law1 = try OriginalRationalVectorDerivativeLaw(homogeneous: h1, throughOrder: throughOrder, usage: &usage)
        let law2 = try OriginalRationalVectorDerivativeLaw(homogeneous: h2, throughOrder: throughOrder, usage: &usage)
        for numerator in try law1.equalityNumerators(with: law2, usage: &usage) {
            guard try zero(numerator, usage: &usage) else { throw discontinuity(tolerance) }
        }
        // Every field was separately proved strictly nonzero on its whole
        // chart. Projective derivatives agree on the dense nonzero anchor
        // subset, and their oriented analytic normalization extends equality
        // over the isolated zeros of that anchor component.
    }

    private static func discontinuity(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
            message: "Original oriented normal partials disagree at a selected native join.")
    }
}
