import CADCore

/// Actual real transverse fibers over an original (u, edge-parameter) projection root.
struct OriginalProjectedNativeSectionFiber: Sendable {
    struct Point: Sendable {
        let originalU: OriginalSingularFieldElement
        let originalV: OriginalSingularFieldElement
        let originalEdgeParameter: OriginalSingularFieldElement
        let transverseRoot: OriginalSingularFieldRoot
    }
    let sourceProjection: ExactBivariateSystemRoot
    let originalHorizontal: OriginalSingularFieldPolynomial
    let originalVertical: OriginalSingularFieldPolynomial
    let originalLocus: OriginalSingularFieldPolynomial
    let common: OriginalSingularFieldPolynomial
    let points: [Point]
    let hasWholeTransverseFiber: Bool
    private let context: OriginalSingularFieldContext

    init(original: OriginalProjectedNativePolynomialPair, locus: ExactBivariatePolynomial,
        at root: ExactBivariateSystemRoot, usage: inout SurfaceSilhouetteUsage) throws {
        sourceProjection = root
        let field = try OriginalSingularFieldContext(original: root, usage: &usage)
        context = field
        let u = try OriginalSingularFieldElement.original(.coordinate(alongU: true, usage: &usage), in: field, usage: &usage)
        let s = try OriginalSingularFieldElement.original(.coordinate(alongU: false, usage: &usage), in: field, usage: &usage)
        let lower = try ExactRationalCoefficient.originalDouble(original.edgeRange.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(original.edgeRange.upper, usage: &usage)
        let uBounds = original.silhouette.original.chart.u
        let uLow = try u.subtracting(.constant(.originalDouble(uBounds.lower, usage: &usage), in: field,
            maximumDepth: usage.maximumDepth, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
        let uHigh = try OriginalSingularFieldElement.constant(.originalDouble(uBounds.upper, usage: &usage),
            in: field, maximumDepth: usage.maximumDepth, usage: &usage)
            .subtracting(u, maximumDepth: usage.maximumDepth, usage: &usage)
        let low = try s.subtracting(.constant(lower, in: field, maximumDepth: usage.maximumDepth, usage: &usage),
            maximumDepth: usage.maximumDepth, usage: &usage)
        let high = try OriginalSingularFieldElement.constant(upper, in: field, maximumDepth: usage.maximumDepth, usage: &usage)
            .subtracting(s, maximumDepth: usage.maximumDepth, usage: &usage)
        let horizontal = try Self.specialized(original.horizontal, at: s, in: field, usage: &usage)
        let vertical = try Self.specialized(original.vertical, at: s, in: field, usage: &usage)
        let h = try Self.transverse(locus, in: field, usage: &usage)
        originalHorizontal = horizontal; originalVertical = vertical; originalLocus = h
        let gcd = try OriginalSingularFieldPolynomial.gcd(
            OriginalSingularFieldPolynomial.gcd(h, horizontal, maximumDepth: usage.maximumDepth, usage: &usage),
            vertical, maximumDepth: usage.maximumDepth, usage: &usage)
        common = gcd
        if case .negative = try uLow.sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            points = []; hasWholeTransverseFiber = false; return
        }
        if case .negative = try uHigh.sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            points = []; hasWholeTransverseFiber = false; return
        }
        if case .negative = try low.sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            points = []; hasWholeTransverseFiber = false; return
        }
        if case .negative = try high.sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            points = []; hasWholeTransverseFiber = false; return
        }
        if gcd.isZero {
            guard h.isZero, horizontal.isZero, vertical.isZero else {
                throw rationalAlgebraFailure("Original section whole fiber contradicts its three original equations.")
            }
            points = []; hasWholeTransverseFiber = true; return
        }
        hasWholeTransverseFiber = false
        let range = original.silhouette.original.chart.v
        let first = try ExactRationalCoefficient.originalDouble(range.lower, usage: &usage)
        let last = try ExactRationalCoefficient.originalDouble(range.upper, usage: &usage)
        let axis = try Self.coordinate(in: field, usage: &usage)
        let lowerPolynomial = try Self.constant(first, in: field, usage: &usage)
        let upperPolynomial = try Self.constant(last, in: field, usage: &usage)
        let firstDifference = try axis.subtracting(lowerPolynomial, maximumDepth: usage.maximumDepth, usage: &usage)
        let lastDifference = try upperPolynomial.subtracting(axis, maximumDepth: usage.maximumDepth, usage: &usage)
        var values: [Point] = []
        for transverse in try OriginalSingularFieldRoot.allRealRoots(gcd, inheritedDepth: field.depth,
            maximumDepth: usage.maximumDepth, usage: &usage) {
            if case .negative = try transverse.sign(of: firstDifference, maximumDepth: usage.maximumDepth, usage: &usage) { continue }
            if case .negative = try transverse.sign(of: lastDifference, maximumDepth: usage.maximumDepth, usage: &usage) { continue }
            guard case .zero = try transverse.sign(of: h, maximumDepth: usage.maximumDepth, usage: &usage),
                case .zero = try transverse.sign(of: horizontal, maximumDepth: usage.maximumDepth, usage: &usage),
                case .zero = try transverse.sign(of: vertical, maximumDepth: usage.maximumDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Original lifted projected section violates a source equation.")
            }
            let v = try transverse.value(maximumDepth: usage.maximumDepth, usage: &usage)
            let originalU = try u.embedded(in: v.context, maximumDepth: usage.maximumDepth, usage: &usage)
            let originalS = try s.embedded(in: v.context, maximumDepth: usage.maximumDepth, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Point.self, usage: &usage)
            values.append(.init(originalU: originalU, originalV: v, originalEdgeParameter: originalS,
                transverseRoot: transverse))
        }
        points = values
    }

    private static func transverse(_ original: ExactBivariatePolynomial,
        in context: OriginalSingularFieldContext, usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        let count = original.vDegree < 0 ? 0 : try rationalAlgebraCount(original.vDegree, 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(count)
        for index in 0..<count {
            coefficients.append(try .original(original.coefficient(ofV: index, usage: &usage), in: context, usage: &usage))
        }
        return try .init(context: context, coefficients: coefficients, maximumDepth: usage.maximumDepth, usage: &usage)
    }
    private static func specialized(_ original: ExactSurfaceCoefficientPolynomial,
        at s: OriginalSingularFieldElement, in context: OriginalSingularFieldContext,
        usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        var value = try OriginalSingularFieldPolynomial(context: context, coefficients: [],
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        let scalar = try OriginalSingularFieldPolynomial(context: context, coefficients: [s],
            maximumDepth: usage.maximumDepth, usage: &usage)
        for coefficient in original.coefficients.reversed() {
            try usage.consumeWork()
            value = try value.multiplied(by: scalar, maximumDepth: usage.maximumDepth, usage: &usage)
                .adding(transverse(coefficient, in: context, usage: &usage), maximumDepth: usage.maximumDepth, usage: &usage)
        }
        return value
    }
    private static func constant(_ coefficient: ExactRationalCoefficient,
        in context: OriginalSingularFieldContext, usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        return try .init(context: context,
            coefficients: [.constant(coefficient, in: context, maximumDepth: usage.maximumDepth, usage: &usage)],
            maximumDepth: usage.maximumDepth, usage: &usage)
    }
    private static func coordinate(in context: OriginalSingularFieldContext,
        usage: inout SurfaceSilhouetteUsage) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
        return try .init(context: context,
            coefficients: [.constant(.zero, in: context, maximumDepth: usage.maximumDepth, usage: &usage),
                .constant(.one, in: context, maximumDepth: usage.maximumDepth, usage: &usage)],
            maximumDepth: usage.maximumDepth, usage: &usage)
    }
}
