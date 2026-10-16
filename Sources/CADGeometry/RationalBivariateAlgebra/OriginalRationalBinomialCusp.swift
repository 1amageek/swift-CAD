import CADCore

/// Complete original coprime-binomial real cusp, with its exact native polynomial map.
package struct OriginalRationalBinomialCusp: Sendable {
    package let original: ExactBivariatePolynomial
    package let oddCoordinateAlongU: Bool
    package let characteristicExponent: Int
    package let branchMultiplicity: Int
    package let parameterExponent: Int
    package let gain: ExactRationalCoefficient
    package let centerU: ExactRationalCoefficient
    package let centerV: ExactRationalCoefficient
    package let parameterPowerCoordinate: ExactBivariatePolynomial
    package let u: ExactBivariatePolynomial
    package let v: ExactBivariatePolynomial

    package static func proven<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        if let native = try reduced(original: original, usage: &usage) { return native }
        for chart in try OriginalRationalBinomialChart.candidates(original: original, usage: &usage) {
            guard let inner = try reduced(original: chart.transformed, usage: &usage) else { continue }
            let u = try chart.originalU.composed(withU: inner.u, v: inner.v, usage: &usage)
            let v = try chart.originalV.composed(withU: inner.u, v: inner.v, usage: &usage)
            guard try original.composed(withU: u, v: v, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original rotated cusp failed its full native polynomial identity.")
            }
            let free = try inner.parameterPowerCoordinate.composed(withU: chart.chartU,
                v: chart.chartV, usage: &usage)
            return try Self(original: original, oddCoordinateAlongU: chart.swapped ? !inner.oddCoordinateAlongU : inner.oddCoordinateAlongU,
                characteristicExponent: inner.characteristicExponent, branchMultiplicity: inner.branchMultiplicity,
                parameterExponent: inner.parameterExponent, gain: inner.gain,
                centerU: u.evaluated(atU: .zero, v: .zero, usage: &usage),
                centerV: v.evaluated(atU: .zero, v: .zero, usage: &usage),
                parameterPowerCoordinate: free, u: u, v: v)
        }
        return nil
    }

    private static func reduced<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        if let completed = try axisAligned(original: original, usage: &usage) { return completed }
        if let separated = try translatedBinomial(original: original, usage: &usage) { return separated }
        for chart in try OriginalRationalPolynomialShearChart.candidates(original: original, usage: &usage) {
            let inner: Self
            if let square = try axisAligned(original: chart.transformed, usage: &usage) { inner = square }
            else if let binomial = try translatedBinomial(original: chart.transformed, usage: &usage) { inner = binomial }
            else { continue }
            let u = try chart.originalU.composed(withU: inner.u, v: inner.v, usage: &usage)
            let v = try chart.originalV.composed(withU: inner.u, v: inner.v, usage: &usage)
            guard try original.composed(withU: u, v: v, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original polynomial-sheared cusp failed its complete source identity.")
            }
            return try Self(original: original, oddCoordinateAlongU: chart.swapped ? !inner.oddCoordinateAlongU : inner.oddCoordinateAlongU,
                characteristicExponent: inner.characteristicExponent, branchMultiplicity: inner.branchMultiplicity,
                parameterExponent: inner.parameterExponent, gain: inner.gain,
                centerU: u.evaluated(atU: .zero, v: .zero, usage: &usage),
                centerV: v.evaluated(atU: .zero, v: .zero, usage: &usage),
                parameterPowerCoordinate: inner.parameterPowerCoordinate.composed(withU: chart.chartU, v: chart.chartV, usage: &usage),
                u: u, v: v)
        }
        return nil
    }

    private static func axisAligned<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        // Exact square completion admits polynomial shears while preserving
        // every original source coefficient and the complete real zero set.
        for alongU in [true, false] {
            let oriented = alongU ? original : try original.exchangedAxes(usage: &usage)
            guard oriented.vDegree == 2 else { continue }
            let quadratic = try oriented.coefficient(ofV: 2, usage: &usage)
            guard quadratic.uDegree == 0, let square = quadratic.leading?.value else { continue }
            let linear = try oriented.coefficient(ofV: 1, usage: &usage)
            let constant = try oriented.coefficient(ofV: 0, usage: &usage)
            let two = try ExactRationalCoefficient.natural(2, usage: &usage)
            let four = try two.multiplied(by: two, usage: &usage)
            let centerLaw = try linear.scaled(by: .one.negated.divided(
                by: square.multiplied(by: two, usage: &usage), usage: &usage), usage: &usage)
            let residual = try constant.subtracting(linear.multiplied(by: linear, usage: &usage)
                .scaled(by: .one.divided(by: square.multiplied(by: four, usage: &usage), usage: &usage), usage: &usage), usage: &usage)
            let exponent = residual.uDegree
            guard exponent >= 3, exponent % 2 == 1, let odd = residual.leading?.value else { continue }
            let terms = try residual.orderedTerms(usage: &usage)
            let next = terms.first(where: { $0.0.u == exponent - 1 && $0.0.v == 0 })?.1 ?? .zero
            let oddCenter = try next.negated.divided(by: odd.multiplied(
                by: .natural(exponent, usage: &usage), usage: &usage), usage: &usage)
            let shiftedOdd = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                .subtracting(.constant(oddCenter, usage: &usage), usage: &usage)
            try RationalAlgebraStorage.retain(1, of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            let monomial = try ExactBivariatePolynomial([.init(u: exponent, v: 0): .one])
            let reconstructedOdd = try monomial.composed(withU: shiftedOdd, v: .zero, usage: &usage)
                .scaled(by: odd, usage: &usage)
            guard try residual.subtracting(reconstructedOdd, usage: &usage).isZero else { continue }
            let shiftedSquare = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
                .subtracting(centerLaw, usage: &usage)
            let reconstructedSquare = try shiftedSquare.multiplied(by: shiftedSquare, usage: &usage)
                .scaled(by: square, usage: &usage)
            guard try oriented.subtracting(reconstructedOdd.adding(reconstructedSquare, usage: &usage), usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original cusp square completion fails its full source identity.")
            }
            let gain = try square.negated.divided(by: odd, usage: &usage)
            let k = (exponent - 1) / 2
            var oddGain = ExactRationalCoefficient.one
            for _ in 0..<k { oddGain = try oddGain.multiplied(by: gain, usage: &usage) }
            try RationalAlgebraStorage.retain(2, of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            let evenMap = try ExactBivariatePolynomial([.init(u: 2, v: 0): gain])
                .adding(.constant(oddCenter, usage: &usage), usage: &usage)
            let oddMap = try ExactBivariatePolynomial([.init(u: exponent, v: 0): oddGain])
                .adding(centerLaw.composed(withU: evenMap, v: .zero, usage: &usage), usage: &usage)
            let squareCenter = try centerLaw.evaluated(atU: oddCenter, v: .zero, usage: &usage)
            let u = alongU ? evenMap : oddMap, v = alongU ? oddMap : evenMap
            guard try original.composed(withU: u, v: v, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original cusp parameterization fails its exact source identity.")
            }
            return try Self(original: original, oddCoordinateAlongU: alongU, characteristicExponent: exponent,
                branchMultiplicity: 2, parameterExponent: 2,
                gain: gain, centerU: alongU ? oddCenter : squareCenter,
                centerV: alongU ? squareCenter : oddCenter,
                parameterPowerCoordinate: alongU ? shiftedOdd : shiftedOdd.exchangedAxes(usage: &usage), u: u, v: v)
        }
        return nil
    }

    package func clipped<B: ExactScalarAdmission & ~Copyable>(over domain: SurfaceParameterBox,
        maximumDepth: Int, usage: inout B) throws -> OriginalRationalPolynomialParameterDomain {
        guard domain.u.width > 0, domain.v.width > 0 else {
            throw rationalAlgebraFailure("Original cusp clipping requires a positive native rectangle.")
        }
        // The retained affine law is gain*t^parameterExponent after rotation.
        // Its extrema on the original rectangle occur at the four corners.
        var largest = ExactRationalCoefficient.zero
        for originalU in [domain.u.lower, domain.u.upper] {
            for originalV in [domain.v.lower, domain.v.upper] {
                let value = try parameterPowerCoordinate.evaluated(
                    atU: .originalDouble(originalU, usage: &usage),
                    v: .originalDouble(originalV, usage: &usage), usage: &usage)
                    .divided(by: gain, usage: &usage)
                let magnitude = value.isNegative ? value.negated : value
                if try magnitude.subtracting(largest, usage: &usage).isPositive { largest = magnitude }
            }
        }
        if try rationalAlgebraCount(max(0, parameterPowerCoordinate.uDegree), max(0, parameterPowerCoordinate.vDegree)) > 1 {
            let absolute = try parameterPowerCoordinate.exactAbsoluteBound(over: domain, usage: &usage)
            largest = try absolute.divided(by: gain.isNegative ? gain.negated : gain, usage: &usage)
        }
        let bound = try largest.adding(.one, usage: &usage)
        return try OriginalRationalPolynomialParameterDomain.clipped(u: u, v: v,
            originalDomain: domain, lower: bound.negated, upper: bound,
            maximumDepth: maximumDepth, usage: &usage, interiorStations: [.zero])
    }
}
