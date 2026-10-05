import CADCore

/// Proves original C0 chart continuity before a mean-value embedding argument.
package struct OriginalSplineSurfaceContinuityAdmission {
    /// Whole original C0 authority; no tangent or regular-normal guarantee.
    package struct Receipt: Sendable {
        package let source: BSplineSurface3D
        package let tolerance: ModelingTolerance

        fileprivate init(source: BSplineSurface3D, tolerance: ModelingTolerance) {
            self.source = source
            self.tolerance = tolerance
        }

        package func matches<B: RationalAlgebraAdmitting>(source other: BSplineSurface3D,
            tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),
                using: { try usage.consumeExactWork($0) })
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(other),
                using: { try usage.consumeExactWork($0) })
            return self.tolerance == tolerance && source == other
        }
    }

    package init() {}

    /// The composing source validator owns structural and positive-weight admission.
    package func certificateAssumingSourceValidated<B: RationalAlgebraAdmitting>(
        _ original: BSplineSurface3D, tolerance: ModelingTolerance, usage: inout B) throws -> Receipt {
        try validate(original, tolerance: tolerance, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Receipt.self, usage: &usage)
        return Receipt(source: original, tolerance: tolerance)
    }

    package func validate<B: RationalAlgebraAdmitting>(_ original: BSplineSurface3D,
        tolerance: ModelingTolerance, usage: inout B) throws {
        for alongU in [true, false] {
            let knots = alongU ? original.uKnots : original.vKnots
            let degree = alongU ? original.uDegree : original.vDegree
            let count = alongU ? original.controlPoints[0].count : original.controlPoints.count
            let freeKnots = alongU ? original.vKnots : original.uKnots
            let freeDegree = alongU ? original.vDegree : original.uDegree
            let freeCount = alongU ? original.controlPoints.count : original.controlPoints[0].count
            try usage.consumeExactWork(knots.count)
            try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
            let spans = (degree..<count).filter { knots[$0] < knots[$0 + 1] }
            try usage.consumeExactWork(freeKnots.count)
            try RationalAlgebraStorage.retain(freeCount, of: Int.self, usage: &usage)
            let freeSpans = (freeDegree..<freeCount).filter { freeKnots[$0] < freeKnots[$0 + 1] }
            for pair in zip(spans, spans.dropFirst()) {
                let station = knots[pair.1]
                try usage.consumeExactWork(knots.count)
                let multiplicity = knots.reduce(0) { $0 + ($1 == station ? 1 : 0) }
                if multiplicity <= degree { continue }
                for freeSpan in freeSpans {
                    try usage.visitExactCell(depth: 0)
                    let first = try homogeneous(original, alongU: alongU, fixedSpan: pair.0,
                        station: station, freeSpan: freeSpan, usage: &usage)
                    let second = try homogeneous(original, alongU: alongU, fixedSpan: pair.1,
                        station: station, freeSpan: freeSpan, usage: &usage)
                    try equal(first, second, tolerance: tolerance, usage: &usage)
                }
            }
            if alongU ? original.isUPeriodic : original.isVPeriodic {
                guard let first = spans.first, let last = spans.last else {
                    throw GeometryConversionError.invalidInput("Original periodic surface has no positive source chart.")
                }
                for freeSpan in freeSpans {
                    try usage.visitExactCell(depth: 0)
                    let a = try homogeneous(original, alongU: alongU, fixedSpan: first,
                        station: knots[degree], freeSpan: freeSpan, usage: &usage)
                    let b = try homogeneous(original, alongU: alongU, fixedSpan: last,
                        station: knots[count], freeSpan: freeSpan, usage: &usage)
                    try equal(a, b, tolerance: tolerance, usage: &usage)
                }
            }
        }
    }

    private func equal<B: RationalAlgebraAdmitting>(_ first: [ExactBivariatePolynomial],
        _ second: [ExactBivariatePolynomial], tolerance: ModelingTolerance, usage: inout B) throws {
        for axis in 0..<3 {
            let difference = try first[axis].multiplied(by: second[3], usage: &usage)
                .subtracting(second[axis].multiplied(by: first[3], usage: &usage), usage: &usage)
            guard difference.isZero else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original surface chart join has a proved discontinuous original position law.")
            }
        }
    }

    private func homogeneous<B: RationalAlgebraAdmitting>(_ source: BSplineSurface3D,
        alongU: Bool, fixedSpan: Int, station: Double, freeSpan: Int,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        let fixedKnots = alongU ? source.uKnots : source.vKnots
        let fixedDegree = alongU ? source.uDegree : source.vDegree
        let freeKnots = alongU ? source.vKnots : source.uKnots
        let freeDegree = alongU ? source.vDegree : source.uDegree
        let fixedBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: fixedKnots,
            degree: fixedDegree, span: fixedSpan, alongU: true, translation: 0, usage: &usage)
        let freeBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: freeKnots,
            degree: freeDegree, span: freeSpan, alongU: true, translation: 0, usage: &usage)
        let parameter = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var result = [ExactBivariatePolynomial](repeating: .zero, count: 4)
        for fixed in (fixedSpan - fixedDegree)...fixedSpan {
            guard let basis = fixedBasis[fixed] else {
                throw GeometryConversionError.invalidInput("Original surface continuity lacks a fixed owning basis coefficient.")
            }
            let fixedValue = try basis.evaluated(atU: parameter, v: .zero, usage: &usage)
            for free in (freeSpan - freeDegree)...freeSpan {
                guard let freeValue = freeBasis[free] else {
                    throw GeometryConversionError.invalidInput("Original surface continuity lacks a transverse owning basis coefficient.")
                }
                let i = alongU ? fixed : free, j = alongU ? free : fixed
                let weight = try ExactRationalCoefficient.originalDouble(source.weights[j][i], usage: &usage)
                    .multiplied(by: fixedValue, usage: &usage)
                let point = source.controlPoints[j][i]
                for (axis, coordinate) in [point.x, point.y, point.z].enumerated() {
                    let value = try weight.multiplied(by: .originalDouble(coordinate, usage: &usage), usage: &usage)
                    result[axis] = try result[axis].adding(freeValue.scaled(by: value, usage: &usage), usage: &usage)
                }
                result[3] = try result[3].adding(freeValue.scaled(by: weight, usage: &usage), usage: &usage)
            }
        }
        return result
    }
}
