import CADCore

/// One original pcurve span, expressed in the original whole-curve fraction.
struct OriginalRationalSilhouetteBoundarySegment: Sendable {
    let ordinal: Int
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    let u: ExactBivariatePolynomial
    let v: ExactBivariatePolynomial
    let weight: ExactBivariatePolynomial
    struct FractionImage: Sendable {
        let start: OriginalSingularFieldElement
        let gain: OriginalSingularFieldElement
        let sourceDepth: Int
    }
    let originalFractionImage: FractionImage?

    init(ordinal: Int, lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        u: ExactBivariatePolynomial, v: ExactBivariatePolynomial, weight: ExactBivariatePolynomial,
        originalFractionImage: FractionImage? = nil) {
        self.ordinal = ordinal; self.lower = lower; self.upper = upper
        self.u = u; self.v = v; self.weight = weight; self.originalFractionImage = originalFractionImage
    }

    static func extract(_ source: SurfaceParameterCurve, tolerance: ModelingTolerance,
        usage: inout SurfaceSilhouetteUsage, sourceDepth: Int = 0) throws -> [Self] {
        try usage.consumeSourceVisit(depth: sourceDepth)
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        func scalar(_ value: Double) throws -> ExactRationalCoefficient {
            guard value.isFinite else { throw rationalAlgebraFailure("Original pcurve coefficient is nonfinite.") }
            return try .originalDouble(value, usage: &usage)
        }
        func affine(_ origin: Double, _ gain: ExactRationalCoefficient) throws -> ExactBivariatePolynomial {
            try .constant(scalar(origin), usage: &usage).adding(t.scaled(by: gain, usage: &usage), usage: &usage)
        }
        func single(_ u: ExactBivariatePolynomial, _ v: ExactBivariatePolynomial) throws -> [Self] {
            try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
            return [Self(ordinal: 0, lower: .zero, upper: .one, u: u, v: v, weight: one)]
        }
        switch source {
        case .constantU(let u, let start, let end):
            return try single(.constant(scalar(u), usage: &usage),
                affine(start, scalar(end).subtracting(scalar(start), usage: &usage)))
        case .constantV(let v, let start, let end):
            return try single(affine(start, scalar(end).subtracting(scalar(start), usage: &usage)),
                .constant(scalar(v), usage: &usage))
        case .affine(let origin, let direction, let start, let end):
            let first = try scalar(start), gain = try scalar(end).subtracting(first, usage: &usage)
            let parameter = try ExactBivariatePolynomial.constant(first, usage: &usage)
                .adding(t.scaled(by: gain, usage: &usage), usage: &usage)
            return try single(.constant(scalar(origin.x), usage: &usage)
                .adding(parameter.scaled(by: scalar(direction.x), usage: &usage), usage: &usage),
                .constant(scalar(origin.y), usage: &usage)
                .adding(parameter.scaled(by: scalar(direction.y), usage: &usage), usage: &usage))
        case .polyline(let points):
            let law = try OriginalEuclideanPolylineParameterLaw(originalPoints: points,
                inheritedDepth: 0, maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
            try RationalAlgebraStorage.retain(law.segments.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(law.segments.count)
            for segment in law.segments {
                let u = try ExactBivariatePolynomial.constant(segment.originalUStart, usage: &usage)
                    .adding(t.scaled(by: segment.originalUDifference, usage: &usage), usage: &usage)
                let v = try ExactBivariatePolynomial.constant(segment.originalVStart, usage: &usage)
                    .adding(t.scaled(by: segment.originalVDifference, usage: &usage), usage: &usage)
                result.append(Self(ordinal: segment.originalPointIndex, lower: .zero, upper: .one,
                    u: u, v: v, weight: one, originalFractionImage: .init(start: segment.lowerFraction,
                        gain: segment.fractionGain, sourceDepth: segment.sourceDepth)))
            }
            return result
        case .bSpline(let curve):
            try curve.validate(tolerance: tolerance, consumeWork: { try usage.consumeWork() })
            return try nativeSpline(curve, start: curve.knots[curve.degree], end: curve.knots[curve.controlPoints.count],
                continues: false, tolerance: tolerance, usage: &usage)
        case .originalBSplineContinuation(let source):
            guard source.certificationTolerance == tolerance else {
                throw rationalAlgebraFailure("Original pcurve continuation tolerance differs from its source certificate.")
            }
            try source.original.validate(tolerance: tolerance, consumeWork: { try usage.consumeWork() })
            return try nativeSpline(source.original, start: source.startParameter, end: source.endParameter,
                continues: true, tolerance: tolerance, usage: &usage)
        case .originalAffineWord(let image):
            let source = try extract(image.source.parameterCurve, tolerance: tolerance, usage: &usage,
                sourceDepth: try rationalAlgebraCount(sourceDepth, 1))
            return try remapped(source, from: scalar(image.startFraction), to: scalar(image.endFraction), usage: &usage)
        case .originalImage(let image):
            let source = try extract(image.source.parameterCurve, tolerance: tolerance, usage: &usage,
                sourceDepth: try rationalAlgebraCount(sourceDepth, 1))
            let mapped = try remapped(source, from: scalar(image.startFraction), to: scalar(image.endFraction), usage: &usage)
            let uGain = try image.targetImage.uParameterGain.exactCoefficient(usage: &usage)
            let vGain = try image.targetImage.vParameterGain.exactCoefficient(usage: &usage)
            guard !uGain.isZero, !vGain.isZero else { throw rationalAlgebraFailure("Original pcurve image gain vanishes.") }
            let uOffset = try scalar(image.targetImage.uOffset), vOffset = try scalar(image.targetImage.vOffset)
            try RationalAlgebraStorage.retain(mapped.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(mapped.count)
            for span in mapped {
                let nativeU = image.targetImage.swapAxes ? span.v : span.u
                let nativeV = image.targetImage.swapAxes ? span.u : span.v
                result.append(try Self(ordinal: span.ordinal, lower: span.lower, upper: span.upper,
                    u: nativeU.subtracting(span.weight.scaled(by: uOffset, usage: &usage), usage: &usage)
                        .scaled(by: .one.divided(by: uGain, usage: &usage), usage: &usage),
                    v: nativeV.subtracting(span.weight.scaled(by: vOffset, usage: &usage), usage: &usage)
                        .scaled(by: .one.divided(by: vGain, usage: &usage), usage: &usage), weight: span.weight,
                    originalFractionImage: span.originalFractionImage))
            }
            return result
        case .offsetSurfaceImage(let image):
            return try extract(image.source, tolerance: tolerance, usage: &usage,
                sourceDepth: try rationalAlgebraCount(sourceDepth, 1))
        case .periodicTranslation(let base, let uShift, let vShift):
            let original = try extract(base, tolerance: tolerance, usage: &usage, sourceDepth: try rationalAlgebraCount(sourceDepth, 1))
            try RationalAlgebraStorage.retain(original.count, of: Self.self, usage: &usage)
            var result: [Self] = []; result.reserveCapacity(original.count)
            for span in original {
                result.append(try Self(ordinal: span.ordinal, lower: span.lower, upper: span.upper,
                    u: span.u.adding(span.weight.scaled(by: scalar(uShift), usage: &usage), usage: &usage),
                    v: span.v.adding(span.weight.scaled(by: scalar(vShift), usage: &usage), usage: &usage), weight: span.weight,
                    originalFractionImage: span.originalFractionImage))
            }
            return result
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Production D1 trim clipping needs
            // exact original nonrational/implicit pcurve laws and their fraction
            // charts. Enclosures alone cannot authorize a complete event list.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original trim events require the pcurve family's retained exact source chart.")
        }
    }

    private static func nativeSpline(_ curve: BSplineCurve2D, start: Double, end: Double,
        continues: Bool, tolerance: ModelingTolerance, usage: inout SurfaceSilhouetteUsage) throws -> [Self] {
        guard start.isFinite, end.isFinite, start != end else {
            throw rationalAlgebraFailure("Original pcurve traversal requires distinct finite source labels.")
        }
        let first = try ExactRationalCoefficient.originalDouble(start, usage: &usage)
        let gain = try ExactRationalCoefficient.originalDouble(end, usage: &usage).subtracting(first, usage: &usage)
        let t = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let parameter = try ExactBivariatePolynomial.constant(first, usage: &usage)
            .adding(t.scaled(by: gain, usage: &usage), usage: &usage)
        var firstSpan: Int?, lastSpan: Int?
        for span in curve.degree..<curve.controlPoints.count {
            try usage.consumeWork()
            if curve.knots[span] < curve.knots[span + 1] {
                if firstSpan == nil { firstSpan = span }; lastSpan = span
            }
        }
        guard let firstSpan, let lastSpan else { throw rationalAlgebraFailure("Original pcurve has no positive native span cover.") }
        var result: [Self] = []
        for span in curve.degree..<curve.controlPoints.count {
            try usage.consumeWork()
            if curve.knots[span] == curve.knots[span + 1] { continue }
            let nativeLow = continues && span == firstSpan ? min(start, end, curve.knots[span]) : curve.knots[span]
            let nativeHigh = continues && span == lastSpan ? max(start, end, curve.knots[span + 1]) : curve.knots[span + 1]
            let a = try ExactRationalCoefficient.originalDouble(nativeLow, usage: &usage).subtracting(first, usage: &usage).divided(by: gain, usage: &usage)
            let b = try ExactRationalCoefficient.originalDouble(nativeHigh, usage: &usage).subtracting(first, usage: &usage).divided(by: gain, usage: &usage)
            var lower = gain.isPositive ? a : b, upper = gain.isPositive ? b : a
            if lower.isNegative { lower = .zero }
            if try upper.subtracting(.one, usage: &usage).isPositive { upper = .one }
            guard try upper.subtracting(lower, usage: &usage).isPositive else { continue }
            let basis = try OriginalRationalBSplineBasis.powerPolynomials(knots: curve.knots,
                degree: curve.degree, span: span, alongU: true, translation: 0, usage: &usage)
            var u = ExactBivariatePolynomial.zero, v = ExactBivariatePolynomial.zero, w = ExactBivariatePolynomial.zero
            for index in (span - curve.degree)...span {
                try usage.consumeWork()
                guard let original = basis[index] else { continue }
                let value = try original.composed(withU: parameter, v: .zero, usage: &usage)
                let weight = try ExactRationalCoefficient.originalDouble(curve.weights[index], usage: &usage)
                guard weight.isPositive else { throw rationalAlgebraFailure("Original pcurve native weight is nonpositive.") }
                let term = try value.scaled(by: weight, usage: &usage)
                w = try w.adding(term, usage: &usage)
                u = try u.adding(term.scaled(by: .originalDouble(curve.controlPoints[index].x, usage: &usage), usage: &usage), usage: &usage)
                v = try v.adding(term.scaled(by: .originalDouble(curve.controlPoints[index].y, usage: &usage), usage: &usage), usage: &usage)
            }
            if continues {
                let sequence = try ExactUnivariateSturmSequence(w, usage: &usage)
                guard try sequence.count(lower: lower, upper: upper, excludesLower: false, excludesUpper: false, usage: &usage) == 0 else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original continuation pcurve has a homogeneous denominator zero on its requested closed chart.")
                }
                let station = try lower.adding(upper, usage: &usage).divided(by: .natural(2, usage: &usage), usage: &usage)
                let sign = try w.evaluated(atU: station, v: .zero, usage: &usage)
                guard !sign.isZero else { throw rationalAlgebraFailure("Original continuation weight contradicts its complete root exclusion.") }
                if sign.isNegative {
                    u = try u.scaled(by: .one.negated, usage: &usage)
                    v = try v.scaled(by: .one.negated, usage: &usage)
                    w = try w.scaled(by: .one.negated, usage: &usage)
                }
            }
            try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
            result.append(Self(ordinal: span, lower: lower, upper: upper, u: u, v: v, weight: w))
        }
        return result
    }

    private static func remapped(_ source: [Self], from first: ExactRationalCoefficient,
        to last: ExactRationalCoefficient, usage: inout SurfaceSilhouetteUsage) throws -> [Self] {
        let gain = try last.subtracting(first, usage: &usage)
        guard !gain.isZero, !first.isNegative, !last.isNegative,
            !(try ExactRationalCoefficient.one.subtracting(first, usage: &usage)).isNegative,
            !(try ExactRationalCoefficient.one.subtracting(last, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original pcurve image fractions exceed their retained source.")
        }
        let variable = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .scaled(by: gain, usage: &usage).adding(.constant(first, usage: &usage), usage: &usage)
        try RationalAlgebraStorage.retain(source.count, of: Self.self, usage: &usage)
        var result: [Self] = []; result.reserveCapacity(source.count)
        for span in source {
            if let image = span.originalFractionImage {
                let firstValue = try OriginalSingularFieldElement.constant(first, in: image.start.context,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                let selectedGain = try OriginalSingularFieldElement.constant(gain, in: image.start.context,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                let start = try image.start.subtracting(firstValue, maximumDepth: usage.maximumDepth, usage: &usage)
                    .divided(by: selectedGain, maximumDepth: usage.maximumDepth, usage: &usage)
                let slope = try image.gain.divided(by: selectedGain, maximumDepth: usage.maximumDepth, usage: &usage)
                result.append(Self(ordinal: span.ordinal, lower: span.lower, upper: span.upper,
                    u: span.u, v: span.v, weight: span.weight,
                    originalFractionImage: .init(start: start, gain: slope, sourceDepth: image.sourceDepth)))
                continue
            }
            let a = try span.lower.subtracting(first, usage: &usage).divided(by: gain, usage: &usage)
            let b = try span.upper.subtracting(first, usage: &usage).divided(by: gain, usage: &usage)
            var lower = gain.isPositive ? a : b, upper = gain.isPositive ? b : a
            if lower.isNegative { lower = .zero }
            if try upper.subtracting(.one, usage: &usage).isPositive { upper = .one }
            guard try upper.subtracting(lower, usage: &usage).isPositive else { continue }
            result.append(try Self(ordinal: span.ordinal, lower: lower, upper: upper,
                u: span.u.composed(withU: variable, v: .zero, usage: &usage),
                v: span.v.composed(withU: variable, v: .zero, usage: &usage),
                weight: span.weight.composed(withU: variable, v: .zero, usage: &usage)))
        }
        return result
    }

    func substituted(_ source: ExactBivariatePolynomial,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactBivariatePolynomial {
        let terms = try source.orderedTerms(usage: &usage)
        var degree = 0
        for (power, _) in terms { degree = max(degree, try rationalAlgebraCount(power.u, power.v)) }
        func power(_ value: ExactBivariatePolynomial, _ count: Int) throws -> ExactBivariatePolynomial {
            var result = try ExactBivariatePolynomial.constant(.one, usage: &usage)
            for _ in 0..<count { result = try result.multiplied(by: value, usage: &usage) }
            return result
        }
        var result = ExactBivariatePolynomial.zero
        for (exponent, coefficient) in terms {
            let term = try power(u, exponent.u).multiplied(by: power(v, exponent.v), usage: &usage)
                .multiplied(by: power(weight, degree - exponent.u - exponent.v), usage: &usage)
                .scaled(by: coefficient, usage: &usage)
            result = try result.adding(term, usage: &usage)
        }
        return result
    }
}
